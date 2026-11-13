import { describe, expect, it, vi } from "vitest";

import { validateTaskFile } from "../../supabase/functions/_shared/file-validation";
import { validateTaskFileStream } from "../../supabase/functions/_shared/file-stream-validation";

import {
  type LegacyDocByteSource,
  validateLegacyDoc,
} from "../../supabase/functions/_shared/legacy-doc-validation";

const FREE_SECTOR = 0xffffffff;
const END_OF_CHAIN = 0xfffffffe;
const FAT_SECTOR = 0xfffffffd;
const SECTOR_SIZE = 512;
const HEADER_SIZE = 512;

function makeSource(bytes: Uint8Array): LegacyDocByteSource {
  return {
    size: bytes.length,
    read: async (offset, length) => bytes.slice(offset, offset + length),
  };
}
function makeDenoMock() {
  const files = new Map<string, Uint8Array>();
  return {
    makeTempFile: async () => "legacy-doc-temp",
    open: async (
      path: string,
      options: { read?: boolean; write?: boolean; truncate?: boolean },
    ) => {
      if (options.write) {
        const chunks: Uint8Array[] = [];
        return {
          write: async (chunk: Uint8Array) => {
            chunks.push(chunk.slice());
            return chunk.length;
          },
          close: () => {
            const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
            const joined = new Uint8Array(total);
            let offset = 0;
            for (const chunk of chunks) {
              joined.set(chunk, offset);
              offset += chunk.length;
            }
            files.set(path, joined);
          },
        };
      }
      const content = files.get(path) ?? new Uint8Array();
      let position = 0;
      return {
        seek: async (offset: number) => {
          position = offset;
        },
        read: async (target: Uint8Array) => {
          if (position >= content.length) return null;
          const count = Math.min(target.length, content.length - position);
          target.set(content.subarray(position, position + count));
          position += count;
          return count;
        },
        close: () => {},
      };
    },
    readFile: async (path: string) =>
      files.get(path)?.slice() ?? new Uint8Array(),
    remove: async (path: string) => {
      files.delete(path);
    },
  };
}

function writeDirectoryEntry(
  bytes: Uint8Array,
  sectorId: number,
  entryIndex: number,
  name: string,
  type: number,
  left: number,
  right: number,
  child: number,
  startSector: number,
  size: number,
) {
  const offset = HEADER_SIZE + sectorId * SECTOR_SIZE + entryIndex * 128;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const encodedName = new TextEncoder().encode(
    name
      .split("")
      .map((char) => char + "\0")
      .join("") + "\0\0",
  );
  bytes.set(encodedName.subarray(0, 64), offset);
  view.setUint16(offset + 64, Math.min(encodedName.length, 64), true);
  bytes[offset + 66] = type;
  bytes[offset + 67] = 1;
  view.setUint32(offset + 68, left, true);
  view.setUint32(offset + 72, right, true);
  view.setUint32(offset + 76, child, true);
  view.setUint32(offset + 116, startSector, true);
  view.setUint32(offset + 120, size, true);
}

function buildLegacyDoc(
  options: {
    activeEntry?: string;
    corruptFib?: boolean;
    cyclicFat?: boolean;
    encrypted?: boolean;
    miniTable?: boolean;
    missingTable?: boolean;
    truncated?: boolean;
    badFatCount?: boolean;
  } = {},
) {
  // One FAT sector, one directory sector, and two eight-sector regular streams.
  const sectorCount = 18;
  const bytes = new Uint8Array(HEADER_SIZE + sectorCount * SECTOR_SIZE);
  const view = new DataView(bytes.buffer);
  bytes.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1], 0);
  view.setUint16(24, 0x003e, true);
  view.setUint16(26, 3, true);
  view.setUint16(28, 0xfffe, true);
  view.setUint16(30, 9, true);
  view.setUint16(32, 6, true);
  view.setUint32(40, 0, true);
  view.setUint32(44, options.badFatCount ? 0xffffffff : 1, true);
  view.setUint32(48, 1, true);
  view.setUint32(56, 4096, true);
  view.setUint32(60, options.miniTable ? 11 : END_OF_CHAIN, true);
  view.setUint32(64, options.miniTable ? 1 : 0, true);
  view.setUint32(68, END_OF_CHAIN, true);
  view.setUint32(72, 0, true);
  for (let index = 0; index < 109; index += 1) {
    view.setUint32(76 + index * 4, FREE_SECTOR, true);
  }
  view.setUint32(76, 0, true);

  const fatOffset = HEADER_SIZE;
  const fat = new DataView(bytes.buffer, fatOffset, SECTOR_SIZE);
  for (let index = 0; index < 128; index += 1) {
    fat.setUint32(index * 4, FREE_SECTOR, true);
  }
  fat.setUint32(0, FAT_SECTOR, true);
  fat.setUint32(4, END_OF_CHAIN, true);
  for (let sector = 2; sector < 9; sector += 1) {
    fat.setUint32(
      sector * 4,
      options.cyclicFat && sector === 2 ? 2 : sector + 1,
      true,
    );
  }
  fat.setUint32(9 * 4, END_OF_CHAIN, true);
  for (let sector = 10; sector < 17; sector += 1) {
    fat.setUint32(sector * 4, sector + 1, true);
  }
  fat.setUint32(17 * 4, END_OF_CHAIN, true);
  if (options.miniTable) {
    for (let sector = 10; sector < 18; sector += 1) {
      fat.setUint32(sector * 4, FREE_SECTOR, true);
    }
    fat.setUint32(10 * 4, END_OF_CHAIN, true);
    fat.setUint32(11 * 4, END_OF_CHAIN, true);
    const miniFat = new DataView(
      bytes.buffer,
      HEADER_SIZE + 11 * SECTOR_SIZE,
      SECTOR_SIZE,
    );
    for (let index = 0; index < 128; index += 1) {
      miniFat.setUint32(index * 4, FREE_SECTOR, true);
    }
    miniFat.setUint32(0, END_OF_CHAIN, true);
  }

  writeDirectoryEntry(
    bytes,
    1,
    0,
    "Root Entry",
    5,
    FREE_SECTOR,
    FREE_SECTOR,
    1,
    options.miniTable ? 10 : END_OF_CHAIN,
    options.miniTable ? 64 : 0,
  );
  writeDirectoryEntry(
    bytes,
    1,
    1,
    "WordDocument",
    2,
    2,
    FREE_SECTOR,
    FREE_SECTOR,
    2,
    4096,
  );
  if (options.missingTable) {
    writeDirectoryEntry(
      bytes,
      1,
      2,
      "0Table",
      0,
      FREE_SECTOR,
      FREE_SECTOR,
      FREE_SECTOR,
      FREE_SECTOR,
      0,
    );
  } else {
    writeDirectoryEntry(
      bytes,
      1,
      2,
      "0Table",
      2,
      FREE_SECTOR,
      FREE_SECTOR,
      FREE_SECTOR,
      options.miniTable ? 0 : 10,
      options.miniTable ? 64 : 4096,
    );
  }
  if (options.activeEntry) {
    writeDirectoryEntry(
      bytes,
      1,
      3,
      options.activeEntry,
      2,
      FREE_SECTOR,
      FREE_SECTOR,
      FREE_SECTOR,
      END_OF_CHAIN,
      0,
    );
  }

  const wordOffset = HEADER_SIZE + 2 * SECTOR_SIZE;
  const wordView = new DataView(bytes.buffer, wordOffset, 4096);
  wordView.setUint16(0, options.corruptFib ? 0 : 0xa5ec, true);
  wordView.setUint16(2, 0x00c1, true);
  wordView.setUint16(10, options.encrypted ? 1 << 8 : 0, true);
  wordView.setUint32(64, 4096, true);
  return options.truncated ? bytes.slice(0, -1) : bytes;
}

function buildLargeLegacyDocV4() {
  const sectorSize = 4096;
  const headerSize = sectorSize;
  const sectorCount = 12_800;
  const fatSectorCount = 100;
  const bytes = new Uint8Array(headerSize + sectorCount * sectorSize);
  const view = new DataView(bytes.buffer);

  bytes.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1], 0);
  view.setUint16(24, 0x003e, true);
  view.setUint16(26, 4, true);
  view.setUint16(28, 0xfffe, true);
  view.setUint16(30, 12, true);
  view.setUint16(32, 6, true);
  view.setUint32(40, 1, true);
  view.setUint32(44, fatSectorCount, true);
  view.setUint32(48, 100, true);
  view.setUint32(56, 4096, true);
  view.setUint32(60, END_OF_CHAIN, true);
  view.setUint32(64, 0, true);
  view.setUint32(68, END_OF_CHAIN, true);
  view.setUint32(72, 0, true);
  for (let index = 0; index < 109; index += 1) {
    view.setUint32(
      76 + index * 4,
      index < fatSectorCount ? index : FREE_SECTOR,
      true,
    );
  }

  bytes.fill(0xff, headerSize, headerSize + fatSectorCount * sectorSize);
  const fat = new DataView(
    bytes.buffer,
    headerSize,
    fatSectorCount * sectorSize,
  );
  for (let sectorId = 0; sectorId < fatSectorCount; sectorId += 1) {
    fat.setUint32(sectorId * 4, FAT_SECTOR, true);
  }
  fat.setUint32(100 * 4, END_OF_CHAIN, true);
  fat.setUint32(101 * 4, END_OF_CHAIN, true);
  fat.setUint32(102 * 4, END_OF_CHAIN, true);

  const writeEntry = (
    index: number,
    name: string,
    type: number,
    left: number,
    right: number,
    child: number,
    startSector: number,
    size: number,
  ) => {
    const offset = headerSize + 100 * sectorSize + index * 128;
    const encodedName = new TextEncoder().encode(
      name
        .split("")
        .map((char) => char + "\0")
        .join("") + "\0\0",
    );
    bytes.set(encodedName.subarray(0, 64), offset);
    view.setUint16(offset + 64, Math.min(encodedName.length, 64), true);
    bytes[offset + 66] = type;
    bytes[offset + 67] = 1;
    view.setUint32(offset + 68, left, true);
    view.setUint32(offset + 72, right, true);
    view.setUint32(offset + 76, child, true);
    view.setUint32(offset + 116, startSector, true);
    view.setUint32(offset + 120, size, true);
    view.setUint32(offset + 124, 0, true);
  };

  writeEntry(0, "Root Entry", 5, FREE_SECTOR, FREE_SECTOR, 1, END_OF_CHAIN, 0);
  writeEntry(1, "WordDocument", 2, 2, FREE_SECTOR, FREE_SECTOR, 101, 4096);
  writeEntry(2, "0Table", 2, FREE_SECTOR, FREE_SECTOR, FREE_SECTOR, 102, 4096);

  const wordView = new DataView(
    bytes.buffer,
    headerSize + 101 * sectorSize,
    sectorSize,
  );
  wordView.setUint16(0, 0xa5ec, true);
  wordView.setUint16(2, 0x00c1, true);
  wordView.setUint16(10, 0, true);
  wordView.setUint32(64, 4096, true);
  return bytes;
}

describe("legacy Word DOC structural validation", () => {
  it("accepts a structurally valid Word 97 CFB document", async () => {
    expect(await validateLegacyDoc(makeSource(buildLegacyDoc()))).toEqual({
      valid: true,
    });
  });

  it("rejects a file with only the CFB signature and no valid directory/FIB", async () => {
    const magicOnly = new Uint8Array([
      0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1,
    ]);
    expect((await validateLegacyDoc(makeSource(magicOnly))).valid).toBe(false);
  });

  it("rejects an invalid Word FIB identifier", async () => {
    expect(
      (
        await validateLegacyDoc(
          makeSource(buildLegacyDoc({ corruptFib: true })),
        )
      ).valid,
    ).toBe(false);
  });

  it("rejects cyclic FAT chains instead of looping", async () => {
    expect(
      (await validateLegacyDoc(makeSource(buildLegacyDoc({ cyclicFat: true }))))
        .valid,
    ).toBe(false);
  });

  it("validates a small Table stream stored through the mini stream", async () => {
    expect(
      await validateLegacyDoc(makeSource(buildLegacyDoc({ miniTable: true }))),
    ).toEqual({ valid: true });
  });

  it("rejects truncated sectors and impossible FAT counts", async () => {
    expect(
      await validateLegacyDoc(makeSource(buildLegacyDoc({ truncated: true }))),
    ).toMatchObject({ valid: false, reason: "invalid_container" });
    expect(
      await validateLegacyDoc(
        makeSource(buildLegacyDoc({ badFatCount: true })),
      ),
    ).toMatchObject({ valid: false, reason: "invalid_container" });
  });

  it("rejects missing table streams and ambiguous directory names", async () => {
    expect(
      (
        await validateLegacyDoc(
          makeSource(buildLegacyDoc({ missingTable: true })),
        )
      ).valid,
    ).toBe(false);
    expect(
      await validateLegacyDoc(
        makeSource(buildLegacyDoc({ activeEntry: "VBA\u0000hidden" })),
      ),
    ).toMatchObject({ valid: false, reason: "invalid_container" });
  });

  it("reports encrypted documents as unsupported instead of accepting them", async () => {
    expect(
      await validateLegacyDoc(makeSource(buildLegacyDoc({ encrypted: true }))),
    ).toMatchObject({ valid: false, reason: "unsupported_encryption" });
  });

  it.each([
    "VBA",
    "_VBA_PROJECT",
    "_VBA_PROJECT_CUR",
    "PROJECT",
    "PROJECTwm",
    "ObjectPool",
    "Ole10Native",
    "OlePres000",
    "CompObj",
    "Package",
    "ActiveX",
  ])("rejects active content entry %s", async (activeEntry) => {
    expect(
      (await validateLegacyDoc(makeSource(buildLegacyDoc({ activeEntry }))))
        .valid,
    ).toBe(false);
  });

  it("accepts a structurally valid DOC through the buffered upload validator", async () => {
    const bytes = buildLegacyDoc();
    const result = await validateTaskFile({
      bytes,
      declaredMimeType: "application/msword",
      originalName: "审核表.doc",
    });
    expect(result.ok).toBe(true);
  });

  it("rejects malformed DOC through the buffered upload validator", async () => {
    const result = await validateTaskFile({
      bytes: new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]),
      declaredMimeType: "application/msword",
      originalName: "审核表.doc",
    });
    expect(result).toMatchObject({ ok: false, code: "FILE_VALIDATION_FAILED" });
  });

  it("accepts a structurally valid DOC through the streaming upload entry point", async () => {
    const bytes = buildLegacyDoc();
    vi.stubGlobal("Deno", makeDenoMock());
    try {
      const result = await validateTaskFileStream({
        stream: new Response(bytes).body!,
        declaredMimeType: "application/msword",
        originalName: "审核表.doc",
        maxBytes: 50 * 1024 * 1024,
      });
      expect(result.ok).toBe(true);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("validates a large CFB v4 DOC through the disk-backed streaming path", async () => {
    const bytes = buildLargeLegacyDocV4();
    expect(bytes.byteLength).toBeGreaterThan(50 * 1024 * 1024);
    vi.stubGlobal("Deno", makeDenoMock());
    try {
      const result = await validateTaskFileStream({
        stream: new Response(bytes).body!,
        declaredMimeType: "application/msword",
        originalName: "大型审核表.doc",
        maxBytes: 200 * 1024 * 1024,
      });
      expect(result.ok).toBe(true);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("rejects DOC files that contain macro or embedded-object streams", async () => {
    const result = await validateTaskFile({
      bytes: buildLegacyDoc({ activeEntry: "VBA" }),
      declaredMimeType: "application/msword",
      originalName: "审核表.doc",
    });
    expect(result).toMatchObject({ ok: false, code: "FILE_TYPE_NOT_ALLOWED" });
  });
});
