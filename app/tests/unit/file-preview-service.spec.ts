import { afterEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  convertToHtml: vi.fn(),
  readWorkbook: vi.fn(),
}));

vi.mock("mammoth", () => ({
  default: {
    convertToHtml: mocks.convertToHtml,
    images: {
      imgElement: vi.fn((converter) => converter),
    },
  },
}));

vi.mock("read-excel-file/browser", () => ({
  default: mocks.readWorkbook,
}));

import {
  DOCX_PREVIEW_MAX_BYTES,
  PDF_PREVIEW_MAX_BYTES,
  TABLE_PREVIEW_MAX_COLUMNS,
  TABLE_PREVIEW_MAX_ROWS,
  getFilePreviewKind,
  loadDocxPreview,
  loadPdfPreview,
  loadTextPreview,
  loadWorkbookPreview,
  parseCsvPreview,
} from "@/services/file-preview";
import { createRepository } from "@/services/repository";

function version(originalName: string, mimeType: string) {
  return { originalName, mimeType };
}

function successfulResponse(bytes: Uint8Array, contentType?: string) {
  return new Response(
    bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer,
    {
      status: 200,
      headers: contentType ? { "content-type": contentType } : undefined,
    },
  );
}

afterEach(() => {
  vi.restoreAllMocks();
  mocks.convertToHtml.mockReset();
  mocks.readWorkbook.mockReset();
});

describe("file preview type selection", () => {
  it.each([
    ["photo.png", "image/png", "image"],
    ["photo.jpg", "image/jpeg", "image"],
    ["photo.jpeg", "image/jpeg", "image"],
    ["photo.webp", "image/webp", "image"],
    ["photo.gif", "image/gif", "image"],
    ["paper.pdf", "application/pdf", "pdf"],
    ["clip.mp4", "video/mp4", "video"],
    [
      "notes.docx",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "docx",
    ],
    [
      "table.xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "xlsx",
    ],
    ["rows.csv", "text/csv", "csv"],
    ["notes.txt", "text/plain", "text"],
    ["notes.md", "text/markdown", "text"],
    ["data.json", "application/json", "text"],
  ])("accepts trusted %s metadata", (name, mime, expected) => {
    expect(getFilePreviewKind(version(name, mime))).toBe(expected);
  });

  it.each([
    [
      "deck.pptx",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ],
    ["old.doc", "application/msword"],
    ["archive.zip", "application/zip"],
    ["paper.exe", "application/pdf"],
    ["paper.pdf", "application/octet-stream"],
    ["clip.mov", "video/mp4"],
  ])("keeps unsupported or mismatched %s out of preview", (name, mime) => {
    expect(getFilePreviewKind(version(name, mime))).toBe("unsupported");
  });
});

describe("bounded preview parsing", () => {
  it("accepts a fetched PDF only when its response and body are valid", async () => {
    const bytes = new TextEncoder().encode(
      "%PDF-1.7\n1 0 obj\nendobj\n%%EOF\n",
    );
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(successfulResponse(bytes, "application/pdf"));

    const blob = await loadPdfPreview(
      "https://signed.test/pdf",
      bytes.byteLength,
    );

    expect(fetchMock).toHaveBeenCalledWith(
      "https://signed.test/pdf",
      expect.objectContaining({ cache: "no-store", credentials: "omit" }),
    );
    expect(blob.type).toBe("application/pdf");
    expect(blob.size).toBe(bytes.byteLength);
  });

  it("rejects PDF preview when the signed fetch fails", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("not found", {
        status: 404,
        headers: { "content-type": "text/plain" },
      }),
    );

    await expect(loadPdfPreview("https://signed.test/pdf", 9)).rejects.toThrow(
      "Preview fetch failed",
    );
  });

  it("rejects invalid PDF responses before they can become preview success", async () => {
    const invalid = new TextEncoder().encode("not-a-pdf-body");
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      successfulResponse(invalid, "application/pdf"),
    );

    await expect(
      loadPdfPreview("https://signed.test/pdf", invalid.byteLength),
    ).rejects.toThrow("Invalid PDF header");
  });

  it("rejects oversized PDF previews before fetching", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    await expect(
      loadPdfPreview("https://signed.test/pdf", PDF_PREVIEW_MAX_BYTES + 1),
    ).rejects.toThrow("too large");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("reads only the configured text prefix and marks large content partial", async () => {
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(
        successfulResponse(
          new TextEncoder().encode("abcdefghijklmnopqrstuvwxyz"),
        ),
      );

    const result = await loadTextPreview("https://signed.test/file", 2048, 10);

    expect(result).toEqual({ text: "abcdefghij", partial: true });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://signed.test/file",
      expect.objectContaining({
        cache: "no-store",
        credentials: "omit",
        headers: { Range: "bytes=0-9" },
      }),
    );
  });

  it("limits CSV rows and columns without rendering the whole table", () => {
    const wideRow = Array.from(
      { length: TABLE_PREVIEW_MAX_COLUMNS + 3 },
      (_, index) => `c${index}`,
    ).join(",");
    const source = Array.from(
      { length: TABLE_PREVIEW_MAX_ROWS + 5 },
      () => wideRow,
    ).join("\n");

    const result = parseCsvPreview(source, true);

    expect(result.rows).toHaveLength(TABLE_PREVIEW_MAX_ROWS);
    expect(result.rows[0]).toHaveLength(TABLE_PREVIEW_MAX_COLUMNS);
    expect(result.truncatedRows).toBe(true);
    expect(result.truncatedColumns).toBe(true);
    expect(result.partialSource).toBe(true);
  });

  it("sanitizes DOCX-generated HTML before returning it", async () => {
    mocks.convertToHtml.mockResolvedValue({
      value:
        '<h1>Hello</h1><script>alert(1)</script><img src="javascript:alert(1)"><p><strong>World</strong></p>',
    });
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      successfulResponse(new Uint8Array([1, 2, 3])),
    );

    const html = await loadDocxPreview("https://signed.test/docx", 3);

    expect(html).toContain("<h1>Hello</h1>");
    expect(html).toContain("<strong>World</strong>");
    expect(html).not.toContain("<script");
    expect(html).not.toContain("javascript:");
  });

  it("falls back before parsing oversized DOCX files", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    await expect(
      loadDocxPreview("https://signed.test/docx", DOCX_PREVIEW_MAX_BYTES + 1),
    ).rejects.toThrow("too large");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mocks.convertToHtml).not.toHaveBeenCalled();
  });

  it("limits XLSX rows and columns and keeps sheet names", async () => {
    mocks.readWorkbook.mockResolvedValue([
      {
        sheet: "Sheet A",
        data: Array.from({ length: TABLE_PREVIEW_MAX_ROWS + 4 }, (_, row) =>
          Array.from(
            { length: TABLE_PREVIEW_MAX_COLUMNS + 2 },
            (_, column) => `${row}:${column}`,
          ),
        ),
      },
      { sheet: "Sheet B", data: [["ok"]] },
    ]);
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      successfulResponse(new Uint8Array([4, 5, 6])),
    );

    const result = await loadWorkbookPreview("https://signed.test/xlsx", 3);

    expect(result.sheets.map((sheet) => sheet.name)).toEqual([
      "Sheet A",
      "Sheet B",
    ]);
    expect(result.sheets[0]?.rows).toHaveLength(TABLE_PREVIEW_MAX_ROWS);
    expect(result.sheets[0]?.rows[0]).toHaveLength(TABLE_PREVIEW_MAX_COLUMNS);
    expect(result.sheets[0]?.truncatedRows).toBe(true);
    expect(result.sheets[0]?.truncatedColumns).toBe(true);
  });
});

describe("file-version signed access", () => {
  function clientWithVersion(row: Record<string, unknown> | null) {
    const maybeSingle = vi.fn().mockResolvedValue({ data: row, error: null });
    const projectEq = vi.fn(() => ({ maybeSingle }));
    const idEq = vi.fn(() => ({ eq: projectEq }));
    const select = vi.fn(() => ({ eq: idEq }));
    const from = vi.fn(() => ({ select }));
    const createSignedUrl = vi.fn().mockResolvedValue({
      data: { signedUrl: "https://signed.test/final" },
      error: null,
    });
    const storageFrom = vi.fn(() => ({ createSignedUrl }));
    return {
      client: {
        from,
        storage: { from: storageFrom },
        functions: {},
        rpc: vi.fn(),
      } as never,
      from,
      idEq,
      projectEq,
      createSignedUrl,
    };
  }

  it("rechecks file version and project through RLS before signing a short URL", async () => {
    const row = {
      id: "version-1",
      project_id: "project-1",
      object_path: "pending/project-1/final.pdf",
      file_id: "file-1",
      task_id: "task-1",
      reservation_id: "reservation-1",
      created_at: "2026-10-11T00:00:00Z",
      original_name: "final.pdf",
      mime_type: "application/pdf",
      sha256_hex: "a".repeat(64),
      size_bytes: 512,
      version_number: 1,
    };
    const mock = clientWithVersion(row);

    await expect(
      createRepository(mock.client).createFileVersionSignedAccess(
        "version-1",
        "project-1",
        120,
      ),
    ).resolves.toEqual({
      version: row,
      signedUrl: "https://signed.test/final",
    });

    expect(mock.from).toHaveBeenCalledWith("task_file_versions_visible");
    expect(mock.idEq).toHaveBeenCalledWith("id", "version-1");
    expect(mock.projectEq).toHaveBeenCalledWith("project_id", "project-1");
    expect(mock.createSignedUrl).toHaveBeenCalledWith(
      "pending/project-1/final.pdf",
      120,
    );
  });

  it("does not sign unauthorized, cross-project, or unfinalized UUIDs", async () => {
    const mock = clientWithVersion(null);

    await expect(
      createRepository(mock.client).createFileVersionSignedAccess(
        "version-from-another-project",
        "project-1",
        120,
      ),
    ).rejects.toThrow("File version unavailable");
    expect(mock.createSignedUrl).not.toHaveBeenCalled();
  });
});
