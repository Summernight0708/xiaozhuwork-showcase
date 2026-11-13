import { createHash } from "node:crypto";
import { mkdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";

import {
  REPORT_DISCLAIMER,
  renderProjectReport,
  type ProjectReportExportSnapshot,
} from "../supabase/functions/_shared/report-export.ts";

const outputPath = resolve(process.argv[2] ?? ".tmp/xiaozhuwork-report-probe.pdf");

const snapshot: ProjectReportExportSnapshot = {
  schemaVersion: 1,
  projectId: "f2000000-0000-0000-0000-000000000001",
  projectName: "课程项目",
  reportId: "f8000000-0000-0000-0000-000000000001",
  reportState: "formal",
  statusLabel: "FORMAL",
  contributionMode: "weighted",
  sourceProjectVersion: 7,
  reportVersion: 2,
  createdAt: "2026-09-29T10:00:00.000Z",
  formalizedAt: "2026-09-29T12:34:56.000Z",
  eligibleCount: 3,
  confirmedCount: 2,
  requiredCount: 2,
  disclaimer: REPORT_DISCLAIMER,
  items: [
    {
      taskId: "f3000000-0000-0000-0000-000000000001",
      taskTitle: "实现导出",
      memberUserId: "f1000000-0000-0000-0000-000000000002",
      memberDisplayName: "成员甲",
      taskWeightAuthority: "3.0000",
      taskWeightDisplay: "3.00",
      shareAuthority: "1.0000",
      shareDisplay: "1.00",
      contributionValueAuthority: "3.0000",
      contributionValueDisplay: "3.00",
      completedAt: "2026-09-29T09:00:00.000Z",
    },
    {
      taskId: "f3000000-0000-0000-0000-000000000002",
      taskTitle: "整理结果",
      memberUserId: "f1000000-0000-0000-0000-000000000003",
      memberDisplayName: "成员乙",
      taskWeightAuthority: "2.0000",
      taskWeightDisplay: "2.00",
      shareAuthority: "1.0000",
      shareDisplay: "1.00",
      contributionValueAuthority: "2.0000",
      contributionValueDisplay: "2.00",
      completedAt: "2026-09-29T09:30:00.000Z",
    },
  ],
};

const sourcePaths = [
  resolve("supabase/functions/export-project-report/index.ts"),
  resolve("supabase/functions/_shared/report-export.ts"),
];
const sourceBytes = sourcePaths.reduce(
  (total, path) => total + statSync(path).size,
  0,
);

const warmup = await renderProjectReport(snapshot, "pdf");
const iterations = 1_000;
const cpuBefore = process.cpuUsage();
const resourceBefore = process.resourceUsage();
const wallStart = performance.now();

let rendered = warmup;
for (let index = 0; index < iterations; index += 1) {
  rendered = await renderProjectReport(snapshot, "pdf");
}

const batchWallMs = performance.now() - wallStart;
const cpuDelta = process.cpuUsage(cpuBefore);
const resourceAfter = process.resourceUsage();
const batchCpuTotalMs = (cpuDelta.user + cpuDelta.system) / 1000;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, rendered.bytes);

const result = {
  outputPath,
  sha256: createHash("sha256").update(rendered.bytes).digest("hex"),
  localSourceBundleBytes: sourceBytes,
  pdfBytes: rendered.bytes.length,
  iterations,
  batchWallMs: Number(batchWallMs.toFixed(3)),
  wallPerGenerationMs: Number((batchWallMs / iterations).toFixed(4)),
  batchCpuTotalMs: Number(batchCpuTotalMs.toFixed(3)),
  cpuPerGenerationMs: Number((batchCpuTotalMs / iterations).toFixed(4)),
  maxRssBeforeKiB: resourceBefore.maxRSS,
  maxRssAfterKiB: resourceAfter.maxRSS,
};

console.log(JSON.stringify(result, null, 2));
