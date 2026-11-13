/* global process, fetch, console, TextEncoder */
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const secret = process.env.FILE_WITHDRAWAL_CRON_SECRET;
const dbUrl = process.env.SUPABASE_DB_URL;
if (
  url !== "http://127.0.0.1:55811" ||
  !key ||
  !secret ||
  secret.length < 32 ||
  !/^postgresql:\/\/postgres:postgres@127\.0\.0\.1:55812\/postgres/.test(
    dbUrl ?? "",
  )
) {
  throw new Error("Refusing non-isolated Storage worker test");
}
const db = postgres(dbUrl, { max: 2, ssl: false });
const admin = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const email = `g-withdraw-${randomUUID()}@example.test`;
const password = `G-file-${randomUUID()}!`;
const payload = new TextEncoder().encode(
  "G real pending withdrawal proof " + randomUUID(),
);
const sha = createHash("sha256").update(payload).digest("hex");
const objectPath = `g-real-withdrawal/${randomUUID()}.pdf`;
try {
  const { data: created, error: createError } =
    await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
  assert.equal(createError, null);
  const userId = created.user.id;
  const user = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: signError } = await user.auth.signInWithPassword({
    email,
    password,
  });
  assert.equal(signError, null);

  const [project] = await db`
    insert into public.projects(name,deadline_at,created_by,leader_id)
    values('G real file withdrawal worker',now()+interval '12 days',
      ${userId}::uuid,${userId}::uuid) returning id
  `;
  const projectId = project.id;
  await db`insert into public.project_members(project_id,user_id,role,member_state)
    values(${projectId}::uuid,${userId}::uuid,'leader','active')`;
  const [task] = await db`insert into public.tasks(
    project_id,title,created_by,assignee_id,deadline_at,
    status,assignment_state,weight
  ) values(${projectId}::uuid,'G file-version quarantine',
    ${userId}::uuid,${userId}::uuid,now()+interval '8 days',
    'in_progress','assigned',3) returning id`;
  const taskId = task.id;
  const { error: upError } = await admin.storage
    .from("teamup-files")
    .upload(objectPath, payload, {
      contentType: "application/pdf",
      upsert: false,
    });
  assert.equal(upError, null, "service-role upload of fixture succeeds");
  const { data: signed, error: signUrlError } = await admin.storage
    .from("teamup-files")
    .createSignedUrl(objectPath, 600);
  assert.equal(signUrlError, null);
  const before = await fetch(signed.signedUrl, { cache: "no-store" });
  assert.equal(before.status, 200);
  assert.deepEqual(new Uint8Array(await before.arrayBuffer()), payload);

  const [reservation] = await db`
    insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,
     object_path,original_name,declared_mime_type,declared_size_bytes,
     expires_at,state)
    values(${projectId}::uuid,${taskId}::uuid,${userId}::uuid,'new_file',
      ${objectPath},'withdrawal.pdf','application/pdf',${payload.length},
      now()+interval '2 hours','finalized') returning id
  `;
  const [file] = await db`
    insert into public.task_files(project_id,task_id,logical_name,created_by)
    values(${projectId}::uuid,${taskId}::uuid,'withdrawal.pdf',${userId}::uuid)
    returning id,version
  `;
  const [version] = await db`
    insert into public.task_file_versions(file_id,project_id,task_id,reservation_id,
      version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by)
    values(${file.id}::uuid,${projectId}::uuid,${taskId}::uuid,${reservation.id}::uuid,
       1,${objectPath},'withdrawal.pdf','application/pdf',${payload.length},
       ${sha},${userId}::uuid) returning id
  `;
  await db`update public.task_files set current_version_id=${version.id}::uuid
    where id=${file.id}::uuid`;

  const { data: command, error: commandError } = await user.rpc(
    "cmd_withdraw_file_version",
    {
      p_project_id: projectId,
      p_file_version_id: version.id,
      p_reason: "Isolated automatic quarantine E2E",
      p_request_id: randomUUID(),
      p_expected_version: file.version,
    },
  );
  assert.equal(commandError, null);
  assert.equal(command?.ok, true, JSON.stringify(command));
  assert.equal(command?.data?.state, "pending_quarantine");
  const pending = await db`
    select id,state,quarantine_path from public.file_version_withdrawals
    where file_version_id=${version.id}::uuid
  `;
  assert.equal(pending[0].state, "pending_quarantine");
  const afterRequest = await fetch(signed.signedUrl, { cache: "no-store" });
  assert.equal(
    afterRequest.status,
    200,
    "old signed URL may remain until real move",
  );

  const headers = {
    Authorization: `Bearer ${key}`,
    apikey: key,
    "x-file-withdrawal-secret": secret,
    "content-type": "application/json",
  };
  const run = async () => {
    const response = await fetch(
      `${url}/functions/v1/process-file-withdrawals`,
      {
        method: "POST",
        headers,
        body: "{}",
      },
    );
    const outcome = await response.json();
    assert.equal(response.status, 200, JSON.stringify(outcome));
    assert.equal(outcome.ok, true);
    return outcome;
  };
  const first = await run();
  assert.ok(first.completed >= 1, "worker moved pending object");
  const status = await db`
    select state,revoked_at,quarantine_path from public.file_version_withdrawals
    where file_version_id=${version.id}::uuid
  `;
  assert.equal(status[0].state, "withdrawn");
  assert.ok(status[0].revoked_at);
  const afterMove = await fetch(signed.signedUrl, { cache: "no-store" });
  const denial = await afterMove.text();
  assert.ok(
    [403, 404].includes(afterMove.status) ||
      (afterMove.status === 400 &&
        /Object not found|not found|NoSuchKey/i.test(denial)),
    `old signed URL must be denied after quarantine, got ${afterMove.status}`,
  );

  const { data: quarantine, error: quarantineError } = await admin.storage
    .from("teamup-files")
    .createSignedUrl(status[0].quarantine_path, 60);
  assert.equal(quarantineError, null);
  const copy = await fetch(quarantine.signedUrl, { cache: "no-store" });
  assert.equal(copy.status, 200);
  assert.deepEqual(new Uint8Array(await copy.arrayBuffer()), payload);
  const second = await run();
  assert.equal(
    second.completed,
    0,
    "retry must not reprocess withdrawn version",
  );
  const [events] = await db`
    select count(*)::int as total from public.business_events
    where event_type='file_version_withdrawn' and entity_id=${version.id}::uuid
  `;
  assert.equal(events.total, 1, "quarantine audit event is unique");
  console.log(
    `PASS real withdrawal worker: pending→withdrawn, oldSignedURL=${afterMove.status}, movedBytes=200, retry=0, event=1`,
  );
} finally {
  await db.end({ timeout: 5 });
}
