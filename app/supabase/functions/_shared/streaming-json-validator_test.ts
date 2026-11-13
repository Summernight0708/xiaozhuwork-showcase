import { StreamingJsonSyntax } from "./streaming-json-validator.ts";
import { validateTaskFileStream } from "./file-stream-validation.ts";

function assert(value: unknown, reason: string): asserts value {
  if (!value) throw Error(reason);
}

Deno.test(
  "streamed JSON grammar matches JSON.parse across chunk boundaries",
  () => {
    const valid = [
      "null",
      "true",
      "false",
      "0",
      "-10.25e+3",
      '{"name":"escape \\" \\\\ \\/ \\u2603","v":[true,null,{},[],5]}',
      '[{},[1,2,3],"😀",{"a":false}]',
    ];
    for (const json of valid) {
      JSON.parse(json);
      const parser = new StreamingJsonSyntax();
      for (const character of json) parser.feed(character);
      assert(parser.finish(), "rejected valid JSON: " + json);
    }
    const invalid = [
      "",
      "01",
      "-.1",
      "1e+",
      "[1,]",
      '{"a":1,}',
      "[true false]",
      "{unquoted:2}",
      '{"a":bad}',
      "[1",
      '"bad\\xescape"',
      "{} true",
      "[[",
      '{"a":',
      '{"a":false,"b":}',
    ];
    for (const json of invalid) {
      let failed = false;
      try {
        const parser = new StreamingJsonSyntax();
        for (const character of json) parser.feed(character);
        if (!parser.finish()) failed = true;
      } catch {
        failed = true;
      }
      assert(failed, "accepted invalid JSON: " + json);
    }
  },
);

Deno.test(
  "over 50 MiB valid JSON is parsed incrementally with bounded memory",
  async () => {
    const size = 51 * 1024 * 1024;
    const prefix = new TextEncoder().encode('{"payload":"');
    let position = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (position >= size) {
          controller.close();
          return;
        }
        const length = Math.min(64 * 1024, size - position);
        const part = new Uint8Array(length).fill(0x61);
        for (let i = 0; i < length; i++) {
          const at = position + i;
          if (at < prefix.length) part[i] = prefix[at];
          else if (at === size - 2) part[i] = 0x22;
          else if (at === size - 1) part[i] = 0x7d;
        }
        position += length;
        controller.enqueue(part);
      },
    });
    const result = await validateTaskFileStream({
      stream,
      declaredMimeType: "application/json",
      originalName: "large.json",
      maxBytes: 200 * 1024 * 1024,
    });
    assert(result.ok && result.sizeBytes === size, "large JSON rejected");
  },
);
