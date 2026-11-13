import { readSupabaseBrowserEnvironment } from "@shared/supabase/environment";

export type OpsApiInput =
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

export type OpsApiErrorCode =
  | "UNAUTHENTICATED"
  | "FORBIDDEN"
  | "VALIDATION_FAILED"
  | "NOT_FOUND"
  | "SERVICE_UNAVAILABLE";

export type OpsApiResult<T = unknown> =
  | ({ ok: true } & Record<string, unknown> & { data?: T })
  | { ok: false; code: OpsApiErrorCode };

export async function callOpsApi<T = unknown>(
  input: OpsApiInput,
  accessToken: string,
  fetcher: typeof fetch = fetch,
): Promise<OpsApiResult<T>> {
  const env = readSupabaseBrowserEnvironment(import.meta.env);
  if (!env.configured || !accessToken) {
    return { ok: false, code: "SERVICE_UNAVAILABLE" };
  }

  try {
    const response = await fetcher(
      env.url.replace(/\/+$/, "") + "/functions/v1/ops-api",
      {
        method: "POST",
        headers: {
          apikey: env.key,
          authorization: "Bearer " + accessToken,
          "content-type": "application/json",
        },
        body: JSON.stringify(input),
        cache: "no-store",
      },
    );
    const payload = (await response.json()) as OpsApiResult<T>;
    if (
      !payload ||
      typeof payload !== "object" ||
      typeof payload.ok !== "boolean"
    ) {
      return { ok: false, code: "SERVICE_UNAVAILABLE" };
    }
    if (!payload.ok) {
      return [
        "UNAUTHENTICATED",
        "FORBIDDEN",
        "VALIDATION_FAILED",
        "NOT_FOUND",
        "SERVICE_UNAVAILABLE",
      ].includes(payload.code)
        ? payload
        : { ok: false, code: "SERVICE_UNAVAILABLE" };
    }
    return payload;
  } catch {
    return { ok: false, code: "SERVICE_UNAVAILABLE" };
  }
}
