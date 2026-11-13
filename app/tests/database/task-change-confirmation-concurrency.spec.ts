import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const admin = postgres(databaseUrl, { max: 6 });

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  data?: { state?: string };
};

async function asAuthenticated(
  sql: Sql,
  userId: string,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
): Promise<RpcResult> {
  return sql.begin(async (tx): Promise<RpcResult> => {
    await tx`select set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx.unsafe("set local role authenticated");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.notifications where project_id::text like 'f2000000-%'`;
    await admin`delete from public.business_events where project_id::text like 'f2000000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'f2000000-%'`;
    await admin`delete from public.task_change_proposals where project_id::text like 'f2000000-%'`;
    await admin`delete from public.tasks where project_id::text like 'f2000000-%'`;
    await admin`delete from public.project_members where project_id::text like 'f2000000-%'`;
    await admin`delete from public.projects where id::text like 'f2000000-%'`;
    await admin`delete from auth.users where id::text like 'f1000000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seed(taskId: string, createProposal = true) {
  await admin`insert into auth.users(id,email) values
    ('f1000000-0000-0000-0000-000000000001','change-race-creator@example.test'),
    ('f1000000-0000-0000-0000-000000000002','change-race-assignee@example.test')`;
  await admin`insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state)
    values('f2000000-0000-0000-0000-000000000001','Change race',now()+interval '30 days',
    'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',1,'weighted','active')`;
  await admin`insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
    ('f3000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','leader','active',false,1),
    ('f3000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','member','active',false,1)`;
  await admin.unsafe(`insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version)
    values('${taskId}','f2000000-0000-0000-0000-000000000001','Race task',
    'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002',
    now()+interval '5 days','in_progress',2,now()-interval '1 day','assigned',1)`);
  if (!createProposal) return;

  return asAuthenticated(
    admin,
    "f1000000-0000-0000-0000-000000000001",
    (tx) => tx`select public.cmd_propose_task_change(
      'f2000000-0000-0000-0000-000000000001',${taskId}::uuid,
      now()+interval '10 days',3::smallint,
      'f9000000-0000-0000-0000-000000000001',1) as result`,
  );
}

beforeAll(async () => {
  await cleanup();
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("task change confirmation concurrency", () => {
  test("serializes concurrent approve/reject so exactly one decision commits", async () => {
    await seed("f4000000-0000-0000-0000-000000000001");
    const [proposal] = await admin<{ id: string }[]>`
      select id::text from public.task_change_proposals
      where task_id='f4000000-0000-0000-0000-000000000001' and state='pending'
    `;
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        "f1000000-0000-0000-0000-000000000002",
        (tx) => tx`
        select public.cmd_respond_to_task_change(
          'f2000000-0000-0000-0000-000000000001',
          'f4000000-0000-0000-0000-000000000001',
          ${proposal!.id}::uuid,'approve',null,
          'f9000000-0000-0000-0000-000000000002',1) as result`,
      ),
      asAuthenticated(
        b,
        "f1000000-0000-0000-0000-000000000002",
        (tx) => tx`
        select public.cmd_respond_to_task_change(
          'f2000000-0000-0000-0000-000000000001',
          'f4000000-0000-0000-0000-000000000001',
          ${proposal!.id}::uuid,'reject','race',
          'f9000000-0000-0000-0000-000000000003',1) as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const [row] = await admin<{ state: string; version: number }[]>`
      select state,version from public.task_change_proposals where id=${proposal!.id}::uuid
    `;
    const [task] = await admin<{ weight: number; version: number }[]>`
      select weight,version from public.tasks where id='f4000000-0000-0000-0000-000000000001'
    `;
    expect(row!.version).toBe(2);
    expect(["approved", "rejected"]).toContain(row!.state);
    if (row!.state === "approved") {
      expect(task).toMatchObject({ weight: 3, version: 2 });
    } else {
      expect(task).toMatchObject({ weight: 2, version: 1 });
    }
  });

  test("serializes concurrent proposal creation so only one pending proposal survives", async () => {
    await cleanup();
    const taskId = "f4000000-0000-0000-0000-000000000003";
    await seed(taskId, false);
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        "f1000000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_propose_task_change(
          'f2000000-0000-0000-0000-000000000001',${taskId}::uuid,
          now()+interval '10 days',3::smallint,
          'f9000000-0000-0000-0000-000000000005',1) as result`,
      ),
      asAuthenticated(
        b,
        "f1000000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_propose_task_change(
          'f2000000-0000-0000-0000-000000000001',${taskId}::uuid,
          now()+interval '11 days',4::smallint,
          'f9000000-0000-0000-0000-000000000006',1) as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "INVALID_TRANSITION",
    );
    const proposals = await admin<{ state: string }[]>`
      select state from public.task_change_proposals
      where task_id=${taskId}::uuid
    `;
    expect(proposals).toEqual([{ state: "pending" }]);
    const [task] = await admin<{ weight: number; version: number }[]>`
      select weight,version from public.tasks where id=${taskId}::uuid
    `;
    expect(task).toMatchObject({ weight: 2, version: 1 });
  });

  test("identical concurrent replay applies an approved change exactly once", async () => {
    await cleanup();
    await seed("f4000000-0000-0000-0000-000000000002");
    const [proposal] = await admin<{ id: string }[]>`
      select id::text from public.task_change_proposals
      where task_id='f4000000-0000-0000-0000-000000000002' and state='pending'
    `;
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const invoke = (sql: Sql) =>
      asAuthenticated(
        sql,
        "f1000000-0000-0000-0000-000000000002",
        (tx) => tx`
        select public.cmd_respond_to_task_change(
          'f2000000-0000-0000-0000-000000000001',
          'f4000000-0000-0000-0000-000000000002',
          ${proposal!.id}::uuid,'approve',null,
          'f9000000-0000-0000-0000-000000000004',1) as result`,
      );
    const results = await Promise.all([invoke(a), invoke(b)]);
    await Promise.all([a.end(), b.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.filter((result) => result.replayed)).toHaveLength(1);
    const [task] = await admin<{ weight: number; version: number }[]>`
      select weight,version from public.tasks where id='f4000000-0000-0000-0000-000000000002'
    `;
    expect(task).toMatchObject({ weight: 3, version: 2 });
  });
});
