import {
  parseProjectReportExportSnapshot,
  REPORT_DISCLAIMER,
  type ProjectReportExportItem,
  type ProjectReportExportSnapshot,
} from "./report-export.ts";

export type EnhancedReportEnvelope = {
  ok: true;
  schemaVersion: 1;
  reportId: string;
  projectId: string;
  snapshot: ProjectReportExportSnapshot;
};

export type EnhancedMemberRow = {
  key: string;
  name: string;
  userId: string | null;
  itemCount: number;
  value4dp: string | null;
  percent2dp: string | null;
  /** The exact scaled snapshot value. Never use JS floating-point to reweight. */
  valueUnits: bigint;
};

export const ENHANCED_REPORT_PROVENANCE =
  "来源：任务与验收记录、现有贡献报告快照及已确认的正式版本。成员占比为快照贡献值的展示性汇总，不是新的评分。";
export const ENHANCED_REPORT_MAX_ITEMS = 5000;
const FOUR_DP = /^\d{1,12}\.\d{4}$/;

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function units4(value: string): bigint {
  if (!FOUR_DP.test(value))
    throw new Error("Invalid enhanced report snapshot amount");
  return BigInt(value.replace(".", ""));
}

function fixed4(value: bigint): string {
  return `${value / 10000n}.${(value % 10000n).toString().padStart(4, "0")}`;
}

export function parseEnhancedReportEnvelope(
  value: unknown,
): EnhancedReportEnvelope {
  if (
    !record(value) ||
    value.ok !== true ||
    value.schemaVersion !== 1 ||
    typeof value.reportId !== "string" ||
    typeof value.projectId !== "string"
  ) {
    throw new Error("Invalid enhanced report envelope");
  }
  const snapshot = parseProjectReportExportSnapshot(value.snapshot);
  if (
    snapshot.reportState !== "formal" ||
    snapshot.statusLabel !== "FORMAL" ||
    snapshot.reportId !== value.reportId ||
    snapshot.projectId !== value.projectId ||
    snapshot.items.length > ENHANCED_REPORT_MAX_ITEMS
  ) {
    throw new Error("Invalid enhanced report snapshot");
  }
  return {
    ok: true,
    schemaVersion: 1,
    reportId: value.reportId,
    projectId: value.projectId,
    snapshot,
  };
}

export function summarizeEnhancedReport(
  snapshot: ProjectReportExportSnapshot,
): {
  members: EnhancedMemberRow[];
  totalValue4dp: string | null;
  totalValueUnits: bigint;
  weighted: boolean;
} {
  if (snapshot.reportState !== "formal")
    throw new Error("Enhanced report requires formal snapshot");
  const weighted = snapshot.contributionMode === "weighted";
  const byMember = new Map<string, EnhancedMemberRow>();
  let total = 0n;
  snapshot.items.forEach((item: ProjectReportExportItem) => {
    // A removed member has no stable user identity. Do not collapse unrelated
    // historical people with identical display names into a fabricated identity.
    const key = item.memberUserId ?? `removed:${item.taskId}`;
    let member = byMember.get(key);
    if (!member) {
      member = {
        key,
        name: item.memberDisplayName,
        userId: item.memberUserId,
        itemCount: 0,
        value4dp: null,
        percent2dp: null,
        valueUnits: 0n,
      };
      byMember.set(key, member);
    }
    member.itemCount += 1;
    if (weighted) {
      if (item.contributionValueAuthority === null) {
        throw new Error("Invalid enhanced report snapshot amount");
      }
      const amount = units4(item.contributionValueAuthority);
      member.valueUnits += amount;
      total += amount;
    }
  });

  const members = [...byMember.values()].map((member) => ({
    ...member,
    value4dp: weighted ? fixed4(member.valueUnits) : null,
    percent2dp:
      weighted && total > 0n
        ? `${(member.valueUnits * 10000n + total / 2n) / total / 100n}.${(((member.valueUnits * 10000n + total / 2n) / total) % 100n).toString().padStart(2, "0")}`
        : null,
  }));
  return {
    members,
    totalValue4dp: weighted ? fixed4(total) : null,
    totalValueUnits: total,
    weighted,
  };
}

function neutralizeCell(text: string): string {
  // Normalize embedded controls before CSV quoting: importing a multiline
  // cell in a lax spreadsheet must not expose a formula on the next row.
  const isFormula = /^[\s\uFEFF\u200B]*[=+\-@]/u.test(text);
  const normalized = text
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")
    .replace(/\t/g, "\\t")
    // Intentional control-character sanitization: CSV must never emit an active row break.
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ");
  return isFormula ? "'" + normalized : normalized;
}

function cell(value: string, untrusted = false): string {
  const safe = untrusted ? neutralizeCell(value) : value;
  const escaped = safe.replace(/"/g, '""');
  return /[",\r\n]/.test(escaped) ? `"${escaped}"` : escaped;
}

export const ENHANCED_CSV_COLUMNS = [
  "schema_version",
  "report_id",
  "report_version",
  "source_project_version",
  "project_id",
  "project_name",
  "report_state",
  "created_at",
  "formalized_at",
  "generated_at",
  "contribution_mode",
  "member_count",
  "item_count",
  "snapshot_total_contribution_4dp",
  "member_user_id",
  "member_display_name",
  "member_item_count",
  "member_total_contribution_4dp",
  "member_snapshot_percentage_2dp",
  "task_id",
  "task_title",
  "task_weight_4dp",
  "task_weight_display_2dp",
  "task_share_4dp",
  "task_share_display_2dp",
  "task_contribution_4dp",
  "task_contribution_display_2dp",
  "completed_at",
  "provenance",
  "disclaimer",
] as const;

export function renderEnhancedReportCsv(
  envelopeValue: unknown,
  generatedAt: string = new Date().toISOString(),
): Uint8Array {
  const { snapshot } = parseEnhancedReportEnvelope(envelopeValue);
  if (!Number.isFinite(Date.parse(generatedAt)))
    throw new Error("Invalid generation time");
  const totals = summarizeEnhancedReport(snapshot);
  const memberLookup = new Map(totals.members.map((row) => [row.key, row]));

  const rows = snapshot.items.map((item) => {
    const member = memberLookup.get(
      item.memberUserId ?? `removed:${item.taskId}`,
    )!;
    const fields: Array<[string, boolean?]> = [
      ["1"],
      [snapshot.reportId],
      [String(snapshot.reportVersion)],
      [String(snapshot.sourceProjectVersion)],
      [snapshot.projectId],
      [snapshot.projectName, true],
      ["FORMAL"],
      [snapshot.createdAt],
      [snapshot.formalizedAt!],
      [generatedAt],
      [snapshot.contributionMode],
      [String(totals.members.length)],
      [String(snapshot.items.length)],
      [totals.totalValue4dp ?? ""],
      [item.memberUserId ?? ""],
      [item.memberDisplayName, true],
      [String(member.itemCount)],
      [member.value4dp ?? ""],
      [member.percent2dp ?? ""],
      [item.taskId],
      [item.taskTitle, true],
      [item.taskWeightAuthority ?? ""],
      [item.taskWeightDisplay ?? ""],
      [item.shareAuthority],
      [item.shareDisplay],
      [item.contributionValueAuthority ?? ""],
      [item.contributionValueDisplay ?? ""],
      [item.completedAt],
      [ENHANCED_REPORT_PROVENANCE],
      [REPORT_DISCLAIMER],
    ];
    return fields.map(([value, untrusted]) => cell(value, untrusted)).join(",");
  });
  const csv =
    "\uFEFF" + [ENHANCED_CSV_COLUMNS.join(","), ...rows].join("\r\n") + "\r\n";
  return new TextEncoder().encode(csv);
}
