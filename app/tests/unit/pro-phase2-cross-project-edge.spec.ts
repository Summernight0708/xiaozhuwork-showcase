import { describe, expect, it, vi } from "vitest";
import {
  handleCrossProjectRequest,
  parseCrossProjectInput,
} from "../../supabase/functions/cross-project-analytics/handler";
import { utcDays } from "../../supabase/functions/_shared/cross-project-aggregation";

const actor = "20000000-0000-4000-8000-000000000001";
const id = (n: number) =>
  "30000000-0000-4000-8000-" + String(n).padStart(12, "0");
const now = Date.parse("2026-10-03T00:00:00.000Z");
const from = "2026-09-30T00:00:00.000Z";
const to = "2026-10-03T00:00:00.000Z";
const config = { supabaseUrl: "http://local.test", anonKey: "public-anon-key" };
const request = (body: unknown, bearer = "Bearer user-jwt") =>
  new Request("https://edge.test", {
    method: "POST",
    headers: { authorization: bearer },
    body: JSON.stringify(body),
  });
const success = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
const analytics = (projectId: string) => ({
  ok: true,
  schemaVersion: 1,
  projectId,
  asOf: new Date(now).toISOString(),
  window: { from, to, bucket: "day", timezone: "UTC" },
  projectTimezone: "Asia/Shanghai",
  provenance: "current_rows",
  historyComplete: false,
  totals: {
    taskTotal: 1,
    completedTasks: 1,
    overdueTasks: 0,
    awaitingReviewTasks: 0,
    blockedTasks: 0,
    completedInWindow: 1,
  },
  difficultyDistribution: [1, 2, 3, 4, 5, null].map((stars, i) => ({
    stars,
    count: i === 0 ? 1 : 0,
  })),
  trends: utcDays(from, to).map((day, i) => ({
    day,
    created: i === 0 ? 1 : 0,
    completed: i === 1 ? 1 : 0,
  })),
});
function mockFetch(
  projectIds: string[],
  settings: {
    rejectCode?: string;
    revoke?: boolean;
    upstream?: (id: string) => unknown;
    missing?: boolean;
    authorization?: (value: string | null) => void;
  } = {},
) {
  let preflight = 0;
  const fetcher = vi.fn(
    async (url: string | URL | Request, options?: RequestInit) => {
      const path = String(url);
      settings.authorization?.(
        new Headers(options?.headers).get("authorization"),
      );
      if (path.includes("/auth/v1/user")) return success({ id: actor });
      if (path.endsWith("/get_my_cross_project_access")) {
        preflight++;
        if (settings.rejectCode)
          return success({ ok: false, code: settings.rejectCode });
        if (settings.revoke && preflight === 2)
          return success({ ok: false, code: "NOT_FOUND_OR_NOT_AUTHORIZED" });
        return success({ ok: true, schemaVersion: 1, projectIds });
      }
      if (path.endsWith("/get_project_analytics")) {
        if (settings.missing)
          return success({ message: "Could not find function" }, 404);
        const body = JSON.parse(String(options?.body));
        return success(
          settings.upstream?.(body.p_project_id) ??
            analytics(body.p_project_id),
        );
      }
      return success({}, 500);
    },
  );
  return fetcher as unknown as typeof fetch;
}
async function call(
  body: unknown,
  ids = [id(1)],
  settings: Parameters<typeof mockFetch>[1] = {},
) {
  const fetcher = mockFetch(ids, settings);
  const response = await handleCrossProjectRequest(
    request(body),
    config,
    fetcher,
    now,
  );
  return {
    response,
    json: (await response.json()) as Record<string, unknown>,
    fetcher,
  };
}

describe("F Edge function auth, revocation and C integration mock", () => {
  it("authenticates and calls each C RPC with the user's JWT then postchecks membership", async () => {
    const check = vi.fn();
    const { response, json, fetcher } = await call(
      { from, to, projectIds: [id(1), id(1), id(2)] },
      [id(1), id(2)],
      { authorization: check },
    );
    expect(response.status).toBe(200);
    expect(json.projectCount).toBe(2);
    expect(check).toHaveBeenCalledWith("Bearer user-jwt");
    expect(fetcher).toHaveBeenCalledTimes(5);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
  });
  it.each([
    "CAPABILITY_NOT_AVAILABLE",
    "CAPABILITY_REQUIRES_PRO",
    "NOT_FOUND_OR_NOT_AUTHORIZED",
    "QUERY_LIMIT_EXCEEDED",
  ])("returns complete request denial for %s", async (code) => {
    const { json, fetcher } = await call({ from, to }, [id(1)], {
      rejectCode: code,
    });
    expect(json).toEqual({ ok: false, code });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it("does not return any partial data if membership is revoked after C calls", async () => {
    const { json } = await call({ from, to }, [id(1)], { revoke: true });
    expect(json).toEqual({ ok: false, code: "NOT_FOUND_OR_NOT_AUTHORIZED" });
  });
  it("never returns partial data for a failing or missing C function", async () => {
    const { json: missing } = await call({ from, to }, [id(1)], {
      missing: true,
    });
    expect(missing).toEqual({ ok: false, code: "SERVICE_UNAVAILABLE" });
    const { json: invalid } = await call({ from, to }, [id(1), id(2)], {
      upstream: (projectId) =>
        projectId === id(2)
          ? { ok: false, code: "CAPABILITY_NOT_AVAILABLE" }
          : analytics(projectId),
    });
    expect(invalid).toEqual({ ok: false, code: "SERVICE_UNAVAILABLE" });
    const { json: inconsistent } = await call({ from, to }, [id(1)], {
      upstream: (projectId) => ({ ...analytics(projectId), schemaVersion: 2 }),
    });
    expect(inconsistent).toEqual({ ok: false, code: "SERVICE_UNAVAILABLE" });
  });
  it("rejects any mismatched authorized set", async () => {
    const { json } = await call({ from, to, projectIds: [id(1)] }, [id(2)]);
    expect(json).toEqual({ ok: false, code: "SERVICE_UNAVAILABLE" });
  });
  it("rejects missing auth and non-post method", async () => {
    const noToken = await handleCrossProjectRequest(
      request({ from, to }, ""),
      config,
      mockFetch([id(1)]),
      now,
    );
    expect(noToken.status).toBe(401);
    const options = await handleCrossProjectRequest(
      new Request("http://edge", { method: "OPTIONS" }),
      config,
      mockFetch([]),
      now,
    );
    expect(options.status).toBe(204);
  });
  it("accepts explicit zero projects and retains daily zero buckets", async () => {
    const { json } = await call({ from, to, projectIds: [] }, []);
    expect(json.projectCount).toBe(0);
    expect(json.completionRate).toBeNull();
    expect((json.trends as unknown[]).length).toBe(3);
  });
  it("enforces strict window, body fields, ids, dedup and 100 project cap", async () => {
    expect(() => parseCrossProjectInput({ from: to, to: from }, now)).toThrow();
    expect(() =>
      parseCrossProjectInput({ from, to, actorId: actor }, now),
    ).toThrow();
    expect(() =>
      parseCrossProjectInput({ from: "2026-09-30", to }, now),
    ).toThrow();
    expect(() =>
      parseCrossProjectInput({ from: "2026-01-01T00:00:00Z", to }, now),
    ).toThrow();
    expect(() =>
      parseCrossProjectInput({ from, to, projectIds: [id(1), "bad"] }, now),
    ).toThrow();
    expect(() =>
      parseCrossProjectInput(
        { from, to, projectIds: Array.from({ length: 101 }, (_, i) => id(i)) },
        now,
      ),
    ).toThrow();
    expect(
      parseCrossProjectInput({ from, to, projectIds: [id(1), id(1)] }, now)
        .projectIds,
    ).toEqual([id(1)]);
  });
  it("caps concurrency at four RPC calls", async () => {
    let concurrent = 0,
      peak = 0;
    const ids = Array.from({ length: 12 }, (_, i) => id(i + 1));
    const fetcher = vi.fn(
      async (url: string | URL | Request, options?: RequestInit) => {
        const name = String(url);
        if (name.includes("/auth/v1/user")) return success({ id: actor });
        if (name.includes("/get_my_cross_project_access"))
          return success({ ok: true, schemaVersion: 1, projectIds: ids });
        concurrent++;
        peak = Math.max(peak, concurrent);
        await new Promise((resolve) => setTimeout(resolve, 2));
        concurrent--;
        const projectId = JSON.parse(String(options?.body)).p_project_id;
        return success(analytics(projectId));
      },
    ) as unknown as typeof fetch;
    const res = await handleCrossProjectRequest(
      request({ from, to }),
      config,
      fetcher,
      now,
    );
    expect(res.status).toBe(200);
    expect(peak).toBeLessThanOrEqual(4);
    expect(peak).toBeGreaterThan(1);
  });
  it("rejects oversized streaming request bodies", async () => {
    const resp = await handleCrossProjectRequest(
      request({ from, to, padding: "a".repeat(20_000) }),
      config,
      mockFetch([]),
      now,
    );
    expect(resp.status).toBe(400);
  });
});
