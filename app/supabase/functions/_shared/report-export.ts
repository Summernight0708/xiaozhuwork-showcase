export const REPORT_DISCLAIMER = "仅供参考，不代表教师评分或成员能力评价";

export type ProjectReportExportItem = {
  taskId: string;
  taskTitle: string;
  memberUserId: string | null;
  memberDisplayName: string;
  taskWeightAuthority: string | null;
  taskWeightDisplay: string | null;
  shareAuthority: string;
  shareDisplay: string;
  contributionValueAuthority: string | null;
  contributionValueDisplay: string | null;
  completedAt: string;
};

export type ProjectReportExportSnapshot = {
  schemaVersion: 1;
  projectId: string;
  projectName: string;
  reportId: string;
  reportState: "draft" | "formal";
  statusLabel: "DRAFT" | "FORMAL";
  contributionMode: "weighted" | "facts_only";
  sourceProjectVersion: number;
  reportVersion: number;
  createdAt: string;
  formalizedAt: string | null;
  eligibleCount: number;
  confirmedCount: number;
  requiredCount: number;
  disclaimer: typeof REPORT_DISCLAIMER;
  items: ProjectReportExportItem[];
};

export type ReportExportFormat = "csv" | "pdf";

export type RenderedProjectReport = {
  bytes: Uint8Array;
  contentType: string;
  extension: ReportExportFormat;
};

const FOUR_DECIMAL = /^-?\d+\.\d{4}$/;
const TWO_DECIMAL = /^-?\d+\.\d{2}$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function isInteger(value: unknown, minimum = 0): value is number {
  return Number.isInteger(value) && (value as number) >= minimum;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isIsoDate(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    Number.isFinite(Date.parse(value))
  );
}

function isDecimal(
  value: unknown,
  pattern: RegExp,
  nullable: boolean,
): value is string | null {
  return (
    (nullable && value === null) ||
    (typeof value === "string" && pattern.test(value))
  );
}

function parseItem(value: unknown): ProjectReportExportItem | null {
  if (!isRecord(value)) return null;
  if (
    !isNonEmptyString(value.taskId) ||
    !isNonEmptyString(value.taskTitle) ||
    !(value.memberUserId === null || isNonEmptyString(value.memberUserId)) ||
    !isNonEmptyString(value.memberDisplayName) ||
    !isDecimal(value.taskWeightAuthority, FOUR_DECIMAL, true) ||
    !isDecimal(value.taskWeightDisplay, TWO_DECIMAL, true) ||
    !isDecimal(value.shareAuthority, FOUR_DECIMAL, false) ||
    !isDecimal(value.shareDisplay, TWO_DECIMAL, false) ||
    !isDecimal(value.contributionValueAuthority, FOUR_DECIMAL, true) ||
    !isDecimal(value.contributionValueDisplay, TWO_DECIMAL, true) ||
    !isIsoDate(value.completedAt)
  ) {
    return null;
  }

  if (
    (value.taskWeightAuthority === null) !==
      (value.taskWeightDisplay === null) ||
    (value.contributionValueAuthority === null) !==
      (value.contributionValueDisplay === null)
  ) {
    return null;
  }

  return value as ProjectReportExportItem;
}

export function parseProjectReportExportSnapshot(
  value: unknown,
): ProjectReportExportSnapshot {
  if (!isRecord(value)) {
    throw new Error("Invalid report export snapshot");
  }

  const items = Array.isArray(value.items) ? value.items.map(parseItem) : [];
  if (
    value.schemaVersion !== 1 ||
    !isNonEmptyString(value.projectId) ||
    !isNonEmptyString(value.projectName) ||
    !isNonEmptyString(value.reportId) ||
    (value.reportState !== "draft" && value.reportState !== "formal") ||
    (value.statusLabel !== "DRAFT" && value.statusLabel !== "FORMAL") ||
    (value.contributionMode !== "weighted" &&
      value.contributionMode !== "facts_only") ||
    !isInteger(value.sourceProjectVersion, 1) ||
    !isInteger(value.reportVersion, 1) ||
    !isIsoDate(value.createdAt) ||
    !isInteger(value.eligibleCount, 1) ||
    !isInteger(value.confirmedCount, 0) ||
    !isInteger(value.requiredCount, 1) ||
    value.requiredCount > value.eligibleCount ||
    value.confirmedCount > value.eligibleCount ||
    value.disclaimer !== REPORT_DISCLAIMER ||
    !Array.isArray(value.items) ||
    items.length === 0 ||
    items.some((item) => item === null)
  ) {
    throw new Error("Invalid report export snapshot");
  }

  const requiredCount = Math.floor(value.eligibleCount / 2) + 1;
  if (
    value.requiredCount !== requiredCount ||
    (value.reportState === "draft" &&
      (value.statusLabel !== "DRAFT" ||
        value.formalizedAt !== null ||
        value.confirmedCount >= value.requiredCount)) ||
    (value.reportState === "formal" &&
      (value.statusLabel !== "FORMAL" ||
        !isIsoDate(value.formalizedAt) ||
        value.confirmedCount < value.requiredCount))
  ) {
    throw new Error("Invalid report export snapshot");
  }

  const typedItems = items as ProjectReportExportItem[];
  if (
    typedItems.some(
      (item) =>
        item.shareAuthority !== "1.0000" || item.shareDisplay !== "1.00",
    ) ||
    (value.contributionMode === "facts_only" &&
      typedItems.some(
        (item) =>
          item.taskWeightAuthority !== null ||
          item.taskWeightDisplay !== null ||
          item.contributionValueAuthority !== null ||
          item.contributionValueDisplay !== null,
      )) ||
    (value.contributionMode === "weighted" &&
      typedItems.some(
        (item) =>
          item.taskWeightAuthority === null ||
          item.taskWeightDisplay === null ||
          item.contributionValueAuthority === null ||
          item.contributionValueDisplay === null ||
          item.contributionValueAuthority !== item.taskWeightAuthority ||
          item.contributionValueDisplay !== item.taskWeightDisplay,
      ))
  ) {
    throw new Error("Invalid report export snapshot");
  }

  return {
    ...(value as Omit<ProjectReportExportSnapshot, "items">),
    items: typedItems,
  };
}

function neutralizeSpreadsheetText(value: string) {
  return /^[\t\r\n ]*[=+\-@]/.test(value) ? "'" + value : value;
}

function csvCell(value: string) {
  const escaped = value.replace(/"/g, '""');
  return /[",\r\n]/.test(escaped) ? `"${escaped}"` : escaped;
}

function csvText(value: string) {
  return csvCell(neutralizeSpreadsheetText(value));
}

function renderCsv(snapshot: ProjectReportExportSnapshot) {
  const columns = [
    "report_status",
    "formalized_at",
    "project_id",
    "project_name",
    "report_id",
    "task_id",
    "task_title",
    "member_name",
    "member_user_id",
    "task_weight_4dp",
    "task_weight_2dp",
    "share_4dp",
    "share_2dp",
    "contribution_value_4dp",
    "contribution_value_2dp",
    "completed_at",
    "disclaimer",
  ];

  const rows = snapshot.items.map((item) =>
    [
      csvCell(snapshot.statusLabel),
      csvCell(snapshot.formalizedAt ?? ""),
      csvCell(snapshot.projectId),
      csvText(snapshot.projectName),
      csvCell(snapshot.reportId),
      csvCell(item.taskId),
      csvText(item.taskTitle),
      csvText(item.memberDisplayName),
      csvCell(item.memberUserId ?? ""),
      csvCell(item.taskWeightAuthority ?? ""),
      csvCell(item.taskWeightDisplay ?? ""),
      csvCell(item.shareAuthority),
      csvCell(item.shareDisplay),
      csvCell(item.contributionValueAuthority ?? ""),
      csvCell(item.contributionValueDisplay ?? ""),
      csvCell(item.completedAt),
      csvCell(snapshot.disclaimer),
    ].join(","),
  );

  const csv = "\uFEFF" + [columns.join(","), ...rows].join("\r\n") + "\r\n";
  return new TextEncoder().encode(csv);
}

function normalizePdfText(value: string) {
  let sanitized = "";
  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0;
    const blockedControl =
      codePoint <= 0x08 ||
      (codePoint >= 0x0b && codePoint <= 0x0c) ||
      (codePoint >= 0x0e && codePoint <= 0x1f);
    sanitized += blockedControl ? " " : character;
  }
  return sanitized.replace(/\s+/g, " ").trim();
}

function reportLines(snapshot: ProjectReportExportSnapshot) {
  const lines = [
    "小猪作业贡献报告",
    `状态: ${snapshot.statusLabel}`,
    snapshot.reportState === "formal"
      ? `正式时间: ${snapshot.formalizedAt}`
      : "草稿状态: DRAFT",
    `项目: ${snapshot.projectName}`,
    `报告 ID: ${snapshot.reportId}`,
    `确认: ${snapshot.confirmedCount}/${snapshot.eligibleCount}（正式阈值 ${snapshot.requiredCount}）`,
    `贡献模式: ${snapshot.contributionMode}`,
    "",
  ];

  for (const item of snapshot.items) {
    lines.push(
      `任务: ${item.taskTitle}`,
      `成员: ${item.memberDisplayName}`,
      item.contributionValueDisplay === null
        ? "贡献: 仅事实模式"
        : `贡献: ${item.contributionValueDisplay}（权威值 ${item.contributionValueAuthority}）`,
      `完成时间: ${item.completedAt}`,
      "",
    );
  }

  lines.push("免责声明:", snapshot.disclaimer);
  return lines.map(normalizePdfText);
}

function pdfCharacterUnits(character: string) {
  const codePoint = character.codePointAt(0) ?? 0;
  return codePoint <= 0x7f ? 0.55 : 1;
}

function wrapPdfLine(value: string, maxUnits = 48) {
  const normalized = normalizePdfText(value);
  if (!normalized) return [""];
  const lines: string[] = [];
  let current = "";
  let units = 0;
  for (const character of normalized) {
    const safeCharacter =
      (character.codePointAt(0) ?? 0) <= 0xffff ? character : "?";
    const nextUnits = pdfCharacterUnits(safeCharacter);
    if (current && units + nextUnits > maxUnits) {
      lines.push(current);
      current = safeCharacter;
      units = nextUnits;
    } else {
      current += safeCharacter;
      units += nextUnits;
    }
  }
  lines.push(current);
  return lines;
}

function utf16BeHex(value: string) {
  let result = "";
  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0x3f;
    const bmp = codePoint <= 0xffff ? codePoint : 0x3f;
    result += bmp.toString(16).padStart(4, "0").toUpperCase();
  }
  return result;
}

function toUnicodeCMap(lines: string[]) {
  const codes = new Set<number>();
  for (const line of lines) {
    for (const character of line) {
      const codePoint = character.codePointAt(0) ?? 0x3f;
      codes.add(codePoint <= 0xffff ? codePoint : 0x3f);
    }
  }
  const sorted = [...codes].sort((left, right) => left - right);
  const mappings: string[] = [];
  for (let offset = 0; offset < sorted.length; offset += 100) {
    const chunk = sorted.slice(offset, offset + 100);
    mappings.push(
      `${chunk.length} beginbfchar`,
      ...chunk.map((codePoint) => {
        const hex = codePoint.toString(16).padStart(4, "0").toUpperCase();
        return `<${hex}> <${hex}>`;
      }),
      "endbfchar",
    );
  }
  return [
    "/CIDInit /ProcSet findresource begin",
    "12 dict begin",
    "begincmap",
    "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
    "/CMapName /XiaozhuWork-UCS def",
    "/CMapType 2 def",
    "1 begincodespacerange",
    "<0000> <FFFF>",
    "endcodespacerange",
    ...mappings,
    "endcmap",
    "CMapName currentdict /CMap defineresource pop",
    "end",
    "end",
  ].join("\n");
}

function pdfStream(content: string) {
  return `<< /Length ${content.length} >>\nstream\n${content}\nendstream`;
}

function buildPdf(objects: string[]) {
  const header = "%PDF-1.4\n";
  let body = header;
  const offsets = [0];
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(body.length);
    body += `${index + 1} 0 obj\n${objects[index]}\nendobj\n`;
  }
  const xrefOffset = body.length;
  body += `xref\n0 ${objects.length + 1}\n`;
  body += "0000000000 65535 f \n";
  for (let index = 1; index < offsets.length; index += 1) {
    body += `${String(offsets[index]).padStart(10, "0")} 00000 n \n`;
  }
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  body += `startxref\n${xrefOffset}\n%%EOF\n`;
  return new TextEncoder().encode(body);
}

function renderPdf(snapshot: ProjectReportExportSnapshot) {
  const wrappedLines = reportLines(snapshot).flatMap((line) =>
    wrapPdfLine(line),
  );
  const linesPerPage = 44;
  const pages: string[][] = [];
  for (let offset = 0; offset < wrappedLines.length; offset += linesPerPage) {
    pages.push(wrappedLines.slice(offset, offset + linesPerPage));
  }
  if (pages.length === 0) pages.push([""]);

  const fontId = 3 + pages.length * 2;
  const descendantFontId = fontId + 1;
  const fontDescriptorId = fontId + 2;
  const toUnicodeId = fontId + 3;
  const objects: string[] = new Array(toUnicodeId);

  objects[0] = "<< /Type /Catalog /Pages 2 0 R >>";
  const pageIds = pages.map((_, index) => 3 + index * 2);
  objects[1] = `<< /Type /Pages /Kids [${pageIds
    .map((id) => `${id} 0 R`)
    .join(" ")}] /Count ${pages.length} >>`;

  pages.forEach((pageLines, pageIndex) => {
    const pageId = 3 + pageIndex * 2;
    const contentId = pageId + 1;
    const operations = ["BT", "/F1 10 Tf"];
    pageLines.forEach((line, lineIndex) => {
      const y = 797 - lineIndex * 17;
      operations.push(`1 0 0 1 45 ${y} Tm <${utf16BeHex(line)}> Tj`);
    });
    operations.push("ET");
    const content = operations.join("\n");
    objects[pageId - 1] =
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 ${fontId} 0 R >> >> /Contents ${contentId} 0 R >>`;
    objects[contentId - 1] = pdfStream(content);
  });

  objects[fontId - 1] =
    `<< /Type /Font /Subtype /Type0 /BaseFont /STSong-Light /Encoding /UniGB-UCS2-H /DescendantFonts [${descendantFontId} 0 R] /ToUnicode ${toUnicodeId} 0 R >>`;
  objects[descendantFontId - 1] =
    `<< /Type /Font /Subtype /CIDFontType0 /BaseFont /STSong-Light /CIDSystemInfo << /Registry (Adobe) /Ordering (GB1) /Supplement 4 >> /FontDescriptor ${fontDescriptorId} 0 R /DW 1000 >>`;
  objects[fontDescriptorId - 1] =
    "<< /Type /FontDescriptor /FontName /STSong-Light /Flags 6 /FontBBox [-25 -254 1000 880] /ItalicAngle 0 /Ascent 880 /Descent -120 /CapHeight 880 /StemV 80 >>";
  const cMap = toUnicodeCMap(wrappedLines);
  objects[toUnicodeId - 1] = pdfStream(cMap);

  return buildPdf(objects);
}

export async function renderProjectReport(
  value: unknown,
  format: ReportExportFormat,
): Promise<RenderedProjectReport> {
  const snapshot = parseProjectReportExportSnapshot(value);
  if (format === "csv") {
    return {
      bytes: renderCsv(snapshot),
      contentType: "text/csv; charset=utf-8",
      extension: "csv",
    };
  }
  if (format === "pdf") {
    return {
      bytes: renderPdf(snapshot),
      contentType: "application/pdf",
      extension: "pdf",
    };
  }
  throw new Error("Unsupported report export format");
}
