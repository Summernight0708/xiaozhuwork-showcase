import { deflateRawSync } from "node:zlib";
import { describe, expect, test } from "vitest";

import {
  TASK_FILE_MAX_BYTES,
  validateTaskFile,
} from "../../supabase/functions/_shared/file-validation";

const encoder = new TextEncoder();

function bytes(text: string) {
  return encoder.encode(text);
}

function concat(...parts: Uint8Array[]) {
  const size = parts.reduce((total, part) => total + part.length, 0);
  const output = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function littleEndian(value: number, width: 2 | 4) {
  const output = new Uint8Array(width);
  const view = new DataView(output.buffer);
  if (width === 2) view.setUint16(0, value, true);
  else view.setUint32(0, value, true);
  return output;
}

function crc32(input: Uint8Array) {
  let crc = 0xffffffff;
  for (const value of input) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1)
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function storedZipEntry(name: string, content = "") {
  const nameBytes = bytes(name);
  const contentBytes = bytes(content);
  return concat(
    new Uint8Array([0x50, 0x4b, 0x03, 0x04]),
    littleEndian(20, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(crc32(contentBytes), 4),
    littleEndian(contentBytes.length, 4),
    littleEndian(contentBytes.length, 4),
    littleEndian(nameBytes.length, 2),
    littleEndian(0, 2),
    nameBytes,
    contentBytes,
  );
}

function storedZip(entries: ReadonlyArray<readonly [string, string?]>) {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let localOffset = 0;

  for (const [name, content = ""] of entries) {
    const nameBytes = bytes(name);
    const contentBytes = bytes(content);
    const local = storedZipEntry(name, content);
    localParts.push(local);
    centralParts.push(
      concat(
        new Uint8Array([0x50, 0x4b, 0x01, 0x02]),
        littleEndian(20, 2),
        littleEndian(20, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(crc32(contentBytes), 4),
        littleEndian(contentBytes.length, 4),
        littleEndian(contentBytes.length, 4),
        littleEndian(nameBytes.length, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 4),
        littleEndian(localOffset, 4),
        nameBytes,
      ),
    );
    localOffset += local.length;
  }

  const central = concat(...centralParts);
  const eocd = concat(
    new Uint8Array([0x50, 0x4b, 0x05, 0x06]),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(entries.length, 2),
    littleEndian(entries.length, 2),
    littleEndian(central.length, 4),
    littleEndian(localOffset, 4),
    littleEndian(0, 2),
  );
  return concat(...localParts, central, eocd);
}

function deflatedZip(entries: ReadonlyArray<readonly [string, string?]>) {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let localOffset = 0;

  for (const [name, content = ""] of entries) {
    const nameBytes = bytes(name);
    const contentBytes = bytes(content);
    const compressedBytes = new Uint8Array(deflateRawSync(contentBytes));
    const local = concat(
      new Uint8Array([0x50, 0x4b, 0x03, 0x04]),
      littleEndian(20, 2),
      littleEndian(0, 2),
      littleEndian(8, 2),
      littleEndian(0, 2),
      littleEndian(0, 2),
      littleEndian(crc32(contentBytes), 4),
      littleEndian(compressedBytes.length, 4),
      littleEndian(contentBytes.length, 4),
      littleEndian(nameBytes.length, 2),
      littleEndian(0, 2),
      nameBytes,
      compressedBytes,
    );
    localParts.push(local);
    centralParts.push(
      concat(
        new Uint8Array([0x50, 0x4b, 0x01, 0x02]),
        littleEndian(20, 2),
        littleEndian(20, 2),
        littleEndian(0, 2),
        littleEndian(8, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(crc32(contentBytes), 4),
        littleEndian(compressedBytes.length, 4),
        littleEndian(contentBytes.length, 4),
        littleEndian(nameBytes.length, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 2),
        littleEndian(0, 4),
        littleEndian(localOffset, 4),
        nameBytes,
      ),
    );
    localOffset += local.length;
  }

  const central = concat(...centralParts);
  const eocd = concat(
    new Uint8Array([0x50, 0x4b, 0x05, 0x06]),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(entries.length, 2),
    littleEndian(entries.length, 2),
    littleEndian(central.length, 4),
    littleEndian(localOffset, 4),
    littleEndian(0, 2),
  );
  return concat(...localParts, central, eocd);
}

describe("task file byte validation", () => {
  test("accepts supported binary signatures and computes server-side sha256", async () => {
    const pdf = concat(bytes("%PDF-1.7\n"), bytes("body"));
    const result = await validateTaskFile({
      bytes: pdf,
      declaredMimeType: "application/pdf",
      originalName: "report.pdf",
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.mimeType).toBe("application/pdf");
    expect(result.sizeBytes).toBe(pdf.length);
    expect(result.sha256Hex).toMatch(/^[0-9a-f]{64}$/);
  });

  test("accepts valid utf-8 text/json and rejects disguised html/svg/executables", async () => {
    await expect(
      validateTaskFile({
        bytes: bytes('{"ok":true}\n'),
        declaredMimeType: "application/json",
        originalName: "result.json",
      }),
    ).resolves.toMatchObject({ ok: true, mimeType: "application/json" });

    for (const [name, mimeType, content] of [
      ["page.txt", "text/plain", "<!doctype html><html></html>"],
      [
        "drawing.xml",
        "application/xml",
        '<svg xmlns="http://www.w3.org/2000/svg"/>',
      ],
      ["program.txt", "text/plain", "MZ\u0000\u0002"],
    ] as const) {
      await expect(
        validateTaskFile({
          bytes: bytes(content),
          declaredMimeType: mimeType,
          originalName: name,
        }),
      ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });
    }
  });

  test("rejects invalid utf-8, extension/mime mismatches, and oversized bytes", async () => {
    await expect(
      validateTaskFile({
        bytes: new Uint8Array([0xc3, 0x28]),
        declaredMimeType: "text/plain",
        originalName: "bad.txt",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });

    await expect(
      validateTaskFile({
        bytes: bytes("plain"),
        declaredMimeType: "text/plain",
        originalName: "plain.pdf",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });

    await expect(
      validateTaskFile({
        bytes: new Uint8Array(TASK_FILE_MAX_BYTES + 1),
        declaredMimeType: "text/plain",
        originalName: "large.txt",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });
  });

  test("rejects local-header-only fake OOXML packages", async () => {
    const fakeDocx = concat(
      storedZipEntry("[Content_Types].xml"),
      storedZipEntry("word/document.xml", "<w:document/>"),
      bytes("MZ\u0000payload"),
    );

    await expect(
      validateTaskFile({
        bytes: fakeDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "fake.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });
  });

  test("recognizes OOXML package families and rejects VBA-bearing packages", async () => {
    const docx = storedZip([
      [
        "[Content_Types].xml",
        '<?xml version="1.0"?><Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
      ],
      ["word/document.xml", "<w:document/>"],
    ]);
    await expect(
      validateTaskFile({
        bytes: docx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "essay.docx",
      }),
    ).resolves.toMatchObject({ ok: true });

    const macroDocx = storedZip([
      ["[Content_Types].xml"],
      ["word/document.xml"],
      ["word/vbaProject.bin"],
    ]);
    await expect(
      validateTaskFile({
        bytes: macroDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "macro.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });

    const macroMarkedDocx = storedZip([
      [
        "[Content_Types].xml",
        '<?xml version="1.0"?><Types><Override PartName="/word/document.xml" ContentType="application/vnd.ms-word.document.macroEnabled.main+xml"/></Types>',
      ],
      ["word/document.xml", "<w:document/>"],
    ]);
    await expect(
      validateTaskFile({
        bytes: macroMarkedDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "macro-marker.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });

    const deflatedMacroMarkedDocx = deflatedZip([
      [
        "[Content_Types].xml",
        '<?xml version="1.0"?><Types><Override PartName="/word/document.xml" ContentType="application/vnd.ms-word.document.macroEnabled.main+xml"/></Types>',
      ],
      ["word/document.xml", "<w:document/>"],
    ]);
    await expect(
      validateTaskFile({
        bytes: deflatedMacroMarkedDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "compressed-macro-marker.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });

    const emptyContentTypesDocx = storedZip([
      ["[Content_Types].xml"],
      ["word/document.xml", "<w:document/>"],
    ]);
    await expect(
      validateTaskFile({
        bytes: emptyContentTypesDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "empty-content-types.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });

    const executablePayloadDocx = storedZip([
      [
        "[Content_Types].xml",
        '<?xml version="1.0"?><Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
      ],
      ["word/document.xml", "<w:document/>"],
      ["word/media/payload.exe", "not-a-real-pe"],
    ]);
    await expect(
      validateTaskFile({
        bytes: executablePayloadDocx,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "embedded-executable.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });

    const genericZip = storedZip([["payload.bin", "data"]]);
    await expect(
      validateTaskFile({
        bytes: genericZip,
        declaredMimeType:
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        originalName: "fake.docx",
      }),
    ).resolves.toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });
  });
});
