declare const Deno: {
  makeTempDir(options: { prefix: string }): Promise<string>;
  writeFile(path: string, bytes: Uint8Array): Promise<void>;
  stat(path: string): Promise<{ size: number }>;
  remove(path: string, options: { recursive: boolean }): Promise<void>;
  Command: new (
    executable: string,
    options: { args: string[]; stdout: "piped"; stderr: "piped" },
  ) => {
    output(): Promise<{ code: number; stdout: Uint8Array; stderr: Uint8Array }>;
  };
  test(name: string, fn: () => Promise<void>): void;
};

import { renderEnhancedReportPdf } from "../../functions/_shared/enhanced-report-pdf.ts";
import {
  parseEnhancedReportEnvelope,
  renderEnhancedReportCsv,
} from "../../functions/_shared/enhanced-report-export.ts";
import { REPORT_DISCLAIMER } from "../../functions/_shared/report-export.ts";

function assert(condition: unknown, description: string): asserts condition {
  if (!condition) throw new Error(description);
}

function fixture(count = 2, mode: "weighted" | "facts_only" = "weighted") {
  const projectId = "b2000000-0000-4000-8000-000000000001";
  const reportId = "b8000000-0000-4000-8000-000000000001";
  return {
    ok: true,
    schemaVersion: 1,
    reportId,
    projectId,
    snapshot: {
      schemaVersion: 1,
      projectId,
      projectName: "中文项目名称测试" + "超长课程项目".repeat(40) + " 🌟 café",
      reportId,
      reportState: "formal",
      statusLabel: "FORMAL",
      contributionMode: mode,
      sourceProjectVersion: 8,
      reportVersion: 5,
      createdAt: "2026-10-05T08:00:00.000Z",
      formalizedAt: "2026-10-06T10:00:00.000Z",
      eligibleCount: Math.max(1, count),
      confirmedCount: Math.max(1, count),
      requiredCount: Math.floor(Math.max(1, count) / 2) + 1,
      disclaimer: REPORT_DISCLAIMER,
      items: Array.from({ length: count }, (_, i) => ({
        taskId:
          "b3000000-0000-4000-8000-" + (i + 1).toString().padStart(12, "0"),
        taskTitle:
          "作业任务 " + (i + 1) + " 中文测试 " + "很长的多行任务名".repeat(9),
        memberUserId:
          "b1000000-0000-4000-8000-" + (i + 1).toString().padStart(12, "0"),
        memberDisplayName: "姓名：" + i + " 王同学 测试",
        taskWeightAuthority:
          mode === "weighted" ? ((i % 5) + 1).toFixed(4) : null,
        taskWeightDisplay:
          mode === "weighted" ? ((i % 5) + 1).toFixed(2) : null,
        shareAuthority: "1.0000",
        shareDisplay: "1.00",
        contributionValueAuthority:
          mode === "weighted" ? ((i % 5) + 1).toFixed(4) : null,
        contributionValueDisplay:
          mode === "weighted" ? ((i % 5) + 1).toFixed(2) : null,
        completedAt: "2026-10-05T08:00:00.000Z",
      })),
    },
  };
}

const decoder = new TextDecoder("latin1");
async function verifyExtractable(bytes: Uint8Array) {
  const dir = await Deno.makeTempDir({ prefix: "xiaozhu-b-pdf-" });
  const pdf = dir + "/report.pdf";
  try {
    await Deno.writeFile(pdf, bytes);
    const result = await new Deno.Command("pdftotext", {
      args: ["-enc", "UTF-8", pdf, "-"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      result.code === 0,
      "pdftotext failed: " + new TextDecoder().decode(result.stderr),
    );
    const text = new TextDecoder().decode(result.stdout);
    assert(text.includes("小猪作业"), "Chinese branding cannot be extracted");
    assert(text.includes("王同学"), "Chinese member names cannot be extracted");
    assert(
      text.includes(REPORT_DISCLAIMER),
      "PDF disclaimer cannot be extracted",
    );
    assert(text.includes("café"), "Latin Unicode cannot be extracted");
    const raster = await new Deno.Command("pdftoppm", {
      args: [
        "-f",
        "1",
        "-l",
        "1",
        "-r",
        "72",
        "-png",
        "-singlefile",
        pdf,
        dir + "/first-page",
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      raster.code === 0,
      "PDF first page could not render: " +
        new TextDecoder().decode(raster.stderr),
    );
    assert(
      (await Deno.stat(dir + "/first-page.png")).size > 3000,
      "PDF raster output is missing or empty",
    );
    return text;
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test(
  "B PDF renders valid embedded font, ToUnicode, provenance, and extracted Unicode",
  async () => {
    const bytes = await renderEnhancedReportPdf(
      fixture(),
      "2026-10-06T12:34:56Z",
    );
    const raw = decoder.decode(bytes);
    assert(raw.startsWith("%PDF-1.4"), "PDF magic");
    assert(raw.includes("/Subtype /CIDFontType2"), "CID font missing");
    assert(raw.includes("/FontFile2"), "embedded font missing");
    assert(raw.includes("/ToUnicode"), "Unicode map missing");
    assert(raw.includes("/CIDToGIDMap"), "CIDToGIDMap missing");
    assert(raw.includes("/FlateDecode"), "embedded font compressed");
    assert(bytes.length < 25 * 1024 * 1024, "PDF too large");
    const text = await verifyExtractable(bytes);
    assert(text.includes("展示占比"), "contribution chart/table label missing");
    assert(text.includes("正式报告版本"), "formal version metadata missing");
  },
);

Deno.test(
  "B PDF paginates many members and renders intact long names and task rows",
  async () => {
    const e = fixture(125);
    const bytes = await renderEnhancedReportPdf(e, "2026-10-06T12:34:56Z");
    const text = await verifyExtractable(bytes);
    assert(text.includes("姓名：124"), "last member clipped");
    assert(text.includes("记录 125"), "last task record clipped");
    const matches = [
      ...decoder.decode(bytes).matchAll(/\/Type \/Page \/Parent /g),
    ];
    assert(
      matches.length > 15,
      "expected multiple content pages for 125 members",
    );
  },
);

Deno.test(
  "B facts-only does not invent contribution percentage or hours",
  async () => {
    const bytes = await renderEnhancedReportPdf(
      fixture(1, "facts_only"),
      "2026-10-06T12:34:56Z",
    );
    const text = await verifyExtractable(bytes);
    assert(text.includes("仅事实模式"), "facts-only explanation missing");
    assert(text.includes("不适用"), "percentage should be unavailable");
    assert(!text.includes("工作小时"), "no invented work hours");
  },
);

Deno.test("B invalid empty/mismatched/draft snapshot is refused", async () => {
  const empty = fixture(0);
  let rejected = false;
  try {
    await renderEnhancedReportPdf(empty);
  } catch {
    rejected = true;
  }
  assert(rejected, "empty report should fail");
  const broken = fixture();
  broken.reportId = "b8000000-0000-4000-8000-000000000009";
  rejected = false;
  try {
    await renderEnhancedReportPdf(broken);
  } catch {
    rejected = true;
  }
  assert(rejected, "report identity mismatch should fail");
  const snapshot = parseEnhancedReportEnvelope(fixture());
  assert(snapshot.snapshot.items.length === 2, "snapshot test failure");
  assert(
    renderEnhancedReportCsv(snapshot).byteLength > 100,
    "CSV rendering failed",
  );
});
