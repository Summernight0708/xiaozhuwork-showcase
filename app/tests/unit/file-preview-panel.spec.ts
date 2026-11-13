import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  kind: "image" as
    | "image"
    | "pdf"
    | "video"
    | "docx"
    | "xlsx"
    | "csv"
    | "text"
    | "unsupported",
  createPreviewAccess: vi.fn(),
  createDownloadUrl: vi.fn(),
  loadDocxPreview: vi.fn(),
  loadPdfPreview: vi.fn(),
  createPdfCanvasSession: vi.fn(),
  pdfPageRender: vi.fn(),
  pdfClose: vi.fn(),
  loadTextPreview: vi.fn(),
  loadWorkbookPreview: vi.fn(),
  openDownload: vi.fn(),
  parseCsvPreview: vi.fn(),
}));

vi.mock("@/services/file-preview", () => ({
  createPreviewAccess: mocks.createPreviewAccess,
  createDownloadUrl: mocks.createDownloadUrl,
  getFilePreviewKind: () => mocks.kind,
  loadDocxPreview: mocks.loadDocxPreview,
  loadPdfPreview: mocks.loadPdfPreview,
  loadTextPreview: mocks.loadTextPreview,
  loadWorkbookPreview: mocks.loadWorkbookPreview,
  openDownload: mocks.openDownload,
  parseCsvPreview: mocks.parseCsvPreview,
}));

vi.mock("@/services/pdf-canvas-preview", () => ({
  createPdfCanvasSession: mocks.createPdfCanvasSession,
}));

import FilePreviewPanel from "@/components/file/FilePreviewPanel.vue";

const baseVersion = {
  id: "version-1",
  originalName: "photo.png",
  mimeType: "image/png",
  sizeBytes: 1024,
  versionNumber: 3,
  uploadedBy: "user-1",
  createdAt: "2026-10-04T00:00:00.000Z",
};

const mountedWrappers: Array<ReturnType<typeof mount>> = [];

function mountPanel() {
  const wrapper = mount(FilePreviewPanel, {
    attachTo: document.body,
    props: {
      projectId: "project-1",
      fileVersion: baseVersion,
      uploaderName: "小明",
    },
    global: {
      stubs: {
        Teleport: true,
      },
    },
  });
  mountedWrappers.push(wrapper);
  return wrapper;
}

beforeEach(() => {
  mocks.kind = "image";
  mocks.createPreviewAccess.mockReset().mockResolvedValue({
    signedUrl: "https://signed.test/preview",
    version: baseVersion,
  });
  mocks.createDownloadUrl
    .mockReset()
    .mockResolvedValue("https://signed.test/download");
  mocks.loadDocxPreview.mockReset();
  mocks.pdfPageRender.mockReset().mockResolvedValue(undefined);
  mocks.pdfClose.mockReset();
  mocks.createPdfCanvasSession.mockReset().mockImplementation(async () => ({
    pageCount: 2,
    renderPage: mocks.pdfPageRender,
    close: mocks.pdfClose,
  }));
  mocks.loadPdfPreview
    .mockReset()
    .mockResolvedValue(
      new Blob(["%PDF-1.7\n%%EOF\n"], { type: "application/pdf" }),
    );
  Object.defineProperty(URL, "createObjectURL", {
    configurable: true,
    writable: true,
    value: vi.fn(() => "blob:pdf-preview"),
  });
  Object.defineProperty(URL, "revokeObjectURL", {
    configurable: true,
    writable: true,
    value: vi.fn(),
  });
  mocks.loadTextPreview.mockReset();
  mocks.loadWorkbookPreview.mockReset();
  mocks.openDownload.mockReset();
  mocks.parseCsvPreview.mockReset();
});

afterEach(() => {
  for (const wrapper of mountedWrappers.splice(0)) wrapper.unmount();
  document.body.replaceChildren();
  document.body.style.overflow = "";
});

describe("FilePreviewPanel", () => {
  it("opens in a viewport modal, manages focus, and closes on Escape", async () => {
    const trigger = document.createElement("button");
    trigger.textContent = "打开预览";
    document.body.append(trigger);
    trigger.focus();

    const wrapper = mountPanel();
    await flushPromises();

    const dialog = wrapper.get('[role="dialog"]');
    expect(dialog.attributes("aria-modal")).toBe("true");
    expect(document.body.style.overflow).toBe("hidden");
    const close = wrapper.get<HTMLButtonElement>(
      'button[aria-label="关闭文件预览"]',
    ).element;
    const download = wrapper.get<HTMLButtonElement>(".download-button").element;
    expect(document.activeElement).toBe(close);

    document.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Tab",
        shiftKey: true,
        bubbles: true,
      }),
    );
    expect(document.activeElement).toBe(download);
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Tab", bubbles: true }),
    );
    expect(document.activeElement).toBe(close);

    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    expect(wrapper.emitted("close")).toHaveLength(1);

    wrapper.unmount();
    expect(document.body.style.overflow).toBe("");
    expect(document.activeElement).toBe(trigger);
  });

  it("emits preview-success only after an image actually loads", async () => {
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.emitted("preview-success")).toBeUndefined();
    const image = wrapper.get("img");
    expect(image.attributes("alt")).toBe("photo.png");

    await image.trigger("load");
    await image.trigger("load");

    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("does not emit preview-success when native preview fails", async () => {
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.get("img").trigger("error");

    expect(wrapper.emitted("preview-success")).toBeUndefined();
    expect(wrapper.text()).toContain("当前无法预览此文件");
    expect(wrapper.text()).toContain("下载原文件");
  });

  it("emits PDF success only when Canvas rendering completes", async () => {
    mocks.kind = "pdf";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/pdf",
      version: {
        ...baseVersion,
        originalName: "paper.pdf",
        mimeType: "application/pdf",
      },
    });

    let completeRender: (() => void) | undefined;
    mocks.pdfPageRender.mockImplementationOnce(
      () =>
        new Promise<void>((resolve) => {
          completeRender = resolve;
        }),
    );

    const wrapper = mountPanel();
    await flushPromises();

    expect(mocks.loadPdfPreview).toHaveBeenCalledWith(
      "https://signed.test/pdf",
      1024,
    );
    expect(mocks.createPdfCanvasSession).toHaveBeenCalled();
    expect(wrapper.find("iframe").exists()).toBe(false);
    expect(wrapper.find("canvas.pdf-preview").exists()).toBe(true);
    expect(wrapper.text()).toContain("正在准备预览");
    expect(wrapper.emitted("preview-success")).toBeUndefined();
    expect(mocks.pdfPageRender).toHaveBeenCalledWith(
      1,
      expect.any(HTMLCanvasElement),
    );

    completeRender?.();
    await flushPromises();

    expect(wrapper.text()).toContain("第 1 / 2 页");
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
    await wrapper.findAll(".pdf-controls button")[1]!.trigger("click");
    await flushPromises();
    expect(mocks.pdfPageRender).toHaveBeenCalledWith(
      2,
      expect.any(HTMLCanvasElement),
    );
    expect(wrapper.text()).toContain("第 2 / 2 页");
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
    wrapper.unmount();
    expect(mocks.pdfClose).toHaveBeenCalledTimes(1);
  });

  it("does not record a PDF preview when canvas rendering fails", async () => {
    mocks.kind = "pdf";
    mocks.pdfPageRender.mockRejectedValue(new Error("Canvas unavailable"));
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/pdf",
      version: {
        ...baseVersion,
        originalName: "paper.pdf",
        mimeType: "application/pdf",
      },
    });
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.emitted("preview-success")).toBeUndefined();
    expect(wrapper.text()).toContain("当前无法预览此文件");
    expect(wrapper.text()).toContain("下载原文件");
  });

  it("does not emit PDF success when validation or fetch fails", async () => {
    mocks.kind = "pdf";
    mocks.loadPdfPreview.mockRejectedValue(new Error("invalid pdf"));
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/pdf",
      version: {
        ...baseVersion,
        originalName: "paper.pdf",
        mimeType: "application/pdf",
      },
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.find("iframe").exists()).toBe(false);
    expect(wrapper.emitted("preview-success")).toBeUndefined();
    expect(wrapper.text()).toContain("当前无法预览此文件");
  });

  it("emits success only after MP4 metadata becomes playable", async () => {
    mocks.kind = "video";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/video",
      version: {
        ...baseVersion,
        originalName: "clip.mp4",
        mimeType: "video/mp4",
      },
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.emitted("preview-success")).toBeUndefined();
    await wrapper.get("video").trigger("loadedmetadata");
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("emits success after DOCX parsing and rendering succeeds", async () => {
    mocks.kind = "docx";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/docx",
      version: {
        ...baseVersion,
        originalName: "report.docx",
        mimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      },
    });
    mocks.loadDocxPreview.mockResolvedValue(
      "<h1>标题</h1><p><strong>正文</strong></p>",
    );

    const wrapper = mountPanel();
    await flushPromises();
    await flushPromises();

    expect(document.querySelector(".docx-preview")?.textContent).toContain(
      "标题",
    );
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("falls back without success when DOCX parsing fails", async () => {
    mocks.kind = "docx";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/docx",
      version: {
        ...baseVersion,
        originalName: "broken.docx",
        mimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      },
    });
    mocks.loadDocxPreview.mockRejectedValue(new Error("bad docx"));

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain("当前无法预览此文件");
    expect(wrapper.text()).toContain("下载原文件");
    expect(wrapper.emitted("preview-success")).toBeUndefined();
  });

  it("shows XLSX sheet tabs and succeeds only after parsed table data exists", async () => {
    mocks.kind = "xlsx";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/xlsx",
      version: {
        ...baseVersion,
        originalName: "data.xlsx",
        mimeType:
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      },
    });
    mocks.loadWorkbookPreview.mockResolvedValue({
      sheets: [
        {
          name: "Sheet1",
          rows: [
            ["Name", "Score"],
            ["A", "95"],
          ],
          truncatedRows: false,
          truncatedColumns: false,
          partialSource: false,
        },
        {
          name: "Sheet2",
          rows: [["Other"]],
          truncatedRows: false,
          truncatedColumns: false,
          partialSource: false,
        },
      ],
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain("Sheet1");
    expect(wrapper.text()).toContain("Sheet2");
    expect(wrapper.find("table").text()).toContain("95");
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("shows limited CSV data and the partial-content notice", async () => {
    mocks.kind = "csv";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/csv",
      version: {
        ...baseVersion,
        originalName: "rows.csv",
        mimeType: "text/csv",
      },
    });
    mocks.loadTextPreview.mockResolvedValue({
      text: "name,value\na,1",
      partial: true,
    });
    mocks.parseCsvPreview.mockReturnValue({
      rows: [
        ["name", "value"],
        ["a", "1"],
      ],
      truncatedRows: false,
      truncatedColumns: false,
      partialSource: true,
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.find("table").text()).toContain("value");
    expect(wrapper.text()).toContain("当前仅显示文件部分内容");
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("renders text as text rather than HTML", async () => {
    mocks.kind = "text";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/text",
      version: {
        ...baseVersion,
        originalName: "notes.md",
        mimeType: "text/markdown",
      },
    });
    mocks.loadTextPreview.mockResolvedValue({
      text: "# title\n<script>alert(1)</script>",
      partial: false,
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.get("pre").text()).toContain("<script>alert(1)</script>");
    expect(wrapper.find(".text-preview script").exists()).toBe(false);
    expect(wrapper.emitted("preview-success")).toEqual([["version-1"]]);
  });

  it("treats unsupported files as a normal fallback with download available", async () => {
    mocks.kind = "unsupported";
    mocks.createPreviewAccess.mockResolvedValue({
      signedUrl: "https://signed.test/pptx",
      version: {
        ...baseVersion,
        originalName: "deck.pptx",
        mimeType:
          "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      },
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain("当前文件类型暂不支持在线预览");
    expect(wrapper.emitted("preview-success")).toBeUndefined();

    await wrapper
      .findAll("button")
      .find((button) => button.text() === "下载原文件")!
      .trigger("click");
    await flushPromises();

    expect(mocks.createDownloadUrl).toHaveBeenCalledWith(
      "project-1",
      "version-1",
    );
    expect(mocks.openDownload).toHaveBeenCalledWith(
      "https://signed.test/download",
      "deck.pptx",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    );
  });

  it("keeps responsive previews inside their own scroll containers on mobile", () => {
    const source = readFileSync(
      resolve(process.cwd(), "src/components/file/FilePreviewPanel.vue"),
      "utf8",
    );

    expect(source).toContain("@media (max-width: 767px)");
    expect(source).toMatch(
      /\.preview-overlay\s*\{[^}]*position:\s*fixed;[^}]*inset:\s*0;/s,
    );
    expect(source).toMatch(
      /@media \(max-width: 767px\)[\s\S]*\.file-preview-panel\s*\{[^}]*height:\s*100dvh;/s,
    );
    expect(source).toMatch(/\.table-scroll\s*\{[^}]*overflow:\s*auto/s);
    expect(source).toMatch(/\.image-preview,[\s\S]*max-width:\s*100%/);
  });

  it("provides an accessible close action", async () => {
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.get('button[aria-label="关闭文件预览"]').trigger("click");

    expect(wrapper.emitted("close")).toHaveLength(1);
  });
});
