import { describe, expect, test, vi } from "vitest";

import {
  ENHANCED_CSV_COLUMNS,
  parseEnhancedReportEnvelope,
  renderEnhancedReportCsv,
  summarizeEnhancedReport,
} from "../../supabase/functions/_shared/enhanced-report-export";
import { handleEnhancedReportRequest } from "../../supabase/functions/_shared/enhanced-report-edge";
import {
  renderProjectReport,
  REPORT_DISCLAIMER,
} from "../../supabase/functions/_shared/report-export";

const PROJECT = "b2000000-0000-4000-8000-000000000001";
const REPORT = "b8000000-0000-4000-8000-000000000001";
const MEMBER = "b1000000-0000-4000-8000-000000000001";
const SECOND = "b1000000-0000-4000-8000-000000000002";
const FORMALIZED = "2026-10-06T10:00:00.000Z";

function fixture(mode: "weighted" | "facts_only" = "weighted") {
  const item = (
    i: number,
    memberUserId: string | null,
    name: string,
    task: string,
    weight: number,
  ) => ({
    taskId: "b3000000-0000-4000-8000-" + i.toString().padStart(12, "0"),
    taskTitle: task,
    memberUserId,
    memberDisplayName: name,
    taskWeightAuthority: mode === "weighted" ? weight.toFixed(4) : null,
    taskWeightDisplay: mode === "weighted" ? weight.toFixed(2) : null,
    shareAuthority: "1.0000",
    shareDisplay: "1.00",
    contributionValueAuthority: mode === "weighted" ? weight.toFixed(4) : null,
    contributionValueDisplay: mode === "weighted" ? weight.toFixed(2) : null,
    completedAt: "2026-10-06T08:00:00.000Z",
  });
  const snapshot = {
    schemaVersion: 1,
    projectId: PROJECT,
    projectName: "课程项目",
    reportId: REPORT,
    reportState: "formal",
    statusLabel: "FORMAL",
    contributionMode: mode,
    sourceProjectVersion: 21,
    reportVersion: 3,
    createdAt: "2026-10-05T08:00:00.000Z",
    formalizedAt: FORMALIZED,
    eligibleCount: 2,
    confirmedCount: 2,
    requiredCount: 2,
    disclaimer: REPORT_DISCLAIMER,
    items: [
      item(1, MEMBER, "成员甲", "任务甲", 3),
      item(2, SECOND, "成员乙", "任务乙", 2),
    ],
  };
  return {
    ok: true,
    schemaVersion: 1,
    reportId: REPORT,
    projectId: PROJECT,
    snapshot,
  };
}
const encoded = (body: unknown) =>
  new TextDecoder().decode(renderEnhancedReportCsv(body, FORMALIZED));

describe("B enhanced report immutable snapshot and CSV", () => {
  test("retains F2 privacy masks through enhanced totals and CSV", () => {
    const envelope = fixture();
    envelope.snapshot.items[0]!.memberUserId = null;
    envelope.snapshot.items[0]!.memberDisplayName = "已注销成员";
    const csv = encoded(envelope);
    expect(csv).toContain("已注销成员");
    expect(csv).not.toContain(MEMBER);
    expect(csv).not.toContain("成员甲");
    expect(csv).toContain(SECOND);
    expect(
      summarizeEnhancedReport(parseEnhancedReportEnvelope(envelope).snapshot)
        .totalValue4dp,
    ).toBe("5.0000");
  });

  test("preserves base snapshot and both original Free formats", async () => {
    const snapshot = fixture().snapshot;
    const before = JSON.stringify(snapshot);
    const freeCsvBefore = (await renderProjectReport(snapshot, "csv")).bytes;
    const freePdfBefore = (await renderProjectReport(snapshot, "pdf")).bytes;
    const envelope = fixture();
    const csv = encoded(envelope);
    expect(csv).toContain(REPORT_DISCLAIMER);
    expect(JSON.stringify(snapshot)).toBe(before);
    expect(
      Array.from((await renderProjectReport(snapshot, "csv")).bytes),
    ).toEqual(Array.from(freeCsvBefore));
    expect(
      Array.from((await renderProjectReport(snapshot, "pdf")).bytes),
    ).toEqual(Array.from(freePdfBefore));
  });

  test("renders precise member totals without reweighting task facts or confounding task share", () => {
    const envelope = parseEnhancedReportEnvelope(fixture());
    const { members, totalValue4dp } = summarizeEnhancedReport(
      envelope.snapshot,
    );
    expect(totalValue4dp).toBe("5.0000");
    expect(members.map((m) => [m.value4dp, m.percent2dp, m.itemCount])).toEqual(
      [
        ["3.0000", "60.00", 1],
        ["2.0000", "40.00", 1],
      ],
    );
    const csv = encoded(envelope);
    expect(csv).toContain("source_project_version");
    expect(csv).toContain("member_snapshot_percentage_2dp");
    expect(csv).toContain("task_share_4dp");
    expect(csv).toContain(",3.0000,60.00,");
    expect(csv).toContain(",2.0000,40.00,");
    expect(csv).toContain(",1.0000,1.00,3.0000,3.00,");
    expect(csv).toContain(",1.0000,1.00,2.0000,2.00,");
    expect(
      Array.from(renderEnhancedReportCsv(envelope, FORMALIZED).slice(0, 3)),
    ).toEqual([0xef, 0xbb, 0xbf]);
    expect(csv.split("\r\n")[0]).toBe(ENHANCED_CSV_COLUMNS.join(","));
    expect(csv.split("\r\n")).toHaveLength(4);
  });

  test.each(["=2+2", "+cmd", "-HYPERLINK", "@SUM(1)", " \t=Evil", "\r\n@evil"])(
    "neutralizes untrusted spreadsheet input %s",
    (attack) => {
      const source = fixture();
      source.snapshot.projectName = attack;
      source.snapshot.items[0]!.taskTitle = attack;
      source.snapshot.items[0]!.memberDisplayName = attack;
      const csv = encoded(source);
      expect(csv).not.toMatch(/(?:^|\r\n)[=+\-@]/);
      expect(csv).toContain(
        "'" +
          attack
            .replace(/\r/g, "\\r")
            .replace(/\n/g, "\\n")
            .replace(/\t/g, "\\t"),
      );
      expect(csv).toContain(REPORT_DISCLAIMER);
    },
  );

  test("retains Unicode, quotes, commas and long text in valid RFC4180 rows", () => {
    const source = fixture();
    source.snapshot.projectName = '中文 café, "学习"';
    source.snapshot.items[0]!.taskTitle =
      "国际化 \u{1F31F} " + "中文".repeat(70);
    const csv = encoded(source);
    expect(csv).toContain('"中文 café, ""学习"""');
    expect(csv).toContain("国际化 🌟");
    expect(csv).toContain("中文".repeat(70));
  });

  test("rejects draft, mismatched versions/IDs, empty and corrupt snapshots", () => {
    const draft = fixture();
    draft.snapshot.reportState = "draft";
    draft.snapshot.statusLabel = "DRAFT";
    draft.snapshot.formalizedAt = null as unknown as string;
    expect(() => encoded(draft)).toThrow(/snapshot/i);
    const mismatch = fixture();
    mismatch.reportId = "b8000000-0000-4000-8000-000000000009";
    expect(() => encoded(mismatch)).toThrow(/snapshot/i);
    const empty = fixture();
    empty.snapshot.items = [];
    expect(() => encoded(empty)).toThrow(/snapshot/i);
    const corrupted = fixture();
    corrupted.snapshot.items[0]!.shareAuthority = "0.5000";
    expect(() => encoded(corrupted)).toThrow(/snapshot/i);
  });

  test("facts-only mode declines fabricated weights and percentages", () => {
    const value = fixture("facts_only");
    const summary = summarizeEnhancedReport(
      parseEnhancedReportEnvelope(value).snapshot,
    );
    expect(summary.weighted).toBe(false);
    expect(summary.totalValue4dp).toBeNull();
    expect(summary.members[0]?.percent2dp).toBeNull();
    const csv = encoded(value);
    expect(csv).toContain("facts_only");
    expect(csv).not.toContain(",60.00,");
  });
});

const config = { supabaseUrl: "https://local.example", anonKey: "anon-local" };
function call(body: unknown, token = "member-token"): Request {
  return new Request(
    "https://local.example/functions/v1/export-enhanced-project-report",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(token ? { authorization: "Bearer " + token } : {}),
      },
      body: JSON.stringify(body),
    },
  );
}
function ok(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

describe("B enhanced Edge authority, errors, and reliability", () => {
  const request = { reportId: REPORT, format: "csv" };
  function provider(data: unknown = fixture()) {
    return vi.fn(async (uri: RequestInfo | URL) =>
      String(uri).includes("/auth/v1/user") ? ok({ id: MEMBER }) : ok(data),
    ) as typeof fetch;
  }

  test("returns 401 before fetching anything without Bearer token", async () => {
    const upstream = provider();
    const response = await handleEnhancedReportRequest(
      call(request, ""),
      config,
      upstream,
    );
    expect(response.status).toBe(401);
    expect(upstream).not.toHaveBeenCalled();
  });
  test("returns 400 on UUID, format, extra fields, JSON and size errors", async () => {
    const upstream = provider();
    for (const input of [
      { reportId: "oops", format: "pdf" },
      { reportId: REPORT, format: "xlsx" },
      { ...request, projectId: PROJECT },
    ])
      expect(
        (await handleEnhancedReportRequest(call(input), config, upstream))
          .status,
      ).toBe(400);
    const oversized = call({
      reportId: REPORT,
      format: "csv",
      padding: "z".repeat(5000),
    });
    expect(
      (await handleEnhancedReportRequest(oversized, config, upstream)).status,
    ).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  test.each([
    ["UNAUTHENTICATED", 401],
    ["NOT_FOUND_OR_NOT_AUTHORIZED", 404],
    ["REPORT_NOT_READY", 409],
    ["CAPABILITY_NOT_AVAILABLE", 403],
    ["CAPABILITY_REQUIRES_PRO", 403],
    ["VALIDATION_FAILED", 400],
    ["INTERNAL_SQL_MESSAGE", 502],
  ])(
    "maps RPC %s to HTTP %i without leaking internals",
    async (code, status) => {
      const fetchStub = provider({ ok: false, code, sql: "secret" });
      const response = await handleEnhancedReportRequest(
        call(request),
        config,
        fetchStub,
      );
      expect(response.status).toBe(status);
      const json = await response.json();
      expect(json).toEqual({
        ok: false,
        code: code === "INTERNAL_SQL_MESSAGE" ? "SERVICE_UNAVAILABLE" : code,
      });
      expect(fetchStub).toHaveBeenCalledTimes(2);
    },
  );

  test("blocks invalid response snapshot and upstream failures", async () => {
    const corrupted = fixture();
    corrupted.snapshot.reportId = "b8000000-0000-4000-8000-000000000009";
    expect(
      (
        await handleEnhancedReportRequest(
          call(request),
          config,
          provider(corrupted),
        )
      ).status,
    ).toBe(502);
    const outage = vi.fn(async () => {
      throw new Error("database: sensitive");
    }) as typeof fetch;
    const response = await handleEnhancedReportRequest(
      call(request),
      config,
      outage,
    );
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain("sensitive");
  });

  test("exports signed-in snapshot with secure headers, no business writes, repeatable download", async () => {
    const upstream = provider();
    const response = await handleEnhancedReportRequest(
      call(request),
      config,
      upstream,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^text\/csv/);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("content-disposition")).toContain(
      "xiaozhu-enhanced-report-" + REPORT,
    );
    expect(await response.text()).toContain("60.00");
    const spy = upstream as typeof fetch & {
      mock: { calls: Array<[RequestInfo | URL, RequestInit?]> };
    };
    const calls = spy.mock.calls.map(([url, options]) => ({
      url: String(url),
      options,
    }));
    expect(calls.map((x) => x.url)).toEqual([
      config.supabaseUrl + "/auth/v1/user",
      config.supabaseUrl + "/rest/v1/rpc/get_enhanced_project_report_export",
    ]);
    expect(calls[1]!.options?.body).toBe(
      JSON.stringify({ p_report_id: REPORT }),
    );
    expect(calls[1]!.options?.headers).toEqual(
      expect.objectContaining({ authorization: "Bearer member-token" }),
    );
    expect(
      (await handleEnhancedReportRequest(call(request), config, upstream))
        .status,
    ).toBe(200);
  });

  test("handles PDF via injected renderer, never relying on untrusted project ID", async () => {
    const renderer = vi.fn(async () =>
      new TextEncoder().encode("%PDF-1.4\nTEST"),
    );
    const response = await handleEnhancedReportRequest(
      call({ reportId: REPORT, format: "pdf" }),
      config,
      provider(),
      renderer,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/pdf");
    expect((await response.text()).startsWith("%PDF")).toBe(true);
    expect(renderer).toHaveBeenCalledOnce();
  });

  test("refuses cancelled/aborted requests, upstream invalid JSON, and oversized RPC response", async () => {
    const aborted = call(request);
    // jsdom AbortSignal and undici Request use incompatible realm brands.
    // Simulate an already-disconnected HTTP request without issuing I/O.
    Object.defineProperty(aborted, "signal", { value: { aborted: true } });
    const upstream = provider();
    const fail = vi.fn(
      async () => new Response("{", { status: 200 }),
    ) as typeof fetch;
    expect(
      (await handleEnhancedReportRequest(call(request), config, fail)).status,
    ).toBe(502);
    expect(
      (await handleEnhancedReportRequest(aborted, config, upstream)).status,
    ).toBe(502);
    expect(upstream).not.toHaveBeenCalled();
    const huge = vi.fn(async (uri: RequestInfo | URL) =>
      String(uri).includes("/auth/")
        ? ok({ id: MEMBER })
        : ok({ payload: "x".repeat(9 * 1024 * 1024) }),
    ) as typeof fetch;
    expect(
      (await handleEnhancedReportRequest(call(request), config, huge)).status,
    ).toBe(502);
  });
});
