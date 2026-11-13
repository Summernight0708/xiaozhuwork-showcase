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
  aggregateVersion?: number;
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
    await admin`delete from public.notifications where project_id::text like 'b7200000-%'`;
    await admin`delete from public.business_events where project_id::text like 'b7200000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'b7200000-%'`;
    await admin`delete from public.task_collaborators where project_id::text like 'b7200000-%'`;
    await admin`delete from public.tasks where project_id::text like 'b7200000-%'`;
    await admin`delete from public.project_members where project_id::text like 'b7200000-%'`;
    await admin`delete from public.projects where id::text like 'b7200000-%'`;
    await admin`delete from auth.users where id::text like 'b7100000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seed() {
  await admin`insert into auth.users(id,email) values
    ('b7100000-0000-0000-0000-000000000001','collab-race-leader@example.test'),
    ('b7100000-0000-0000-0000-000000000002','collab-race-primary@example.test'),
    ('b7100000-0000-0000-0000-000000000003','collab-race-target@example.test')`;
  await admin`insert into public.projects(
      id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
    ) values(
      'b7200000-0000-0000-0000-000000000001','Collaborator race',
      now()+interval '20 days',
      'b7100000-0000-0000-0000-000000000001',
      'b7100000-0000-0000-0000-000000000001',1,'weighted','active'
    )`;
  await admin`insert into public.project_members(
      id,project_id,user_id,role,member_state,is_observer,version
    ) values
    ('b7300000-0000-0000-0000-000000000001','b7200000-0000-0000-0000-000000000001','b7100000-0000-0000-0000-000000000001','leader','active',false,1),
    ('b7300000-0000-0000-0000-000000000002','b7200000-0000-0000-0000-000000000001','b7100000-0000-0000-0000-000000000002','member','active',false,1),
    ('b7300000-0000-0000-0000-000000000003','b7200000-0000-0000-0000-000000000001','b7100000-0000-0000-0000-000000000003','member','active',false,1)`;
  await admin`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      accepted_at,assignment_state,version
    ) values(
      'b7400000-0000-0000-0000-000000000001',
      'b7200000-0000-0000-0000-000000000001',
      'Collaborator race task',
      'b7100000-0000-0000-0000-000000000001',
      'b7100000-0000-0000-0000-000000000002',
      now()+interval '5 days','in_progress',2,now()-interval '1 day','assigned',1
    )`;

  const invited = await asAuthenticated(
    admin,
    "b7100000-0000-0000-0000-000000000001",
    (tx) => tx`select public.cmd_invite_task_collaborator(
      'b7200000-0000-0000-0000-000000000001',
      'b7400000-0000-0000-0000-000000000001',
      'b7100000-0000-0000-0000-000000000003',
      'b7900000-0000-0000-0000-000000000001',0
    ) as result`,
  );
  expect(invited.ok).toBe(true);
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

describe("task collaborator concurrency", () => {
  test("serializes concurrent accept/remove so only one state transition commits", async () => {
    await seed();
    const [relation] = await admin<{ id: string; version: number }[]>`
      select id::text,version from public.task_collaborators
      where task_id='b7400000-0000-0000-0000-000000000001'
        and user_id='b7100000-0000-0000-0000-000000000003'
    `;
    const accepter = postgres(databaseUrl, { max: 1 });
    const remover = postgres(databaseUrl, { max: 1 });

    const results = await Promise.all([
      asAuthenticated(
        accepter,
        "b7100000-0000-0000-0000-000000000003",
        (tx) => tx`select public.cmd_respond_to_task_collaborator(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          ${relation!.id}::uuid,'accept',
          'b7900000-0000-0000-0000-000000000002',
          ${relation!.version}
        ) as result`,
      ),
      asAuthenticated(
        remover,
        "b7100000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_remove_task_collaborator(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          ${relation!.id}::uuid,
          'b7900000-0000-0000-0000-000000000003',
          ${relation!.version}
        ) as result`,
      ),
    ]);
    await Promise.all([accepter.end(), remover.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const [after] = await admin<{ state: string; version: number }[]>`
      select state,version from public.task_collaborators where id=${relation!.id}::uuid
    `;
    expect(["accepted", "removed"]).toContain(after!.state);
    expect(after!.version).toBe(2);
  });

  test("serializes concurrent leave/remove on an accepted collaborator", async () => {
    await cleanup();
    await seed();
    const [relation] = await admin<{ id: string; version: number }[]>`
      select id::text,version from public.task_collaborators
      where task_id='b7400000-0000-0000-0000-000000000001'
        and user_id='b7100000-0000-0000-0000-000000000003'
    `;
    const accepted = await asAuthenticated(
      admin,
      "b7100000-0000-0000-0000-000000000003",
      (tx) => tx`select public.cmd_respond_to_task_collaborator(
        'b7200000-0000-0000-0000-000000000001',
        'b7400000-0000-0000-0000-000000000001',
        ${relation!.id}::uuid,'accept',
        'b7900000-0000-0000-0000-000000000004',
        ${relation!.version}
      ) as result`,
    );
    expect(accepted.ok).toBe(true);

    const leaver = postgres(databaseUrl, { max: 1 });
    const remover = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        leaver,
        "b7100000-0000-0000-0000-000000000003",
        (tx) => tx`select public.cmd_leave_task_collaboration(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          ${relation!.id}::uuid,
          'b7900000-0000-0000-0000-000000000005',2
        ) as result`,
      ),
      asAuthenticated(
        remover,
        "b7100000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_remove_task_collaborator(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          ${relation!.id}::uuid,
          'b7900000-0000-0000-0000-000000000006',2
        ) as result`,
      ),
    ]);
    await Promise.all([leaver.end(), remover.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const [after] = await admin<{ state: string; version: number }[]>`
      select state,version from public.task_collaborators where id=${relation!.id}::uuid
    `;
    expect(after).toMatchObject({ state: "removed", version: 3 });
  });
  test("keeps collaborator removal and Task Help authorization linearizable", async () => {
    await cleanup();
    await seed();
    const [relation] = await admin<{ id: string; version: number }[]>`
      select id::text,version from public.task_collaborators
      where task_id='b7400000-0000-0000-0000-000000000001'
        and user_id='b7100000-0000-0000-0000-000000000003'
    `;
    const accepted = await asAuthenticated(
      admin,
      "b7100000-0000-0000-0000-000000000003",
      (tx) => tx`select public.cmd_respond_to_task_collaborator(
        'b7200000-0000-0000-0000-000000000001',
        'b7400000-0000-0000-0000-000000000001',
        ${relation!.id}::uuid,'accept',
        'b7900000-0000-0000-0000-000000000007',
        ${relation!.version}
      ) as result`,
    );
    expect(accepted.ok).toBe(true);

    const remover = postgres(databaseUrl, { max: 1 });
    const requester = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        remover,
        "b7100000-0000-0000-0000-000000000001",
        (tx) => tx`select public.cmd_remove_task_collaborator(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          ${relation!.id}::uuid,
          'b7900000-0000-0000-0000-000000000008',2
        ) as result`,
      ),
      asAuthenticated(
        requester,
        "b7100000-0000-0000-0000-000000000003",
        (tx) => tx`select public.cmd_create_task_help_request(
          'b7200000-0000-0000-0000-000000000001',
          'b7400000-0000-0000-0000-000000000001',
          'b7900000-0000-0000-0000-000000000009',1,
          'Concurrent help request',null,false
        ) as result`,
      ),
    ]);
    await Promise.all([remover.end(), requester.end()]);

    expect(results[0]?.ok).toBe(true);
    expect(
      results[1]?.ok ||
        ["NOT_FOUND_OR_NOT_AUTHORIZED", "NOT_AUTHORIZED"].includes(
          results[1]?.code ?? "",
        ),
    ).toBe(true);

    const [after] = await admin<{ state: string; version: number }[]>`
      select state,version from public.task_collaborators where id=${relation!.id}::uuid
    `;
    expect(after).toMatchObject({ state: "removed", version: 3 });

    const afterRemoval = await asAuthenticated(
      admin,
      "b7100000-0000-0000-0000-000000000003",
      (tx) => tx`select public.cmd_create_task_help_request(
        'b7200000-0000-0000-0000-000000000001',
        'b7400000-0000-0000-0000-000000000001',
        'b7900000-0000-0000-0000-000000000010',1,
        'Must be denied after removal',null,false
      ) as result`,
    );
    expect(afterRemoval.ok).toBe(false);
    expect(["NOT_FOUND_OR_NOT_AUTHORIZED", "NOT_AUTHORIZED"]).toContain(
      afterRemoval.code,
    );
  });
});
