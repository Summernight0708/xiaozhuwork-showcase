export interface LegacyDocByteSource {
  readonly size: number;
  read(offset: number, length: number): Promise<Uint8Array>;
}

export type LegacyDocFailureReason =
  | "invalid_container"
  | "invalid_word_document"
  | "active_content"
  | "unsupported_encryption";

export type LegacyDocValidationResult =
  { valid: true } | { valid: false; reason: LegacyDocFailureReason };

const CFB_SIGNATURE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1] as const;
const FREE_SECTOR = 0xffffffff;
const END_OF_CHAIN = 0xfffffffe;
const FAT_SECTOR = 0xfffffffd;
const DIFAT_SECTOR = 0xfffffffc;
const MAX_REGULAR_SECTOR = 0xfffffffa;
const MAX_LEGACY_DOC_BYTES = 209_715_200;
const MAX_DIRECTORY_ENTRIES = 4096;
const MAX_DIRECTORY_BYTES = MAX_DIRECTORY_ENTRIES * 128;
const MAX_DIFAT_SECTORS = 256;
const MAX_FAT_SECTORS = 4096;
const MAX_RANDOM_READS = 16_000;
const MAX_MINI_FAT_BYTES = 4 * 1024 * 1024;
const MINI_SECTOR_SIZE = 64;
const MINI_STREAM_CUTOFF = 4096;

type DirectoryEntry = {
  id: number;
  name: string;
  type: number;
  color: number;
  left: number;
  right: number;
  child: number;
  startSector: number;
  size: number;
};

class LegacyDocError extends Error {
  constructor(readonly reason: LegacyDocFailureReason) {
    super(reason);
  }
}

function reject(reason: LegacyDocFailureReason): never {
  throw new LegacyDocError(reason);
}

function isSpecialSector(value: number) {
  return (
    value === FREE_SECTOR ||
    value === END_OF_CHAIN ||
    value === FAT_SECTOR ||
    value === DIFAT_SECTOR
  );
}

function isValidSectorId(value: number, sectorCount: number) {
  return value >= 0 && value < sectorCount && value <= MAX_REGULAR_SECTOR;
}

async function readExact(
  source: LegacyDocByteSource,
  offset: number,
  length: number,
): Promise<Uint8Array> {
  if (
    !Number.isSafeInteger(offset) ||
    !Number.isSafeInteger(length) ||
    offset < 0 ||
    length < 0 ||
    offset + length > source.size ||
    !Number.isSafeInteger(offset + length)
  ) {
    reject("invalid_container");
  }
  const result = await source.read(offset, length);
  if (!(result instanceof Uint8Array) || result.length !== length) {
    reject("invalid_container");
  }
  return result;
}

function chainFor(
  start: number,
  expectedCount: number | null,
  fat: readonly number[],
  sectorCount: number,
  allocated: Set<number>,
): number[] {
  if (expectedCount === 0) {
    if (start !== END_OF_CHAIN && start !== FREE_SECTOR) {
      reject("invalid_container");
    }
    return [];
  }
  if (!isValidSectorId(start, sectorCount)) reject("invalid_container");

  const chain: number[] = [];
  const seen = new Set<number>();
  let current = start;
  while (current !== END_OF_CHAIN) {
    if (
      !isValidSectorId(current, sectorCount) ||
      current >= fat.length ||
      seen.has(current) ||
      allocated.has(current)
    ) {
      reject("invalid_container");
    }
    seen.add(current);
    allocated.add(current);
    chain.push(current);
    if (chain.length > sectorCount) reject("invalid_container");
    const next = fat[current];
    if (next === undefined) reject("invalid_container");
    if (next === END_OF_CHAIN) {
      current = END_OF_CHAIN;
    } else if (isValidSectorId(next, sectorCount)) {
      current = next;
    } else {
      reject("invalid_container");
    }
  }
  if (expectedCount !== null && chain.length !== expectedCount) {
    reject("invalid_container");
  }
  return chain;
}

function chainBytes(
  chunks: readonly Uint8Array[],
  maxBytes: number,
): Uint8Array {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  if (total <= 0 || total > maxBytes) reject("invalid_container");
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

function decodeDirectoryName(
  bytes: Uint8Array,
  offset: number,
  nameLength: number,
) {
  if (nameLength < 2 || nameLength > 64 || nameLength % 2 !== 0) {
    reject("invalid_container");
  }
  if (
    bytes[offset + nameLength - 2] !== 0 ||
    bytes[offset + nameLength - 1] !== 0
  ) {
    reject("invalid_container");
  }
  try {
    const decoded = new TextDecoder("utf-16le", { fatal: true }).decode(
      bytes.subarray(offset, offset + nameLength - 2),
    );
    if (decoded.includes("\u0000")) reject("invalid_container");
    return decoded;
  } catch {
    reject("invalid_container");
  }
}

function parseDirectory(directoryBytes: Uint8Array): DirectoryEntry[] {
  if (
    directoryBytes.length % 128 !== 0 ||
    directoryBytes.length > MAX_DIRECTORY_BYTES
  ) {
    reject("invalid_container");
  }
  const view = new DataView(
    directoryBytes.buffer,
    directoryBytes.byteOffset,
    directoryBytes.byteLength,
  );
  const entries: DirectoryEntry[] = [];
  const names = new Set<string>();
  for (
    let offset = 0, id = 0;
    offset < directoryBytes.length;
    offset += 128, id += 1
  ) {
    const type = directoryBytes[offset + 66];
    if (type === 0) {
      entries.push({
        id,
        name: "",
        type,
        color: 0,
        left: FREE_SECTOR,
        right: FREE_SECTOR,
        child: FREE_SECTOR,
        startSector: FREE_SECTOR,
        size: 0,
      });
      continue;
    }
    if (type !== 1 && type !== 2 && type !== 5) reject("invalid_container");
    const nameLength = view.getUint16(offset + 64, true);
    const name = decodeDirectoryName(directoryBytes, offset, nameLength);
    const key = name.normalize("NFC").toLocaleLowerCase("en-US");
    if (!key || names.has(key)) reject("invalid_container");
    names.add(key);

    const sizeBig = view.getBigUint64(offset + 120, true);
    if (
      sizeBig > BigInt(MAX_LEGACY_DOC_BYTES) ||
      sizeBig > BigInt(Number.MAX_SAFE_INTEGER)
    ) {
      reject("invalid_container");
    }
    if (view.getUint32(offset + 124, true) !== 0) {
      // Word 97–2003 CFB streams use the v3 32-bit stream-size field.
      reject("invalid_container");
    }
    entries.push({
      id,
      name,
      type,
      color: directoryBytes[offset + 67] ?? 0,
      left: view.getUint32(offset + 68, true),
      right: view.getUint32(offset + 72, true),
      child: view.getUint32(offset + 76, true),
      startSector: view.getUint32(offset + 116, true),
      size: Number(sizeBig),
    });
  }
  const root = entries[0];
  if (
    entries.length < 3 ||
    !root ||
    root.type !== 5 ||
    root.name !== "Root Entry"
  ) {
    reject("invalid_container");
  }
  if (root.left !== FREE_SECTOR || root.right !== FREE_SECTOR) {
    reject("invalid_container");
  }
  return entries;
}

function rejectActiveContent(entries: readonly DirectoryEntry[]) {
  const blocked =
    /^(?:vba(?:\d+)?|_vba_project(?:_cur)?|project(?:wm)?|objectpool|ole10native|olepres\d*|ole|compobj|objinfo|package|contents|dir|activex|control\d*|macros?)$/i;
  for (const entry of entries) {
    if (entry.type === 0) continue;
    const normalized =
      entry.name.charCodeAt(0) === 1 ? entry.name.slice(1) : entry.name;
    if (blocked.test(normalized)) reject("active_content");
    if (entry.type === 1 && entry.id !== 0) {
      // Nested storages are unnecessary for plain Word text and may hide embedded OLE.
      reject("active_content");
    }
  }
}

function reachableStreams(
  entries: readonly DirectoryEntry[],
): DirectoryEntry[] {
  const root = entries[0];
  if (!root) reject("invalid_container");
  const reachable = new Set<number>();
  const stack = root.child === FREE_SECTOR ? [] : [root.child];
  while (stack.length) {
    const id = stack.pop()!;
    if (!Number.isSafeInteger(id) || id < 0 || id >= entries.length) {
      reject("invalid_container");
    }
    if (reachable.has(id)) reject("invalid_container");
    const entry = entries[id];
    if (!entry) reject("invalid_container");
    if (entry.type !== 2 || entry.child !== FREE_SECTOR) {
      reject(entry.type === 1 ? "active_content" : "invalid_container");
    }
    if (entry.color !== 0 && entry.color !== 1) reject("invalid_container");
    reachable.add(id);
    if (entry.right !== FREE_SECTOR) stack.push(entry.right);
    if (entry.left !== FREE_SECTOR) stack.push(entry.left);
  }

  for (const entry of entries) {
    if (entry.type === 0 || entry.id === 0) continue;
    if (entry.type !== 2 || !reachable.has(entry.id)) {
      reject(entry.type === 1 ? "active_content" : "invalid_container");
    }
    for (const pointer of [entry.left, entry.right, entry.child]) {
      if (
        pointer !== FREE_SECTOR &&
        (pointer < 0 || pointer >= entries.length)
      ) {
        reject("invalid_container");
      }
    }
  }
  return entries.filter((entry) => entry.type === 2);
}

export async function validateLegacyDoc(
  source: LegacyDocByteSource,
): Promise<LegacyDocValidationResult> {
  try {
    if (
      !Number.isSafeInteger(source.size) ||
      source.size < 512 ||
      source.size > MAX_LEGACY_DOC_BYTES
    ) {
      reject("invalid_container");
    }
    let randomReadCount = 0;
    const boundedSource: LegacyDocByteSource = {
      size: source.size,
      read: async (offset, length) => {
        randomReadCount += 1;
        if (randomReadCount > MAX_RANDOM_READS) reject("invalid_container");
        return await source.read(offset, length);
      },
    };
    const header = await readExact(boundedSource, 0, 512);
    if (!CFB_SIGNATURE.every((byte, index) => header[index] === byte)) {
      reject("invalid_container");
    }
    const headerView = new DataView(
      header.buffer,
      header.byteOffset,
      header.byteLength,
    );
    const majorVersion = headerView.getUint16(26, true);
    const byteOrder = headerView.getUint16(28, true);
    const sectorShift = headerView.getUint16(30, true);
    const miniSectorShift = headerView.getUint16(32, true);
    if (
      byteOrder !== 0xfffe ||
      miniSectorShift !== 6 ||
      !(
        (majorVersion === 3 && sectorShift === 9) ||
        (majorVersion === 4 && sectorShift === 12)
      )
    ) {
      reject("invalid_container");
    }
    const sectorSize = 1 << sectorShift;
    const headerSize = sectorSize;
    if (
      source.size < headerSize + sectorSize ||
      (source.size - headerSize) % sectorSize !== 0
    ) {
      reject("invalid_container");
    }
    if (majorVersion === 4 && headerView.getUint32(40, true) === 0) {
      reject("invalid_container");
    }
    if (majorVersion === 3 && headerView.getUint32(40, true) !== 0) {
      reject("invalid_container");
    }

    const sectorCount = (source.size - headerSize) / sectorSize;
    if (!Number.isSafeInteger(sectorCount) || sectorCount <= 0) {
      reject("invalid_container");
    }
    const numFatSectors = headerView.getUint32(44, true);
    const firstDirectorySector = headerView.getUint32(48, true);
    const miniCutoff = headerView.getUint32(56, true);
    const firstMiniFatSector = headerView.getUint32(60, true);
    const numMiniFatSectors = headerView.getUint32(64, true);
    const firstDifatSector = headerView.getUint32(68, true);
    const numDifatSectors = headerView.getUint32(72, true);
    if (
      numFatSectors < 1 ||
      numFatSectors > Math.min(sectorCount, MAX_FAT_SECTORS) ||
      numMiniFatSectors > Math.floor(MAX_MINI_FAT_BYTES / sectorSize) ||
      miniCutoff !== MINI_STREAM_CUTOFF ||
      numDifatSectors > Math.min(MAX_DIFAT_SECTORS, sectorCount) ||
      numMiniFatSectors > sectorCount
    ) {
      reject("invalid_container");
    }
    if (
      (numDifatSectors === 0 &&
        firstDifatSector !== END_OF_CHAIN &&
        firstDifatSector !== FREE_SECTOR) ||
      (numDifatSectors > 0 &&
        !isValidSectorId(firstDifatSector, sectorCount)) ||
      (numMiniFatSectors === 0 &&
        firstMiniFatSector !== END_OF_CHAIN &&
        firstMiniFatSector !== FREE_SECTOR) ||
      (numMiniFatSectors > 0 &&
        !isValidSectorId(firstMiniFatSector, sectorCount))
    ) {
      reject("invalid_container");
    }

    const difat = new Set<number>();
    const fatSectorIds: number[] = [];
    for (let index = 0; index < 109; index += 1) {
      const sectorId = headerView.getUint32(76 + index * 4, true);
      if (sectorId === FREE_SECTOR) continue;
      if (!isValidSectorId(sectorId, sectorCount) || difat.has(sectorId)) {
        reject("invalid_container");
      }
      difat.add(sectorId);
      fatSectorIds.push(sectorId);
    }
    let nextDifat = firstDifatSector;
    const difatSectorsSeen = new Set<number>();
    const difatEntriesPerSector = sectorSize / 4 - 1;
    for (let count = 0; count < numDifatSectors; count += 1) {
      if (
        !isValidSectorId(nextDifat, sectorCount) ||
        difatSectorsSeen.has(nextDifat) ||
        difat.has(nextDifat)
      ) {
        reject("invalid_container");
      }
      difatSectorsSeen.add(nextDifat);
      const sector = await readExact(
        boundedSource,
        headerSize + nextDifat * sectorSize,
        sectorSize,
      );
      const view = new DataView(
        sector.buffer,
        sector.byteOffset,
        sector.byteLength,
      );
      for (let index = 0; index < difatEntriesPerSector; index += 1) {
        const sectorId = view.getUint32(index * 4, true);
        if (sectorId === FREE_SECTOR) continue;
        if (!isValidSectorId(sectorId, sectorCount) || difat.has(sectorId)) {
          reject("invalid_container");
        }
        difat.add(sectorId);
        fatSectorIds.push(sectorId);
      }
      nextDifat = view.getUint32(sectorSize - 4, true);
      if (
        count + 1 < numDifatSectors &&
        !isValidSectorId(nextDifat, sectorCount)
      ) {
        reject("invalid_container");
      }
    }
    if (
      (numDifatSectors > 0 && nextDifat !== END_OF_CHAIN) ||
      fatSectorIds.length !== numFatSectors ||
      new Set(fatSectorIds).size !== fatSectorIds.length ||
      fatSectorIds.some((id) => difatSectorsSeen.has(id))
    ) {
      reject("invalid_container");
    }

    const fatChunks: Uint8Array[] = [];
    for (const sectorId of fatSectorIds) {
      fatChunks.push(
        await readExact(
          boundedSource,
          headerSize + sectorId * sectorSize,
          sectorSize,
        ),
      );
    }
    const fatBytes = chainBytes(fatChunks, MAX_LEGACY_DOC_BYTES);
    const fatView = new DataView(
      fatBytes.buffer,
      fatBytes.byteOffset,
      fatBytes.byteLength,
    );
    const fat: number[] = [];
    for (let offset = 0; offset < fatBytes.length; offset += 4) {
      fat.push(fatView.getUint32(offset, true));
    }
    if (fat.length < sectorCount) reject("invalid_container");
    for (const sectorId of fatSectorIds) {
      if (fat[sectorId] !== FAT_SECTOR) reject("invalid_container");
    }
    for (const sectorId of difatSectorsSeen) {
      if (fat[sectorId] !== DIFAT_SECTOR) reject("invalid_container");
    }
    for (let id = 0; id < sectorCount; id += 1) {
      const value = fat[id];
      if (
        value === undefined ||
        (!isSpecialSector(value) && !isValidSectorId(value, sectorCount))
      ) {
        reject("invalid_container");
      }
    }

    const allocatedSectors = new Set<number>([
      ...fatSectorIds,
      ...difatSectorsSeen,
    ]);
    const readSector = (sectorId: number) =>
      readExact(boundedSource, headerSize + sectorId * sectorSize, sectorSize);
    const directoryChain = chainFor(
      firstDirectorySector,
      majorVersion === 4 ? headerView.getUint32(40, true) : null,
      fat,
      sectorCount,
      allocatedSectors,
    );
    const directoryChunks: Uint8Array[] = [];
    for (const sectorId of directoryChain) {
      directoryChunks.push(await readSector(sectorId));
    }
    const directoryBytes = chainBytes(directoryChunks, MAX_DIRECTORY_BYTES);
    const entries = parseDirectory(directoryBytes);
    rejectActiveContent(entries);
    const streams = reachableStreams(entries);
    const root = entries[0];
    if (!root) reject("invalid_container");
    if (
      root.size > MAX_LEGACY_DOC_BYTES ||
      (root.size === 0 &&
        root.startSector !== END_OF_CHAIN &&
        root.startSector !== FREE_SECTOR)
    ) {
      reject("invalid_container");
    }

    const miniFat: number[] = [];
    if (numMiniFatSectors > 0) {
      const miniFatChain = chainFor(
        firstMiniFatSector,
        numMiniFatSectors,
        fat,
        sectorCount,
        allocatedSectors,
      );
      const miniFatChunks: Uint8Array[] = [];
      for (const sectorId of miniFatChain) {
        miniFatChunks.push(await readSector(sectorId));
      }
      const miniFatBytes = chainBytes(miniFatChunks, MAX_MINI_FAT_BYTES);
      const miniFatView = new DataView(
        miniFatBytes.buffer,
        miniFatBytes.byteOffset,
        miniFatBytes.byteLength,
      );
      for (let offset = 0; offset < miniFatBytes.length; offset += 4) {
        miniFat.push(miniFatView.getUint32(offset, true));
      }
    }

    const rootMiniChain =
      root.size > 0
        ? chainFor(
            root.startSector,
            Math.ceil(root.size / sectorSize),
            fat,
            sectorCount,
            allocatedSectors,
          )
        : [];
    const miniSectorCapacity = Math.ceil(root.size / MINI_SECTOR_SIZE);
    const allocatedMiniSectors = new Set<number>();
    const streamChains = new Map<number, number[]>();
    for (const stream of streams) {
      if (stream.size === 0) {
        if (
          stream.startSector !== END_OF_CHAIN &&
          stream.startSector !== FREE_SECTOR
        ) {
          reject("invalid_container");
        }
        streamChains.set(stream.id, []);
      } else if (stream.size >= miniCutoff) {
        streamChains.set(
          stream.id,
          chainFor(
            stream.startSector,
            Math.ceil(stream.size / sectorSize),
            fat,
            sectorCount,
            allocatedSectors,
          ),
        );
      } else {
        if (miniFat.length === 0) reject("invalid_container");
        const miniChain: number[] = [];
        const miniSeen = new Set<number>();
        let current = stream.startSector;
        const expected = Math.ceil(stream.size / MINI_SECTOR_SIZE);
        while (current !== END_OF_CHAIN) {
          if (
            !Number.isSafeInteger(current) ||
            current < 0 ||
            current >= miniFat.length ||
            current >= miniSectorCapacity ||
            miniSeen.has(current) ||
            allocatedMiniSectors.has(current)
          ) {
            reject("invalid_container");
          }
          miniSeen.add(current);
          allocatedMiniSectors.add(current);
          miniChain.push(current);
          if (miniChain.length > expected) reject("invalid_container");
          const next = miniFat[current];
          if (next === undefined) reject("invalid_container");
          if (next === END_OF_CHAIN) current = END_OF_CHAIN;
          else if (
            Number.isSafeInteger(next) &&
            next >= 0 &&
            next < miniFat.length
          ) {
            current = next;
          } else {
            reject("invalid_container");
          }
        }
        if (miniChain.length !== expected) reject("invalid_container");
        streamChains.set(stream.id, miniChain);
      }
    }

    const readRegularRange = async (
      chain: readonly number[],
      streamSize: number,
      offset: number,
      length: number,
    ) => {
      if (offset < 0 || length < 0 || offset + length > streamSize) {
        reject("invalid_container");
      }
      const output = new Uint8Array(length);
      let copied = 0;
      while (copied < length) {
        const absolute = offset + copied;
        const chainIndex = Math.floor(absolute / sectorSize);
        const withinSector = absolute % sectorSize;
        const amount = Math.min(length - copied, sectorSize - withinSector);
        if (chainIndex >= chain.length) reject("invalid_container");
        const sectorId = chain[chainIndex];
        if (sectorId === undefined) reject("invalid_container");
        const sector = await readSector(sectorId);
        output.set(
          sector.subarray(withinSector, withinSector + amount),
          copied,
        );
        copied += amount;
      }
      return output;
    };
    const readMiniRange = async (
      chain: readonly number[],
      streamSize: number,
      offset: number,
      length: number,
    ) => {
      if (offset < 0 || length < 0 || offset + length > streamSize) {
        reject("invalid_container");
      }
      const output = new Uint8Array(length);
      let copied = 0;
      while (copied < length) {
        const absolute = offset + copied;
        const miniIndex = Math.floor(absolute / MINI_SECTOR_SIZE);
        const withinMini = absolute % MINI_SECTOR_SIZE;
        const amount = Math.min(length - copied, MINI_SECTOR_SIZE - withinMini);
        if (miniIndex >= chain.length) reject("invalid_container");
        const rootMiniSector = chain[miniIndex];
        if (rootMiniSector === undefined) reject("invalid_container");
        const rootOffset = rootMiniSector * MINI_SECTOR_SIZE + withinMini;
        if (rootOffset + amount > root.size) reject("invalid_container");
        const chunk = await readRegularRange(
          rootMiniChain,
          root.size,
          rootOffset,
          amount,
        );
        output.set(chunk, copied);
        copied += amount;
      }
      return output;
    };

    const readStream = async (
      entry: DirectoryEntry,
      offset: number,
      length: number,
    ) => {
      const chain = streamChains.get(entry.id);
      if (!chain) reject("invalid_container");
      if (entry.size < miniCutoff) {
        return readMiniRange(chain, entry.size, offset, length);
      }
      return readRegularRange(chain, entry.size, offset, length);
    };

    const wordStreams = streams.filter(
      (entry) => entry.name === "WordDocument",
    );
    const word = wordStreams[0];
    if (wordStreams.length !== 1 || !word || word.size < 512) {
      reject("invalid_word_document");
    }
    const fib = await readStream(word, 0, 512);
    const fibView = new DataView(fib.buffer, fib.byteOffset, fib.byteLength);
    if (fibView.getUint16(0, true) !== 0xa5ec) reject("invalid_word_document");
    const nFib = fibView.getUint16(2, true);
    if (![0x00c1, 0x00d9, 0x0101, 0x010c].includes(nFib)) {
      reject("invalid_word_document");
    }
    const flags = fibView.getUint16(10, true);
    if ((flags & (1 << 8)) !== 0 || (flags & (1 << 15)) !== 0) {
      reject("unsupported_encryption");
    }
    const cbMac = fibView.getUint32(64, true);
    const ccpOffsets = [76, 80, 84, 88, 92, 96, 100, 104];
    const characterCounts = ccpOffsets.map((offset) =>
      fibView.getUint32(offset, true),
    );
    const characterTotal = characterCounts.reduce(
      (sum, count) => sum + count,
      0,
    );
    if (
      cbMac < 512 ||
      cbMac > word.size ||
      !Number.isSafeInteger(characterTotal) ||
      characterTotal > word.size
    ) {
      reject("invalid_word_document");
    }

    const tableName = (flags & (1 << 9)) !== 0 ? "1Table" : "0Table";
    const tableStreams = streams.filter((entry) => entry.name === tableName);
    const tableStream = tableStreams[0];
    if (tableStreams.length !== 1 || !tableStream || tableStream.size === 0) {
      reject("invalid_word_document");
    }
    await readStream(tableStream, 0, Math.min(1, tableStream.size));

    return { valid: true };
  } catch (error) {
    if (error instanceof LegacyDocError) {
      return { valid: false, reason: error.reason };
    }
    return { valid: false, reason: "invalid_container" };
  }
}
