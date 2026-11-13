import { isValidH264Mp4 } from "./mp4-validation.ts";
import { validateLegacyDoc } from "./legacy-doc-validation.ts";

export const TASK_FILE_MAX_BYTES = 52_428_800;

export type FileValidationFailureCode =
  | "FILE_TYPE_NOT_ALLOWED"
  | "FILE_VALIDATION_FAILED";

export type FileValidationResult =
  | {
      ok: true;
      mimeType: string;
      sizeBytes: number;
      sha256Hex: string;
    }
  | {
      ok: false;
      code: FileValidationFailureCode;
    };

type ValidateTaskFileInput = {
  bytes: Uint8Array;
  declaredMimeType: string;
  originalName: string;
};

const OOXML_MIME_ROOTS = new Map<string, string>([
  [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "word/",
  ],
  [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "xl/",
  ],
  [
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "ppt/",
  ],
]);

const MIME_EXTENSIONS = new Map<string, ReadonlySet<string>>([
  ["application/pdf", new Set(["pdf"])],
  ["application/msword", new Set(["doc"])],
  [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    new Set(["docx"]),
  ],
  [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    new Set(["xlsx"]),
  ],
  [
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    new Set(["pptx"]),
  ],
  ["text/csv", new Set(["csv"])],
  ["text/plain", new Set(["txt"])],
  ["text/markdown", new Set(["md", "markdown"])],
  ["application/json", new Set(["json"])],
  ["application/xml", new Set(["xml"])],
  ["text/xml", new Set(["xml"])],
  ["text/css", new Set(["css"])],
  ["text/javascript", new Set(["js", "mjs"])],
  ["application/javascript", new Set(["js", "mjs"])],
  ["text/typescript", new Set(["ts", "mts", "cts"])],
  ["application/typescript", new Set(["ts", "mts", "cts"])],
  ["image/png", new Set(["png"])],
  ["image/jpeg", new Set(["jpg", "jpeg"])],
  ["image/gif", new Set(["gif"])],
  ["image/webp", new Set(["webp"])],
  ["video/mp4", new Set(["mp4"])],
]);

const TEXT_MIME_TYPES = new Set([
  "text/csv",
  "text/plain",
  "text/markdown",
  "application/json",
  "application/xml",
  "text/xml",
  "text/css",
  "text/javascript",
  "application/javascript",
  "text/typescript",
  "application/typescript",
]);

function startsWithBytes(bytes: Uint8Array, signature: readonly number[]) {
  if (bytes.length < signature.length) return false;
  return signature.every((value, index) => bytes[index] === value);
}

function hasAsciiAt(bytes: Uint8Array, offset: number, value: string) {
  if (bytes.length < offset + value.length) return false;
  for (let index = 0; index < value.length; index += 1) {
    if (bytes[offset + index] !== value.charCodeAt(index)) return false;
  }
  return true;
}

function extensionOf(name: string) {
  const leaf = name.trim().toLowerCase();
  const dot = leaf.lastIndexOf(".");
  return dot > 0 && dot < leaf.length - 1 ? leaf.slice(dot + 1) : "";
}

function hasDangerousBinarySignature(bytes: Uint8Array) {
  return (
    startsWithBytes(bytes, [0x4d, 0x5a]) ||
    startsWithBytes(bytes, [0x7f, 0x45, 0x4c, 0x46]) ||
    startsWithBytes(bytes, [0xca, 0xfe, 0xba, 0xbe]) ||
    startsWithBytes(bytes, [0xfe, 0xed, 0xfa, 0xce]) ||
    startsWithBytes(bytes, [0xfe, 0xed, 0xfa, 0xcf]) ||
    startsWithBytes(bytes, [0xce, 0xfa, 0xed, 0xfe]) ||
    startsWithBytes(bytes, [0xcf, 0xfa, 0xed, 0xfe]) ||
    startsWithBytes(bytes, [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]) ||
    startsWithBytes(bytes, [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) ||
    startsWithBytes(bytes, [0x1f, 0x8b])
  );
}

function decodeUtf8(bytes: Uint8Array) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

function looksLikeBlockedMarkup(text: string) {
  const normalized = text.replace(/^\uFEFF/, "").trimStart().toLowerCase();
  return (
    normalized.startsWith("<!doctype html") ||
    normalized.startsWith("<html") ||
    normalized.startsWith("<svg") ||
    /<svg(?:\s|>)/i.test(normalized)
  );
}

const ZIP_LOCAL_FILE_HEADER = 0x04034b50;
const ZIP_CENTRAL_DIRECTORY_HEADER = 0x02014b50;
const ZIP_END_OF_CENTRAL_DIRECTORY = 0x06054b50;
const ZIP_EOCD_MIN_BYTES = 22;
const ZIP_MAX_COMMENT_BYTES = 65_535;
const OOXML_CONTENT_TYPES_MAX_BYTES = 1_048_576;

type ZipEntry = {
  compression: number;
  dataStart: number;
  compressedSize: number;
  uncompressedSize: number;
};

const OOXML_REQUIRED_MAIN_PART = new Map<string, string>([
  ["application/vnd.openxmlformats-officedocument.wordprocessingml.document", "word/document.xml"],
  ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xl/workbook.xml"],
  ["application/vnd.openxmlformats-officedocument.presentationml.presentation", "ppt/presentation.xml"],
]);

const OOXML_REQUIRED_MAIN_CONTENT_TYPE = new Map<string, string>([
  [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
  ],
  [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
  ],
  [
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
  ],
]);

const OOXML_BLOCKED_ENTRY_SUFFIXES = [
  ".exe",
  ".dll",
  ".com",
  ".scr",
  ".msi",
  ".msp",
  ".cpl",
  ".sys",
  ".bat",
  ".cmd",
  ".ps1",
  ".vbs",
  ".vbe",
  ".jse",
  ".wsf",
  ".wsh",
  ".hta",
  ".jar",
];

function bytesEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

function findZipEndOfCentralDirectory(bytes: Uint8Array, view: DataView) {
  const minimumOffset = Math.max(0, bytes.length - ZIP_EOCD_MIN_BYTES - ZIP_MAX_COMMENT_BYTES);
  for (let offset = bytes.length - ZIP_EOCD_MIN_BYTES; offset >= minimumOffset; offset -= 1) {
    if (view.getUint32(offset, true) !== ZIP_END_OF_CENTRAL_DIRECTORY) continue;
    const commentLength = view.getUint16(offset + 20, true);
    if (offset + ZIP_EOCD_MIN_BYTES + commentLength === bytes.length) return offset;
  }
  return -1;
}

function zipEntries(bytes: Uint8Array) {
  if (bytes.length < ZIP_EOCD_MIN_BYTES) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const decoder = new TextDecoder("utf-8", { fatal: false });
  const eocdOffset = findZipEndOfCentralDirectory(bytes, view);
  if (eocdOffset < 0) return null;

  const diskNumber = view.getUint16(eocdOffset + 4, true);
  const centralDirectoryDisk = view.getUint16(eocdOffset + 6, true);
  const entriesOnDisk = view.getUint16(eocdOffset + 8, true);
  const totalEntries = view.getUint16(eocdOffset + 10, true);
  const centralDirectorySize = view.getUint32(eocdOffset + 12, true);
  const centralDirectoryOffset = view.getUint32(eocdOffset + 16, true);
  if (
    diskNumber !== 0 ||
    centralDirectoryDisk !== 0 ||
    entriesOnDisk !== totalEntries ||
    totalEntries === 0 ||
    totalEntries === 0xffff ||
    centralDirectorySize === 0xffffffff ||
    centralDirectoryOffset === 0xffffffff ||
    centralDirectoryOffset + centralDirectorySize !== eocdOffset
  ) {
    return null;
  }

  const names = new Set<string>();  const entries = new Map<string, ZipEntry>();
  let offset = centralDirectoryOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    if (offset + 46 > eocdOffset || view.getUint32(offset, true) !== ZIP_CENTRAL_DIRECTORY_HEADER) return null;

    const flags = view.getUint16(offset + 8, true);
    const compression = view.getUint16(offset + 10, true);
    const compressedSize = view.getUint32(offset + 20, true);    const uncompressedSize = view.getUint32(offset + 24, true);
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    const diskStart = view.getUint16(offset + 34, true);
    const localOffset = view.getUint32(offset + 42, true);
    const nameStart = offset + 46;
    const nameEnd = nameStart + nameLength;
    const nextOffset = nameEnd + extraLength + commentLength;
    if (
      (flags & 0x1) !== 0 ||
      ![0, 8].includes(compression) ||
      compressedSize === 0xffffffff ||
      uncompressedSize === 0xffffffff ||
      (compression === 0 && compressedSize !== uncompressedSize) ||
      diskStart !== 0 ||
      nextOffset > eocdOffset ||
      localOffset + 30 > centralDirectoryOffset ||
      view.getUint32(localOffset, true) !== ZIP_LOCAL_FILE_HEADER
    ) {
      return null;
    }

    const localFlags = view.getUint16(localOffset + 6, true);
    const localCompression = view.getUint16(localOffset + 8, true);
    const localNameLength = view.getUint16(localOffset + 26, true);
    const localExtraLength = view.getUint16(localOffset + 28, true);
    const localNameStart = localOffset + 30;
    const localNameEnd = localNameStart + localNameLength;
    const dataStart = localNameEnd + localExtraLength;
    if (
      localNameEnd > centralDirectoryOffset ||
      dataStart + compressedSize > centralDirectoryOffset ||
      localFlags !== flags ||
      localCompression !== compression
    ) {
      return null;
    }

    const centralNameBytes = bytes.subarray(nameStart, nameEnd);
    const localNameBytes = bytes.subarray(localNameStart, localNameEnd);
    if (!bytesEqual(centralNameBytes, localNameBytes)) return null;

    const name = decoder.decode(centralNameBytes).split("\\").join("/").toLowerCase();
    const segments = name.split("/");
    if (
      !name ||
      name.startsWith("/") ||
      name.includes("\u0000") ||
      segments.some((segment) => segment === "..") ||
      names.has(name)
    ) {
      return null;
    }
    names.add(name);    entries.set(name, {
      compression,
      dataStart,
      compressedSize,
      uncompressedSize,
    });
    offset = nextOffset;
  }

  return offset === eocdOffset ? { names, entries } : null;
}

async function readZipTextEntry(
  bytes: Uint8Array,
  zip: { entries: Map<string, ZipEntry> },
  name: string,
) {
  const entry = zip.entries.get(name);
  if (!entry || entry.uncompressedSize > OOXML_CONTENT_TYPES_MAX_BYTES) {
    return null;
  }

  const compressed = bytes.slice(
    entry.dataStart,
    entry.dataStart + entry.compressedSize,
  );
  let output: Uint8Array;

  if (entry.compression === 0) {
    output = compressed;
  } else {
    try {
      const decompressor = new DecompressionStream(
        "deflate-raw",
      ) as unknown as TransformStream<Uint8Array, Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(compressed);
          controller.close();
        },
      }).pipeThrough(decompressor);
      const reader = stream.getReader();
      const chunks: Uint8Array[] = [];
      let total = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.length;
        if (
          total > OOXML_CONTENT_TYPES_MAX_BYTES ||
          total > entry.uncompressedSize
        ) {
          await reader.cancel();
          return null;
        }
        chunks.push(value);
      }

      if (total !== entry.uncompressedSize) return null;
      output = new Uint8Array(total);
      let cursor = 0;
      for (const chunk of chunks) {
        output.set(chunk, cursor);
        cursor += chunk.length;
      }
    } catch {
      return null;
    }
  }

  if (output.length !== entry.uncompressedSize) return null;
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(output);
  } catch {
    return null;
  }
}

async function validateOoxml(bytes: Uint8Array, mimeType: string) {
  if (!startsWithBytes(bytes, [0x50, 0x4b, 0x03, 0x04])) {
    return "FILE_VALIDATION_FAILED" as const;
  }

  const zip = zipEntries(bytes);
  const root = OOXML_MIME_ROOTS.get(mimeType);
  const mainPart = OOXML_REQUIRED_MAIN_PART.get(mimeType);
  const mainContentType = OOXML_REQUIRED_MAIN_CONTENT_TYPE.get(mimeType);
  if (
    !zip ||
    !root ||
    !mainPart ||
    !mainContentType ||
    !zip.names.has("[content_types].xml") ||
    !zip.names.has(mainPart)
  ) {
    return "FILE_VALIDATION_FAILED" as const;
  }

  if (
    [...zip.names].some(
      (name) =>
        name.endsWith("/vbaproject.bin") ||
        name.endsWith("/vbadata.xml") ||
        name.includes("activex/") ||
        OOXML_BLOCKED_ENTRY_SUFFIXES.some((suffix) => name.endsWith(suffix)),
    )
  ) {
    return "FILE_TYPE_NOT_ALLOWED" as const;
  }

  const contentTypes = await readZipTextEntry(
    bytes,
    zip,
    "[content_types].xml",
  );
  if (contentTypes === null) return "FILE_VALIDATION_FAILED" as const;

  const normalizedContentTypes = contentTypes.toLowerCase();
  if (
    normalizedContentTypes.includes("macroenabled") ||
    normalizedContentTypes.includes("application/vnd.ms-office.vbaproject") ||
    normalizedContentTypes.includes("activex")
  ) {
    return "FILE_TYPE_NOT_ALLOWED" as const;
  }
  if (
    !normalizedContentTypes.includes(mainPart.toLowerCase()) ||
    !normalizedContentTypes.includes(mainContentType.toLowerCase())
  ) {
    return "FILE_VALIDATION_FAILED" as const;
  }

  return null;
}

function validateBinarySignature(bytes: Uint8Array, mimeType: string) {
  switch (mimeType) {
    case "application/pdf":
      return hasAsciiAt(bytes, 0, "%PDF-");
    case "image/png":
      return startsWithBytes(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case "image/jpeg":
      return startsWithBytes(bytes, [0xff, 0xd8, 0xff]);
    case "image/gif":
      return hasAsciiAt(bytes, 0, "GIF87a") || hasAsciiAt(bytes, 0, "GIF89a");
    case "image/webp":
      return hasAsciiAt(bytes, 0, "RIFF") && hasAsciiAt(bytes, 8, "WEBP");
    default:
      return false;
  }
}

async function sha256Hex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes));
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export async function validateTaskFile({
  bytes,
  declaredMimeType,
  originalName,
}: ValidateTaskFileInput): Promise<FileValidationResult> {
  if (bytes.length === 0 || bytes.length > TASK_FILE_MAX_BYTES) {
    return { ok: false, code: "FILE_VALIDATION_FAILED" };
  }

  const extensions = MIME_EXTENSIONS.get(declaredMimeType);
  if (!extensions || !extensions.has(extensionOf(originalName))) {
    return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
  }

  if (hasDangerousBinarySignature(bytes)) {
    return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
  }

  if (declaredMimeType === "video/mp4") {
    if (!(await isValidH264Mp4(bytes.length, async (at, length) => bytes.subarray(at, at + length)))) {
      return { ok: false, code: "FILE_VALIDATION_FAILED" };
    }
    return {
      ok: true,
      mimeType: declaredMimeType,
      sizeBytes: bytes.length,
      sha256Hex: await sha256Hex(bytes),
    };
  }

  if (declaredMimeType === "application/msword") {
    const legacyDoc = await validateLegacyDoc({
      size: bytes.length,
      read: async (offset, length) => bytes.subarray(offset, offset + length),
    });
    if (!legacyDoc.valid) {
      return {
        ok: false,
        code: legacyDoc.reason === "active_content"
          ? "FILE_TYPE_NOT_ALLOWED"
          : "FILE_VALIDATION_FAILED",
      };
    }
  } else {
    const ooxmlRoot = OOXML_MIME_ROOTS.get(declaredMimeType);
    if (ooxmlRoot) {
      const failure = await validateOoxml(bytes, declaredMimeType);
      if (failure) return { ok: false, code: failure };
    } else if (TEXT_MIME_TYPES.has(declaredMimeType)) {
      const text = decodeUtf8(bytes);
      if (text === null) return { ok: false, code: "FILE_VALIDATION_FAILED" };
      if (looksLikeBlockedMarkup(text)) {
        return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
      }
      if (declaredMimeType === "application/json") {
        try {
          JSON.parse(text);
        } catch {
          return { ok: false, code: "FILE_VALIDATION_FAILED" };
        }
      }
      if (
        (declaredMimeType === "application/xml" || declaredMimeType === "text/xml") &&
        !text.replace(/^\uFEFF/, "").trimStart().startsWith("<")
      ) {
        return { ok: false, code: "FILE_VALIDATION_FAILED" };
      }
    } else if (!validateBinarySignature(bytes, declaredMimeType)) {
      return { ok: false, code: "FILE_VALIDATION_FAILED" };
    }
  }

  return {
    ok: true,
    mimeType: declaredMimeType,
    sizeBytes: bytes.length,
    sha256Hex: await sha256Hex(bytes),
  };
}
