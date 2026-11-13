import {
  parseProjectReportExportSnapshot,
  renderProjectReport,
  type ReportExportFormat,
} from "../_shared/report-export.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type ExportRequest = {
  reportId: string;
  format: ReportExportFormat;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function bearerToken(header: string | null) {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

function authHeaders(apiKey: string, bearer: string) {
  return {
    apikey: apiKey,
    authorization: `Bearer ${bearer}`,
  };
}

async function readJson(response: Response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function parseRequest(value: unknown): ExportRequest | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  if (
    typeof input.reportId !== "string" ||
    !UUID_PATTERN.test(input.reportId) ||
    (input.format !== "csv" && input.format !== "pdf")
  ) {
    return null;
  }
  return { reportId: input.reportId, format: input.format };
}

function failureStatus(code: unknown) {
  switch (code) {
    case "UNAUTHENTICATED":
      return 401;
    case "VALIDATION_FAILED":
      return 400;
    case "REPORT_NOT_READY":
      return 409;
    case "NOT_FOUND_OR_NOT_AUTHORIZED":
      return 404;
    default:
      return 502;
  }
}

async function handleRequest(request: Request) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return json({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    return json({ ok: false, code: "SERVER_MISCONFIGURED" }, 500);
  }

  const token = bearerToken(request.headers.get("authorization"));
  if (!token) {
    return json({ ok: false, code: "UNAUTHENTICATED" }, 401);
  }

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return json({ ok: false, code: "VALIDATION_FAILED", field: "body" }, 400);
  }
  const input = parseRequest(rawBody);
  if (!input) {
    return json({ ok: false, code: "VALIDATION_FAILED", field: "body" }, 400);
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: authHeaders(anonKey, token),
  });
  const userBody = await readJson(userResponse);
  if (
    !userResponse.ok ||
    !userBody ||
    typeof userBody !== "object" ||
    Array.isArray(userBody) ||
    typeof (userBody as Record<string, unknown>).id !== "string"
  ) {
    return json({ ok: false, code: "UNAUTHENTICATED" }, 401);
  }

  const rpcResponse = await fetch(
    `${supabaseUrl}/rest/v1/rpc/get_project_report_export`,
    {
      method: "POST",
      headers: {
        ...authHeaders(anonKey, token),
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({ p_report_id: input.reportId }),
      cache: "no-store",
    },
  );
  if (!rpcResponse.ok) {
    return json({ ok: false, code: "SERVICE_UNAVAILABLE" }, 502);
  }

  const snapshotValue = await readJson(rpcResponse);
  if (
    snapshotValue &&
    typeof snapshotValue === "object" &&
    !Array.isArray(snapshotValue) &&
    typeof (snapshotValue as Record<string, unknown>).code === "string"
  ) {
    const failure = snapshotValue as Record<string, unknown>;
    return json(failure, failureStatus(failure.code));
  }

  let rendered;
  try {
    const snapshot = parseProjectReportExportSnapshot(snapshotValue);
    rendered = await renderProjectReport(snapshot, input.format);
  } catch {
    return json({ ok: false, code: "SERVICE_UNAVAILABLE" }, 502);
  }

  const filename = `xiaozhuwork-report-${input.reportId}.${rendered.extension}`;
  return new Response(rendered.bytes, {
    status: 200,
    headers: {
      ...CORS_HEADERS,
      "content-type": rendered.contentType,
      "content-disposition": `attachment; filename="${filename}"`,
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

Deno.serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch {
    return json({ ok: false, code: "SERVICE_UNAVAILABLE" }, 502);
  }
});
