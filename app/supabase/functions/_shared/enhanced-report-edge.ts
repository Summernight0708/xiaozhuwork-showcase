import {
  parseEnhancedReportEnvelope,
  renderEnhancedReportCsv,
} from "./enhanced-report-export.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REQUEST = 4096;
const MAX_RPC_RESPONSE = 8 * 1024 * 1024;
const MAX_OUTPUT = 25 * 1024 * 1024;
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};
export type EnhancedEdgeConfig = { supabaseUrl: string; anonKey: string };
type PdfRenderer = (
  snapshot: ReturnType<typeof parseEnhancedReportEnvelope>,
  generatedAt: string,
) => Promise<Uint8Array>;

function responseJson(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS,
      "cache-control": "private, no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
}

async function boundedText(
  response: Response | Request,
  limit: number,
): Promise<string> {
  if (Number(response.headers.get("content-length")) > limit) {
    throw new Error("Response exceeds size limit");
  }
  if (!response.body) throw new Error("Missing response body");
  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > limit) throw new Error("Response exceeds size limit");
      parts.push(next.value);
    }
  } finally {
    await reader.cancel().catch(() => undefined);
  }
  const joined = new Uint8Array(size);
  let cursor = 0;
  for (const part of parts) {
    joined.set(part, cursor);
    cursor += part.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(joined);
}

function failureStatus(code: string): number {
  switch (code) {
    case "UNAUTHENTICATED":
      return 401;
    case "VALIDATION_FAILED":
      return 400;
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
      return 404;
    case "REPORT_NOT_READY":
      return 409;
    case "CAPABILITY_NOT_AVAILABLE":
    case "CAPABILITY_REQUIRES_PRO":
      return 403;
    default:
      return 502;
  }
}

function fail(code: string, status = failureStatus(code)) {
  return responseJson({ ok: false, code }, status);
}

export async function handleEnhancedReportRequest(
  request: Request,
  config: EnhancedEdgeConfig,
  fetchImpl: typeof fetch = fetch,
  renderPdf?: PdfRenderer,
): Promise<Response> {
  if (request.method === "OPTIONS")
    return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST") return fail("METHOD_NOT_ALLOWED", 405);
  if (request.signal.aborted) return fail("SERVICE_UNAVAILABLE");

  const match = /^Bearer\s+([^\s]{1,4096})$/i.exec(
    request.headers.get("authorization") ?? "",
  );
  if (!match) return fail("UNAUTHENTICATED");
  if (!config.anonKey || !/^https?:\/\/[^\s/]+/i.test(config.supabaseUrl)) {
    return fail("SERVICE_UNAVAILABLE");
  }
  if (
    !/^application\/json(?:\s*;|$)/i.test(
      request.headers.get("content-type") ?? "",
    )
  ) {
    return fail("VALIDATION_FAILED");
  }

  let input: unknown;
  try {
    input = JSON.parse(await boundedText(request, MAX_REQUEST));
  } catch {
    return fail("VALIDATION_FAILED");
  }
  if (
    !input ||
    typeof input !== "object" ||
    Array.isArray(input) ||
    Object.keys(input).some((key) => key !== "reportId" && key !== "format") ||
    typeof (input as { reportId?: unknown }).reportId !== "string" ||
    !UUID.test((input as { reportId: string }).reportId) ||
    !["csv", "pdf"].includes(String((input as { format?: unknown }).format))
  )
    return fail("VALIDATION_FAILED");

  const { reportId, format } = input as {
    reportId: string;
    format: "csv" | "pdf";
  };
  const headers = {
    authorization: `Bearer ${match[1]}`,
    apikey: config.anonKey,
  };
  const base = config.supabaseUrl.replace(/\/$/, "");
  try {
    const auth = await fetchImpl(`${base}/auth/v1/user`, {
      headers,
      signal: request.signal,
      cache: "no-store",
    });
    if (!auth.ok) {
      return auth.status === 400 || auth.status === 401 || auth.status === 403
        ? fail("UNAUTHENTICATED")
        : fail("SERVICE_UNAVAILABLE");
    }
    const user = JSON.parse(await boundedText(auth, 32 * 1024)) as unknown;
    if (
      !user ||
      typeof user !== "object" ||
      !("id" in user) ||
      typeof (user as { id: unknown }).id !== "string"
    )
      return fail("UNAUTHENTICATED");

    const rpc = await fetchImpl(
      `${base}/rest/v1/rpc/get_enhanced_project_report_export`,
      {
        method: "POST",
        headers: {
          ...headers,
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify({ p_report_id: reportId }),
        signal: request.signal,
        cache: "no-store",
      },
    );
    if (!rpc.ok) return fail("SERVICE_UNAVAILABLE");
    const body = JSON.parse(
      await boundedText(rpc, MAX_RPC_RESPONSE),
    ) as unknown;
    if (
      body &&
      typeof body === "object" &&
      !Array.isArray(body) &&
      "ok" in body &&
      (body as { ok?: unknown }).ok === false &&
      "code" in body &&
      typeof (body as { code?: unknown }).code === "string"
    ) {
      const code = (body as { code: string }).code;
      // Do not forward unknown internal codes or database exception details.
      return fail(
        [
          "UNAUTHENTICATED",
          "NOT_FOUND_OR_NOT_AUTHORIZED",
          "REPORT_NOT_READY",
          "CAPABILITY_NOT_AVAILABLE",
          "CAPABILITY_REQUIRES_PRO",
          "VALIDATION_FAILED",
        ].includes(code)
          ? code
          : "SERVICE_UNAVAILABLE",
      );
    }
    const envelope = parseEnhancedReportEnvelope(body);
    if (envelope.reportId.toLowerCase() !== reportId.toLowerCase()) {
      return fail("SERVICE_UNAVAILABLE");
    }

    const generatedAt = new Date().toISOString();
    let bytes: Uint8Array;
    if (format === "csv") {
      bytes = renderEnhancedReportCsv(envelope, generatedAt);
    } else if (renderPdf) {
      bytes = await renderPdf(envelope, generatedAt);
    } else {
      const module = await import("./enhanced-report-pdf.ts");
      bytes = await module.renderEnhancedReportPdf(envelope, generatedAt);
    }
    if (
      !bytes.byteLength ||
      bytes.byteLength > MAX_OUTPUT ||
      request.signal.aborted
    ) {
      return fail("SERVICE_UNAVAILABLE");
    }
    const ext: "pdf" | "csv" = format;
    // Filename comes only from validated UUID, never the project name.
    return new Response(bytes as BodyInit, {
      status: 200,
      headers: {
        ...CORS,
        "content-type":
          ext === "pdf" ? "application/pdf" : "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="xiaozhu-enhanced-report-${reportId}.${ext}"`,
        "cache-control": "private, no-store",
        "x-content-type-options": "nosniff",
      },
    });
  } catch {
    return fail("SERVICE_UNAVAILABLE");
  }
}
