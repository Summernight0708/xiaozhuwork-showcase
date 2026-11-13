import { createHash } from "node:crypto";
import { validateTaskFileStream } from "./file-stream-validation.ts";

const MIB = 1_048_576;
const pdf = new TextEncoder().encode("%PDF-1.7\n");

type ZipFixturePart = {
  name: string;
  bytes: Uint8Array;
  method?: number;
  claimedSize?: number;
};

function zipFixture(parts: ZipFixturePart[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const chunks: BlobPart[] = [];
  const entries: Array<
    ZipFixturePart & { filename: Uint8Array; offset: number }
  > = [];
  let offset = 0;
  for (const part of parts) {
    const filename = encoder.encode(part.name);
    const header = new Uint8Array(30);
    const h = new DataView(header.buffer);
    h.setUint32(0, 0x04034b50, true);
    h.setUint16(4, 20, true);
    h.setUint16(8, part.method ?? 0, true);
    h.setUint32(18, part.bytes.length, true);
    h.setUint32(22, part.claimedSize ?? part.bytes.length, true);
    h.setUint16(26, filename.length, true);
    chunks.push(
      header as BlobPart,
      filename as BlobPart,
      part.bytes as BlobPart,
    );
    entries.push({ ...part, filename, offset });
    offset += header.length + filename.length + part.bytes.length;
  }
  const centralStart = offset;
  for (const entry of entries) {
    const header = new Uint8Array(46);
    const h = new DataView(header.buffer);
    h.setUint32(0, 0x02014b50, true);
    h.setUint16(4, 20, true);
    h.setUint16(6, 20, true);
    h.setUint16(10, entry.method ?? 0, true);
    h.setUint32(20, entry.bytes.length, true);
    h.setUint32(24, entry.claimedSize ?? entry.bytes.length, true);
    h.setUint16(28, entry.filename.length, true);
    h.setUint32(42, entry.offset, true);
    chunks.push(header as BlobPart, entry.filename as BlobPart);
    offset += header.length + entry.filename.length;
  }
  const trailer = new Uint8Array(22);
  const t = new DataView(trailer.buffer);
  t.setUint32(0, 0x06054b50, true);
  t.setUint16(8, entries.length, true);
  t.setUint16(10, entries.length, true);
  t.setUint32(12, offset - centralStart, true);
  t.setUint32(16, centralStart, true);
  chunks.push(trailer as BlobPart);
  return new Blob(chunks).stream();
}

Deno.test(
  "large OOXML checks 90 KiB content-types and rejects ZIP bombs/macros",
  async () => {
    const mime =
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    const parts: ZipFixturePart[] = [
      {
        name: "[Content_Types].xml",
        bytes: new TextEncoder().encode(
          '<Types><Override PartName="/word/document.xml" ContentType="' +
            mime +
            '.main+xml"/></Types>' +
            " ".repeat(90_000),
        ),
      },
      { name: "word/document.xml", bytes: new TextEncoder().encode("<doc/>") },
      { name: "word/media/padding.bin", bytes: new Uint8Array(51 * MIB) },
    ];
    const input = (extra: ZipFixturePart[] = []) => ({
      stream: zipFixture([...parts, ...extra]),
      declaredMimeType: mime,
      originalName: "large.docx",
      maxBytes: 200 * MIB,
    });
    const ok = await validateTaskFileStream(input());
    assert(ok.ok && ok.sizeBytes > 50 * MIB, "valid large OOXML rejected");

    const bomb = await validateTaskFileStream(
      input([
        {
          name: "word/media/bomb.deflate",
          bytes: new Uint8Array([0]),
          method: 8,
          claimedSize: 129 * MIB,
        },
      ]),
    );
    assert(
      !bomb.ok && bomb.code === "FILE_VALIDATION_FAILED",
      "ZIP bomb accepted",
    );

    const macro = await validateTaskFileStream(
      input([
        {
          name: "word/vbaProject.bin",
          bytes: new Uint8Array([1, 2, 3]),
        },
      ]),
    );
    assert(
      !macro.ok && macro.code === "FILE_TYPE_NOT_ALLOWED",
      "macro part accepted",
    );
  },
);

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function generatedStream(
  bytes: number,
  header = pdf,
): ReadableStream<Uint8Array> {
  let sent = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (sent === bytes) {
        controller.close();
        return;
      }
      const length = Math.min(64 * 1024, bytes - sent);
      const chunk = new Uint8Array(length);
      if (sent === 0) chunk.set(header.subarray(0, length));
      sent += length;
      controller.enqueue(chunk);
    },
  });
}

Deno.test(
  "Pro large PDF is streamed, hashed and validated without buffering 200 MiB",
  async () => {
    const size = 200 * MIB;
    const result = await validateTaskFileStream({
      stream: generatedStream(size),
      declaredMimeType: "application/pdf",
      originalName: "proposal.pdf",
      maxBytes: size,
    });
    assert(result.ok, JSON.stringify(result));
    assert(result.sizeBytes === size, "incorrect accepted size");
    const hash = createHash("sha256");
    const first = new Uint8Array(64 * 1024);
    first.set(pdf);
    hash.update(first);
    const zero = new Uint8Array(64 * 1024);
    for (let i = 1; i < size / zero.length; i++) hash.update(zero);
    assert(
      result.sha256Hex === hash.digest("hex"),
      "incremental hash mismatch",
    );
  },
);

Deno.test(
  "200 MiB + one byte aborts and rejects without finalizing",
  async () => {
    const result = await validateTaskFileStream({
      stream: generatedStream(200 * MIB + 1),
      declaredMimeType: "application/pdf",
      originalName: "proposal.pdf",
      maxBytes: 200 * MIB,
    });
    assert(
      !result.ok && result.code === "FILE_VALIDATION_FAILED",
      "overflow accepted",
    );
  },
);

Deno.test("Pro stream rejects masquerading dangerous binaries", async () => {
  const result = await validateTaskFileStream({
    stream: generatedStream(51 * MIB, new Uint8Array([0x4d, 0x5a])),
    declaredMimeType: "application/pdf",
    originalName: "malicious.pdf",
    maxBytes: 200 * MIB,
  });
  assert(
    !result.ok && result.code === "FILE_TYPE_NOT_ALLOWED",
    "executable accepted",
  );
});

Deno.test(
  "invalid MIME-extension combination fails before streaming",
  async () => {
    const result = await validateTaskFileStream({
      stream: generatedStream(200 * MIB),
      declaredMimeType: "application/pdf",
      originalName: "danger.exe",
      maxBytes: 200 * MIB,
    });
    assert(
      !result.ok && result.code === "FILE_TYPE_NOT_ALLOWED",
      "wrong extension accepted",
    );
  },
);

Deno.test("transient stream failure preserves reservation for retry", async () => {
  const interrupted = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(pdf);
      controller.error(new Error("interrupted Storage stream"));
    },
  });
  let failed = false;
  try {
    await validateTaskFileStream({
      stream: interrupted,
      declaredMimeType: "application/pdf",
      originalName: "proposal.pdf",
      maxBytes: 200 * MIB,
    });
  } catch (error) {
    failed = error instanceof Error && error.message.includes("interrupted");
  }
  assert(
    failed,
    "I/O failure was misclassified as a permanent content rejection",
  );
});

Deno.test(
  "Free maximum remains covered by existing deep validation",
  async () => {
    const result = await validateTaskFileStream({
      stream: generatedStream(50 * MIB),
      declaredMimeType: "application/pdf",
      originalName: "legacy.pdf",
      maxBytes: 50 * MIB,
    });
    assert(
      result.ok && result.sizeBytes === 50 * MIB,
      "legacy 50 MiB regressed",
    );
  },
);

function mp4TestU32(n: number): Uint8Array {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, n);
  return out;
}
function mp4TestBytes(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}
function mp4TestJoin(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, part) => n + part.length, 0));
  let i = 0;
  for (const part of parts) {
    out.set(part, i);
    i += part.length;
  }
  return out;
}
function mp4TestBox(name: string, body: Uint8Array): Uint8Array {
  return mp4TestJoin(mp4TestU32(body.length + 8), mp4TestBytes(name), body);
}
function mp4TestFixture(large: boolean, codec = "avc1"): Blob {
  const sample = mp4TestBox(
    codec,
    mp4TestJoin(
      new Uint8Array(78),
      mp4TestBox("avcC", new Uint8Array([1, 100, 0, 40, 255, 225, 0])),
    ),
  );
  const stsd = mp4TestBox(
    "stsd",
    mp4TestJoin(new Uint8Array(4), mp4TestU32(1), sample),
  );
  const moov = mp4TestBox(
    "moov",
    mp4TestBox(
      "trak",
      mp4TestBox("mdia", mp4TestBox("minf", mp4TestBox("stbl", stsd))),
    ),
  );
  const ftyp = mp4TestBox(
    "ftyp",
    mp4TestJoin(
      mp4TestBytes("mp42"),
      mp4TestU32(0),
      mp4TestBytes("isom"),
      mp4TestBytes("mp42"),
    ),
  );
  const payload = new Uint8Array(large ? 51 * MIB : 4);
  return new Blob([
    ftyp,
    mp4TestU32(payload.length + 8),
    mp4TestBytes("mdat"),
    payload,
    moov,
  ] as unknown as BlobPart[]);
}

Deno.test(
  "MP4 H264 stream validates with security checks, no full file buffering",
  async () => {
    for (const large of [false, true]) {
      const media = mp4TestFixture(large);
      const result = await validateTaskFileStream({
        stream: media.stream(),
        declaredMimeType: "video/mp4",
        originalName: "mobile-test.mp4",
        maxBytes: 200 * MIB,
      });
      assert(
        result.ok && result.sizeBytes === media.size,
        "H264 MP4 stream rejected",
      );
    }
  },
);

Deno.test(
  "MP4 lookalike without supported H264 codec is rejected",
  async () => {
    const media = mp4TestFixture(false, "hvc1");
    const result = await validateTaskFileStream({
      stream: media.stream(),
      declaredMimeType: "video/mp4",
      originalName: "h265.mp4",
      maxBytes: 50 * MIB,
    });
    assert(
      !result.ok && result.code === "FILE_VALIDATION_FAILED",
      "H265 bypassed H264-only policy",
    );
  },
);
