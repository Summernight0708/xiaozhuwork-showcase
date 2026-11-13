import { beforeEach, describe, expect, it, vi } from "vitest";

const fake = vi.hoisted(() => ({
  getDocument: vi.fn(),
  worker: { workerSrc: "" },
  render: vi.fn(),
  cancel: vi.fn(),
  cleanup: vi.fn(),
  destroy: vi.fn(),
}));

vi.mock("pdfjs-dist", () => ({
  getDocument: fake.getDocument,
  GlobalWorkerOptions: fake.worker,
}));

import {
  createPdfCanvasSession,
  PDF_CANVAS_MAX_PAGES,
  PDF_CANVAS_MAX_PIXELS,
} from "@/services/pdf-canvas-preview";

function testPdf() {
  const blob = new Blob(["%PDF-1.4\n%%EOF\n"], { type: "application/pdf" });
  Object.defineProperty(blob, "arrayBuffer", {
    value: vi
      .fn()
      .mockResolvedValue(new TextEncoder().encode("%PDF-1.4\n%%EOF\n").buffer),
  });
  return blob;
}

function canvasFixture() {
  const parent = document.createElement("div");
  Object.defineProperty(parent, "clientWidth", { value: 580 });
  const canvas = document.createElement("canvas");
  parent.append(canvas);
  vi.spyOn(canvas, "getContext").mockReturnValue(
    {} as CanvasRenderingContext2D,
  );
  return canvas;
}

beforeEach(() => {
  vi.clearAllMocks();
  fake.worker.workerSrc = "";
  fake.render.mockReturnValue({
    promise: Promise.resolve(),
    cancel: fake.cancel,
  });
  fake.destroy.mockResolvedValue(undefined);
  const page = {
    getViewport: ({ scale }: { scale: number }) => ({
      width: 612 * scale,
      height: 792 * scale,
    }),
    render: fake.render,
    cleanup: fake.cleanup,
  };
  fake.getDocument.mockReturnValue({
    promise: Promise.resolve({
      numPages: 2,
      getPage: vi.fn().mockResolvedValue(page),
    }),
    destroy: fake.destroy,
  });
});

describe("PDF.js Canvas preview", () => {
  it("renders a bounded page, then releases the worker/document on close", async () => {
    const session = await createPdfCanvasSession(testPdf());
    const canvas = canvasFixture();
    expect(session.pageCount).toBe(2);
    await session.renderPage(1, canvas);

    expect(canvas.width).toBeGreaterThan(0);
    expect(canvas.width * canvas.height).toBeLessThanOrEqual(
      PDF_CANVAS_MAX_PIXELS + 4096,
    );
    expect(fake.render).toHaveBeenCalledOnce();
    expect(fake.cleanup).toHaveBeenCalledOnce();
    session.close();
    session.close();
    expect(fake.destroy).toHaveBeenCalledOnce();
  });

  it("rejects an out-of-range page without attempting rendering", async () => {
    const session = await createPdfCanvasSession(testPdf());
    await expect(session.renderPage(3, canvasFixture())).rejects.toThrow(
      "Invalid PDF page number",
    );
    expect(fake.render).not.toHaveBeenCalled();
    session.close();
  });

  it("rejects PDFs over the maximum page count", async () => {
    fake.getDocument.mockReturnValueOnce({
      promise: Promise.resolve({ numPages: PDF_CANVAS_MAX_PAGES + 1 }),
      destroy: fake.destroy,
    });
    await expect(createPdfCanvasSession(testPdf())).rejects.toThrow(
      "PDF page count exceeds",
    );
    expect(fake.destroy).toHaveBeenCalledOnce();
  });

  it("refuses to emit a painted result when the renderer rejects", async () => {
    fake.render.mockReturnValueOnce({
      promise: Promise.reject(new Error("bad PDF paint")),
      cancel: fake.cancel,
    });
    const session = await createPdfCanvasSession(testPdf());
    await expect(session.renderPage(1, canvasFixture())).rejects.toThrow(
      "bad PDF paint",
    );
    expect(fake.cleanup).toHaveBeenCalledOnce();
    session.close();
  });

  it("enforces PDF media type before opening a parser", async () => {
    await expect(
      createPdfCanvasSession(new Blob(["fake"], { type: "text/plain" })),
    ).rejects.toThrow("content type");
    expect(fake.getDocument).not.toHaveBeenCalled();
  });
});
