import { describe, expect, test } from "vitest";

import {
  renderProjectReport,
  type ProjectReportExportSnapshot,
} from "../../supabase/functions/_shared/report-export";

const DISCLAIMER = "仅供参考，不代表教师评分或成员能力评价";

function utf16BeHex(value: string) {
  return [...value]
    .map((character) =>
      (character.codePointAt(0) ?? 0x3f)
        .toString(16)
        .padStart(4, "0")
        .toUpperCase(),
    )
    .join("");
}

function snapshot(
  overrides: Partial<ProjectReportExportSnapshot> = {},
): ProjectReportExportSnapshot {
  return {
    schemaVersion: 1,
    projectId: "a2000000-0000-0000-0000-000000000001",
    projectName: "课程项目",
    reportId: "a8000000-0000-0000-0000-000000000001",
    reportState: "draft",
    statusLabel: "DRAFT",
    contributionMode: "weighted",
    sourceProjectVersion: 7,
    reportVersion: 2,
    createdAt: "2026-09-29T10:00:00.000Z",
    formalizedAt: null,
    eligibleCount: 3,
    confirmedCount: 1,
    requiredCount: 2,
    disclaimer: DISCLAIMER,
    items: [
      {
        taskId: "a3000000-0000-0000-0000-000000000001",
        taskTitle: "实现导出",
        memberUserId: "a1000000-0000-0000-0000-000000000002",
        memberDisplayName: "成员甲",
        taskWeightAuthority: "3.0000",
        taskWeightDisplay: "3.00",
        shareAuthority: "1.0000",
        shareDisplay: "1.00",
        contributionValueAuthority: "3.0000",
        contributionValueDisplay: "3.00",
        completedAt: "2026-09-29T09:00:00.000Z",
      },
    ],
    ...overrides,
  };
}

describe("project report export renderer", () => {
  test("preserves F2 masked identities and numeric facts in CSV and PDF", async () => {
    const original = snapshot().items[0]!;
    const masked = snapshot({
      items: [
        { ...original, memberUserId: null, memberDisplayName: "已注销成员" },
        {
          ...original,
          taskId: "peer-task",
          memberUserId: "peer-id",
          memberDisplayName: "保留成员",
        },
      ],
    });
    const csv = new TextDecoder().decode(
      (await renderProjectReport(masked, "csv")).bytes,
    );
    const pdf = new TextDecoder().decode(
      (await renderProjectReport(masked, "pdf")).bytes,
    );
    expect(csv).toContain("已注销成员,,3.0000,3.00");
    expect(csv).toContain("保留成员,peer-id");
    expect(csv).not.toContain(original.memberUserId);
    expect(pdf).toContain(utf16BeHex("已注销成员"));
    expect(pdf).toContain(utf16BeHex("保留成员"));
    expect(pdf).not.toContain(utf16BeHex(original.memberDisplayName));
  });

  test("renders deterministic RFC 4180 CSV with BOM, stable columns, draft marker, and disclaimer", async () => {
    const result = await renderProjectReport(snapshot(), "csv");

    expect(result.contentType).toBe("text/csv; charset=utf-8");
    expect(result.extension).toBe("csv");
    expect(result.bytes[0]).toBe(0xef);
    expect(result.bytes[1]).toBe(0xbb);
    expect(result.bytes[2]).toBe(0xbf);

    const csv = new TextDecoder().decode(result.bytes);
    expect(csv).toContain(
      "report_status,formalized_at,project_id,project_name,report_id,task_id,task_title,member_name,member_user_id,task_weight_4dp,task_weight_2dp,share_4dp,share_2dp,contribution_value_4dp,contribution_value_2dp,completed_at,disclaimer\r\n",
    );
    expect(csv).toContain("DRAFT");
    expect(csv).toContain("3.0000,3.00,1.0000,1.00,3.0000,3.00");
    expect(csv).toContain(DISCLAIMER);
    expect(csv.endsWith("\r\n")).toBe(true);
  });

  test("neutralizes spreadsheet formulas only in untrusted text cells without changing numeric values", async () => {
    const malicious = snapshot({
      projectName: '=HYPERLINK("https://evil.example")',
      items: [
        {
          ...snapshot().items[0]!,
          taskTitle: "+cmd|' /C calc'!A0",
          memberDisplayName: "@SUM(1+1)",
        },
      ],
    });

    const csv = new TextDecoder().decode(
      (await renderProjectReport(malicious, "csv")).bytes,
    );
    expect(csv).toContain('"\'=HYPERLINK(""https://evil.example"")"');
    expect(csv).toContain(",'+cmd|' /C calc'!A0,");
    expect(csv).toContain("'@SUM(1+1)");
    expect(csv).toContain("3.0000,3.00,1.0000,1.00,3.0000,3.00");
  });

  test("renders a lightweight Type 0/CID PDF with extractable Chinese mappings", async () => {
    const result = await renderProjectReport(snapshot(), "pdf");
    expect(result.contentType).toBe("application/pdf");
    expect(result.extension).toBe("pdf");
    expect(result.bytes.length).toBeGreaterThan(2_000);
    expect(result.bytes.length).toBeLessThan(100_000);

    const raw = new TextDecoder("latin1").decode(result.bytes);
    expect(raw.startsWith("%PDF-1.4")).toBe(true);
    expect(raw).toContain("/Subtype /Type0");
    expect(raw).toContain("/Encoding /UniGB-UCS2-H");
    expect(raw).toContain("/ToUnicode");
    expect(raw).toContain(utf16BeHex(DISCLAIMER));
  });

  test("renders a semantically valid formal snapshot with the FORMAL state and timestamp", async () => {
    const result = await renderProjectReport(
      snapshot({
        reportState: "formal",
        statusLabel: "FORMAL",
        formalizedAt: "2026-09-29T12:34:56.000Z",
        confirmedCount: 2,
      }),
      "pdf",
    );
    const raw = new TextDecoder("latin1").decode(result.bytes);
    expect(raw).toContain(utf16BeHex("状态: FORMAL"));
    expect(raw).toContain(utf16BeHex("正式时间: 2026-09-29T12:34:56.000Z"));
  });

  test("rejects semantically inconsistent report snapshots", async () => {
    const invalidSnapshots: ProjectReportExportSnapshot[] = [
      snapshot({ eligibleCount: 4, requiredCount: 2 }),
      snapshot({ confirmedCount: 2, requiredCount: 2 }),
      snapshot({
        reportState: "formal",
        statusLabel: "FORMAL",
        formalizedAt: "2026-09-29T12:34:56.000Z",
        confirmedCount: 1,
      }),
      snapshot({ items: [] }),
      snapshot({
        items: [
          {
            ...snapshot().items[0]!,
            taskWeightAuthority: null,
            taskWeightDisplay: null,
            contributionValueAuthority: null,
            contributionValueDisplay: null,
          },
        ],
      }),
      snapshot({
        items: [
          {
            ...snapshot().items[0]!,
            shareAuthority: "0.5000",
            shareDisplay: "0.50",
          },
        ],
      }),
    ];

    for (const invalid of invalidSnapshots) {
      await expect(renderProjectReport(invalid, "csv")).rejects.toThrow(
        /snapshot/i,
      );
    }
  });
  test("rejects malformed authoritative snapshots instead of rendering guessed data", async () => {
    await expect(
      renderProjectReport(
        {
          ...snapshot(),
          disclaimer: "wrong",
        },
        "csv",
      ),
    ).rejects.toThrow(/snapshot/i);

    await expect(
      renderProjectReport(
        {
          ...snapshot(),
          reportState: "formal",
          statusLabel: "FORMAL",
          formalizedAt: null,
        },
        "pdf",
      ),
    ).rejects.toThrow(/snapshot/i);
  });
});
