/**
 * Strict, bounded ISO BMFF (MP4) metadata inspection for H.264/AVC files.
 * No decoder, media parser dependency, or arbitrary HTML/script execution.
 * Byte range reads allow files up to the Pro quota without buffering the video.
 */
type ReadRange = (offset: number, length: number) => Promise<Uint8Array>;
const MAX_MOOV_BYTES = 16 * 1024 * 1024;
const MAX_BOXES = 4096;
const MAX_TOP_LEVEL_BOXES = 8192;
const MAX_STSD_ENTRIES = 32;
const HEADER_BYTES = 16;
const SAFE_BRANDS = new Set([
  "mp41",
  "mp42",
  "isom",
  "iso2",
  "iso4",
  "iso5",
  "iso6",
  "avc1",
  "M4V ",
]);
const OTHER_VIDEO_CODECS = new Set([
  "hvc1",
  "hev1",
  "av01",
  "vp09",
  "mp4v",
  "encv",
]);

interface Mp4Box {
  type: string;
  start: number;
  contentStart: number;
  end: number;
}
function uint32(data: Uint8Array, i: number): number {
  return (
    (data[i]! * 16777216 +
      (data[i + 1]! << 16) +
      (data[i + 2]! << 8) +
      data[i + 3]!) >>>
    0
  );
}
function ascii(data: Uint8Array, i: number, length: number): string {
  return String.fromCharCode(...data.subarray(i, i + length));
}
function parseBox(
  data: Uint8Array,
  start: number,
  limit: number,
): Mp4Box | null {
  if (start + 8 > limit || start + 8 > data.length) return null;
  let size = uint32(data, start);
  let header = 8;
  if (size === 1) {
    if (start + 16 > limit || start + 16 > data.length) return null;
    const high = uint32(data, start + 8);
    const low = uint32(data, start + 12);
    size = high * 0x100000000 + low;
    header = 16;
  } else if (size === 0) {
    size = limit - start;
  }
  if (!Number.isSafeInteger(size) || size < header || start + size > limit)
    return null;
  const type = ascii(data, start + 4, 4);
  if (!/^[\x20-\x7e]{4}$/.test(type)) return null;
  return { type, start, contentStart: start + header, end: start + size };
}
function childBoxes(
  data: Uint8Array,
  first: number,
  end: number,
): Mp4Box[] | null {
  const result: Mp4Box[] = [];
  let pos = first;
  while (pos < end) {
    if (result.length >= MAX_BOXES) return null;
    const box = parseBox(data, pos, end);
    if (!box) return null;
    result.push(box);
    pos = box.end;
  }
  return result;
}
function h264Description(
  data: Uint8Array,
  stsd: Mp4Box,
): { h264: boolean; invalid: boolean } {
  if (stsd.contentStart + 8 > stsd.end) return { h264: false, invalid: true };
  const count = uint32(data, stsd.contentStart + 4);
  if (count < 1 || count > MAX_STSD_ENTRIES)
    return { h264: false, invalid: true };
  let pos = stsd.contentStart + 8;
  let h264 = false;
  for (let i = 0; i < count; i += 1) {
    const entry = parseBox(data, pos, stsd.end);
    if (!entry) return { h264: false, invalid: true };
    if (OTHER_VIDEO_CODECS.has(entry.type))
      return { h264: false, invalid: true };
    if (entry.type === "avc1" || entry.type === "avc3") {
      // ISO/IEC 14496-12 visual sample entry: 78 bytes after the box header.
      const visualEnd = entry.contentStart + 78;
      if (visualEnd + 8 > entry.end) return { h264: false, invalid: true };
      const subBoxes = childBoxes(data, visualEnd, entry.end);
      if (!subBoxes) return { h264: false, invalid: true };
      const avcc = subBoxes.find(
        (b) =>
          b.type === "avcC" &&
          b.end - b.contentStart >= 7 &&
          data[b.contentStart] === 1,
      );
      if (!avcc) return { h264: false, invalid: true };
      h264 = true;
    }
    pos = entry.end;
  }
  return { h264, invalid: pos !== stsd.end };
}
function containsH264Track(data: Uint8Array): boolean {
  const root = parseBox(data, 0, data.length);
  if (!root || root.type !== "moov" || root.end !== data.length) return false;
  const moov = childBoxes(data, root.contentStart, root.end);
  if (!moov) return false;
  let hasAvc = false;
  for (const trak of moov.filter((b) => b.type === "trak")) {
    const tracks = childBoxes(data, trak.contentStart, trak.end);
    if (!tracks) return false;
    for (const mdia of tracks.filter((b) => b.type === "mdia")) {
      const media = childBoxes(data, mdia.contentStart, mdia.end);
      if (!media) return false;
      for (const minf of media.filter((b) => b.type === "minf")) {
        const info = childBoxes(data, minf.contentStart, minf.end);
        if (!info) return false;
        for (const stbl of info.filter((b) => b.type === "stbl")) {
          const samples = childBoxes(data, stbl.contentStart, stbl.end);
          if (!samples) return false;
          for (const stsd of samples.filter((b) => b.type === "stsd")) {
            const parsed = h264Description(data, stsd);
            if (parsed.invalid) return false;
            hasAvc ||= parsed.h264;
          }
        }
      }
    }
  }
  return hasAvc;
}

/** Fail closed for malformed box lengths, spoofed MIME, or unsupported video codecs. */
export async function isValidH264Mp4(
  size: number,
  readRange: ReadRange,
): Promise<boolean> {
  if (!Number.isSafeInteger(size) || size < 64) return false;
  let offset = 0;
  let first = true;
  let hasMdat = false;
  let hasMoov = false;
  let h264 = false;
  try {
    for (
      let scanned = 0;
      offset < size && scanned < MAX_TOP_LEVEL_BOXES;
      scanned += 1
    ) {
      const head = await readRange(
        offset,
        Math.min(HEADER_BYTES, size - offset),
      );
      if (head.length < 8) return false;
      const boxSize = uint32(head, 0);
      const type = ascii(head, 4, 4);
      let headerSize = 8;
      let sizeBytes = boxSize;
      if (boxSize === 1) {
        if (head.length < 16) return false;
        sizeBytes = uint32(head, 8) * 0x100000000 + uint32(head, 12);
        headerSize = 16;
      } else if (boxSize === 0) {
        if (type !== "mdat") return false;
        sizeBytes = size - offset;
      }
      if (
        !Number.isSafeInteger(sizeBytes) ||
        sizeBytes < headerSize ||
        offset + sizeBytes > size ||
        !/^[\x20-\x7e]{4}$/.test(type)
      )
        return false;
      if (first) {
        if (type !== "ftyp" || sizeBytes < 16 || sizeBytes > 256) return false;
        const brand = await readRange(offset + headerSize, 4);
        if (brand.length !== 4 || !SAFE_BRANDS.has(ascii(brand, 0, 4)))
          return false;
        first = false;
      } else if (type === "ftyp") {
        return false;
      }
      if (type === "moov") {
        if (hasMoov || sizeBytes > MAX_MOOV_BYTES) return false;
        hasMoov = true;
        const bytes = new Uint8Array(sizeBytes);
        // A bounded scratch buffer, independent of the file size.
        for (let at = 0; at < sizeBytes; at += 262144) {
          const length = Math.min(262144, sizeBytes - at);
          const chunk = await readRange(offset + at, length);
          if (chunk.length !== length) return false;
          bytes.set(chunk, at);
        }
        h264 = containsH264Track(bytes);
        if (!h264) return false;
      }
      if (type === "mdat") hasMdat ||= sizeBytes > headerSize;
      offset += sizeBytes;
    }
  } catch {
    return false;
  }
  return offset === size && hasMdat && hasMoov && h264;
}
