import type { SupabaseClient } from "@supabase/supabase-js";

import { downloadUrl } from "@/platform/downloads";
import { getBackend } from "@/services/backend";
import { createRepository } from "@/services/repository";
import type { Database } from "@/types/database.generated";

export const PREVIEW_SIGNED_URL_TTL_SECONDS = 120;
export const DOWNLOAD_SIGNED_URL_TTL_SECONDS = 600;
export const TEXT_PREVIEW_MAX_BYTES = 1_048_576;
export const PDF_PREVIEW_MAX_BYTES = 52_428_800;
export const DOCX_PREVIEW_MAX_BYTES = 12_582_912;
export const XLSX_PREVIEW_MAX_BYTES = 8_388_608;
export const TABLE_PREVIEW_MAX_ROWS = 200;
export const TABLE_PREVIEW_MAX_COLUMNS = 30;

export type FilePreviewKind =
  "image" | "pdf" | "video" | "docx" | "xlsx" | "csv" | "text" | "unsupported";

export interface PreviewFileVersion {
  id: string;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  versionNumber: number;
  uploadedBy?: string | null;
  createdAt: string;
}

export interface TablePreview {
  rows: string[][];
  truncatedRows: boolean;
  truncatedColumns: boolean;
  partialSource: boolean;
}

export interface WorkbookSheetPreview extends TablePreview {
  name: string;
}

export interface WorkbookPreview {
  sheets: WorkbookSheetPreview[];
}

type MammothApi = {
  convertToHtml: (
    input: { arrayBuffer: ArrayBuffer },
    options: {
      externalFileAccess: false;
      convertImage: unknown;
    },
  ) => Promise<{ value: string }>;
  images: {
    imgElement: (
      converter: (image: {
        contentType: string;
        readAsBase64String: () => Promise<string>;
      }) => Promise<{ src: string }>,
    ) => unknown;
  };
};

function extensionOf(filename: string) {
  const leaf = filename.trim().toLowerCase();
  const index = leaf.lastIndexOf(".");
  return index > 0 && index < leaf.length - 1 ? leaf.slice(index + 1) : "";
}

function exactType(
  version: Pick<PreviewFileVersion, "originalName" | "mimeType">,
  mimeType: string,
  extensions: readonly string[],
) {
  return (
    version.mimeType.trim().toLowerCase() === mimeType &&
    extensions.includes(extensionOf(version.originalName))
  );
}

export function getFilePreviewKind(
  version: Pick<PreviewFileVersion, "originalName" | "mimeType">,
): FilePreviewKind {
  if (exactType(version, "image/png", ["png"])) return "image";
  if (exactType(version, "image/jpeg", ["jpg", "jpeg"])) return "image";
  if (exactType(version, "image/webp", ["webp"])) return "image";
  if (exactType(version, "image/gif", ["gif"])) return "image";
  if (exactType(version, "application/pdf", ["pdf"])) return "pdf";
  if (exactType(version, "video/mp4", ["mp4"])) return "video";
  if (
    exactType(
      version,
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ["docx"],
    )
  ) {
    return "docx";
  }
  if (
    exactType(
      version,
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ["xlsx"],
    )
  ) {
    return "xlsx";
  }
  if (exactType(version, "text/csv", ["csv"])) return "csv";
  if (exactType(version, "text/plain", ["txt"])) return "text";
  if (exactType(version, "text/markdown", ["md", "markdown"])) return "text";
  if (exactType(version, "application/json", ["json"])) return "text";
  return "unsupported";
}

function toPreviewFileVersion(version: {
  id: string;
  original_name: string;
  mime_type: string;
  size_bytes: number;
  version_number: number;
  uploaded_by: string | null;
  created_at: string;
}): PreviewFileVersion {
  return {
    id: version.id,
    originalName: version.original_name,
    mimeType: version.mime_type,
    sizeBytes: version.size_bytes,
    versionNumber: version.version_number,
    uploadedBy: version.uploaded_by,
    createdAt: version.created_at,
  };
}

function requireBackend() {
  const backend = getBackend();
  if (!backend) throw new Error("Backend unavailable");
  return backend;
}

async function signedAccess(
  client: SupabaseClient<Database>,
  projectId: string,
  fileVersionId: string,
  expiresInSeconds: number,
) {
  return createRepository(client).createFileVersionSignedAccess(
    fileVersionId,
    projectId,
    expiresInSeconds,
  );
}

export async function createPreviewAccess(
  projectId: string,
  fileVersionId: string,
) {
  const backend = requireBackend();
  const access = await signedAccess(
    backend.client,
    projectId,
    fileVersionId,
    PREVIEW_SIGNED_URL_TTL_SECONDS,
  );
  return {
    signedUrl: access.signedUrl,
    version: toPreviewFileVersion(access.version),
  };
}

export async function createDownloadUrl(
  projectId: string,
  fileVersionId: string,
) {
  const backend = requireBackend();
  const access = await signedAccess(
    backend.client,
    projectId,
    fileVersionId,
    DOWNLOAD_SIGNED_URL_TTL_SECONDS,
  );
  return access.signedUrl;
}

async function fetchChecked(url: string, init?: RequestInit) {
  const response = await fetch(url, {
    cache: "no-store",
    credentials: "omit",
    ...init,
  });
  if (!response.ok) throw new Error("Preview fetch failed");
  return response;
}

async function readResponseBytes(
  response: Response,
  maxBytes: number,
  allowPartial: boolean,
) {
  if (!response.body) {
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > maxBytes && !allowPartial) {
      throw new Error("Preview file is too large");
    }
    return {
      bytes: bytes.subarray(0, maxBytes),
      partial: bytes.byteLength > maxBytes,
    };
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let partial = false;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value?.byteLength) continue;
    const remaining = maxBytes - total;
    if (remaining <= 0) {
      partial = true;
      await reader.cancel();
      break;
    }
    if (value.byteLength > remaining) {
      chunks.push(value.subarray(0, remaining));
      total += remaining;
      partial = true;
      await reader.cancel();
      break;
    }
    chunks.push(value);
    total += value.byteLength;
  }

  if (partial && !allowPartial) {
    throw new Error("Preview file is too large");
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { bytes, partial };
}

export async function loadTextPreview(
  signedUrl: string,
  sizeBytes: number,
  maxBytes = TEXT_PREVIEW_MAX_BYTES,
) {
  const response = await fetchChecked(signedUrl, {
    headers: { Range: `bytes=0-${maxBytes - 1}` },
  });
  const { bytes, partial } = await readResponseBytes(response, maxBytes, true);
  return {
    text: new TextDecoder("utf-8", { fatal: false }).decode(bytes),
    partial: partial || sizeBytes > bytes.byteLength,
  };
}

export function parseCsvPreview(
  text: string,
  partialSource: boolean,
): TablePreview {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  let truncatedColumns = false;
  let truncatedRows = false;
  let index = 0;

  const pushCell = () => {
    if (row.length < TABLE_PREVIEW_MAX_COLUMNS) row.push(cell);
    else truncatedColumns = true;
    cell = "";
  };
  const pushRow = () => {
    pushCell();
    if (rows.length < TABLE_PREVIEW_MAX_ROWS) rows.push(row);
    else truncatedRows = true;
    row = [];
  };

  while (index < text.length && !truncatedRows) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') {
        cell += '"';
        index += 2;
        continue;
      }
      if (char === '"') quoted = false;
      else cell += char;
      index += 1;
      continue;
    }
    if (char === '"' && cell.length === 0) {
      quoted = true;
      index += 1;
      continue;
    }
    if (char === ",") {
      pushCell();
      index += 1;
      continue;
    }
    if (char === "\n") {
      pushRow();
      index += 1;
      continue;
    }
    if (char === "\r") {
      if (text[index + 1] === "\n") index += 1;
      pushRow();
      index += 1;
      continue;
    }
    cell += char;
    index += 1;
  }

  if ((cell.length || row.length) && rows.length <= TABLE_PREVIEW_MAX_ROWS) {
    pushRow();
  }

  return {
    rows: rows.slice(0, TABLE_PREVIEW_MAX_ROWS),
    truncatedRows: truncatedRows || index < text.length,
    truncatedColumns,
    partialSource,
  };
}

async function loadBoundedBytes(
  signedUrl: string,
  sizeBytes: number,
  maxBytes: number,
) {
  if (sizeBytes > maxBytes) throw new Error("Preview file is too large");
  const response = await fetchChecked(signedUrl);
  const { bytes } = await readResponseBytes(response, maxBytes, false);
  if (bytes.byteLength !== sizeBytes) throw new Error("Preview size mismatch");
  return bytes;
}

export async function loadPdfPreview(
  signedUrl: string,
  sizeBytes: number,
  maxBytes = PDF_PREVIEW_MAX_BYTES,
) {
  if (sizeBytes > maxBytes) throw new Error("Preview file is too large");
  const response = await fetchChecked(signedUrl);
  const contentType = (response.headers.get("content-type") ?? "")
    .split(";", 1)[0]
    ?.trim()
    .toLowerCase();
  if (contentType !== "application/pdf") {
    throw new Error("Preview response is not a PDF");
  }

  const { bytes } = await readResponseBytes(response, maxBytes, false);
  if (bytes.byteLength !== sizeBytes) throw new Error("Preview size mismatch");
  if (bytes.byteLength < 10) throw new Error("Invalid PDF body");

  const decoder = new TextDecoder("ascii");
  if (decoder.decode(bytes.subarray(0, 5)) !== "%PDF-") {
    throw new Error("Invalid PDF header");
  }
  const tail = decoder.decode(
    bytes.subarray(Math.max(0, bytes.byteLength - 2048)),
  );
  if (!tail.includes("%%EOF")) throw new Error("Invalid PDF trailer");

  return new Blob([bytes], { type: "application/pdf" });
}

export async function loadDocxPreview(signedUrl: string, sizeBytes: number) {
  const bytes = await loadBoundedBytes(
    signedUrl,
    sizeBytes,
    DOCX_PREVIEW_MAX_BYTES,
  );
  const module = (await import("mammoth")) as unknown as {
    default?: MammothApi;
    convertToHtml?: MammothApi["convertToHtml"];
    images?: MammothApi["images"];
  };
  const mammoth = (module.default ?? module) as MammothApi;
  const result = await mammoth.convertToHtml(
    {
      arrayBuffer: bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength,
      ) as ArrayBuffer,
    },
    {
      externalFileAccess: false,
      convertImage: mammoth.images.imgElement(async (image) => ({
        src: `data:${image.contentType};base64,${await image.readAsBase64String()}`,
      })),
    },
  );
  if (!result.value.trim())
    throw new Error("Document has no previewable content");

  const { default: DOMPurify } = await import("dompurify");
  const sanitized = DOMPurify.sanitize(result.value, {
    ALLOWED_TAGS: [
      "p",
      "br",
      "h1",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "ul",
      "ol",
      "li",
      "table",
      "thead",
      "tbody",
      "tfoot",
      "tr",
      "th",
      "td",
      "strong",
      "b",
      "em",
      "i",
      "u",
      "s",
      "blockquote",
      "pre",
      "code",
      "sub",
      "sup",
      "span",
      "a",
      "img",
    ],
    ALLOWED_ATTR: ["href", "title", "src", "alt", "colspan", "rowspan"],
    ALLOW_DATA_ATTR: false,
  });

  const template = document.createElement("template");
  template.innerHTML = sanitized;
  for (const image of template.content.querySelectorAll("img")) {
    const src = image.getAttribute("src") ?? "";
    if (!/^data:image\/(?:png|jpeg|jpg|gif|webp);base64,/i.test(src)) {
      image.removeAttribute("src");
    }
  }
  for (const link of template.content.querySelectorAll("a")) {
    const href = link.getAttribute("href") ?? "";
    if (
      href &&
      !href.startsWith("#") &&
      !/^https?:\/\//i.test(href) &&
      !/^mailto:/i.test(href)
    ) {
      link.removeAttribute("href");
    }
  }
  const html = template.innerHTML.trim();
  if (!html) throw new Error("Document has no previewable content");
  return html;
}

function stringifyCell(value: unknown) {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value.toLocaleString();
  return String(value);
}

export async function loadWorkbookPreview(
  signedUrl: string,
  sizeBytes: number,
): Promise<WorkbookPreview> {
  const bytes = await loadBoundedBytes(
    signedUrl,
    sizeBytes,
    XLSX_PREVIEW_MAX_BYTES,
  );
  const { default: readWorkbook } = await import("read-excel-file/browser");
  const rawSheets = await readWorkbook(new Blob([bytes]));
  const sheets = rawSheets.map((sheet) => {
    const sourceRows = Array.isArray(sheet.data) ? sheet.data : [];
    const rows = sourceRows
      .slice(0, TABLE_PREVIEW_MAX_ROWS)
      .map((sourceRow) =>
        sourceRow
          .slice(0, TABLE_PREVIEW_MAX_COLUMNS)
          .map((cell) => stringifyCell(cell)),
      );
    return {
      name: sheet.sheet,
      rows,
      truncatedRows: sourceRows.length > TABLE_PREVIEW_MAX_ROWS,
      truncatedColumns: sourceRows.some(
        (sourceRow) => sourceRow.length > TABLE_PREVIEW_MAX_COLUMNS,
      ),
      partialSource: false,
    };
  });
  if (
    !sheets.length ||
    !sheets.some((sheet) =>
      sheet.rows.some((row) => row.some((cell) => cell.length > 0)),
    )
  ) {
    throw new Error("Workbook has no previewable cells");
  }
  return { sheets };
}

export async function openDownload(
  url: string,
  fileName?: string,
  mimeType?: string,
) {
  return downloadUrl({ url, fileName, mimeType });
}
