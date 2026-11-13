import { createHash } from "node:crypto";
import {
  type FileValidationFailureCode,
  type FileValidationResult,
  TASK_FILE_MAX_BYTES,
  validateTaskFile,
} from "./file-validation.ts";
import { StreamingJsonSyntax } from "./streaming-json-validator.ts";
import { isValidH264Mp4 } from "./mp4-validation.ts";
import { validateLegacyDoc } from "./legacy-doc-validation.ts";

/**
 * A disk-spooled, bounded-memory alternative to Response.arrayBuffer().
 * All paths clean up their temporary file, even on stream errors/cancellation.
 * The standard <=50 MiB validator remains authoritative (no security regression).
 */
export const PHASE2_LARGE_FILE_MAX_BYTES = 209_715_200;
const MAX_BUFFERED_VALIDATION = TASK_FILE_MAX_BYTES;
const ZIP_EOCD_SCAN_BYTES = 65_535 + 22;
const MAX_ZIP_ENTRIES = 20_000;
const MAX_ZIP_UNCOMPRESSED_BYTES = 512 * 1024 * 1024;
const MAX_ZIP_SINGLE_UNCOMPRESSED_BYTES = 128 * 1024 * 1024;
const MAX_ZIP_COMPRESSION_RATIO = 200;
const MAX_ZIP_TEXT_BYTES = 1_048_576;
const BLOCKED_ZIP_NAMES =
  /\.(?:exe|dll|com|scr|msi|msp|cpl|sys|bat|cmd|ps1|vbs|vbe|jse|wsf|wsh|hta|jar)$/;
const BIN_SIGNATURES = [
  [0x4d, 0x5a],
  [0x7f, 0x45, 0x4c, 0x46],
  [0xca, 0xfe, 0xba, 0xbe],
  [0xfe, 0xed, 0xfa, 0xce],
  [0xfe, 0xed, 0xfa, 0xcf],
  [0xce, 0xfa, 0xed, 0xfe],
  [0xcf, 0xfa, 0xed, 0xfe],
  [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07],
  [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c],
  [0x1f, 0x8b],
];
const EXTENSIONS: Record<string, string[]> = {
  "application/pdf": ["pdf"],
  "application/msword": ["doc"],
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": [
    "docx",
  ],
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ["xlsx"],
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": [
    "pptx",
  ],
  "text/csv": ["csv"],
  "text/plain": ["txt"],
  "text/markdown": ["md", "markdown"],
  "application/json": ["json"],
  "application/xml": ["xml"],
  "text/xml": ["xml"],
  "text/css": ["css"],
  "text/javascript": ["js", "mjs"],
  "application/javascript": ["js", "mjs"],
  "text/typescript": ["ts", "mts", "cts"],
  "application/typescript": ["ts", "mts", "cts"],
  "image/png": ["png"],
  "image/jpeg": ["jpg", "jpeg"],
  "image/gif": ["gif"],
  "image/webp": ["webp"],
  "video/mp4": ["mp4"],
};
const MAIN_PART: Record<string, [string, string]> = {
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": [
    "word/document.xml",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
  ],
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": [
    "xl/workbook.xml",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
  ],
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": [
    "ppt/presentation.xml",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
  ],
};

type ValidationInput = {
  stream: ReadableStream<Uint8Array>;
  declaredMimeType: string;
  originalName: string;
  maxBytes: number;
};
type ZipEntry = {
  start: number;
  compressed: number;
  inflated: number;
  method: number;
};

function begins(input: Uint8Array, pattern: readonly number[]): boolean {
  return (
    input.length >= pattern.length &&
    pattern.every((byte, i) => input[i] === byte)
  );
}
function asciiAt(
  input: Uint8Array,
  offset: number,
  signature: string,
): boolean {
  return (
    input.length >= offset + signature.length &&
    [...signature].every((ch, i) => input[offset + i] === ch.charCodeAt(0))
  );
}
function forbiddenBinary(prefix: Uint8Array): boolean {
  return BIN_SIGNATURES.some((pattern) => begins(prefix, pattern));
}
function isAllowedBinarySignature(prefix: Uint8Array, mime: string): boolean {
  if (mime === "application/pdf") return asciiAt(prefix, 0, "%PDF-");
  if (mime === "image/png") {
    return begins(prefix, [137, 80, 78, 71, 13, 10, 26, 10]);
  }
  if (mime === "image/jpeg") return begins(prefix, [255, 216, 255]);
  if (mime === "image/gif") {
    return asciiAt(prefix, 0, "GIF87a") || asciiAt(prefix, 0, "GIF89a");
  }
  if (mime === "image/webp") {
    return asciiAt(prefix, 0, "RIFF") && asciiAt(prefix, 8, "WEBP");
  }
  return false;
}

async function readAt(
  file: Deno.FsFile,
  offset: number,
  length: number,
): Promise<Uint8Array> {
  if (
    length < 0 ||
    length > Math.max(ZIP_EOCD_SCAN_BYTES, MAX_ZIP_TEXT_BYTES) ||
    offset < 0
  ) {
    throw Error("invalid read");
  }
  // Supabase Edge Runtime 1.76 exposes FsFile.seek but not Deno.SeekMode.
  // Deno's seek ABI uses 0 for Start; using the numeric mode keeps this
  // compatible with both the current local runtime and newer Deno versions.
  await file.seek(offset, 0);
  const result = new Uint8Array(length);
  let used = 0;
  while (used < length) {
    const n = await file.read(result.subarray(used));
    if (n === null) throw Error("truncated file");
    used += n;
  }
  return result;
}
async function readZipText(
  file: Deno.FsFile,
  entry: ZipEntry,
): Promise<string | null> {
  if (
    entry.inflated > MAX_ZIP_TEXT_BYTES ||
    entry.compressed > MAX_ZIP_TEXT_BYTES
  ) {
    return null;
  }
  const data = await readAt(file, entry.start, entry.compressed);
  if (entry.method === 0) {
    if (data.length !== entry.inflated) return null;
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(data);
    } catch {
      return null;
    }
  }
  try {
    const ds = new DecompressionStream(
      "deflate-raw",
    ) as unknown as TransformStream<Uint8Array, Uint8Array>;
    const reader = new Blob([data as BlobPart])
      .stream()
      .pipeThrough(ds)
      .getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > MAX_ZIP_TEXT_BYTES || length > entry.inflated) {
          await reader.cancel();
          return null;
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    if (length !== entry.inflated) return null;
    const out = new Uint8Array(length);
    let at = 0;
    for (const chunk of chunks) {
      out.set(chunk, at);
      at += chunk.length;
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(out);
  } catch {
    return null;
  }
}
/**
 * Verify actual inflation, not just untrusted ZIP central directory claims.
 * Compressed bytes and output are streamed through 32-KiB/64-KiB windows.
 */
async function verifyZipInflation(
  file: Deno.FsFile,
  entry: ZipEntry,
): Promise<boolean> {
  if (entry.method === 0) return entry.compressed === entry.inflated;
  let cursor = entry.start;
  let remaining = entry.compressed;
  const compressed = new ReadableStream<Uint8Array>({
    async pull(controller) {
      if (remaining === 0) {
        controller.close();
        return;
      }
      try {
        const bytes = await readAt(
          file,
          cursor,
          Math.min(32 * 1024, remaining),
        );
        cursor += bytes.length;
        remaining -= bytes.length;
        controller.enqueue(bytes);
      } catch (error) {
        controller.error(error);
      }
    },
  });
  const ds = new DecompressionStream(
    "deflate-raw",
  ) as unknown as TransformStream<Uint8Array, Uint8Array>;
  const reader = compressed.pipeThrough(ds).getReader();
  let inflated = 0;
  try {
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      inflated += item.value.length;
      if (
        inflated > entry.inflated ||
        inflated > MAX_ZIP_SINGLE_UNCOMPRESSED_BYTES
      ) {
        await reader.cancel();
        return false;
      }
    }
    return inflated === entry.inflated;
  } catch {
    return false;
  } finally {
    reader.releaseLock();
  }
}

/** Parse ZIP64-free single-disk OOXML with bounded central-directory reads. */
async function validateLargeOoxml(
  file: Deno.FsFile,
  size: number,
  mime: string,
): Promise<FileValidationFailureCode | null> {
  const tailStart = Math.max(0, size - ZIP_EOCD_SCAN_BYTES);
  const tail = await readAt(file, tailStart, size - tailStart);
  const tv = new DataView(tail.buffer, tail.byteOffset, tail.byteLength);
  let eocd = -1;
  for (let i = tail.length - 22; i >= 0; i--) {
    if (
      tv.getUint32(i, true) === 0x06054b50 &&
      i + 22 + tv.getUint16(i + 20, true) === tail.length
    ) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return "FILE_VALIDATION_FAILED";
  const count = tv.getUint16(eocd + 10, true),
    disk = tv.getUint16(eocd + 4, true),
    countDisk = tv.getUint16(eocd + 8, true);
  const directorySize = tv.getUint32(eocd + 12, true),
    directoryOffset = tv.getUint32(eocd + 16, true);
  if (
    disk !== 0 ||
    tv.getUint16(eocd + 6, true) !== 0 ||
    count === 0 ||
    count > MAX_ZIP_ENTRIES ||
    count === 65535 ||
    countDisk !== count ||
    directorySize === 0xffffffff ||
    directoryOffset === 0xffffffff ||
    directoryOffset + directorySize !== tailStart + eocd
  ) {
    return "FILE_VALIDATION_FAILED";
  }
  const names = new Map<string, ZipEntry>();
  let cursor = directoryOffset,
    inflatedTotal = 0;
  const decoder = new TextDecoder("utf-8", { fatal: true });
  for (let index = 0; index < count; index++) {
    if (cursor + 46 > directoryOffset + directorySize) {
      return "FILE_VALIDATION_FAILED";
    }
    const header = await readAt(file, cursor, 46);
    const h = new DataView(header.buffer, header.byteOffset, header.byteLength);
    if (h.getUint32(0, true) !== 0x02014b50) return "FILE_VALIDATION_FAILED";
    const flags = h.getUint16(8, true),
      method = h.getUint16(10, true);
    const compressed = h.getUint32(20, true),
      inflated = h.getUint32(24, true);
    const nameLen = h.getUint16(28, true),
      extraLen = h.getUint16(30, true),
      commentLen = h.getUint16(32, true);
    const localOffset = h.getUint32(42, true);
    const next = cursor + 46 + nameLen + extraLen + commentLen;
    if (
      (flags & 1) !== 0 ||
      ![0, 8].includes(method) ||
      compressed === 0xffffffff ||
      inflated === 0xffffffff ||
      localOffset === 0xffffffff ||
      h.getUint16(34, true) !== 0 ||
      next > directoryOffset + directorySize ||
      inflated > MAX_ZIP_SINGLE_UNCOMPRESSED_BYTES ||
      (method === 0 && compressed !== inflated) ||
      (compressed === 0 && inflated !== 0) ||
      inflated > compressed * MAX_ZIP_COMPRESSION_RATIO
    ) {
      return "FILE_VALIDATION_FAILED";
    }
    const nameBytes = await readAt(file, cursor + 46, nameLen);
    let name: string;
    try {
      name = decoder.decode(nameBytes).split("\\").join("/").toLowerCase();
    } catch {
      return "FILE_VALIDATION_FAILED";
    }
    if (
      !name ||
      name.startsWith("/") ||
      name.includes("\0") ||
      name.split("/").includes("..") ||
      names.has(name)
    ) {
      return "FILE_VALIDATION_FAILED";
    }
    if (
      name.endsWith("/vbaproject.bin") ||
      name.endsWith("/vbadata.xml") ||
      name.includes("activex/") ||
      BLOCKED_ZIP_NAMES.test(name)
    ) {
      return "FILE_TYPE_NOT_ALLOWED";
    }
    const local = await readAt(file, localOffset, 30);
    const lv = new DataView(local.buffer, local.byteOffset, local.byteLength);
    if (
      lv.getUint32(0, true) !== 0x04034b50 ||
      lv.getUint16(6, true) !== flags ||
      lv.getUint16(8, true) !== method ||
      lv.getUint16(26, true) !== nameLen
    ) {
      return "FILE_VALIDATION_FAILED";
    }
    const localName = await readAt(file, localOffset + 30, nameLen);
    if (nameBytes.some((v, i) => localName[i] !== v)) {
      return "FILE_VALIDATION_FAILED";
    }
    const dataStart = localOffset + 30 + nameLen + lv.getUint16(28, true);
    if (dataStart + compressed > directoryOffset) {
      return "FILE_VALIDATION_FAILED";
    }
    inflatedTotal += inflated;
    if (inflatedTotal > MAX_ZIP_UNCOMPRESSED_BYTES) {
      return "FILE_VALIDATION_FAILED";
    }
    names.set(name, { start: dataStart, compressed, inflated, method });
    cursor = next;
  }
  if (cursor !== directoryOffset + directorySize) {
    return "FILE_VALIDATION_FAILED";
  }
  // Reject corrupted or dishonest compressed-size metadata in any OOXML part.
  for (const entry of names.values()) {
    if (!(await verifyZipInflation(file, entry))) {
      return "FILE_VALIDATION_FAILED";
    }
  }
  const part = MAIN_PART[mime];
  if (!part || !names.has("[content_types].xml") || !names.has(part[0])) {
    return "FILE_VALIDATION_FAILED";
  }
  const content = await readZipText(file, names.get("[content_types].xml")!);
  if (content === null) return "FILE_VALIDATION_FAILED";
  const lower = content.toLowerCase();
  if (
    lower.includes("macroenabled") ||
    lower.includes("application/vnd.ms-office.vbaproject") ||
    lower.includes("activex")
  ) {
    return "FILE_TYPE_NOT_ALLOWED";
  }
  if (!lower.includes(part[0]) || !lower.includes(part[1])) {
    return "FILE_VALIDATION_FAILED";
  }
  return null;
}

/**
 * The async source is capped before writing and every chunk is hashed.
 * <=50 MiB inputs use the unchanged existing deep checker.
 * >50 MiB inputs are validated directly from a seekable tempfile.
 */
export async function validateTaskFileStream(
  input: ValidationInput,
): Promise<FileValidationResult> {
  const nameParts = input.originalName.toLowerCase().trim().split(".");
  const extension = nameParts[nameParts.length - 1] ?? "";
  if (!EXTENSIONS[input.declaredMimeType]?.includes(extension)) {
    await input.stream.cancel().catch(() => {});
    return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
  }
  if (!Number.isSafeInteger(input.maxBytes) || input.maxBytes <= 0) {
    await input.stream.cancel().catch(() => {});
    return { ok: false, code: "FILE_VALIDATION_FAILED" };
  }
  const maxBytes = Math.min(input.maxBytes, PHASE2_LARGE_FILE_MAX_BYTES);
  const path = await Deno.makeTempFile({ prefix: "xiaozhuwork-phase2-validate-" });
  let size = 0;
  const hash = createHash("sha256");
  let writer: Deno.FsFile | undefined;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    writer = await Deno.open(path, { write: true, truncate: true });
    reader = input.stream.getReader();
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      const bytes = item.value;
      size += bytes.length;
      if (size > maxBytes) {
        await reader.cancel().catch(() => {});
        return { ok: false, code: "FILE_VALIDATION_FAILED" };
      }
      hash.update(bytes);
      let at = 0;
      while (at < bytes.length) {
        const written = await writer.write(bytes.subarray(at));
        if (written <= 0) throw Error("tempfile write failure");
        at += written;
      }
    }
    if (!size) return { ok: false, code: "FILE_VALIDATION_FAILED" };
    writer.close();
    writer = undefined;
    const seekable = await Deno.open(path, { read: true });
    try {
      if (size <= MAX_BUFFERED_VALIDATION) {
        const bytes = await Deno.readFile(path);
        return validateTaskFile({
          bytes,
          declaredMimeType: input.declaredMimeType,
          originalName: input.originalName,
        });
      }
      const prefix = await readAt(seekable, 0, Math.min(256, size));
      if (forbiddenBinary(prefix)) {
        return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
      }
      const mime = input.declaredMimeType;
      if (mime === "application/msword") {
        const legacyDoc = await validateLegacyDoc({
          size,
          read: (offset, length) => readAt(seekable, offset, length),
        });
        if (!legacyDoc.valid) {
          return {
            ok: false,
            code: legacyDoc.reason === "active_content"
              ? "FILE_TYPE_NOT_ALLOWED"
              : "FILE_VALIDATION_FAILED",
          };
        }
      } else if (mime === "video/mp4") {
        if (
          !(await isValidH264Mp4(size, (at, length) =>
            readAt(seekable, at, length),
          ))
        ) {
          return { ok: false, code: "FILE_VALIDATION_FAILED" };
        }
      } else if (MAIN_PART[mime]) {
        if (!begins(prefix, [0x50, 0x4b, 0x03, 0x04])) {
          return { ok: false, code: "FILE_VALIDATION_FAILED" };
        }
        const failure = await validateLargeOoxml(seekable, size, mime);
        if (failure) return { ok: false, code: failure };
      } else if (
        mime.startsWith("text/") ||
        mime === "application/javascript" ||
        mime === "application/typescript" ||
        mime === "application/xml" ||
        mime === "application/json"
      ) {
        const decoder = new TextDecoder("utf-8", { fatal: true });
        const json =
          mime === "application/json" ? new StreamingJsonSyntax() : null;
        const scan = await Deno.open(path, { read: true });
        let scanned = "",
          initial = "";
        try {
          const buf = new Uint8Array(64 * 1024);
          while (true) {
            const n = await scan.read(buf);
            if (n === null) break;
            const chunk = decoder.decode(buf.subarray(0, n), { stream: true });
            if (json) json.feed(chunk);
            scanned = (scanned + chunk).slice(-1024);
            if (initial.length < 64) {
              initial = (initial + chunk)
                .replace(/^\uFEFF/, "")
                .trimStart()
                .slice(0, 64);
            }
            const start = initial.toLowerCase();
            if (
              start.startsWith("<!doctype html") ||
              start.startsWith("<html") ||
              start.startsWith("<svg")
            ) {
              return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
            }
            if (/<svg(?:\s|>)/i.test(scanned)) {
              return { ok: false, code: "FILE_TYPE_NOT_ALLOWED" };
            }
          }
          const end = decoder.decode();
          if (json) {
            if (end) json.feed(end);
            if (!json.finish()) {
              return { ok: false, code: "FILE_VALIDATION_FAILED" };
            }
          }
          if (
            (mime === "application/xml" || mime === "text/xml") &&
            !initial.startsWith("<")
          ) {
            return { ok: false, code: "FILE_VALIDATION_FAILED" };
          }
        } catch {
          return { ok: false, code: "FILE_VALIDATION_FAILED" };
        } finally {
          scan.close();
        }
      } else if (!isAllowedBinarySignature(prefix, mime)) {
        return { ok: false, code: "FILE_VALIDATION_FAILED" };
      }
      return {
        ok: true,
        mimeType: input.declaredMimeType,
        sizeBytes: size,
        sha256Hex: hash.digest("hex"),
      };
    } finally {
      seekable.close();
    }
  } finally {
    if (reader) {
      try {
        reader.releaseLock();
      } catch {
        /* stream failed */
      }
    }
    if (writer) {
      try {
        writer.close();
      } catch {
        /* stream failed */
      }
    }
    await Deno.remove(path).catch(() => {});
  }
}
