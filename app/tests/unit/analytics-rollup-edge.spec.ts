import { describe, expect, it, vi } from "vitest";

import {
  handleAnalyticsRollupRequest,
  type AnalyticsRollupDependencies,
} from "../../supabase/functions/analytics-rollup/handler";

const credential = "service-credential-for-local-test";

function request(body: unknown, bearer = credential, method = "POST") {
  return new Request("https://edge.test/functions/v1/analytics-rollup", {
    method,
    headers: {
      "content-type": "application/json",
      ...(bearer ? { authorization: "Bearer " + bearer } : {}),
    },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

function deps(
  now = new Date("2026-10-15T00:30:00.000Z"),
): AnalyticsRollupDependencies {
  return {
    serviceCredential: credential,
    now: () => now,
    runRollup: vi.fn(async () => ({
      ok: true as const,
      data: {
        fromDate: "2026-10-08",
        toDate: "2026-10-14",
        definitionVersion: 1,
        datesProcessed: 7,
      },
    })),
  };
}

describe("analytics rollup Edge boundary", () => {
  it("rejects non-POST, missing credentials, and wrong credentials", async () => {
    const d = deps();

    expect(
      (await handleAnalyticsRollupRequest(request({}, credential, "GET"), d))
        .status,
    ).toBe(405);
    expect(
      (await handleAnalyticsRollupRequest(request({}, ""), d)).status,
    ).toBe(401);
    expect(
      (await handleAnalyticsRollupRequest(request({}, "wrong-credential"), d))
        .status,
    ).toBe(403);
    expect(d.runRollup).not.toHaveBeenCalled();
  });

  it("defaults to the previous seven Asia/Shanghai dates", async () => {
    const d = deps();
    const response = await handleAnalyticsRollupRequest(
      request({ definitionVersion: 1 }),
      d,
    );

    expect(response.status).toBe(200);
    expect(d.runRollup).toHaveBeenCalledTimes(1);
    expect(d.runRollup).toHaveBeenCalledWith({
      fromDate: "2026-10-08",
      toDate: "2026-10-14",
      definitionVersion: 1,
    });
  });

  it("accepts exact manual backfill dates without changing them", async () => {
    const d = deps();
    await handleAnalyticsRollupRequest(
      request({
        fromDate: "2026-09-01",
        toDate: "2026-09-30",
        definitionVersion: 1,
      }),
      d,
    );

    expect(d.runRollup).toHaveBeenCalledWith({
      fromDate: "2026-09-01",
      toDate: "2026-09-30",
      definitionVersion: 1,
    });
  });

  it.each([
    {},
    { definitionVersion: 2 },
    { fromDate: "2026-10-01", definitionVersion: 1 },
    { toDate: "2026-10-01", definitionVersion: 1 },
    {
      fromDate: "2026-10-20",
      toDate: "2026-10-10",
      definitionVersion: 1,
    },
    {
      fromDate: "2026-02-30",
      toDate: "2026-03-01",
      definitionVersion: 1,
    },
  ])("rejects invalid scheduling input %#", async (body) => {
    const d = deps();
    const response = await handleAnalyticsRollupRequest(request(body), d);
    expect(response.status).toBe(400);
    expect(d.runRollup).not.toHaveBeenCalled();
  });

  it("surfaces database failures without doing metric math in Edge", async () => {
    const d = deps();
    vi.mocked(d.runRollup).mockResolvedValueOnce({
      ok: false,
      code: "ROLLUP_FAILED",
    });

    const response = await handleAnalyticsRollupRequest(
      request({ definitionVersion: 1 }),
      d,
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      ok: false,
      code: "ROLLUP_FAILED",
    });
  });
});
