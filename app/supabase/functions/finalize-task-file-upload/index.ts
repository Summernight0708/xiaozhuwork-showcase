import { type FileValidationFailureCode } from "../_shared/file-validation.ts";
import {
  PHASE2_LARGE_FILE_MAX_BYTES,
  validateTaskFileStream,
} from "../_shared/file-stream-validation.ts";

const BUCKET = "teamup-files";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type RequestBody = {
  reservationId: string;
  requestId: string;
  expectedVersion: number;
};

type Reservation = {
  id: string;
  actor_id: string | null;
  object_path: string;
  original_name: string;
  declared_mime_type: string;
  declared_size_bytes: number;
  reserved_envelope_bytes: number | null;
  state: "reserved" | "finalized" | "rejected";
  rejection_code: string | null;
};

type UserResponse = {
  id?: unknown;
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

function invalidRequest(requestId: string | null, field: string) {
  return json(
    {
      ok: false,
      code: "VALIDATION_FAILED",
      requestId,
      replayed: false,
      field,
    },
    400,
  );
}

function parseBody(value: unknown): RequestBody | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  if (
    typeof body.reservationId !== "string" ||
    !UUID_PATTERN.test(body.reservationId) ||
    typeof body.requestId !== "string" ||
    !UUID_PATTERN.test(body.requestId) ||
    !Number.isInteger(body.expectedVersion) ||
    (body.expectedVersion as number) <= 0
  ) {
    return null;
  }
  return body as RequestBody;
}

function bearerToken(header: string | null) {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

function isRejectionCode(
  value: string | null,
): value is FileValidationFailureCode | "STORAGE_QUOTA_EXCEEDED" {
  return (
    value === "FILE_TYPE_NOT_ALLOWED" ||
    value === "FILE_VALIDATION_FAILED" ||
    value === "STORAGE_QUOTA_EXCEEDED"
  );
}

function encodeStoragePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
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

async function callRpc(
  supabaseUrl: string,
  serviceRoleKey: string,
  name: string,
  body: Record<string, unknown>,
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      ...authHeaders(serviceRoleKey, serviceRoleKey),
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(body),
  });
  return {
    ok: response.ok,
    data: await readJson(response),
  };
}

async function removeStorageObject(
  supabaseUrl: string,
  serviceRoleKey: string,
  objectPath: string,
) {
  try {
    await fetch(`${supabaseUrl}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: {
        ...authHeaders(serviceRoleKey, serviceRoleKey),
        "content-type": "application/json",
      },
      body: JSON.stringify({ prefixes: [objectPath] }),
    });
  } catch {
    // Rejected-object cleanup is best-effort; the physical orphan remains quota-accounted.
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
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
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
    return invalidRequest(null, "body");
  }
  const body = parseBody(rawBody);
  if (!body) {
    const requestId = rawBody &&
        typeof rawBody === "object" &&
        !Array.isArray(rawBody) &&
        typeof (rawBody as Record<string, unknown>).requestId === "string"
      ? ((rawBody as Record<string, unknown>).requestId as string)
      : null;
    return invalidRequest(requestId, "body");
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: authHeaders(anonKey, token),
  });
  const userBody = (await readJson(userResponse)) as UserResponse | null;
  const userId = userResponse.ok && userBody && typeof userBody.id === "string"
    ? userBody.id
    : null;
  if (!userId) {
    return json(
      {
        ok: false,
        code: "UNAUTHENTICATED",
        requestId: body.requestId,
        replayed: false,
      },
      401,
    );
  }

  const reservationUrl = new URL(
    `${supabaseUrl}/rest/v1/file_upload_reservations_visible`,
  );
  reservationUrl.searchParams.set("id", `eq.${body.reservationId}`);
  reservationUrl.searchParams.set(
    "select",
    "id,actor_id,object_path,original_name,declared_mime_type,declared_size_bytes,reserved_envelope_bytes,state,rejection_code",
  );
  const reservationResponse = await fetch(reservationUrl, {
    headers: {
      ...authHeaders(anonKey, token),
      accept: "application/json",
    },
  });
  const reservationRows = await readJson(reservationResponse);
  const reservation = reservationResponse.ok &&
      Array.isArray(reservationRows) &&
      reservationRows.length === 1
    ? (reservationRows[0] as Reservation)
    : null;
  if (!reservation || reservation.actor_id !== userId) {
    return json({
      ok: false,
      code: "NOT_FOUND_OR_NOT_AUTHORIZED",
      requestId: body.requestId,
      replayed: false,
    });
  }

  const reject = async (
    rejectionCode: FileValidationFailureCode | "STORAGE_QUOTA_EXCEEDED",
    removeObject: boolean,
  ) => {
    const result = await callRpc(
      supabaseUrl,
      serviceRoleKey,
      "cmd_reject_task_file_upload_service",
      {
        p_actor_id: userId,
        p_reservation_id: body.reservationId,
        p_request_id: body.requestId,
        p_expected_version: body.expectedVersion,
        p_rejection_code: rejectionCode,
      },
    );
    if (!result.ok) {
      return json(
        {
          ok: false,
          code: "SERVICE_UNAVAILABLE",
          requestId: body.requestId,
          replayed: false,
        },
        502,
      );
    }

    if (
      removeObject &&
      result.data &&
      typeof result.data === "object" &&
      !Array.isArray(result.data) &&
      (result.data as { ok?: unknown }).ok === true &&
      (result.data as { replayed?: unknown }).replayed !== true
    ) {
      await removeStorageObject(
        supabaseUrl,
        serviceRoleKey,
        reservation.object_path,
      );
    }
    return json(result.data);
  };

  if (
    reservation.state === "rejected" &&
    isRejectionCode(reservation.rejection_code)
  ) {
    return reject(reservation.rejection_code, false);
  }

  const downloadResponse = await fetch(
    `${supabaseUrl}/storage/v1/object/${BUCKET}/${
      encodeStoragePath(
        reservation.object_path,
      )
    }`,
    {
      headers: authHeaders(serviceRoleKey, serviceRoleKey),
      cache: "no-store",
    },
  );
  if (downloadResponse.status === 400 || downloadResponse.status === 404) {
    return json({
      ok: false,
      code: "UPLOAD_NOT_READY",
      requestId: body.requestId,
      replayed: false,
    });
  }
  if (!downloadResponse.ok) {
    return json(
      {
        ok: false,
        code: "SERVICE_UNAVAILABLE",
        requestId: body.requestId,
        replayed: false,
      },
      502,
    );
  }

  const storedMimeType = downloadResponse.headers
    .get("content-type")
    ?.split(";", 1)[0]
    ?.trim()
    .toLowerCase();
  if (
    storedMimeType &&
    storedMimeType !== "application/octet-stream" &&
    storedMimeType !== reservation.declared_mime_type.toLowerCase()
  ) {
    return reject("FILE_VALIDATION_FAILED", true);
  }

  // Hash and validate through a bounded-memory tempfile, never arrayBuffer().
  if (!downloadResponse.body) {
    return json({
      ok: false,
      code: "UPLOAD_NOT_READY",
      requestId: body.requestId,
      replayed: false,
    });
  }
  const reservedEnvelope = reservation.reserved_envelope_bytes ?? 52_428_800;
  const validation = await validateTaskFileStream({
    stream: downloadResponse.body,
    declaredMimeType: reservation.declared_mime_type,
    originalName: reservation.original_name,
    maxBytes: Math.min(reservedEnvelope, PHASE2_LARGE_FILE_MAX_BYTES),
  });
  if (!validation.ok) {
    return reject(validation.code, true);
  }
  if (validation.sizeBytes !== reservation.declared_size_bytes) {
    return reject("FILE_VALIDATION_FAILED", true);
  }

  const finalize = await callRpc(
    supabaseUrl,
    serviceRoleKey,
    "cmd_finalize_task_file_upload_service",
    {
      p_actor_id: userId,
      p_reservation_id: body.reservationId,
      p_request_id: body.requestId,
      p_expected_version: body.expectedVersion,
      p_actual_mime_type: validation.mimeType,
      p_actual_size_bytes: validation.sizeBytes,
      p_sha256_hex: validation.sha256Hex,
    },
  );
  if (!finalize.ok) {
    return json(
      {
        ok: false,
        code: "SERVICE_UNAVAILABLE",
        requestId: body.requestId,
        replayed: false,
      },
      502,
    );
  }

  return json(finalize.data);
}

Deno.serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch {
    return json({ ok: false, code: "SERVICE_UNAVAILABLE" }, 502);
  }
});
