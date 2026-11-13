import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeEach, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const admin = postgres(databaseUrl, { max: 6 });

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  data?: {
    state?: string;
    taskResumed?: boolean;
  };
};

const USER_LEADER = "aa100000-0000-0000-0000-000000000001";
const USER_MEMBER = "aa100000-0000-0000-0000-000000000002";
const USER_HELPER = "aa100000-0000-0000-0000-000000000003";
const PROJECT_ID = "aa200000-0000-0000-0000-000000000001";
const UPSTREAM_ID = "aa400000-0000-0000-0000-000000000001";
const DOWNSTREAM_ID = "aa400000-0000-0000-0000-000000000002";
const HELP_TASK_ID = "aa400000-0000-0000-0000-000000000003";

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
    await admin`delete from public.notifications where project_id=${PROJECT_ID}`;
    await admin`delete from public.business_events where project_id=${PROJECT_ID}`;
    await admin`delete from public.command_requests where project_id=${PROJECT_ID}`;
    await admin`delete from public.task_help_requests where project_id=${PROJECT_ID}`;
    await admin`delete from public.upstream_rework_requests where project_id=${PROJECT_ID}`;
    await admin`delete from public.task_collaborators where project_id=${PROJECT_ID}`;
    await admin`delete from public.task_dependencies where project_id=${PROJECT_ID}`;
    await admin`delete from public.tasks where project_id=${PROJECT_ID}`;
    await admin`delete from public.project_members where project_id=${PROJECT_ID}`;
    await admin`delete from public.projects where id=${PROJECT_ID}`;
    await admin`delete from auth.users where id in (${USER_LEADER},${USER_MEMBER},${USER_HELPER})`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seed() {
  await admin`insert into auth.users(id,email) values
    (${USER_LEADER},'workflow-race-leader@example.test'),
    (${USER_MEMBER},'workflow-race-member@example.test'),
    (${USER_HELPER},'workflow-race-helper@example.test')`;
  await admin`insert into public.projects(
      id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
    ) values (
      ${PROJECT_ID},'Workflow race',now()+interval '30 days',
      ${USER_LEADER},${USER_LEADER},1,'weighted','active'
    )`;
  await admin`insert into public.project_members(
      id,project_id,user_id,role,member_state,is_observer,version
    ) values
    ('aa300000-0000-0000-0000-000000000001',${PROJECT_ID},${USER_LEADER},'leader','active',false,1),
    ('aa300000-0000-0000-0000-000000000002',${PROJECT_ID},${USER_MEMBER},'member','active',false,1),
    ('aa300000-0000-0000-0000-000000000003',${PROJECT_ID},${USER_HELPER},'member','active',false,1)`;
  await admin`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,
      assignment_state,first_submitted_at,completed_at,version
    ) values
    (${UPSTREAM_ID},${PROJECT_ID},'Completed upstream',${USER_LEADER},${USER_HELPER},
      now()+interval '5 days','completed',3,now()-interval '3 days','assigned',
      now()-interval '2 days',now()-interval '1 day',5),
    (${DOWNSTREAM_ID},${PROJECT_ID},'Active downstream',${USER_LEADER},${USER_MEMBER},
      now()+interval '8 days','in_progress',2,now()-interval '2 days','assigned',null,null,4),
    (${HELP_TASK_ID},${PROJECT_ID},'Help race task',${USER_LEADER},${USER_MEMBER},
      now()+interval '9 days','in_progress',2,now()-interval '1 day','assigned',null,null,1)`;
  await admin`insert into public.task_dependencies(
      project_id,upstream_task_id,downstream_task_id,created_by
    ) values (${PROJECT_ID},${UPSTREAM_ID},${DOWNSTREAM_ID},${USER_LEADER})`;
  await admin`insert into public.task_collaborators(
      id,project_id,task_id,user_id,user_name_snapshot,state,invited_by,
      invited_by_name_snapshot,responded_at,version
    ) values(
      'aa350000-0000-0000-0000-000000000001',${PROJECT_ID},${HELP_TASK_ID},
      ${USER_HELPER},'Helper','accepted',${USER_LEADER},'Leader',now(),1
    )`;
}

async function createPending(
  requestId = "aa900000-0000-0000-0000-000000000001",
) {
  return asAuthenticated(
    admin,
    USER_MEMBER,
    (tx) => tx`select public.cmd_request_upstream_rework(
      ${PROJECT_ID},${DOWNSTREAM_ID},${UPSTREAM_ID},
      ${requestId}::uuid,4,5,'Please revise upstream') as result`,
  );
}

beforeEach(async () => {
  await cleanup();
  await seed();
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("task help and upstream rework concurrency", () => {
  test("serializes approve/reject so only one rework decision commits", async () => {
    const created = await createPending();
    expect(created).toMatchObject({ ok: true, data: { state: "pending" } });
    const [request] = await admin<{ id: string }[]>`
      select id::text from public.upstream_rework_requests
      where project_id=${PROJECT_ID} and state='pending'
    `;

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        USER_LEADER,
        (tx) => tx`select public.cmd_review_upstream_rework(
          ${PROJECT_ID},${request!.id}::uuid,
          'aa900000-0000-0000-0000-000000000002',1,'approve') as result`,
      ),
      asAuthenticated(
        b,
        USER_LEADER,
        (tx) => tx`select public.cmd_review_upstream_rework(
          ${PROJECT_ID},${request!.id}::uuid,
          'aa900000-0000-0000-0000-000000000003',1,'reject') as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const [row] = await admin<{ state: string; version: number }[]>`
      select state,version from public.upstream_rework_requests where id=${request!.id}::uuid
    `;
    const [upstream] = await admin<{ status: string; version: number }[]>`
      select status,version from public.tasks where id=${UPSTREAM_ID}
    `;
    expect(row!.version).toBe(2);
    expect(["approved", "rejected"]).toContain(row!.state);
    expect(upstream).toEqual(
      row!.state === "approved"
        ? { status: "in_progress", version: 6 }
        : { status: "completed", version: 5 },
    );

    const [events] = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.business_events
      where project_id=${PROJECT_ID}
        and request_id in (
          'aa900000-0000-0000-0000-000000000002',
          'aa900000-0000-0000-0000-000000000003'
        )
    `;
    expect(events!.count).toBe(1);

    const duplicates = await admin<{ count: number }[]>`
      select count(*)::integer as count from (
        select recipient_id,notification_type,source_event_id
        from public.notifications
        where project_id=${PROJECT_ID}
        group by recipient_id,notification_type,source_event_id
        having count(*) > 1
      ) duplicate_groups
    `;
    expect(duplicates[0]!.count).toBe(0);
  });

  test("replays the same concurrent decision request without double reopening", async () => {
    await createPending();
    const [request] = await admin<{ id: string }[]>`
      select id::text from public.upstream_rework_requests
      where project_id=${PROJECT_ID} and state='pending'
    `;
    const requestId = "aa900000-0000-0000-0000-000000000004";
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const invoke = (sql: Sql) =>
      asAuthenticated(
        sql,
        USER_LEADER,
        (tx) => tx`select public.cmd_review_upstream_rework(
          ${PROJECT_ID},${request!.id}::uuid,${requestId}::uuid,1,'approve') as result`,
      );
    const results = await Promise.all([invoke(a), invoke(b)]);
    await Promise.all([a.end(), b.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.filter((result) => result.replayed)).toHaveLength(1);
    const [upstream] = await admin<{ status: string; version: number }[]>`
      select status,version from public.tasks where id=${UPSTREAM_ID}
    `;
    expect(upstream).toEqual({ status: "in_progress", version: 6 });
    const [events] = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.business_events
      where project_id=${PROJECT_ID} and request_id=${requestId}::uuid
    `;
    expect(events!.count).toBe(1);
  });

  test("allows only one pending request for the same upstream under race", async () => {
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        USER_MEMBER,
        (tx) => tx`select public.cmd_request_upstream_rework(
          ${PROJECT_ID},${DOWNSTREAM_ID},${UPSTREAM_ID},
          'aa900000-0000-0000-0000-000000000005',4,5,'First request') as result`,
      ),
      asAuthenticated(
        b,
        USER_MEMBER,
        (tx) => tx`select public.cmd_request_upstream_rework(
          ${PROJECT_ID},${DOWNSTREAM_ID},${UPSTREAM_ID},
          'aa900000-0000-0000-0000-000000000006',4,5,'Second request') as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "INVALID_TRANSITION",
    );
    const [pending] = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.upstream_rework_requests
      where project_id=${PROJECT_ID} and upstream_task_id=${UPSTREAM_ID} and state='pending'
    `;
    expect(pending!.count).toBe(1);
  });

  test("keeps collaborator removal and Task Help request linearizable", async () => {
    const remover = postgres(databaseUrl, { max: 1 });
    const requester = postgres(databaseUrl, { max: 1 });

    const results = await Promise.all([
      asAuthenticated(
        remover,
        USER_LEADER,
        (tx) => tx`select public.cmd_remove_task_collaborator(
          ${PROJECT_ID},${HELP_TASK_ID},
          'aa350000-0000-0000-0000-000000000001',
          'aa900000-0000-0000-0000-000000000020',1
        ) as result`,
      ),
      asAuthenticated(
        requester,
        USER_HELPER,
        (tx) => tx`select public.cmd_create_task_help_request(
          ${PROJECT_ID},${HELP_TASK_ID},
          'aa900000-0000-0000-0000-000000000021',1,
          'Collaborator help race',null,false
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

    const [relation] = await admin<{ state: string }[]>`
      select state from public.task_collaborators
      where id='aa350000-0000-0000-0000-000000000001'
    `;
    const [requests] = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.task_help_requests
      where project_id=${PROJECT_ID} and task_id=${HELP_TASK_ID}
        and requested_by=${USER_HELPER}
    `;
    expect(relation?.state).toBe("removed");
    expect([0, 1]).toContain(requests?.count);

    const afterRemoval = await asAuthenticated(
      admin,
      USER_HELPER,
      (tx) => tx`select public.cmd_create_task_help_request(
        ${PROJECT_ID},${HELP_TASK_ID},
        'aa900000-0000-0000-0000-000000000022',1,
        'Must be rejected after removal',null,false
      ) as result`,
    );
    expect(afterRemoval.ok).toBe(false);
    expect(["NOT_FOUND_OR_NOT_AUTHORIZED", "NOT_AUTHORIZED"]).toContain(
      afterRemoval.code,
    );
  });

  test("never erases a newer blocked state when help resolution races progress", async () => {
    const help = await asAuthenticated(
      admin,
      USER_MEMBER,
      (tx) => tx`select public.cmd_create_task_help_request(
        ${PROJECT_ID},${HELP_TASK_ID},
        'aa900000-0000-0000-0000-000000000007',1,
        'Original help blocker',${USER_HELPER},true) as result`,
    );
    expect(help.ok).toBe(true);
    const [helpRow] = await admin<{ id: string }[]>`
      select id::text from public.task_help_requests
      where project_id=${PROJECT_ID} and task_id=${HELP_TASK_ID} and state='open'
    `;

    const progressSql = postgres(databaseUrl, { max: 1 });
    const resolveSql = postgres(databaseUrl, { max: 1 });
    const [progress, resolved] = await Promise.all([
      asAuthenticated(
        progressSql,
        USER_MEMBER,
        (tx) => tx`select public.cmd_update_task_progress(
          ${PROJECT_ID},${HELP_TASK_ID},
          'aa900000-0000-0000-0000-000000000008',2,
          'blocked','new work fact','Newer blocker') as result`,
      ),
      asAuthenticated(
        resolveSql,
        USER_HELPER,
        (tx) => tx`select public.cmd_resolve_task_help_request(
          ${PROJECT_ID},${helpRow!.id}::uuid,
          'aa900000-0000-0000-0000-000000000009',1) as result`,
      ),
    ]);
    await Promise.all([progressSql.end(), resolveSql.end()]);

    expect(resolved.ok).toBe(true);
    const [task] = await admin<
      { status: string; blocked_reason: string | null; version: number }[]
    >`select status,blocked_reason,version from public.tasks where id=${HELP_TASK_ID}`;

    if (progress.ok) {
      expect(resolved.data?.taskResumed).toBe(false);
      expect(task).toMatchObject({
        status: "blocked",
        blocked_reason: "Newer blocker",
        version: 3,
      });
    } else {
      expect(progress.code).toBe("STALE_VERSION");
      expect(resolved.data?.taskResumed).toBe(true);
      expect(task).toMatchObject({
        status: "in_progress",
        blocked_reason: null,
        version: 3,
      });
    }
  });
});
