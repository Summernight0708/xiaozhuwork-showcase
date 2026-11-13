const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@%_]+@[^\s@%_]+\.[^\s@%_]+$/i;
const UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_BODY_BYTES = 16_384;

export type OpsErrorCode =
  | "UNAUTHENTICATED"
  | "FORBIDDEN"
  | "VALIDATION_FAILED"
  | "NOT_FOUND"
  | "SERVICE_UNAVAILABLE";

export type OpsHandlerConfig = {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  allowedOrigins: readonly string[];
};

type OpsInput =
  | { action: "access" }
  | { action: "account.lookup"; query: string; requestId: string }
  | {
      action: "analytics.overview";
      from: string;
      to: string;
      definitionVersion: 1;
    }
  | {
      action: "analytics.timeseries";
      fromDate: string;
      toDate: string;
      definitionVersion: 1;
    };

class ApiError extends Error {
  constructor(
    public code: OpsErrorCode,
    public status: number,
  ) {
    super(code);
  }
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError("VALIDATION_FAILED", 400);
  }
  return value as Record<string, unknown>;
}

function exactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return (
    actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index])
  );
}

function validUtc(value: unknown): value is string {
  if (typeof value !== "string" || !UTC.test(value)) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed);
}

function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !DATE.test(value)) return false;
  const parsed = Date.parse(value + "T00:00:00.000Z");
  return (
    Number.isFinite(parsed) &&
    new Date(parsed).toISOString().slice(0, 10) === value
  );
}

function parseInput(value: unknown): OpsInput {
  const data = record(value);

  if (data.action === "access") {
    if (!exactKeys(data, ["action"])) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    return { action: "access" };
  }

  if (data.action === "account.lookup") {
    if (!exactKeys(data, ["action", "query", "requestId"])) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    if (
      typeof data.query !== "string" ||
      typeof data.requestId !== "string" ||
      !UUID.test(data.requestId)
    ) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    const query = data.query.trim();
    if (
      query.length < 3 ||
      query.length > 320 ||
      (!UUID.test(query) && !EMAIL.test(query))
    ) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    return {
      action: "account.lookup",
      query,
      requestId: data.requestId.toLowerCase(),
    };
  }

  if (data.action === "analytics.overview") {
    if (!exactKeys(data, ["action", "from", "to", "definitionVersion"])) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    if (
      data.definitionVersion !== 1 ||
      !validUtc(data.from) ||
      !validUtc(data.to) ||
      Date.parse(data.from) >= Date.parse(data.to)
    ) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    return {
      action: "analytics.overview",
      from: new Date(Date.parse(data.from)).toISOString(),
      to: new Date(Date.parse(data.to)).toISOString(),
      definitionVersion: 1,
    };
  }

  if (data.action === "analytics.timeseries") {
    if (
      !exactKeys(data, ["action", "fromDate", "toDate", "definitionVersion"])
    ) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    if (
      data.definitionVersion !== 1 ||
      !validDate(data.fromDate) ||
      !validDate(data.toDate) ||
      data.fromDate > data.toDate
    ) {
      throw new ApiError("VALIDATION_FAILED", 400);
    }
    return {
      action: "analytics.timeseries",
      fromDate: data.fromDate,
      toDate: data.toDate,
      definitionVersion: 1,
    };
  }

  throw new ApiError("VALIDATION_FAILED", 400);
}

async function boundedJson(request: Request): Promise<unknown> {
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError("VALIDATION_FAILED", 400);

  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BODY_BYTES) {
        throw new ApiError("VALIDATION_FAILED", 400);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }

  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new ApiError("VALIDATION_FAILED", 400);
  }
}

function originFor(request: Request, config: OpsHandlerConfig): string | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  return config.allowedOrigins.includes(origin) ? origin : null;
}

function responseHeaders(origin: string | null): Headers {
  const headers = new Headers({
    "cache-control": "private, no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff",
    vary: "Origin",
  });
  if (origin) {
    headers.set("access-control-allow-origin", origin);
    headers.set(
      "access-control-allow-headers",
      "authorization, apikey, content-type, x-client-info",
    );
    headers.set("access-control-allow-methods", "POST, OPTIONS");
  }
  return headers;
}

function json(origin: string | null, payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: responseHeaders(origin),
  });
}

function failure(
  origin: string | null,
  code: OpsErrorCode,
  status: number,
): Response {
  return json(origin, { ok: false, code }, status);
}

function configured(config: OpsHandlerConfig): boolean {
  return (
    /^https?:\/\//.test(config.supabaseUrl) &&
    config.anonKey.trim().length > 0 &&
    config.serviceRoleKey.trim().length > 0 &&
    config.allowedOrigins.length > 0 &&
    config.allowedOrigins.every(
      (origin) => /^https?:\/\/[^/]+(?::\d+)?$/.test(origin) && origin !== "*",
    )
  );
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new ApiError("SERVICE_UNAVAILABLE", 503);
  }
}

function mapRpcResult(value: unknown, origin: string): Response {
  const data = record(value);
  if (data.ok === true) return json(origin, value);

  switch (data.code) {
    case "FORBIDDEN":
      return failure(origin, "FORBIDDEN", 403);
    case "VALIDATION_FAILED":
      return failure(origin, "VALIDATION_FAILED", 400);
    case "NOT_FOUND":
      return failure(origin, "NOT_FOUND", 404);
    default:
      return failure(origin, "SERVICE_UNAVAILABLE", 503);
  }
}

export async function handleOpsRequest(
  request: Request,
  config: OpsHandlerConfig,
  fetcher: typeof fetch = fetch,
): Promise<Response> {
  const origin = originFor(request, config);
  if (!origin) return failure(null, "FORBIDDEN", 403);

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: responseHeaders(origin),
    });
  }
  if (request.method !== "POST") {
    return failure(origin, "VALIDATION_FAILED", 405);
  }
  if (!configured(config)) {
    return failure(origin, "SERVICE_UNAVAILABLE", 503);
  }

  try {
    const input = parseInput(await boundedJson(request));

    const authorization = request.headers.get("authorization")?.trim() ?? "";
    const bearer = /^Bearer\s+(\S+)$/i.exec(authorization)?.[1];
    if (!bearer) throw new ApiError("UNAUTHENTICATED", 401);

    const base = config.supabaseUrl.replace(/\/+$/, "");
    const userResponse = await fetcher(base + "/auth/v1/user", {
      method: "GET",
      headers: {
        apikey: config.anonKey,
        authorization: "Bearer " + bearer,
      },
      cache: "no-store",
    });
    if (!userResponse.ok) throw new ApiError("UNAUTHENTICATED", 401);

    const user = record(await readJson(userResponse));
    if (typeof user.id !== "string" || !UUID.test(user.id)) {
      throw new ApiError("UNAUTHENTICATED", 401);
    }
    const operatorId = user.id.toLowerCase();

    const serviceHeaders = {
      apikey: config.serviceRoleKey,
      authorization: "Bearer " + config.serviceRoleKey,
      "content-type": "application/json",
      accept: "application/json",
    };

    async function serviceRpc(
      name: string,
      args: Record<string, unknown>,
    ): Promise<unknown> {
      let response: Response;
      try {
        response = await fetcher(base + "/rest/v1/rpc/" + name, {
          method: "POST",
          headers: serviceHeaders,
          body: JSON.stringify(args),
          cache: "no-store",
        });
      } catch {
        throw new ApiError("SERVICE_UNAVAILABLE", 503);
      }
      if (!response.ok) throw new ApiError("SERVICE_UNAVAILABLE", 503);
      return readJson(response);
    }

    const access = record(
      await serviceRpc("ops_assert_access_service", {
        p_operator_user_id: operatorId,
      }),
    );
    if (access.ok !== true) {
      if (access.code === "FORBIDDEN") {
        throw new ApiError("FORBIDDEN", 403);
      }
      throw new ApiError("SERVICE_UNAVAILABLE", 503);
    }

    if (input.action === "access") {
      return json(origin, {
        ok: true,
        data: { userId: operatorId },
      });
    }

    if (input.action === "account.lookup") {
      return mapRpcResult(
        await serviceRpc("ops_get_account_support_summary_service", {
          p_operator_user_id: operatorId,
          p_query: input.query,
          p_request_id: input.requestId,
        }),
        origin,
      );
    }

    if (input.action === "analytics.overview") {
      return mapRpcResult(
        await serviceRpc("ops_get_product_analytics_service", {
          p_from: input.from,
          p_to: input.to,
          p_definition_version: input.definitionVersion,
        }),
        origin,
      );
    }

    return mapRpcResult(
      await serviceRpc("ops_get_product_timeseries_service", {
        p_from_date: input.fromDate,
        p_to_date: input.toDate,
        p_definition_version: input.definitionVersion,
      }),
      origin,
    );
  } catch (error) {
    if (error instanceof ApiError) {
      return failure(origin, error.code, error.status);
    }
    return failure(origin, "SERVICE_UNAVAILABLE", 503);
  }
}
