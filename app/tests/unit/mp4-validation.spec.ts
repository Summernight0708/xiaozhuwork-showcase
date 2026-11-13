import { readFileSync, existsSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { isValidH264Mp4 } from "../../supabase/functions/_shared/mp4-validation";
import { validateTaskFile } from "../../supabase/functions/_shared/file-validation";

function bytes(s: string) {
  return new TextEncoder().encode(s);
}
function join(...parts: Uint8Array[]) {
  const result = new Uint8Array(parts.reduce((acc, p) => acc + p.length, 0));
  let i = 0;
  for (const p of parts) {
    result.set(p, i);
    i += p.length;
  }
  return result;
}
function u32(value: number) {
  const b = new Uint8Array(4);
  new DataView(b.buffer).setUint32(0, value);
  return b;
}
function box(type: string, payload: Uint8Array) {
  return join(u32(payload.length + 8), bytes(type), payload);
}
function fixture(
  codec = "avc1",
  withAvcC = true,
  includeMoov = true,
  majorBrand = "mp42",
) {
  const entry = box(
    codec,
    join(
      new Uint8Array(78),
      ...(withAvcC
        ? [box("avcC", new Uint8Array([1, 100, 0, 40, 255, 225, 0]))]
        : []),
    ),
  );
  const stsd = box("stsd", join(new Uint8Array(4), u32(1), entry));
  const moov = box(
    "moov",
    box("trak", box("mdia", box("minf", box("stbl", stsd)))),
  );
  return join(
    box("ftyp", join(bytes(majorBrand), u32(0), bytes("isom"), bytes("mp42"))),
    ...(includeMoov ? [moov] : []),
    box("mdat", new Uint8Array([0, 1, 2, 3])),
  );
}
const inspect = (bytes: Uint8Array) =>
  isValidH264Mp4(bytes.length, async (at, len) => bytes.subarray(at, at + len));

describe("H.264 MP4 end-to-end type hardening", () => {
  it("accepts structurally valid H.264 MP4 but no other MIME/extension", async () => {
    const video = fixture();
    expect(await inspect(video)).toBe(true);
    const ok = await validateTaskFile({
      bytes: video,
      originalName: "phone.mp4",
      declaredMimeType: "video/mp4",
    });
    expect(ok.ok).toBe(true);
    expect(
      (
        await validateTaskFile({
          bytes: video,
          originalName: "phone.mp4.exe",
          declaredMimeType: "video/mp4",
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await validateTaskFile({
          bytes: video,
          originalName: "phone.mp4",
          declaredMimeType: "application/pdf",
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await validateTaskFile({
          bytes: video,
          originalName: "phone.mov",
          declaredMimeType: "video/mp4",
        })
      ).ok,
    ).toBe(false);
  });

  it("rejects video-type spoofing, unsupported codecs and incomplete boxes", async () => {
    expect(await inspect(fixture("hvc1"))).toBe(false);
    expect(await inspect(fixture("avc1", false))).toBe(false);
    expect(await inspect(fixture("avc1", true, false))).toBe(false);
    expect(await inspect(fixture("avc1", true, true, "junk"))).toBe(false);
    const b = fixture();
    expect(await inspect(b.subarray(0, b.length - 3))).toBe(false);
    const tampered = Uint8Array.from(b);
    tampered[0] = 127;
    expect(await inspect(tampered)).toBe(false);
    expect(await inspect(bytes("MZ pseudo-MP4 video/mp4 avc1 avcC"))).toBe(
      false,
    );
  });

  it("accepts a box-level valid H.264 file when moov comes after mdat", async () => {
    const b = fixture();
    const ftypSize = new DataView(b.buffer).getUint32(0);
    const moovSize = new DataView(b.buffer).getUint32(ftypSize);
    const ordered = join(
      b.subarray(0, ftypSize),
      b.subarray(ftypSize + moovSize),
      b.subarray(ftypSize, ftypSize + moovSize),
    );
    expect(await inspect(ordered)).toBe(true);
  });

  const physicalQaFile = process.env.XIAOZHU_H264_QA_FIXTURE;
  it.skipIf(!physicalQaFile || !existsSync(physicalQaFile))(
    "accepts genuine Android H.264 screenrecord fixture without committing it",
    async () => {
      const bytes = new Uint8Array(readFileSync(physicalQaFile!));
      expect(await inspect(bytes)).toBe(true);
      const result = await validateTaskFile({
        bytes,
        originalName: "native-video.mp4",
        declaredMimeType: "video/mp4",
      });
      expect(result.ok).toBe(true);
    },
  );
});
