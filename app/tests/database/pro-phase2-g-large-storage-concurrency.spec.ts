import { createHash, randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const dbUrl = process.env.SUPABASE_DB_URL ?? "";
const apiUrl = process.env.XIAOZHUWORK_G_API_URL ?? "";
const enabled =
  process.env.XIAOZHUWORK_G_LARGE_UPLOAD_TEST === "1" &&
  /^postgres(?:ql)?:\/\/[^@]+@(?:localhost|127\.0\.0\.1):55512\/postgres$/.test(
    dbUrl,
  ) &&
  /^http:\/\/(?:localhost|127\.0\.0\.1):55511$/.test(apiUrl);
const suite = describe.skipIf(!enabled);
const db = enabled ? postgres(dbUrl, { max: 2 }) : null;
const project = "ed200000-0000-4000-8000-000000000001";
const task = "ed300000-0000-4000-8000-000000000001";
const maxBytes = 200 * 1024 * 1024;
const whitelist = [
  "file_full_history",
  "file_batch_rollback",
  "file_version_compare",
  "project_recovery_point",
  "file_large_upload",
  "project_storage_quota",
];
let oldRelease = "";
let actor = "";
let owner: SupabaseClient | null = null;
let admin: SupabaseClient | null = null;

async function clean() {
  if (!db) return;
  await db.begin(async (tx) => {
    await tx.unsafe("set local session_replication_role = replica");
    await tx`delete from public.business_events where project_id=${project}::uuid`;
    await tx`delete from public.command_requests where project_id=${project}::uuid`;
    await tx`delete from public.task_file_versions where project_id=${project}::uuid`;
    await tx`delete from public.task_files where project_id=${project}::uuid`;
    await tx`delete from public.file_upload_reservations where project_id=${project}::uuid`;
    await tx`delete from public.tasks where project_id=${project}::uuid`;
    await tx`delete from public.project_members where project_id=${project}::uuid`;
    await tx`delete from public.projects where id=${project}::uuid`;
    if (actor) {
      await tx`delete from public.account_entitlements where user_id=${actor}::uuid`;
      await tx`delete from public.account_entitlement_audit where user_id=${actor}::uuid`;
    }
  });
}

suite("G gated real 200 MiB local Storage HTTP streaming", () => {
  beforeAll(async () => {
    if (
      !db ||
      !process.env.XIAOZHUWORK_G_ANON_KEY ||
      !process.env.XIAOZHUWORK_G_SERVICE_KEY
    ) {
      throw new Error("G local Storage environment missing");
    }
    const existing = await db`select pg_get_functiondef(
      'private.capability_is_released(text)'::regprocedure) as def`;
    oldRelease = existing[0]!.def as string;
    admin = createClient(apiUrl, process.env.XIAOZHUWORK_G_SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const client = createClient(apiUrl, process.env.XIAOZHUWORK_G_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const email = "g-large-" + randomUUID() + "@example.test";
    const password = "G-local-200MiB-2026!";
    const created = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (created.error || !created.data.user)
      throw new Error("Local user creation failed");
    actor = created.data.user.id;
    const signed = await client.auth.signInWithPassword({ email, password });
    if (signed.error || !signed.data.session)
      throw new Error("Local login failed");
    owner = createClient(apiUrl, process.env.XIAOZHUWORK_G_ANON_KEY, {
      global: {
        headers: {
          Authorization: "Bearer " + signed.data.session.access_token,
        },
      },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    await db`insert into public.projects(
      id,name,leader_id,created_by,deadline_at,version
    ) values (${project}::uuid,'G Large File',${actor}::uuid,${actor}::uuid,now()+interval '30 days',1)`;
    await db`insert into public.project_members(project_id,user_id,role,member_state)
      values (${project}::uuid,${actor}::uuid,'leader','active')`;
    await db`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      assignment_state,accepted_at,version
    ) values (
      ${task}::uuid,${project}::uuid,'Large upload',${actor}::uuid,
      ${actor}::uuid,now()+interval '10 days','in_progress',1,'assigned',now(),1
    )`;
    await db`insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values(${actor}::uuid,'pro','active',now()-interval '1 day',
      now()+interval '30 days',now(),${actor}::uuid,'test',1)`;
    const quoted = whitelist.map((value) => "'" + value + "'").join(",");
    await db.unsafe(`create or replace function private.capability_is_released(
      p_capability text) returns boolean language sql immutable security definer
      set search_path = '' as $$
      select p_capability = any(array[${quoted}]::text[]) $$`);
  }, 40_000);

  afterAll(async () => {
    if (!db) return;
    try {
      if (oldRelease) await db.unsafe(oldRelease);
      if (admin) {
        const items = await db<{ name: string }[]>`
          select name from storage.objects
          where bucket_id='teamup-files'
            and name like ${"pending/" + project + "/%"}`;
        if (items.length) {
          await admin.storage
            .from("teamup-files")
            .remove(items.map((row) => row.name));
        }
      }
      await clean();
      if (actor && admin) await admin.auth.admin.deleteUser(actor);
    } finally {
      await db.end({ timeout: 10 });
    }
  });

  test("accepts exactly 200 MiB via authenticated Storage and stream-finalizes SHA256", async () => {
    if (!db || !owner) throw new Error("G local fixture missing");
    const reservation = await owner.rpc("cmd_reserve_task_file_upload", {
      p_project_id: project,
      p_task_id: task,
      p_request_id: randomUUID(),
      p_expected_version: 1,
      p_mode: "new_file",
      p_target_file_id: null,
      p_original_name: "exactly-200mib.txt",
      p_declared_mime_type: "text/plain",
      p_declared_size_bytes: maxBytes,
    });
    expect(reservation.error).toBeNull();
    expect(reservation.data).toMatchObject({ ok: true });
    const details = (
      reservation.data as {
        data: { reservationId: string; objectPath: string };
      }
    ).data;
    const bytes = Buffer.alloc(maxBytes, 65);
    const expectedHash = createHash("sha256").update(bytes).digest("hex");
    const uploaded = await owner.storage
      .from("teamup-files")
      .upload(details.objectPath, new Blob([bytes], { type: "text/plain" }), {
        contentType: "text/plain",
        upsert: false,
      });
    expect(uploaded.error).toBeNull();
    const finalized = await owner.functions.invoke(
      "finalize-task-file-upload",
      {
        body: {
          reservationId: details.reservationId,
          requestId: randomUUID(),
          expectedVersion: 1,
        },
      },
    );
    expect(finalized.error).toBeNull();
    expect(finalized.data).toMatchObject({
      ok: true,
      data: {
        reservationId: details.reservationId,
        versionNumber: 1,
      },
    });
    const version = await db`select size_bytes,sha256_hex
      from public.task_file_versions where reservation_id=${details.reservationId}::uuid`;
    expect(version).toMatchObject([
      { size_bytes: String(maxBytes), sha256_hex: expectedHash },
    ]);
  }, 240_000);

  test("rejects 200 MiB plus one byte at the reservation boundary", async () => {
    if (!owner) throw new Error("G local fixture missing");
    const result = await owner.rpc("cmd_reserve_task_file_upload", {
      p_project_id: project,
      p_task_id: task,
      p_request_id: randomUUID(),
      p_expected_version: 1,
      p_mode: "new_file",
      p_target_file_id: null,
      p_original_name: "too-big.txt",
      p_declared_mime_type: "text/plain",
      p_declared_size_bytes: maxBytes + 1,
    });
    expect(result.error).toBeNull();
    expect((result.data as { ok: boolean }).ok).toBe(false);
  });
});
