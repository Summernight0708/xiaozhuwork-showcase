import {
  getDocument,
  GlobalWorkerOptions,
  type PDFDocumentProxy,
  type RenderTask,
} from "pdfjs-dist";
import pdfWorkerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";

// Version-matched bundled worker: never load active content from a PDF or a CDN.
GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
export const PDF_CANVAS_MAX_PAGES = 250;
export const PDF_CANVAS_MAX_PIXELS = 6_000_000;
const PDF_CANVAS_MAX_DPR = 2;

export interface PdfCanvasSession {
  readonly pageCount: number;
  renderPage(pageNumber: number, canvas: HTMLCanvasElement): Promise<void>;
  close(): void;
}

export async function createPdfCanvasSession(
  blob: Blob,
): Promise<PdfCanvasSession> {
  if (blob.type !== "application/pdf")
    throw new Error("Invalid PDF content type");
  const loadingTask = getDocument({
    data: new Uint8Array(await blob.arrayBuffer()),
    isEvalSupported: false,
    stopAtErrors: true,
    useSystemFonts: true,
  });
  let document: PDFDocumentProxy;
  try {
    document = await loadingTask.promise;
    if (
      !Number.isSafeInteger(document.numPages) ||
      document.numPages < 1 ||
      document.numPages > PDF_CANVAS_MAX_PAGES
    ) {
      throw new Error("PDF page count exceeds preview limit");
    }
  } catch (error) {
    void loadingTask.destroy().catch(() => undefined);
    throw error;
  }

  let disposed = false;
  let activeRender: RenderTask | null = null;
  return {
    pageCount: document.numPages,
    async renderPage(pageNumber, canvas) {
      if (disposed) throw new Error("PDF preview is closed");
      if (
        !Number.isSafeInteger(pageNumber) ||
        pageNumber < 1 ||
        pageNumber > document.numPages
      )
        throw new Error("Invalid PDF page number");
      if (activeRender) throw new Error("PDF preview is already rendering");

      const page = await document.getPage(pageNumber);
      if (disposed) throw new Error("PDF preview is closed");
      const natural = page.getViewport({ scale: 1 });
      if (!(natural.width > 0 && natural.height > 0)) {
        throw new Error("Invalid PDF page dimensions");
      }
      const availableWidth = Math.max(
        240,
        Math.min(canvas.parentElement?.clientWidth || 720, 1080),
      );
      const dpr = Math.min(
        Math.max(window.devicePixelRatio || 1, 1),
        PDF_CANVAS_MAX_DPR,
      );
      const scale = Math.min(
        (availableWidth / natural.width) * dpr,
        Math.sqrt(PDF_CANVAS_MAX_PIXELS / (natural.width * natural.height)),
        4,
      );
      const viewport = page.getViewport({ scale });
      const pixelWidth = Math.ceil(viewport.width);
      const pixelHeight = Math.ceil(viewport.height);
      if (
        pixelWidth < 1 ||
        pixelHeight < 1 ||
        pixelWidth * pixelHeight > PDF_CANVAS_MAX_PIXELS + 4096
      ) {
        throw new Error("PDF page exceeds canvas limits");
      }
      const context = canvas.getContext("2d", { alpha: false });
      if (!context) throw new Error("PDF canvas is unavailable");
      canvas.width = pixelWidth;
      canvas.height = pixelHeight;
      canvas.style.width = String(Math.ceil(viewport.width / dpr)) + "px";
      canvas.style.height = String(Math.ceil(viewport.height / dpr)) + "px";
      activeRender = page.render({
        canvasContext: context,
        viewport,
        background: "white",
      });
      try {
        await activeRender.promise;
        if (disposed) throw new Error("PDF preview is closed");
      } finally {
        activeRender = null;
        page.cleanup();
      }
    },
    close() {
      if (disposed) return;
      disposed = true;
      activeRender?.cancel();
      void loadingTask.destroy().catch(() => undefined);
    },
  };
}
