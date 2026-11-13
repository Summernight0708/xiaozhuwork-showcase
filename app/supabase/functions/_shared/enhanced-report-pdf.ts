/**
 * Self-contained PDF 1.4 renderer for the immutable V1 contribution snapshot.
 *
 * Uses an embedded, licensed Noto Sans SC TrueType font (see fonts/OFL.txt),
 * Identity-H CIDFontType2, accurate hmtx widths, CIDToGIDMap and ToUnicode.
 * It does NOT rely on the viewer having an installed CJK font.
 *
 * Kept apart from Free's existing lightweight legacy renderer.
 */
import {
  ENHANCED_REPORT_PROVENANCE,
  parseEnhancedReportEnvelope,
  summarizeEnhancedReport,
  type EnhancedReportEnvelope,
} from "./enhanced-report-export.ts";
import { REPORT_DISCLAIMER } from "./report-export.ts";

const enc = new TextEncoder();
const PAGE_WIDTH = 595.28;
const PAGE_HEIGHT = 841.89;
const MARGIN = 52;
const MAX_TEXT_WIDTH = PAGE_WIDTH - MARGIN * 2;
const FONT_URL = new URL("./fonts/NotoSansSC-wght.ttf", import.meta.url);
type FontTable = { offset: number; length: number };
type Font = {
  data: Uint8Array;
  compressed: Uint8Array;
  view: DataView;
  tables: Map<string, FontTable>;
  cmap: number;
  format: number;
  units: number;
  numGlyphs: number;
  numHMetrics: number;
  ascender: number;
  descender: number;
  bbox: [number, number, number, number];
};

function u16(view: DataView, index: number): number {
  return view.getUint16(index);
}
function i16(view: DataView, index: number): number {
  return view.getInt16(index);
}
function u32(view: DataView, index: number): number {
  return view.getUint32(index);
}
function table(font: Font, name: string): FontTable {
  const result = font.tables.get(name);
  if (!result) throw new Error("Invalid embedded report font");
  return result;
}

async function deflate(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes as BlobPart])
    .stream()
    .pipeThrough(new CompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function prepareFont(): Promise<Font> {
  const runtime = globalThis as unknown as {
    Deno: { readFile(path: URL): Promise<Uint8Array> };
  };
  const data = await runtime.Deno.readFile(FONT_URL);
  if (data.byteLength > 24 * 1024 * 1024 || data.byteLength < 1024) {
    throw new Error("Invalid embedded report font");
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const count = u16(view, 4);
  if (count < 5 || count > 128) throw new Error("Invalid embedded report font");
  const tables = new Map<string, FontTable>();
  for (let i = 0; i < count; i++) {
    const pos = 12 + i * 16;
    const name = String.fromCharCode(...data.subarray(pos, pos + 4));
    const offset = u32(view, pos + 8);
    const length = u32(view, pos + 12);
    if (offset + length > data.length)
      throw new Error("Invalid embedded report font");
    tables.set(name, { offset, length });
  }
  const f: Font = {
    data,
    compressed: new Uint8Array(),
    view,
    tables,
    cmap: 0,
    format: 0,
    units: u16(view, table({ tables } as Font, "head").offset + 18),
    numGlyphs: u16(view, table({ tables } as Font, "maxp").offset + 4),
    numHMetrics: u16(view, table({ tables } as Font, "hhea").offset + 34),
    ascender: i16(view, table({ tables } as Font, "hhea").offset + 4),
    descender: i16(view, table({ tables } as Font, "hhea").offset + 6),
    bbox: [
      i16(view, table({ tables } as Font, "head").offset + 36),
      i16(view, table({ tables } as Font, "head").offset + 38),
      i16(view, table({ tables } as Font, "head").offset + 40),
      i16(view, table({ tables } as Font, "head").offset + 42),
    ] as [number, number, number, number],
  };
  if (f.units < 16 || f.numGlyphs < 128 || f.numHMetrics < 1)
    throw new Error("Invalid embedded report font");
  const cmap = table(f, "cmap").offset;
  const subtableCount = u16(view, cmap + 2);
  let choice: { at: number; format: number; score: number } | undefined;
  for (let i = 0; i < subtableCount; i++) {
    const rec = cmap + 4 + i * 8;
    const platform = u16(view, rec);
    const encoding = u16(view, rec + 2);
    const at = cmap + u32(view, rec + 4);
    const format = u16(view, at);
    if (format !== 4 && format !== 12) continue;
    const score =
      (format === 12 ? 100 : 0) +
      (platform === 3 ? 10 : 0) +
      (encoding === 10 ? 5 : 0);
    if (!choice || score > choice.score) choice = { at, format, score };
  }
  if (!choice) throw new Error("Embedded report font has no Unicode cmap");
  f.cmap = choice.at;
  f.format = choice.format;
  f.compressed = await deflate(data);
  return f;
}
let fontPromise: Promise<Font> | null = null;
function loadFont(): Promise<Font> {
  return (fontPromise ??= prepareFont().catch((error) => {
    fontPromise = null;
    throw error;
  }));
}

function glyph(font: Font, cp: number): number {
  const v = font.view;
  const base = font.cmap;
  if (font.format === 12) {
    const n = u32(v, base + 12);
    let lo = 0,
      hi = n - 1;
    while (lo <= hi) {
      const mid = Math.floor((lo + hi) / 2);
      const at = base + 16 + mid * 12;
      const start = u32(v, at),
        end = u32(v, at + 4);
      if (cp < start) hi = mid - 1;
      else if (cp > end) lo = mid + 1;
      else return u32(v, at + 8) + cp - start;
    }
    return 0;
  }
  if (cp > 0xffff) return 0;
  const segCount = u16(v, base + 6) / 2;
  const endCodes = base + 14;
  const startCodes = endCodes + segCount * 2 + 2;
  const deltas = startCodes + segCount * 2;
  const ranges = deltas + segCount * 2;
  for (let i = 0; i < segCount; i++) {
    if (cp > u16(v, endCodes + i * 2)) continue;
    if (cp < u16(v, startCodes + i * 2)) return 0;
    const range = u16(v, ranges + i * 2);
    const delta = i16(v, deltas + i * 2);
    if (!range) return (cp + delta) & 0xffff;
    const ptr = ranges + i * 2 + range + (cp - u16(v, startCodes + i * 2)) * 2;
    const found = u16(v, ptr);
    return found ? (found + delta) & 0xffff : 0;
  }
  return 0;
}

function advance(font: Font, gid: number): number {
  const index = Math.min(gid, font.numHMetrics - 1);
  return (
    (u16(font.view, table(font, "hmtx").offset + index * 4) / font.units) * 1000
  );
}

function asHex(value: number, length = 4): string {
  return value.toString(16).toUpperCase().padStart(length, "0");
}

function unicodeHex(cp: number): string {
  if (cp <= 0xffff) return asHex(cp);
  const value = cp - 0x10000;
  return asHex((value >> 10) + 0xd800) + asHex((value & 0x3ff) + 0xdc00);
}

function sanitize(text: string): string {
  return Array.from(text, (character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint < 32 || codePoint === 127 ? " " : character;
  })
    .join("")
    .trim();
}

type Page = { ops: string[]; y: number };
type Letter = { cid: number; cp: number; glyph: number; width: number };

class ReportCanvas {
  readonly pages: Page[] = [];
  readonly letters = new Map<number, Letter>();
  private readonly codeByPoint = new Map<number, Letter>();
  private page: Page;
  constructor(readonly font: Font) {
    this.page = this.newPage();
  }
  private newPage(): Page {
    const page = { ops: [], y: 788 };
    this.pages.push(page);
    return page;
  }
  pageBreak(): void {
    this.page = this.newPage();
  }
  private letter(cp: number): Letter {
    const old = this.codeByPoint.get(cp);
    if (old) return old;
    // If this font does not contain a glyph, display a visible replacement
    // square while preserving the original Unicode in the extraction map.
    const replacement = glyph(this.font, 0x25a1);
    const g = glyph(this.font, cp) || replacement;
    const entry = {
      cp,
      glyph: g,
      cid: this.codeByPoint.size + 1,
      width: advance(this.font, g),
    };
    if (entry.cid > 65534) throw new Error("Too many PDF glyphs");
    this.codeByPoint.set(cp, entry);
    this.letters.set(entry.cid, entry);
    return entry;
  }
  private measure(text: string, size: number): number {
    let sum = 0;
    for (const ch of text)
      sum += (this.letter(ch.codePointAt(0)!).width * size) / 1000;
    return sum;
  }
  private wrap(text: string, size: number, maxWidth: number): string[] {
    const value = sanitize(text);
    if (!value) return [""];
    const lines: string[] = [];
    let line = "";
    let width = 0;
    for (const ch of value) {
      const w = this.measure(ch, size);
      if (line && width + w > maxWidth) {
        lines.push(line);
        line = ch;
        width = w;
      } else {
        line += ch;
        width += w;
      }
    }
    if (line) lines.push(line);
    return lines;
  }
  private encode(text: string): string {
    return Array.from(text, (ch) =>
      asHex(this.letter(ch.codePointAt(0)!).cid),
    ).join("");
  }
  private ensure(height: number): void {
    if (this.page.y - height < 82) this.pageBreak();
  }
  text(
    text: string,
    opts: { size?: number; indent?: number; gap?: number; color?: string } = {},
  ): void {
    const size = opts.size ?? 10;
    const indent = opts.indent ?? 0;
    const lineHeight = size * 1.65;
    const lines = this.wrap(text, size, MAX_TEXT_WIDTH - indent);
    for (const line of lines) {
      this.ensure(lineHeight);
      this.page.ops.push(
        "BT",
        (opts.color ?? "0.10 0.18 0.29") + " rg",
        "/F1 " + size + " Tf",
        "1 0 0 1 " + (MARGIN + indent) + " " + this.page.y.toFixed(2) + " Tm",
        "<" + this.encode(line) + "> Tj",
        "ET",
      );
      this.page.y -= lineHeight;
    }
    this.page.y -= opts.gap ?? 5;
  }
  heading(text: string): void {
    this.text(text, { size: 17, gap: 14, color: "0.13 0.31 0.59" });
  }
  spacer(height = 12): void {
    this.ensure(height);
    this.page.y -= height;
  }
  bar(numerator: bigint, denominator: bigint): void {
    this.ensure(21);
    const x = MARGIN + 12,
      w = 390,
      y = this.page.y - 5;
    const fill =
      denominator > 0n
        ? Math.max(
            0,
            Math.min(
              w,
              Number((numerator * BigInt(w * 1000)) / denominator) / 1000,
            ),
          )
        : 0;
    this.page.ops.push("0.91 0.93 0.97 rg", x + " " + y + " " + w + " 9 re f");
    if (fill > 0)
      this.page.ops.push(
        "0.22 0.48 0.80 rg",
        x + " " + y + " " + fill.toFixed(2) + " 9 re f",
      );
    this.page.y -= 18;
  }
  addFooters(): void {
    const total = this.pages.length;
    for (let i = 0; i < total; i++) {
      const page = this.pages[i]!;
      const line = [
        REPORT_DISCLAIMER,
        " · ",
        String(i + 1),
        "/",
        String(total),
      ].join("");
      page.ops.push(
        "BT",
        "0.36 0.38 0.43 rg",
        "/F1 8 Tf",
        "1 0 0 1 " + MARGIN + " 35 Tm",
        "<" + this.encode(line) + "> Tj",
        "ET",
      );
    }
  }
}

function makeCmap(entries: Letter[]): Uint8Array {
  const blocks: string[] = [];
  for (let i = 0; i < entries.length; i += 100) {
    const chunk = entries.slice(i, i + 100);
    blocks.push(chunk.length + " beginbfchar");
    for (const e of chunk)
      blocks.push("<" + asHex(e.cid) + "> <" + unicodeHex(e.cp) + ">");
    blocks.push("endbfchar");
  }
  return enc.encode(
    [
      "/CIDInit /ProcSet findresource begin",
      "12 dict begin",
      "begincmap",
      "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
      "/CMapName /XiaozhuEnhancedUnicode def",
      "/CMapType 2 def",
      "1 begincodespacerange",
      "<0000> <FFFF>",
      "endcodespacerange",
      ...blocks,
      "endcmap",
      "CMapName currentdict /CMap defineresource pop",
      "end",
      "end",
    ].join("\n"),
  );
}

function concat(parts: Uint8Array[]): Uint8Array {
  const length = parts.reduce((n, p) => n + p.byteLength, 0);
  const result = new Uint8Array(length);
  let at = 0;
  for (const part of parts) {
    result.set(part, at);
    at += part.length;
  }
  return result;
}

function stream(bytes: Uint8Array, dict = ""): Uint8Array {
  return concat([
    enc.encode("<< /Length " + bytes.length + " " + dict + " >>\nstream\n"),
    bytes,
    enc.encode("\nendstream"),
  ]);
}

function buildPdf(canvas: ReportCanvas): Uint8Array {
  canvas.addFooters();
  const font = canvas.font;
  const pages = canvas.pages;
  const n = pages.length;
  const fontId = 3 + n * 2;
  const descendantId = fontId + 1;
  const descriptorId = fontId + 2;
  const unicodeId = fontId + 3;
  const dataId = fontId + 4;
  const mapId = fontId + 5;
  const objects: Uint8Array[] = new Array(mapId);

  const ids = pages.map((_, i) => 3 + i * 2);
  objects[0] = enc.encode("<< /Type /Catalog /Pages 2 0 R >>");
  objects[1] = enc.encode(
    "<< /Type /Pages /Kids [" +
      ids.map((id) => id + " 0 R").join(" ") +
      "] /Count " +
      n +
      " >>",
  );
  pages.forEach((page, i) => {
    const pageId = ids[i]!,
      contentsId = pageId + 1;
    objects[pageId - 1] = enc.encode(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " +
        PAGE_WIDTH +
        " " +
        PAGE_HEIGHT +
        "] /Resources << /Font << /F1 " +
        fontId +
        " 0 R >> >> /Contents " +
        contentsId +
        " 0 R >>",
    );
    objects[contentsId - 1] = stream(enc.encode(page.ops.join("\n")));
  });
  const entries = [...canvas.letters.values()].sort((a, b) => a.cid - b.cid);
  const widths = entries.map((e) => String(Math.round(e.width))).join(" ");
  objects[fontId - 1] = enc.encode(
    "<< /Type /Font /Subtype /Type0 /BaseFont /NotoSansSC-Regular /Encoding /Identity-H" +
      " /DescendantFonts [" +
      descendantId +
      " 0 R] /ToUnicode " +
      unicodeId +
      " 0 R >>",
  );
  objects[descendantId - 1] = enc.encode(
    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /NotoSansSC-Regular" +
      " /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>" +
      " /FontDescriptor " +
      descriptorId +
      " 0 R /CIDToGIDMap " +
      mapId +
      " 0 R" +
      " /DW 1000 /W [1 [" +
      widths +
      "]] >>",
  );
  const scale = (a: number) => Math.round((a / font.units) * 1000);
  objects[descriptorId - 1] = enc.encode(
    "<< /Type /FontDescriptor /FontName /NotoSansSC-Regular /Flags 4" +
      " /FontBBox [" +
      font.bbox.map(scale).join(" ") +
      "]" +
      " /ItalicAngle 0 /Ascent " +
      scale(font.ascender) +
      " /Descent " +
      scale(font.descender) +
      " /CapHeight " +
      scale(font.ascender) +
      " /StemV 80" +
      " /FontFile2 " +
      dataId +
      " 0 R >>",
  );
  objects[unicodeId - 1] = stream(makeCmap(entries));
  objects[dataId - 1] = stream(
    font.compressed,
    "/Filter /FlateDecode /Length1 " + font.data.length,
  );
  const cidMap = new Uint8Array((entries.length + 1) * 2);
  for (const e of entries) {
    cidMap[e.cid * 2] = (e.glyph >> 8) & 255;
    cidMap[e.cid * 2 + 1] = e.glyph & 255;
  }
  objects[mapId - 1] = stream(cidMap);
  // Binary-safe xref offsets. No JS string length arithmetic on font bytes.
  const chunks: Uint8Array[] = [
    enc.encode("%PDF-1.4\n%\u00E2\u00E3\u00CF\u00D3\n"),
  ];
  const offsets = [0];
  let position = chunks[0]!.length;
  objects.forEach((object, i) => {
    const head = enc.encode(i + 1 + " 0 obj\n");
    const tail = enc.encode("\nendobj\n");
    offsets.push(position);
    chunks.push(head, object, tail);
    position += head.length + object.length + tail.length;
  });
  const xref = position;
  const lines = ["xref", "0 " + (objects.length + 1), "0000000000 65535 f "];
  for (let i = 1; i < offsets.length; i++)
    lines.push(String(offsets[i]).padStart(10, "0") + " 00000 n ");
  lines.push(
    "trailer",
    "<< /Size " + (objects.length + 1) + " /Root 1 0 R >>",
    "startxref",
    String(xref),
    "%%EOF",
    "",
  );
  chunks.push(enc.encode(lines.join("\n")));
  return concat(chunks);
}

export async function renderEnhancedReportPdf(
  value: EnhancedReportEnvelope | unknown,
  generatedAt = new Date().toISOString(),
): Promise<Uint8Array> {
  const { snapshot } = parseEnhancedReportEnvelope(value);
  if (!Number.isFinite(Date.parse(generatedAt)))
    throw new Error("Invalid generation time");
  const font = await loadFont();
  const doc = new ReportCanvas(font);
  const summary = summarizeEnhancedReport(snapshot);

  doc.text("小猪作业 · Pro 增强贡献报告", {
    size: 24,
    gap: 35,
    color: "0.12 0.35 0.67",
  });
  doc.heading("项目：" + snapshot.projectName);
  doc.text("报告 ID：" + snapshot.reportId, { size: 10, gap: 12 });
  doc.text(
    "正式报告版本：" +
      snapshot.reportVersion +
      "    项目来源版本：" +
      snapshot.sourceProjectVersion,
  );
  doc.text("正式化时间：" + snapshot.formalizedAt);
  doc.text("报告生成时间：" + generatedAt);
  doc.spacer(36);
  doc.text(
    "说明：本报告展示已确认的贡献报告快照，不改变任务权重、成员贡献事实或审核结果。",
    { size: 11, gap: 18 },
  );
  doc.text(REPORT_DISCLAIMER, { size: 12, color: "0.55 0.18 0.18" });

  doc.pageBreak();
  doc.heading("一、贡献摘要");
  doc.text("正式报告：" + snapshot.reportId);
  doc.text("快照任务条目数：" + snapshot.items.length);
  doc.text("参与成员数：" + summary.members.length);
  doc.text("贡献模式：" + snapshot.contributionMode);
  doc.text(
    "快照权威贡献值合计：" +
      (summary.totalValue4dp ?? "仅事实记录（不提供权重）"),
  );
  doc.text(
    "已确认成员数：" +
      snapshot.confirmedCount +
      "/" +
      snapshot.eligibleCount +
      "（确认阈值 " +
      snapshot.requiredCount +
      "）",
  );
  doc.spacer(14);
  doc.text(ENHANCED_REPORT_PROVENANCE, { size: 10 });

  doc.pageBreak();
  doc.heading("二、成员贡献明细与占比图");
  if (!summary.weighted) {
    doc.text(
      "该正式报告使用仅事实模式，不存在贡献权重或数值占比；不推测贡献比例。",
    );
  } else if (summary.totalValueUnits === 0n) {
    doc.text("快照总贡献值为零，占比不适用。");
  } else {
    doc.text(
      "图条长度依据下方相同的快照贡献值计算；占比为显示性汇总，不是成员能力评价。",
    );
  }
  doc.spacer(8);
  for (const member of summary.members) {
    doc.text("成员：" + member.name, { size: 11, gap: 2 });
    doc.text(
      "快照任务数：" +
        member.itemCount +
        "    贡献值：" +
        (member.value4dp ?? "无权重") +
        "    展示占比：" +
        (member.percent2dp === null ? "不适用" : member.percent2dp + "%"),
      { size: 10, indent: 12, gap: 4 },
    );
    if (member.percent2dp !== null)
      doc.bar(member.valueUnits, summary.totalValueUnits);
    doc.spacer(7);
  }

  doc.pageBreak();
  doc.heading("三、来源与任务明细");
  doc.text(ENHANCED_REPORT_PROVENANCE);
  doc.text(
    "以下字段直接来自正式贡献快照，任务份额与成员展示占比不是同一个字段。",
  );
  doc.spacer(10);
  for (let i = 0; i < snapshot.items.length; i++) {
    const item = snapshot.items[i]!;
    doc.text("记录 " + (i + 1) + " · " + item.taskTitle, { size: 11, gap: 2 });
    doc.text(
      "成员：" +
        item.memberDisplayName +
        "    原任务权重：" +
        (item.taskWeightAuthority ?? "仅事实") +
        "    原任务份额：" +
        item.shareAuthority,
      { size: 9, indent: 12, gap: 2 },
    );
    doc.text(
      "快照贡献值：" +
        (item.contributionValueAuthority ?? "仅事实") +
        "    完成时间：" +
        item.completedAt,
      { size: 9, indent: 12, gap: 10 },
    );
  }
  doc.spacer(12);
  doc.heading("四、来源及免责声明");
  doc.text(ENHANCED_REPORT_PROVENANCE);
  doc.text(REPORT_DISCLAIMER, { size: 11 });
  const output = buildPdf(doc);
  if (output.byteLength > 25 * 1024 * 1024) {
    throw new Error("Enhanced PDF exceeds size limit");
  }
  return output;
}
