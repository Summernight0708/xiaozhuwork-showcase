import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

// Dedicated local A test stack. The strict host/port guard below remains mandatory.
const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:55412/postgres";
const gIsolated =
  process.env.XIAOZHUWORK_G_INTEGRATION_TEST === "1" &&
  /^postgresql?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):55512\/postgres$/.test(
    databaseUrl,
  );
if (
  !gIsolated &&
  (!databaseUrl ||
    !/^postgresql?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):55412\/postgres$/.test(
      databaseUrl,
    ))
) {
  throw new Error(
    "A concurrency tests require the isolated local xiaozhuwork_p2_a database at port 55412",
  );
}
const db = postgres(databaseUrl, { max: 6, prepare: false });

const freeUser = "a8100000-0000-0000-0000-000000000001";
const proUser = "a8100000-0000-0000-0000-000000000002";
const freeProject = "a8200000-0000-0000-0000-000000000001";
const proProject = "a8200000-0000-0000-0000-000000000002";
const freeTask = "a8300000-0000-0000-0000-000000000001";
const proTask = "a8300000-0000-0000-0000-000000000002";

type Result = { ok: boolean; code?: string; details?: { scope?: string } };

async function asActor(
  actor: string,
  project: string,
  task: string,
): Promise<Result> {
  return db.begin(async (tx: TransactionSql) => {
    await tx`select set_config('request.jwt.claim.sub',${actor},true)`;
    await tx.unsafe("set local role authenticated");
    const request = crypto.randomUUID();
    const rows = await tx`select public.cmd_reserve_task_file_upload(
      ${project}::uuid,${task}::uuid,${request}::uuid,1,
      'new_file',null,'test.pdf','application/pdf',100
    ) as result`;
    return rows[0]!.result as Result;
  });
}

let previousRelease: string;
async function clean() {
  // Disable immutable append-only triggers only on the same transaction
  // connection; the pool must never leak session_replication_role=replica.
  await db.begin(async (tx: TransactionSql) => {
    await tx.unsafe("set local session_replication_role = replica");
    await tx`delete from public.business_events where project_id in (${freeProject},${proProject})`;
    await tx`delete from public.command_requests where project_id in (${freeProject},${proProject})`;
    await tx`delete from public.file_upload_reservations where project_id in (${freeProject},${proProject})`;
    await tx`delete from public.tasks where project_id in (${freeProject},${proProject})`;
    await tx`delete from public.project_members where project_id in (${freeProject},${proProject})`;
    await tx`delete from public.projects where id in (${freeProject},${proProject})`;
    await tx`delete from public.account_entitlements where user_id in (${freeUser},${proUser})`;
    await tx`delete from public.account_entitlement_audit where user_id in (${freeUser},${proUser})`;
    await tx`delete from auth.users where id in (${freeUser},${proUser})`;
  });
}
beforeAll(async () => {
  previousRelease = (
    await db`select pg_get_functiondef(
    'private.capability_is_released(text)'::regprocedure) as ddl`
  )[0]!.ddl as string;
  await clean();
  await db`insert into auth.users(id,email) values
    (${freeUser},'p2a-concurrency-free@example.test'),
    (${proUser},'p2a-concurrency-pro@example.test')`;
  await db`insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
    values(${freeProject},'A Free concurrency',now()+interval '20 days',
      ${freeUser},${freeUser},1),
      (${proProject},'A Pro concurrency',now()+interval '20 days',
      ${proUser},${proUser},1)`;
  await db`insert into public.project_members(project_id,user_id,role,member_state)
    values(${freeProject},${freeUser},'leader','active'),
    (${proProject},${proUser},'leader','active')`;
  await db`insert into public.tasks(id,project_id,title,created_by,assignee_id,
     deadline_at,status,weight,assignment_state,accepted_at,version)
     values
     (${freeTask},${freeProject},'Free upload',${freeUser},${freeUser},
      now()+interval '10 days','in_progress',1,'assigned',now(),1),
     (${proTask},${proProject},'Pro upload',${proUser},${proUser},
      now()+interval '10 days','in_progress',1,'assigned',now(),1)`;
  await db`insert into public.account_entitlements(
    user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version)
    values(${proUser},'pro','active',now()-interval '1 day',
      now()+interval '1 month',now(),${proUser},'test',1)`;
});
afterAll(async () => {
  try {
    if (previousRelease) await db.unsafe(previousRelease);
    await clean();
  } finally {
    await db.end();
  }
});

function reservedPath(project: string, n: number) {
  const uuid = `a8400000-0000-0000-0000-${String(n).padStart(12, "0")}`;
  return { uuid, path: `pending/${project}/${uuid}/a.pdf` };
}
async function seedEnvelopes(
  project: string,
  task: string,
  actor: string,
  count: number,
  bytes: number,
  start: number,
) {
  for (let i = 0; i < count; i++) {
    const { uuid, path } = reservedPath(project, start + i);
    await db`insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,object_path,original_name,
      declared_mime_type,declared_size_bytes,state,expires_at,version,
      reserved_envelope_bytes)
      values(${uuid},${project},${task},${actor},'new_file',${path},
      'a.pdf','application/pdf',1,'reserved',now()+interval '15 minutes',1,
      ${bytes})`;
  }
}
describe("Pro Phase 2 storage concurrency", () => {
  test("Free 0.5 GiB admits only one of two competing complete envelopes", async () => {
    await seedEnvelopes(freeProject, freeTask, freeUser, 9, 52_428_800, 1);
    const [a, b] = await Promise.all([
      asActor(freeUser, freeProject, freeTask),
      asActor(freeUser, freeProject, freeTask),
    ]);
    expect([a, b].filter((x) => x.ok)).toHaveLength(1);
    expect(
      [a, b].filter((x) => x.code === "STORAGE_QUOTA_EXCEEDED"),
    ).toHaveLength(1);
    const [usage] = await db`select private.phase2_project_storage_usage(
      ${freeProject}::uuid) as bytes`;
    expect(Number(usage!.bytes)).toBe(10 * 52_428_800);
  });
  test("Pro 5 GiB admits only one of two racing 200 MiB envelopes", async () => {
    await db.unsafe(`create or replace function private.capability_is_released(
      p_capability text) returns boolean language sql immutable security definer
      set search_path='' as $body$
      select coalesce(p_capability=any(array['file_large_upload',
      'project_storage_quota','file_full_history','file_batch_rollback',
      'file_version_compare','project_recovery_point']::text[]),false)
      $body$;`);
    await seedEnvelopes(proProject, proTask, proUser, 24, 209_715_200, 101);
    const [a, b] = await Promise.all([
      asActor(proUser, proProject, proTask),
      asActor(proUser, proProject, proTask),
    ]);
    expect([a, b].filter((x) => x.ok)).toHaveLength(1);
    expect(
      [a, b].filter((x) => x.code === "STORAGE_QUOTA_EXCEEDED"),
    ).toHaveLength(1);
    const [usage] = await db`select private.phase2_project_storage_usage(
      ${proProject}::uuid) as bytes`;
    expect(Number(usage!.bytes)).toBe(25 * 209_715_200);
  });
});
