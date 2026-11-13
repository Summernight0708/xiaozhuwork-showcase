import { createHash, randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres, { type Sql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const PROJECT_ID = "d2000000-0000-0000-0000-000000000001";
const TASK_VALID = "d3000000-0000-0000-0000-000000000001";
const TASK_INVALID = "d3000000-0000-0000-0000-000000000002";
const TASK_MISSING = "d3000000-0000-0000-0000-000000000003";
const PASSWORD = "Day4-storage-Test-2026!";
const BUCKET = "teamup-files";

type LocalSupabase = {
  apiUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  dbUrl: string;
};

type ReserveData = {
  reservationId: string;
  objectPath: string;
};

type CommandResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  data?: Record<string, unknown>;
};

function localSupabase(): LocalSupabase {
  const command =
    process.platform === "win32"
      ? (process.env.ComSpec ?? "cmd.exe")
      : "corepack";
  const args =
    process.platform === "win32"
      ? [
          "/d",
          "/s",
          "/c",
          "corepack",
          "pnpm",
          "exec",
          "supabase",
          "status",
          "-o",
          "env",
        ]
      : ["pnpm", "exec", "supabase", "status", "-o", "env"];
  const stdout = execFileSync(command, args, { encoding: "utf8" });
  const values = new Map<string, string>();
  for (const line of stdout.split(/\r?\n/)) {
    const match = /^([A-Z0-9_]+)="(.*)"$/.exec(line.trim());
    if (match) values.set(match[1]!, match[2]!);
  }
  const apiUrl = values.get("API_URL");
  const anonKey = values.get("ANON_KEY");
  const serviceRoleKey = values.get("SERVICE_ROLE_KEY");
  const dbUrl = values.get("DB_URL");
  if (!apiUrl || !anonKey || !serviceRoleKey || !dbUrl) {
    throw new Error(
      "Local Supabase status did not expose required test values",
    );
  }
  return { apiUrl, anonKey, serviceRoleKey, dbUrl };
}

function concatBytes(...parts: Uint8Array[]) {
  const output = new Uint8Array(
    parts.reduce((total, part) => total + part.length, 0),
  );
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function littleEndian(value: number, width: number) {
  const output = new Uint8Array(width);
  for (let index = 0; index < width; index += 1)
    output[index] = (value >>> (index * 8)) & 0xff;
  return output;
}

function fakeLocalZipEntry(name: string, content = "") {
  const encoder = new TextEncoder();
  const nameBytes = encoder.encode(name);
  const contentBytes = encoder.encode(content);
  return concatBytes(
    new Uint8Array([0x50, 0x4b, 0x03, 0x04]),
    littleEndian(20, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(0, 2),
    littleEndian(0, 4),
    littleEndian(contentBytes.length, 4),
    littleEndian(contentBytes.length, 4),
    littleEndian(nameBytes.length, 2),
    littleEndian(0, 2),
    nameBytes,
    contentBytes,
  );
}

async function cleanup(sql: Sql, service: SupabaseClient) {
  const objectRows = await sql<{ name: string }[]>`
    select name from storage.objects
    where bucket_id=${BUCKET} and name like ${"pending/" + PROJECT_ID + "/%"}
  `;
  if (objectRows.length > 0) {
    await service.storage
      .from(BUCKET)
      .remove(objectRows.map((row) => row.name));
  }

  await sql.unsafe("set session_replication_role = replica");
  try {
    await sql`delete from public.business_events where project_id=${PROJECT_ID}`;
    await sql`delete from public.command_requests where project_id=${PROJECT_ID}`;
    await sql`delete from public.contribution_confirmations where project_id=${PROJECT_ID}`;
    await sql`delete from public.contribution_items where project_id=${PROJECT_ID}`;
    await sql`delete from public.contribution_reports where project_id=${PROJECT_ID}`;
    await sql`delete from public.task_review_rounds where project_id=${PROJECT_ID}`;
    await sql`delete from public.task_file_versions where project_id=${PROJECT_ID}`;
    await sql`delete from public.task_files where project_id=${PROJECT_ID}`;
    await sql`delete from public.file_upload_reservations where project_id=${PROJECT_ID}`;
    await sql`delete from public.task_assignment_offers where project_id=${PROJECT_ID}`;
    await sql`delete from public.task_dependencies where project_id=${PROJECT_ID}`;
    await sql`delete from public.tasks where project_id=${PROJECT_ID}`;
    await sql`delete from public.project_join_requests where project_id=${PROJECT_ID}`;
    await sql`delete from public.project_invitations where project_id=${PROJECT_ID}`;
    await sql`delete from public.project_members where project_id=${PROJECT_ID}`;
    await sql`delete from public.projects where id=${PROJECT_ID}`;
  } finally {
    await sql.unsafe("set session_replication_role = origin");
  }
}

describe("strict Day 4 real Storage finalization", () => {
  const local = localSupabase();
  const sql = postgres(local.dbUrl, { max: 2 });
  const service = createClient(local.apiUrl, local.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const email = "day4-storage-" + randomUUID() + "@example.test";
  let userId = "";
  let user: SupabaseClient;

  beforeAll(async () => {
    await cleanup(sql, service);
    const { data: created, error: createError } =
      await service.auth.admin.createUser({
        email,
        password: PASSWORD,
        email_confirm: true,
      });
    if (createError || !created.user)
      throw createError ?? new Error("user creation failed");
    userId = created.user.id;

    const anon = createClient(local.apiUrl, local.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: signedIn, error: signInError } =
      await anon.auth.signInWithPassword({
        email,
        password: PASSWORD,
      });
    if (signInError || !signedIn.session)
      throw signInError ?? new Error("sign in failed");
    user = createClient(local.apiUrl, local.anonKey, {
      global: {
        headers: { Authorization: "Bearer " + signedIn.session.access_token },
      },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await sql`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(${PROJECT_ID},'Storage integration',now()+interval '10 days',${userId},${userId},1)
    `;
    await sql`
      insert into public.project_members(project_id,user_id,role,member_state)
      values(${PROJECT_ID},${userId},'leader','active')
    `;
    for (const [taskId, title] of [
      [TASK_VALID, "Valid upload"],
      [TASK_INVALID, "Invalid upload"],
      [TASK_MISSING, "Missing upload"],
    ] as const) {
      await sql`
        insert into public.tasks(
          id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
          is_direct_assignment,accepted_at,assignment_state,version
        ) values(
          ${taskId},${PROJECT_ID},${title},${userId},${userId},now()+interval '5 days',
          'in_progress',1,false,now(),'assigned',1
        )
      `;
    }
  });

  afterAll(async () => {
    try {
      await cleanup(sql, service);
      if (userId) await service.auth.admin.deleteUser(userId);
    } finally {
      await sql.end();
    }
  });

  async function reserve(
    taskId: string,
    name: string,
    mime: string,
    size: number,
  ) {
    const { data, error } = await user.rpc("cmd_reserve_task_file_upload", {
      p_project_id: PROJECT_ID,
      p_task_id: taskId,
      p_request_id: randomUUID(),
      p_expected_version: 1,
      p_mode: "new_file",
      p_target_file_id: null,
      p_original_name: name,
      p_declared_mime_type: mime,
      p_declared_size_bytes: size,
    });
    if (error) throw error;
    const result = data as CommandResult;
    expect(result.ok).toBe(true);
    return result.data as ReserveData;
  }

  test("Storage API enforces the reserved path and trusted function finalizes real bytes", async () => {
    const pdfBytes = new TextEncoder().encode("%PDF-1.7\ntrusted bytes");
    const reservation = await reserve(
      TASK_VALID,
      "trusted.pdf",
      "application/pdf",
      pdfBytes.length,
    );

    const unrelated = await user.storage
      .from(BUCKET)
      .upload(
        "pending/" + PROJECT_ID + "/not-a-reservation/trusted.pdf",
        pdfBytes,
        { contentType: "application/pdf", upsert: false },
      );
    expect(unrelated.error).not.toBeNull();

    const upload = await user.storage
      .from(BUCKET)
      .upload(reservation.objectPath, pdfBytes, {
        contentType: "application/pdf",
        upsert: false,
      });
    expect(upload.error).toBeNull();

    const pendingRead = await user.storage
      .from(BUCKET)
      .download(reservation.objectPath);
    expect(pendingRead.error).not.toBeNull();

    const upsert = await user.storage
      .from(BUCKET)
      .upload(reservation.objectPath, pdfBytes, {
        contentType: "application/pdf",
        upsert: true,
      });
    expect(upsert.error).not.toBeNull();
    await user.storage.from(BUCKET).remove([reservation.objectPath]);
    const afterClientRemove = await sql<{ count: number }[]>`
      select count(*)::integer as count from storage.objects
      where bucket_id=${BUCKET} and name=${reservation.objectPath}
    `;
    expect(afterClientRemove[0]!.count).toBe(1);

    const requestId = randomUUID();
    const finalized = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId,
        expectedVersion: 1,
      },
    });
    expect(finalized.error).toBeNull();
    expect(finalized.data).toMatchObject({ ok: true, replayed: false });

    const replay = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId,
        expectedVersion: 1,
      },
    });
    expect(replay.error).toBeNull();
    expect(replay.data).toMatchObject({ ok: true, replayed: true });

    const rows = await sql<{ sha256_hex: string; count: number }[]>`
      select min(sha256_hex) as sha256_hex, count(*)::integer as count
      from public.task_file_versions
      where reservation_id=${reservation.reservationId}
    `;
    expect(rows[0]).toEqual({
      sha256_hex: createHash("sha256").update(pdfBytes).digest("hex"),
      count: 1,
    });

    const finalizedRead = await user.storage
      .from(BUCKET)
      .download(reservation.objectPath);
    expect(finalizedRead.error).toBeNull();
  });

  test("trusted byte validation rejects disguised HTML and cleans the rejected object", async () => {
    const invalidBytes = new TextEncoder().encode(
      "<!doctype html><html>bad</html>",
    );
    const reservation = await reserve(
      TASK_INVALID,
      "notes.txt",
      "text/plain",
      invalidBytes.length,
    );
    const upload = await user.storage
      .from(BUCKET)
      .upload(reservation.objectPath, invalidBytes, {
        contentType: "text/plain",
        upsert: false,
      });
    expect(upload.error).toBeNull();

    const rejected = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId: randomUUID(),
        expectedVersion: 1,
      },
    });
    expect(rejected.error).toBeNull();
    expect(rejected.data).toMatchObject({
      ok: true,
      replayed: false,
      data: { state: "rejected", rejectionCode: "FILE_TYPE_NOT_ALLOWED" },
    });

    const reservationRows = await sql<
      { state: string; rejection_code: string }[]
    >`
      select state,rejection_code from public.file_upload_reservations
      where id=${reservation.reservationId}
    `;
    expect(reservationRows[0]).toEqual({
      state: "rejected",
      rejection_code: "FILE_TYPE_NOT_ALLOWED",
    });
    const objectRows = await sql<{ count: number }[]>`
      select count(*)::integer as count from storage.objects
      where bucket_id=${BUCKET} and name=${reservation.objectPath}
    `;
    expect(objectRows[0]!.count).toBe(0);
  });

  test("trusted finalization rejects malformed local-header-only OOXML", async () => {
    const mime =
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    const fakeDocx = concatBytes(
      fakeLocalZipEntry("[Content_Types].xml"),
      fakeLocalZipEntry("word/document.xml", "<w:document/>"),
      new TextEncoder().encode("MZ\u0000payload"),
    );
    const reservation = await reserve(
      TASK_INVALID,
      "fake.docx",
      mime,
      fakeDocx.length,
    );
    const upload = await user.storage
      .from(BUCKET)
      .upload(reservation.objectPath, fakeDocx, {
        contentType: mime,
        upsert: false,
      });
    expect(upload.error).toBeNull();

    const rejected = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId: randomUUID(),
        expectedVersion: 1,
      },
    });
    expect(rejected.error).toBeNull();
    expect(rejected.data).toMatchObject({
      ok: true,
      replayed: false,
      data: { state: "rejected", rejectionCode: "FILE_VALIDATION_FAILED" },
    });

    const rows = await sql<{ versions: number; objects: number }[]>`
      select
        (select count(*)::integer from public.task_file_versions where reservation_id=${reservation.reservationId}) as versions,
        (select count(*)::integer from storage.objects where bucket_id=${BUCKET} and name=${reservation.objectPath}) as objects
    `;
    expect(rows[0]).toEqual({ versions: 0, objects: 0 });
  });

  test("trusted finalization rejects an allowed Storage MIME that differs from the reservation", async () => {
    const bytes = new TextEncoder().encode('{"valid":true}');
    const reservation = await reserve(
      TASK_INVALID,
      "metadata-mismatch.txt",
      "text/plain",
      bytes.length,
    );
    const upload = await user.storage
      .from(BUCKET)
      .upload(reservation.objectPath, bytes, {
        contentType: "application/json",
        upsert: false,
      });
    expect(upload.error).toBeNull();

    const rejected = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId: randomUUID(),
        expectedVersion: 1,
      },
    });
    expect(rejected.error).toBeNull();
    expect(rejected.data).toMatchObject({
      ok: true,
      replayed: false,
      data: { state: "rejected", rejectionCode: "FILE_VALIDATION_FAILED" },
    });

    const rows = await sql<{ state: string; rejection_code: string }[]>`
      select state,rejection_code from public.file_upload_reservations
      where id=${reservation.reservationId}
    `;
    expect(rows[0]).toEqual({
      state: "rejected",
      rejection_code: "FILE_VALIDATION_FAILED",
    });
  });

  test("observer demotion revokes an already-issued upload reservation", async () => {
    const bytes = new TextEncoder().encode("revoked after role change");
    const reservation = await reserve(
      TASK_VALID,
      "revoked.txt",
      "text/plain",
      bytes.length,
    );

    await sql.unsafe("set session_replication_role = replica");
    try {
      await sql`
        update public.project_members
        set role='observer',is_observer=true,version=version+1
        where project_id=${PROJECT_ID} and user_id=${userId}
      `;
    } finally {
      await sql.unsafe("set session_replication_role = origin");
    }

    try {
      const revokedUpload = await user.storage
        .from(BUCKET)
        .upload(reservation.objectPath, bytes, {
          contentType: "text/plain",
          upsert: false,
        });
      expect(revokedUpload.error).not.toBeNull();

      const serviceUpload = await service.storage
        .from(BUCKET)
        .upload(reservation.objectPath, bytes, {
          contentType: "text/plain",
          upsert: false,
        });
      expect(serviceUpload.error).toBeNull();

      const finalized = await user.functions.invoke(
        "finalize-task-file-upload",
        {
          body: {
            reservationId: reservation.reservationId,
            requestId: randomUUID(),
            expectedVersion: 1,
          },
        },
      );
      expect(finalized.error).toBeNull();
      expect(finalized.data).toMatchObject({
        ok: false,
        code: "NOT_AUTHORIZED",
      });
    } finally {
      await service.storage.from(BUCKET).remove([reservation.objectPath]);
      await sql.unsafe("set session_replication_role = replica");
      try {
        await sql`
          update public.project_members
          set role='leader',is_observer=false,version=version+1
          where project_id=${PROJECT_ID} and user_id=${userId}
        `;
      } finally {
        await sql.unsafe("set session_replication_role = origin");
      }
    }
  });

  test("missing object stays unfinalized and unauthenticated invocation is rejected", async () => {
    const reservation = await reserve(
      TASK_MISSING,
      "missing.txt",
      "text/plain",
      7,
    );
    const missing = await user.functions.invoke("finalize-task-file-upload", {
      body: {
        reservationId: reservation.reservationId,
        requestId: randomUUID(),
        expectedVersion: 1,
      },
    });
    expect(missing.error).toBeNull();
    expect(missing.data).toMatchObject({ ok: false, code: "UPLOAD_NOT_READY" });

    const response = await fetch(
      local.apiUrl + "/functions/v1/finalize-task-file-upload",
      {
        method: "POST",
        headers: { apikey: local.anonKey, "content-type": "application/json" },
        body: JSON.stringify({
          reservationId: reservation.reservationId,
          requestId: randomUUID(),
          expectedVersion: 1,
        }),
      },
    );
    expect(response.status).toBe(401);
  });
});
