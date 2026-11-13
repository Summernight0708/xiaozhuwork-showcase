import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const admin = postgres(databaseUrl, { max: 4 });

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
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
    await admin`delete from public.business_events where project_id::text like 'e2000000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'e2000000-%'`;
    await admin`delete from public.task_dependencies where project_id::text like 'e2000000-%'`;
    await admin`delete from public.tasks where project_id::text like 'e2000000-%'`;
    await admin`delete from public.project_members where project_id::text like 'e2000000-%'`;
    await admin`delete from public.projects where id::text like 'e2000000-%'`;
    await admin`delete from auth.users where id::text like 'e1000000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
  await admin`insert into auth.users(id,email) values ('e1000000-0000-0000-0000-000000000001','dep-race@example.test')`;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("task dependency concurrency", () => {
  test("serializes competing edges so concurrent A->B and B->A cannot commit a cycle", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values('e2000000-0000-0000-0000-000000000001','Dependency race',now()+interval '20 days',
      'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1)
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
      values('e3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000001','leader','active',false,1)
    `;
    await admin`
      insert into public.tasks(id,project_id,title,created_by,deadline_at,status,assignment_state,version) values
      ('e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','A','e1000000-0000-0000-0000-000000000001',now()+interval '5 days','not_started','claimable',1),
      ('e4000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','B','e1000000-0000-0000-0000-000000000001',now()+interval '6 days','not_started','claimable',1)
    `;

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        "e1000000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_set_task_dependencies(
        'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
        array['e4000000-0000-0000-0000-000000000001'::uuid],
        'e9000000-0000-0000-0000-000000000001',1) as result`,
      ),
      asAuthenticated(
        b,
        "e1000000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_set_task_dependencies(
        'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
        array['e4000000-0000-0000-0000-000000000002'::uuid],
        'e9000000-0000-0000-0000-000000000002',1) as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "INVALID_TRANSITION",
    );
    const edges = await admin<
      { upstream_task_id: string; downstream_task_id: string }[]
    >`
      select upstream_task_id::text, downstream_task_id::text from public.task_dependencies
      where project_id='e2000000-0000-0000-0000-000000000001'
    `;
    expect(edges).toHaveLength(1);
  });
});
