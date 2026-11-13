import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 6 });
const user = (suffix: number) =>
  `e1100000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const project = (suffix: number) =>
  `e2100000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const invite = (suffix: number) =>
  `e3100000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const membership = (suffix: number) =>
  `e4100000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;
const request = (suffix: number) =>
  `e5100000-0000-0000-0000-${suffix.toString().padStart(12, "0")}`;

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed?: boolean;
  details?: Record<string, string | number | boolean>;
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

async function addProject(projectId: string, leaderId: string, version = 1) {
  await admin`
    insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
    values(
      ${projectId},
      ${`P1 concurrency ${projectId}`},
      now()+interval '30 days',
      ${leaderId},
      ${leaderId},
      ${version}
    )
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state)
    values(${projectId},${leaderId},'leader','active')
  `;
}

async function addInvite(
  inviteId: string,
  projectId: string,
  creatorId: string,
  token: string,
) {
  await admin`
    insert into public.project_invitations(
      id,project_id,created_by,token_hash,mode,expires_at,version
    ) values(
      ${inviteId},
      ${projectId},
      ${creatorId},
      extensions.digest(convert_to(${token},'utf8'),'sha256'),
      'direct',
      now()+interval '7 days',
      1
    )
  `;
}

async function addPro(userId: string) {
  await admin`
    insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values(
      ${userId},
      'pro',
      'active',
      now()-interval '1 day',
      now()+interval '30 days',
      now(),
      ${user(1)},
      'test',
      1
    )
  `;
}

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.business_events where project_id::text like 'e2100000-%' or actor_id::text like 'e1100000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'e2100000-%' or actor_id::text like 'e1100000-%'`;
    await admin`delete from public.project_pro_grace where project_id::text like 'e2100000-%'`;
    await admin`delete from public.account_entitlement_audit where user_id::text like 'e1100000-%'`;
    await admin`delete from private.account_entitlement_service_commands where request_id::text like 'e5100000-%'`;
    await admin`delete from public.account_entitlements where user_id::text like 'e1100000-%'`;
    await admin`delete from public.task_assignment_offers where project_id::text like 'e2100000-%'`;
    await admin`delete from public.tasks where project_id::text like 'e2100000-%'`;
    await admin`delete from public.project_join_requests where project_id::text like 'e2100000-%'`;
    await admin`delete from public.project_invitations where project_id::text like 'e2100000-%'`;
    await admin`delete from public.project_members where project_id::text like 'e2100000-%' or user_id::text like 'e1100000-%'`;
    await admin`delete from public.projects where id::text like 'e2100000-%' or created_by::text like 'e1100000-%'`;
    await admin`delete from auth.users where id::text like 'e1100000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
  await admin`
    insert into auth.users(id,email)
    select
      ('e1100000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
      'p1-concurrency-' || i || '@example.test'
    from generate_series(1,70) s(i)
  `;
  await admin`
    update public.profiles
    set display_name='P1 Concurrency',real_name='P1 Real',student_number='P1'
    where id::text like 'e1100000-%'
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("P1 Pro quota concurrency", () => {
  test("rechecks member creation permission after waiting for the project settings lock", async () => {
    await addProject(project(60), user(60));
    await admin`insert into public.project_members(project_id,user_id,role,member_state)
      values(${project(60)},${user(61)},'member','active')`;
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, {
      max: 1,
      connection: { application_name: "xiaozhuwork-options-waiting-create" },
    });
    let unlock!: () => void;
    let markLocked!: () => void;
    const release = new Promise<void>((resolve) => {
      unlock = resolve;
    });
    const locked = new Promise<void>((resolve) => {
      markLocked = resolve;
    });
    const settings = asAuthenticated(connectionA, user(60), async (tx) => {
      const rows = await tx<
        { result: RpcResult }[]
      >`select public.cmd_update_project_settings(
        p_project_id=>${project(60)},p_request_id=>${request(60)},p_expected_version=>1,
        p_name=>p.name,p_course_name=>p.course_name,p_description=>p.description,
        p_deadline_at=>p.deadline_at,p_timezone=>p.timezone,p_contribution_mode=>p.contribution_mode,
        p_auto_penalty_enabled=>false,p_require_real_name=>false,p_require_student_number=>false,
        p_allow_member_task_creation=>false
      ) as result from public.projects p where id=${project(60)}`;
      markLocked();
      await release;
      return Array.from(rows, (row) => ({ result: row.result as RpcResult }));
    });
    let creating: Promise<RpcResult> | undefined;
    try {
      await locked;
      creating = asAuthenticated(
        connectionB,
        user(61),
        (tx) => tx`select public.cmd_create_task(
        ${project(60)},${request(61)},1,'Queued member task',null,now()+interval '2 days',1::smallint
      ) as result`,
      );
      await expect
        .poll(async () => {
          const rows =
            await admin`select count(*)::integer as count from pg_stat_activity
          where application_name='xiaozhuwork-options-waiting-create' and wait_event_type='Lock'`;
          return rows[0]!.count;
        })
        .toBe(1);
      unlock();
      expect((await settings).ok).toBe(true);
      expect(await creating).toMatchObject({
        ok: false,
        code: "NOT_FOUND_OR_NOT_AUTHORIZED",
      });
      const tasks =
        await admin`select id from public.tasks where project_id=${project(60)}`;
      expect(tasks).toHaveLength(0);
    } finally {
      unlock();
      await Promise.allSettled([settings, creating]);
      await Promise.all([connectionA.end(), connectionB.end()]);
    }
  });

  test("never creates a twenty-first Free concurrent task", async () => {
    await addProject(project(1), user(1));
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values(${project(1)},${user(2)},'member','active')
    `;
    await admin`
      insert into public.tasks(project_id,title,created_by,deadline_at,status,weight)
      select
        ${project(1)},
        'Existing task ' || i,
        ${user(1)},
        now()+interval '5 days',
        'not_started',
        1
      from generate_series(1,19) s(i)
    `;
    const deadline = new Date(Date.now() + 5 * 86_400_000).toISOString();
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(1),
        (tx) =>
          tx`select public.cmd_create_task(
            ${project(1)},${request(1)},1,'Race task A',null,${deadline},
            1::smallint,'claimable',null
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(2),
        (tx) =>
          tx`select public.cmd_create_task(
            ${project(1)},${request(2)},1,'Race task B',null,${deadline},
            1::smallint,'claimable',null
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(["STALE_VERSION", "CONCURRENT_TASK_LIMIT_REACHED"]).toContain(
      results.find((result) => !result.ok)?.code,
    );
    const rows = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.tasks
      where project_id=${project(1)}
        and status not in ('completed','canceled')
    `;
    expect(rows[0]!.count).toBe(20);
  });

  test("serializes the Free eight-member cap across different invitations", async () => {
    await addProject(project(2), user(3));
    for (const memberId of [4, 5, 6, 7, 8, 9]) {
      await admin`
        insert into public.project_members(project_id,user_id,role,member_state)
        values(${project(2)},${user(memberId)},'member','active')
      `;
    }
    await addInvite(invite(1), project(2), user(3), "p1-member-race-a");
    await addInvite(invite(2), project(2), user(3), "p1-member-race-b");

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(10),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-member-race-a',${request(3)},1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(11),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-member-race-b',${request(4)},1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "PROJECT_MEMBER_LIMIT_REACHED",
    );
    const rows = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.project_members
      where project_id=${project(2)}
        and member_state='active'
        and user_id is not null
    `;
    expect(rows[0]!.count).toBe(8);
  });

  test("serializes one Free account joining two fifth projects", async () => {
    for (let index = 10; index < 14; index += 1) {
      await addProject(project(index), user(20));
    }
    await addProject(project(14), user(21));
    await addProject(project(15), user(22));
    await addInvite(invite(3), project(14), user(21), "p1-account-race-a");
    await addInvite(invite(4), project(15), user(22), "p1-account-race-b");

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(20),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-account-race-a',${request(5)},1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(20),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-account-race-b',${request(6)},1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
    );
    const rows = await admin<{ count: number }[]>`
      select private.account_active_free_project_count(${user(20)},now()) as count
    `;
    expect(rows[0]!.count).toBe(5);
  });

  test("allows concurrent Pro sources to cross the old Free member cap consistently", async () => {
    await addProject(project(20), user(30));
    for (const memberId of [31, 32, 33, 34, 35, 36, 37]) {
      await admin`
        insert into public.project_members(project_id,user_id,role,member_state)
        values(${project(20)},${user(memberId)},'member','active')
      `;
    }
    await addPro(user(38));
    await addPro(user(39));
    await addInvite(invite(5), project(20), user(30), "p1-pro-race-a");
    await addInvite(invite(6), project(20), user(30), "p1-pro-race-b");

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(38),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-pro-race-a',${request(7)},1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(39),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-pro-race-b',${request(8)},1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    const rows = await admin<{ count: number; state: string }[]>`
      select
        (select count(*)::integer
         from public.project_members
         where project_id=${project(20)}
           and member_state='active'
           and user_id is not null) as count,
        (select state
         from private.resolve_project_entitlement(${project(20)},now())) as state
    `;
    expect(rows[0]).toEqual({ count: 10, state: "active" });
  });

  test("last Pro removal racing another Pro join leaves resolver consistent", async () => {
    await addProject(project(30), user(40));
    await admin`
      insert into public.project_members(
        id,project_id,user_id,role,member_state,version
      ) values(
        ${membership(1)},${project(30)},${user(41)},'member','active',1
      )
    `;
    await addPro(user(41));
    await addPro(user(42));
    await addInvite(invite(7), project(30), user(40), "p1-source-race");

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const [removeResult, joinResult] = await Promise.all([
      asAuthenticated(
        connectionA,
        user(40),
        (tx) =>
          tx`select public.cmd_remove_project_member(
            ${project(30)},${membership(1)},${request(9)},1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(42),
        (tx) =>
          tx`select public.cmd_join_project_via_invite(
            'p1-source-race',${request(10)},1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(removeResult.ok).toBe(true);
    expect(joinResult.ok).toBe(true);
    const rows = await admin<
      {
        state: string;
        source_count: number;
        grace_count: number;
        grace_version: number | null;
      }[]
    >`
      select
        (select state from private.resolve_project_entitlement(${project(30)},now())) as state,
        (select count(*)::integer
         from public.project_members pm
         where pm.project_id=${project(30)}
           and pm.member_state='active'
           and pm.role in ('leader','admin','member')
           and private.is_account_pro(pm.user_id,now())) as source_count,
        (select count(*)::integer
         from public.project_pro_grace
         where project_id=${project(30)}) as grace_count,
        (select version
         from public.project_pro_grace
         where project_id=${project(30)}) as grace_version
    `;
    expect(rows[0]!.state).toBe("active");
    expect(rows[0]!.source_count).toBe(1);
    expect(rows[0]!.grace_count).toBeLessThanOrEqual(1);
    expect(rows[0]!.grace_version ?? 1).toBe(1);
  });

  test("serializes two Free project creates for one account at four", async () => {
    for (let index = 40; index < 44; index += 1) {
      await addProject(project(index), user(50));
    }
    const deadline = new Date(Date.now() + 20 * 86_400_000).toISOString();
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        user(50),
        (tx) =>
          tx`select public.cmd_create_project(
            ${request(11)},0,'P1 create race A',${deadline},
            null,null,null,null,null,null
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        user(50),
        (tx) =>
          tx`select public.cmd_create_project(
            ${request(12)},0,'P1 create race B',${deadline},
            null,null,null,null,null,null
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
    );
    const rows = await admin<{ count: number }[]>`
      select private.account_active_free_project_count(${user(50)},now()) as count
    `;
    expect(rows[0]!.count).toBe(5);
  });
});
