/**
 * Bounded-memory UTF-8 JSON syntax checker for large uploads. The caller
 * separately performs fatal incremental UTF-8 decoding; this parser retains
 * only a <=256-depth context stack and <=512-character numeric tokens.
 * It does not materialize the document or execute any user-provided content.
 */
type Phase = "first" | "value" | "key" | "colon" | "commaOrEnd";
type Frame = { kind: "object" | "array"; phase: Phase };
export class StreamingJsonSyntax {
  private readonly stack: Frame[] = [];
  private rootComplete = false;
  private mode: "none" | "string" | "number" | "literal" = "none";
  private stringRole: "key" | "value" = "value";
  private escaped = false;
  private unicodeDigits = 0;
  private atom = "";
  private target = "";

  private fail(): never {
    throw new Error("Malformed JSON");
  }
  private current(): Frame | undefined {
    return this.stack[this.stack.length - 1];
  }
  private completeValue() {
    const frame = this.current();
    if (!frame) {
      if (this.rootComplete) this.fail();
      this.rootComplete = true;
      return;
    }
    if (
      frame.phase !== "value" &&
      !(frame.kind === "array" && frame.phase === "first")
    ) {
      this.fail();
    }
    frame.phase = "commaOrEnd";
  }
  private addFrame(kind: "object" | "array") {
    if (this.stack.length >= 256) this.fail();
    this.stack.push({ kind, phase: "first" });
  }
  private beginValue(ch: string) {
    if (ch === '"') {
      this.mode = "string";
      this.stringRole = "value";
      return;
    }
    if (ch === "{") {
      this.addFrame("object");
      return;
    }
    if (ch === "[") {
      this.addFrame("array");
      return;
    }
    if (ch === "-" || (ch >= "0" && ch <= "9")) {
      this.mode = "number";
      this.atom = ch;
      return;
    }
    const targets: Record<string, string> = {
      t: "true",
      f: "false",
      n: "null",
    };
    if (targets[ch]) {
      this.mode = "literal";
      this.target = targets[ch];
      this.atom = ch;
      return;
    }
    this.fail();
  }
  private completeNumber() {
    if (!/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(this.atom)) {
      this.fail();
    }
    this.mode = "none";
    this.atom = "";
    this.completeValue();
  }
  feed(chunk: string) {
    for (const ch of chunk) {
      let reconsume = true;
      while (reconsume) {
        reconsume = false;
        if (this.mode === "string") {
          if (this.unicodeDigits > 0) {
            if (!/^[0-9a-fA-F]$/.test(ch)) this.fail();
            this.unicodeDigits--;
          } else if (this.escaped) {
            this.escaped = false;
            if (ch === "u") this.unicodeDigits = 4;
            else if (!'"\\/bfnrt'.includes(ch)) this.fail();
          } else if (ch === "\\") this.escaped = true;
          else if (ch === '"') {
            this.mode = "none";
            if (this.stringRole === "key") {
              const frame = this.current();
              if (!frame || frame.kind !== "object") this.fail();
              frame.phase = "colon";
            } else this.completeValue();
          } else if (ch.charCodeAt(0) < 32) this.fail();
          continue;
        }
        if (this.mode === "number") {
          if (/[0-9eE.+-]/.test(ch)) {
            this.atom += ch;
            if (this.atom.length > 512) this.fail();
            continue;
          }
          this.completeNumber();
          reconsume = true;
          continue;
        }
        if (this.mode === "literal") {
          const next = this.atom.length;
          if (ch !== this.target[next]) this.fail();
          this.atom += ch;
          if (this.atom.length === this.target.length) {
            this.atom = "";
            this.target = "";
            this.mode = "none";
            this.completeValue();
          }
          continue;
        }
        if (ch === " " || ch === "\n" || ch === "\t" || ch === "\r") continue;
        const frame = this.current();
        if (!frame) {
          if (this.rootComplete) this.fail();
          this.beginValue(ch);
          continue;
        }
        if (frame.kind === "object") {
          if (frame.phase === "first" || frame.phase === "key") {
            if (ch === "}" && frame.phase === "first") {
              this.stack.pop();
              this.completeValue();
              continue;
            }
            if (ch !== '"') this.fail();
            this.mode = "string";
            this.stringRole = "key";
            continue;
          }
          if (frame.phase === "colon") {
            if (ch !== ":") this.fail();
            frame.phase = "value";
            continue;
          }
          if (frame.phase === "commaOrEnd") {
            if (ch === ",") {
              frame.phase = "key";
              continue;
            }
            if (ch === "}") {
              this.stack.pop();
              this.completeValue();
              continue;
            }
            this.fail();
          }
          this.beginValue(ch);
          continue;
        }
        if (frame.phase === "first" || frame.phase === "value") {
          if (ch === "]" && frame.phase === "first") {
            this.stack.pop();
            this.completeValue();
            continue;
          }
          this.beginValue(ch);
          continue;
        }
        if (frame.phase === "commaOrEnd") {
          if (ch === ",") {
            frame.phase = "value";
            continue;
          }
          if (ch === "]") {
            this.stack.pop();
            this.completeValue();
            continue;
          }
          this.fail();
        }
        this.fail();
      }
    }
  }
  finish(): boolean {
    if (this.mode === "number") this.completeNumber();
    return this.mode === "none" && this.stack.length === 0 && this.rootComplete;
  }
}
