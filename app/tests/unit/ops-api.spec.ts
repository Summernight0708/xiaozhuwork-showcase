import { describe, expect, it, vi } from "vitest";

import { handleOpsRequest } from "../../supabase/functions/ops-api/handler";

const operatorId = "0a000000-0000-4000-8000-000000000001";
const config = {
  supabaseUrl: "https://db.example.test",
  anonKey: "public-anon-key",
  serviceRoleKey: "service-role-secret",
  allowedOrigins: [
    "https://ops.xiaozhuwork.com",
    "http://127.0.0.1:5174",
    "http://localhost:5174",
  ],
} as const;

function request(
  body: unknown,
  options: {
    origin?: string;
    bearer?: string;
    method?: string;
  } = {},
) {
  const headers = new Headers();
  const origin = options.origin ?? "https://ops.xiaozhuwork.com";
  const bearer = options.bearer ?? "user-jwt";
  if (origin) headers.set("origin", origin);
  if (bearer) headers.set("authorization", "Bearer " + bearer);
  if ((options.method ?? "POST") !== "OPTIONS") {
    headers.set("content-type", "application/json");
  }
  return new Request("https://edge.example.test/functions/v1/ops-api", {
    method: options.method ?? "POST",
    headers,
    body:
      (options.method ?? "POST") === "OPTIONS"
        ? undefined
        : JSON.stringify(body),
  });
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

type RpcCall = {
  name: string;
  body: Record<string, unknown>;
  auth: string | null;
};

function fetchMock(
  options: {
    userStatus?: number;
    userId?: string;
    access?: unknown;
    rpc?: Record<string, unknown>;
  } = {},
) {
  const calls: RpcCall[] = [];
  const fetcher = vi.fn(
    async (url: string | URL | Request, init?: RequestInit) => {
      const path = String(url);
      const headers = new Headers(init?.headers);
      if (path.endsWith("/auth/v1/user")) {
        return json(
          options.userStatus && options.userStatus !== 200
            ? { message: "invalid token" }
            : { id: options.userId ?? operatorId },
          options.userStatus ?? 200,
        );
      }

      const marker = "/rest/v1/rpc/";
      const index = path.indexOf(marker);
      if (index >= 0) {
        const name = path.slice(index + marker.length);
        const body = JSON.parse(String(init?.body ?? "{}")) as Record<
          string,
          unknown
        >;
        calls.push({
          name,
          body,
          auth: headers.get("authorization"),
        });

        if (name === "ops_assert_access_service") {
          return json(
            options.access ?? { ok: true, data: { userId: operatorId } },
          );
        }
        return json(
          options.rpc?.[name] ?? {
            ok: true,
            data: { schemaVersion: 1, marker: name },
          },
        );
      }

      return json({ message: "unexpected" }, 500);
    },
  );
  return { fetcher: fetcher as unknown as typeof fetch, calls };
}

async function call(
  body: unknown,
  fetchSettings: Parameters<typeof fetchMock>[0] = {},
  requestSettings: Parameters<typeof request>[1] = {},
) {
  const mocked = fetchMock(fetchSettings);
  const response = await handleOpsRequest(
    request(body, requestSettings),
    config,
    mocked.fetcher,
  );
  let payload: unknown = null;
  if (response.status !== 204) payload = await response.json();
  return { response, payload, calls: mocked.calls, fetcher: mocked.fetcher };
}

describe("ops-api security boundary", () => {
  it.each([
    "https://ops.xiaozhuwork.com",
    "http://127.0.0.1:5174",
    "http://localhost:5174",
  ])("allows exact configured OPTIONS origin %s", async (origin) => {
    const mocked = fetchMock();
    const response = await handleOpsRequest(
      request(null, { origin, method: "OPTIONS" }),
      config,
      mocked.fetcher,
    );

    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-origin")).toBe(origin);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(mocked.fetcher).not.toHaveBeenCalled();
  });

  it.each([
    "https://evil.example",
    "https://ops.xiaozhuwork.com.evil.example",
    "",
  ])("rejects non-allowlisted origin %s", async (origin) => {
    const { response, payload, fetcher } = await call(
      { action: "access" },
      {},
      { origin },
    );

    expect(response.status).toBe(403);
    expect(payload).toEqual({ ok: false, code: "FORBIDDEN" });
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("returns 401 before any privileged request when bearer is missing", async () => {
    const { response, payload, fetcher } = await call(
      { action: "access" },
      {},
      { bearer: "" },
    );
    expect(response.status).toBe(401);
    expect(payload).toEqual({ ok: false, code: "UNAUTHENTICATED" });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("returns 401 when Supabase rejects the JWT", async () => {
    const { response, payload, calls } = await call(
      { action: "access" },
      { userStatus: 401 },
    );
    expect(response.status).toBe(401);
    expect(payload).toEqual({ ok: false, code: "UNAUTHENTICATED" });
    expect(calls).toHaveLength(0);
  });

  it.each([
    { ok: false, code: "FORBIDDEN" },
    { ok: false, code: "FORBIDDEN", disabled: true },
  ])("returns 403 for normal or disabled XiaozhuWork users", async (access) => {
    const { response, payload, calls } = await call(
      { action: "access" },
      { access },
    );
    expect(response.status).toBe(403);
    expect(payload).toEqual({ ok: false, code: "FORBIDDEN" });
    expect(calls).toHaveLength(1);
    expect(calls[0]?.name).toBe("ops_assert_access_service");
  });

  it("derives operator id only from verified JWT and rejects forged input", async () => {
    const { response, payload, calls } = await call({
      action: "account.lookup",
      query: "target@example.test",
      requestId: "0e000000-0000-4000-8000-000000000001",
      operatorUserId: "ffffffff-ffff-4fff-8fff-ffffffffffff",
    });

    expect(response.status).toBe(400);
    expect(payload).toEqual({ ok: false, code: "VALIDATION_FAILED" });
    expect(calls).toHaveLength(0);
  });

  it("calls atomic account lookup with verified operator and service headers", async () => {
    const expected = {
      ok: true,
      data: {
        schemaVersion: 1,
        userId: "0b000000-0000-4000-8000-000000000001",
        email: "target@example.test",
        recentActivity: [],
      },
    };
    const { response, payload, calls } = await call(
      {
        action: "account.lookup",
        query: "target@example.test",
        requestId: "0e000000-0000-4000-8000-000000000001",
      },
      {
        rpc: {
          ops_get_account_support_summary_service: expected,
        },
      },
    );

    expect(response.status).toBe(200);
    expect(payload).toEqual(expected);
    expect(calls).toEqual([
      {
        name: "ops_assert_access_service",
        body: { p_operator_user_id: operatorId },
        auth: "Bearer service-role-secret",
      },
      {
        name: "ops_get_account_support_summary_service",
        body: {
          p_operator_user_id: operatorId,
          p_query: "target@example.test",
          p_request_id: "0e000000-0000-4000-8000-000000000001",
        },
        auth: "Bearer service-role-secret",
      },
    ]);
    expect(JSON.stringify(payload)).not.toContain("service-role-secret");
    expect(response.headers.get("cache-control")).toBe("private, no-store");
  });

  it("forwards overview without client-supplied lifecycle at", async () => {
    const { response, calls } = await call({
      action: "analytics.overview",
      from: "2026-10-01T00:00:00.000Z",
      to: "2026-10-08T00:00:00.000Z",
      definitionVersion: 1,
    });

    expect(response.status).toBe(200);
    expect(calls[1]).toEqual({
      name: "ops_get_product_analytics_service",
      body: {
        p_from: "2026-10-01T00:00:00.000Z",
        p_to: "2026-10-08T00:00:00.000Z",
        p_definition_version: 1,
      },
      auth: "Bearer service-role-secret",
    });
    expect(calls[1]?.body).not.toHaveProperty("p_at");
  });

  it("forwards only frozen timeseries parameters", async () => {
    const { response, calls } = await call({
      action: "analytics.timeseries",
      fromDate: "2026-10-01",
      toDate: "2026-10-08",
      definitionVersion: 1,
    });

    expect(response.status).toBe(200);
    expect(calls[1]).toEqual({
      name: "ops_get_product_timeseries_service",
      body: {
        p_from_date: "2026-10-01",
        p_to_date: "2026-10-08",
        p_definition_version: 1,
      },
      auth: "Bearer service-role-secret",
    });
  });

  it.each([
    {
      action: "analytics.overview",
      from: "2026-10-01T00:00:00.000Z",
      to: "2026-10-08T00:00:00.000Z",
      definitionVersion: 2,
    },
    {
      action: "analytics.overview",
      from: "2026-10-08T00:00:00.000Z",
      to: "2026-10-01T00:00:00.000Z",
      definitionVersion: 1,
    },
    {
      action: "analytics.overview",
      from: "2026-10-01T00:00:00.000Z",
      to: "2026-10-08T00:00:00.000Z",
      definitionVersion: 1,
      at: "2026-10-08T00:00:00.000Z",
    },
    {
      action: "analytics.timeseries",
      fromDate: "2026-10-01",
      toDate: "2026-10-08",
      definitionVersion: 2,
    },
    {
      action: "analytics.timeseries",
      fromDate: "2026-10-08",
      toDate: "2026-10-01",
      definitionVersion: 1,
    },
  ])("rejects invalid/future analytics contracts", async (body) => {
    const { response, payload, calls } = await call(body);
    expect(response.status).toBe(400);
    expect(payload).toEqual({ ok: false, code: "VALIDATION_FAILED" });
    expect(calls).toHaveLength(0);
  });

  it("maps account lookup validation/not-found failures without leaking upstream details", async () => {
    for (const [code, status] of [
      ["VALIDATION_FAILED", 400],
      ["NOT_FOUND", 404],
    ] as const) {
      const { response, payload } = await call(
        {
          action: "account.lookup",
          query: "target@example.test",
          requestId: "0e000000-0000-4000-8000-000000000001",
        },
        {
          rpc: {
            ops_get_account_support_summary_service: {
              ok: false,
              code,
              secret: "service-role-secret",
            },
          },
        },
      );
      expect(response.status).toBe(status);
      expect(payload).toEqual({ ok: false, code });
      expect(JSON.stringify(payload)).not.toContain("service-role-secret");
    }
  });

  it("returns service unavailable for incomplete server configuration", async () => {
    const mocked = fetchMock();
    const response = await handleOpsRequest(
      request({ action: "access" }),
      { ...config, serviceRoleKey: "" },
      mocked.fetcher,
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      ok: false,
      code: "SERVICE_UNAVAILABLE",
    });
    expect(mocked.fetcher).not.toHaveBeenCalled();
  });
});
