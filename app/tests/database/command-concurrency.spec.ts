import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });
const prefix = "70000000-0000-0000-0000-";
const user = (suffix: number) =>
  `${prefix}${suffix.toString().padStart(12, "0")}`;
const request = (suffix: number) =>
  `71000000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const project = (suffix: number) =>
  `72000000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const task = (suffix: number) =>
  `73000000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const invite = (suffix: number) =>
  `74000000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
  data?: Record<string, unknown>;
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

async function createAuthUsers(count: number) {
  for (let index = 1; index <= count; index += 1) {
    await admin`
      insert into auth.users (id, email)
      values (${user(index)}, ${`concurrency-${index}@example.test`})
      on conflict (id) do nothing
    `;
  }
  await admin`
    update public.profiles
    set display_name = 'Concurrency User', real_name = 'Concurrency Real', student_number = 'C1'
    where id::text like '70000000-0000-0000-0000-%'
  `;
}

async function addProject(projectId: string, leaderId: string, version = 1) {
  await admin`
    insert into public.projects (id, name, deadline_at, leader_id, created_by, version)
    values (${projectId}, ${`Concurrency ${projectId}`}, now() + interval '30 days', ${leaderId}, ${leaderId}, ${version})
  `;
  await admin`
    insert into public.project_members (project_id, user_id, role, member_state)
    values (${projectId}, ${leaderId}, 'leader', 'active')
  `;
}

beforeAll(async () => {
  await createAuthUsers(15);
});

afterAll(async () => {
  try {
    await admin`alter table public.business_events disable trigger business_events_immutable`;
    await admin`
      delete from public.business_events
      where actor_id::text like '70000000-0000-0000-0000-%'
         or project_id::text like '72000000-0000-0000-0000-%'
    `;
    await admin`
      delete from public.command_requests
      where actor_id::text like '70000000-0000-0000-0000-%'
         or project_id::text like '72000000-0000-0000-0000-%'
    `;
    await admin`
      delete from public.projects
      where id::text like '72000000-0000-0000-0000-%'
         or created_by::text like '70000000-0000-0000-0000-%'
    `;
    await admin`delete from auth.users where id::text like '70000000-0000-0000-0000-%'`;
  } finally {
    await admin`alter table public.business_events enable trigger business_events_immutable`;
    await admin.end();
  }
});

describe("command RPC concurrency", () => {
  test("executes concurrent identical request_id exactly once", async () => {
    const requestId = request(1);
    const deadline = new Date(Date.now() + 20 * 86_400_000).toISOString();
    const call = (sql: Sql) =>
      asAuthenticated(
        sql,
        user(1),
        (tx) =>
          tx`select public.cmd_create_project(${requestId}, 0, 'Exactly once', ${deadline}, null, null, null, null, null, null) as result`,
      );

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([call(connectionA), call(connectionB)]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.map((result) => result.replayed).sort()).toEqual([
      false,
      true,
    ]);
    const projectRows = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.projects where name='Exactly once'
    `;
    const eventRows = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.business_events where request_id=${requestId}
    `;
    expect(projectRows[0]!.count).toBe(1);
    expect(eventRows[0]!.count).toBe(1);
  });

  test("serializes the five-active-project account cap", async () => {
    for (let index = 10; index < 14; index += 1)
      await addProject(project(index), user(2));
    const deadline = new Date(Date.now() + 20 * 86_400_000).toISOString();
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const calls = [
      asAuthenticated(
        connectionA,
        user(2),
        (tx) =>
          tx`select public.cmd_create_project(${request(2)}, 0, 'Cap winner A', ${deadline}, null, null, null, null, null, null) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(2),
        (tx) =>
          tx`select public.cmd_create_project(${request(3)}, 0, 'Cap winner B', ${deadline}, null, null, null, null, null, null) as result`,
      ),
    ];
    const results = await Promise.all(calls);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
    );
  });

  test("allows one claimant for a task version", async () => {
    await addProject(project(20), user(3));
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values (${project(20)},${user(4)},'member','active'),(${project(20)},${user(5)},'member','active')
    `;
    await admin`
      insert into public.tasks(id,project_id,title,created_by,deadline_at,weight,assignment_state)
      values (${task(1)},${project(20)},'Race claim',${user(3)},now()+interval '5 days',1,'claimable')
    `;
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(4),
        (tx) =>
          tx`select public.cmd_claim_task(${project(20)},${task(1)},${request(4)},1) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(5),
        (tx) =>
          tx`select public.cmd_claim_task(${project(20)},${task(1)},${request(5)},1) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "TASK_ALREADY_CLAIMED",
    );
  });

  test("allows one project-version task create and returns stale to the loser", async () => {
    await addProject(project(21), user(6));
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values (${project(21)},${user(7)},'member','active')
    `;
    const deadline = new Date(Date.now() + 5 * 86_400_000).toISOString();
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(6),
        (tx) =>
          tx`select public.cmd_create_task(${project(21)},${request(6)},1,'Race task A',null,${deadline},1::smallint,'claimable',null) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(7),
        (tx) =>
          tx`select public.cmd_create_task(${project(21)},${request(7)},1,'Race task B',null,${deadline},1::smallint,'claimable',null) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(2);
  });

  test("serializes concurrent acceptance of one primary handoff", async () => {
    await addProject(project(30), user(3));
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values (${project(30)},${user(4)},'member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        assignment_state,accepted_at,version
      )
      values (
        ${task(30)},${project(30)},'Handoff accept race',${user(3)},${user(3)},
        now()+interval '5 days','in_progress',1,'assigned',now(),1
      )
    `;

    const requested = await asAuthenticated(
      admin,
      user(3),
      (tx) =>
        tx`select public.cmd_request_task_primary_handoff(
          ${project(30)},${task(30)},${user(4)},${request(40)},1
        ) as result`,
    );
    expect(requested.ok).toBe(true);
    const handoffs = await admin<{ id: string }[]>`
      select id from public.task_primary_handoffs
      where task_id=${task(30)} and state='pending'
    `;
    const handoffId = handoffs[0]!.id;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const accept = (sql: Sql, requestId: string) =>
      asAuthenticated(
        sql,
        user(4),
        (tx) =>
          tx`select public.cmd_respond_task_primary_handoff(
            ${project(30)},${task(30)},${handoffId},'accept',${requestId},1,1
          ) as result`,
      );

    const results = await Promise.all([
      accept(connectionA, request(41)),
      accept(connectionB, request(42)),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const rows = await admin<{ assignee_id: string; version: number }[]>`
      select assignee_id,version from public.tasks where id=${task(30)}
    `;
    expect(rows[0]).toMatchObject({ assignee_id: user(4), version: 2 });
  });

  test("serializes primary handoff acceptance against voluntary unassignment", async () => {
    await addProject(project(31), user(5));
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values (${project(31)},${user(6)},'member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        assignment_state,accepted_at,version
      )
      values (
        ${task(31)},${project(31)},'Handoff unassign race',${user(5)},${user(5)},
        now()+interval '5 days','in_progress',1,'assigned',now(),1
      )
    `;

    const requested = await asAuthenticated(
      admin,
      user(5),
      (tx) =>
        tx`select public.cmd_request_task_primary_handoff(
          ${project(31)},${task(31)},${user(6)},${request(43)},1
        ) as result`,
    );
    expect(requested.ok).toBe(true);
    const handoffs = await admin<{ id: string }[]>`
      select id from public.task_primary_handoffs
      where task_id=${task(31)} and state='pending'
    `;
    const handoffId = handoffs[0]!.id;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(6),
        (tx) =>
          tx`select public.cmd_respond_task_primary_handoff(
            ${project(31)},${task(31)},${handoffId},'accept',${request(44)},1,1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(5),
        (tx) =>
          tx`select public.cmd_unassign_task_primary(
            ${project(31)},${task(31)},${request(45)},1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(["STALE_VERSION", "NOT_FOUND_OR_NOT_AUTHORIZED"]).toContain(
      results.find((result) => !result.ok)?.code,
    );
    const rows = await admin<
      {
        assignee_id: string | null;
        assignment_state: string;
        version: number;
      }[]
    >`
      select assignee_id,assignment_state,version
      from public.tasks where id=${task(31)}
    `;
    expect(rows[0]!.version).toBe(2);
    expect(
      (rows[0]!.assignment_state === "assigned" &&
        rows[0]!.assignee_id === user(6)) ||
        (rows[0]!.assignment_state === "claimable" &&
          rows[0]!.assignee_id === null),
    ).toBe(true);
  });

  test("serializes join against revoke", async () => {
    await addProject(project(22), user(8));
    await admin`
      insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
      values (${invite(1)},${project(22)},${user(8)},extensions.digest(convert_to('join-revoke-race','utf8'),'sha256'),'direct',now()+interval '7 days')
    `;
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(9),
        (tx) =>
          tx`select public.cmd_join_project_via_invite('join-revoke-race',${request(8)},1) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(8),
        (tx) =>
          tx`select public.cmd_revoke_project_invite(${project(22)},${invite(1)},${request(9)},1) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(["INVITE_UNAVAILABLE", "STALE_VERSION"]).toContain(
      results.find((result) => !result.ok)?.code,
    );
  });

  test("serializes member capacity across different invitations", async () => {
    await addProject(project(23), user(10));
    for (const memberId of [1, 11, 12, 13, 14, 15]) {
      await admin`
        insert into public.project_members(project_id,user_id,role,member_state)
        values (${project(23)},${user(memberId)},'member','active')
      `;
    }
    await admin`
      insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at) values
      (${invite(2)},${project(23)},${user(10)},extensions.digest(convert_to('capacity-a','utf8'),'sha256'),'direct',now()+interval '7 days'),
      (${invite(3)},${project(23)},${user(10)},extensions.digest(convert_to('capacity-b','utf8'),'sha256'),'direct',now()+interval '7 days')
    `;
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(3),
        (tx) =>
          tx`select public.cmd_join_project_via_invite('capacity-a',${request(10)},1) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(4),
        (tx) =>
          tx`select public.cmd_join_project_via_invite('capacity-b',${request(11)},1) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "PROJECT_MEMBER_LIMIT_REACHED",
    );
  });

  test("serializes concurrent renewals of one invitation version", async () => {
    await addProject(project(24), user(12));
    await admin`
      insert into public.project_invitations(
        id,project_id,created_by,token_hash,mode,expires_at,version
      )
      values (
        ${invite(30)},
        ${project(24)},
        ${user(12)},
        extensions.digest(convert_to('renew-race','utf8'),'sha256'),
        'direct',
        now()+interval '7 days',
        1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const renew = (sql: Sql, requestId: string) =>
      asAuthenticated(
        sql,
        user(12),
        (tx) =>
          tx`select public.cmd_renew_project_invite(
            ${project(24)},
            ${invite(30)},
            ${requestId},
            1,
            7
          ) as result`,
      );

    const results = await Promise.all([
      renew(connectionA, request(30)),
      renew(connectionB, request(31)),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    const loser = results.find((result) => !result.ok);
    expect(loser?.code).toBe("STALE_VERSION");
    expect(loser?.currentVersion).toBe(2);

    const rows = await admin<{ version: number }[]>`
      select version
      from public.project_invitations
      where id=${invite(30)}
    `;
    expect(rows[0]!.version).toBe(2);
  });
});
