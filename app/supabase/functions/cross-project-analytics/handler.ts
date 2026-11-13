import {
  aggregateProjectAnalytics,
  ContractError,
  utcDays,
  type Window,
} from "../_shared/cross-project-aggregation.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UTC = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/;
const MAX_BODY_BYTES = 16_384;
const MAX_WINDOW_MS = 180 * 86_400_000;
const MAX_PROJECTS = 100;

type RequestInput = { window: Window; projectIds: string[] | null };
type ErrorCode =
  | "UNAUTHENTICATED"
  | "VALIDATION_FAILED"
  | "METHOD_NOT_ALLOWED"
  | "CAPABILITY_NOT_AVAILABLE"
  | "CAPABILITY_REQUIRES_PRO"
  | "NOT_FOUND_OR_NOT_AUTHORIZED"
  | "QUERY_LIMIT_EXCEEDED"
  | "SERVICE_UNAVAILABLE";

class ApiError extends Error {
  constructor(public code: ErrorCode) {
    super(code);
  }
}

function statusOf(code: ErrorCode): number {
  switch (code) {
    case "UNAUTHENTICATED":
      return 401;
    case "METHOD_NOT_ALLOWED":
      return 405;
    case "VALIDATION_FAILED":
      return 400;
    case "QUERY_LIMIT_EXCEEDED":
      return 413;
    case "CAPABILITY_NOT_AVAILABLE":
    case "CAPABILITY_REQUIRES_PRO":
      return 403;
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
      return 404;
    default:
      return 503;
  }
}

const headers = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "private, no-store",
  "content-type": "application/json; charset=utf-8",
  "x-content-type-options": "nosniff",
};

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), { status, headers });
}

function failure(code: ErrorCode) {
  return json({ ok: false, code }, statusOf(code));
}

function record(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new ApiError("VALIDATION_FAILED");
  return input as Record<string, unknown>;
}

function readUtc(value: unknown): string {
  if (typeof value !== "string" || !UTC.test(value))
    throw new ApiError("VALIDATION_FAILED");
  const ms = Date.parse(value);
  if (
    !Number.isFinite(ms) ||
    new Date(ms).toISOString() !==
      (value.includes(".")
        ? new Date(ms).toISOString()
        : value.replace("Z", ".000Z"))
  )
    throw new ApiError("VALIDATION_FAILED");
  return new Date(ms).toISOString();
}

export function parseCrossProjectInput(
  value: unknown,
  now = Date.now(),
): RequestInput {
  const data = record(value);
  if (
    Object.keys(data).some((key) => !["from", "to", "projectIds"].includes(key))
  )
    throw new ApiError("VALIDATION_FAILED");
  const from = readUtc(data.from);
  const to = readUtc(data.to);
  if (
    Date.parse(from) >= Date.parse(to) ||
    Date.parse(to) - Date.parse(from) > MAX_WINDOW_MS ||
    Date.parse(to) > now + 60_000
  )
    throw new ApiError("VALIDATION_FAILED");
  utcDays(from, to);
  let projectIds: string[] | null = null;
  if (Object.prototype.hasOwnProperty.call(data, "projectIds")) {
    if (!Array.isArray(data.projectIds) || data.projectIds.length > 500)
      throw new ApiError("VALIDATION_FAILED");
    if (data.projectIds.some((id) => typeof id !== "string" || !UUID.test(id)))
      throw new ApiError("VALIDATION_FAILED");
    projectIds = [
      ...new Set((data.projectIds as string[]).map((id) => id.toLowerCase())),
    ];
    if (projectIds.length > MAX_PROJECTS)
      throw new ApiError("QUERY_LIMIT_EXCEEDED");
  }
  return { window: { from, to, bucket: "day", timezone: "UTC" }, projectIds };
}

async function boundedBody(request: Request): Promise<unknown> {
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError("VALIDATION_FAILED");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BODY_BYTES) throw new ApiError("VALIDATION_FAILED");
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
    throw new ApiError("VALIDATION_FAILED");
  }
}

function checkedIds(value: unknown): string[] {
  const result = record(value);
  if (
    result.ok !== true ||
    result.schemaVersion !== 1 ||
    !Array.isArray(result.projectIds) ||
    result.projectIds.length > MAX_PROJECTS ||
    result.projectIds.some((id) => typeof id !== "string" || !UUID.test(id))
  )
    throw new ApiError("SERVICE_UNAVAILABLE");
  const ids = (result.projectIds as string[]).map((id) => id.toLowerCase());
  if (new Set(ids).size !== ids.length)
    throw new ApiError("SERVICE_UNAVAILABLE");
  return ids;
}

function rpcFailure(value: unknown, upstream = false): never {
  const code = record(value).code;
  if (code === "UNAUTHENTICATED") throw new ApiError("UNAUTHENTICATED");
  if (code === "NOT_FOUND_OR_NOT_AUTHORIZED")
    throw new ApiError("NOT_FOUND_OR_NOT_AUTHORIZED");
  if (code === "CAPABILITY_NOT_AVAILABLE")
    throw new ApiError(
      upstream ? "SERVICE_UNAVAILABLE" : "CAPABILITY_NOT_AVAILABLE",
    );
  if (code === "CAPABILITY_REQUIRES_PRO" && !upstream)
    throw new ApiError("CAPABILITY_REQUIRES_PRO");
  if (code === "QUERY_LIMIT_EXCEEDED" && !upstream)
    throw new ApiError("QUERY_LIMIT_EXCEEDED");
  if (code === "VALIDATION_FAILED" && !upstream)
    throw new ApiError("VALIDATION_FAILED");
  throw new ApiError("SERVICE_UNAVAILABLE");
}

export type HandlerConfig = { supabaseUrl: string; anonKey: string };

export async function handleCrossProjectRequest(
  request: Request,
  config: HandlerConfig,
  fetcher: typeof fetch = fetch,
  now = Date.now(),
): Promise<Response> {
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return failure("METHOD_NOT_ALLOWED");
  try {
    if (!config.supabaseUrl || !config.anonKey)
      throw new ApiError("SERVICE_UNAVAILABLE");
    const authorization = request.headers.get("authorization")?.trim();
    const bearer = /^Bearer\s+(\S+)$/i.exec(authorization ?? "")?.[1];
    if (!bearer) throw new ApiError("UNAUTHENTICATED");
    const input = parseCrossProjectInput(await boundedBody(request), now);
    const authHeaders = {
      apikey: config.anonKey,
      authorization: "Bearer " + bearer,
    };
    const base = config.supabaseUrl.replace(/\/+$/, "");
    const globalAbort = AbortSignal.timeout(25_000);

    async function call(url: string, options: RequestInit): Promise<unknown> {
      try {
        const response = await fetcher(url, {
          ...options,
          headers: { ...authHeaders, ...(options.headers ?? {}) },
          cache: "no-store",
          signal: AbortSignal.any([globalAbort, AbortSignal.timeout(10_000)]),
        });
        if (!response.ok) {
          if (url.includes("/auth/v1/user") || response.status === 401)
            throw new ApiError("UNAUTHENTICATED");
          throw new ApiError("SERVICE_UNAVAILABLE");
        }
        return await response.json();
      } catch (error) {
        if (error instanceof ApiError) throw error;
        throw new ApiError("SERVICE_UNAVAILABLE");
      }
    }
    async function rpc(name: string, args: Record<string, unknown>) {
      return call(base + "/rest/v1/rpc/" + name, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify(args),
      });
    }
    const user = await call(base + "/auth/v1/user", { method: "GET" });
    const userId = record(user).id;
    if (typeof userId !== "string" || !UUID.test(userId))
      throw new ApiError("UNAUTHENTICATED");

    // The database derives and authorizes IDs; user-supplied projectIds only filters.
    const discovered = await rpc("get_my_cross_project_access", {
      p_project_ids: input.projectIds,
    });
    if (record(discovered).ok !== true) rpcFailure(discovered);
    const ids = checkedIds(discovered);
    if (
      input.projectIds !== null &&
      (ids.length !== input.projectIds.length ||
        ids.some((id) => !input.projectIds!.includes(id)))
    )
      throw new ApiError("SERVICE_UNAVAILABLE");

    // At most four in-flight C reads; every call carries the end user's JWT.
    const responses: unknown[] = new Array(ids.length);
    let next = 0;
    let stopped = false;
    let firstError: unknown = null;
    async function worker() {
      while (!stopped && next < ids.length) {
        const i = next++;
        try {
          const response = await rpc("get_project_analytics", {
            p_project_id: ids[i],
            p_from: input.window.from,
            p_to: input.window.to,
          });
          if (record(response).ok !== true) rpcFailure(response, true);
          responses[i] = response;
        } catch (error) {
          stopped = true;
          firstError ??= error;
        }
      }
    }
    await Promise.all(Array.from({ length: Math.min(4, ids.length) }, worker));
    if (firstError) throw firstError;

    const aggregate = aggregateProjectAnalytics(
      responses,
      ids,
      input.window,
      now,
    );

    // Revocations and entitlement expiry during the request fail closed.
    const verified = await rpc("get_my_cross_project_access", {
      p_project_ids: ids,
    });
    if (record(verified).ok !== true) rpcFailure(verified);
    const latestIds = checkedIds(verified);
    if (
      latestIds.length !== ids.length ||
      latestIds.some((id, i) => id !== ids[i])
    )
      throw new ApiError("NOT_FOUND_OR_NOT_AUTHORIZED");

    return json(aggregate);
  } catch (error) {
    if (error instanceof ApiError) return failure(error.code);
    if (error instanceof ContractError) return failure("SERVICE_UNAVAILABLE");
    return failure("SERVICE_UNAVAILABLE");
  }
}
