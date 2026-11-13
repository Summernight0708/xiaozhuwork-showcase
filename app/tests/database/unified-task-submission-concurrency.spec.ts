import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeEach, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 8 });

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
  data?: Record<string, unknown>;
  details?: Record<string, unknown>;
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
    await admin`delete from public.notifications where project_id::text like 'd9200000-%'`;
    await admin`delete from public.business_events where project_id::text like 'd9200000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'd9200000-%'`;
    await admin`delete from public.task_review_round_files where project_id::text like 'd9200000-%'`;
    await admin`delete from public.task_review_rounds where project_id::text like 'd9200000-%'`;
    await admin`delete from public.task_change_proposals where project_id::text like 'd9200000-%'`;
    await admin`delete from public.task_dependencies where project_id::text like 'd9200000-%'`;
    await admin`delete from public.tasks where project_id::text like 'd9200000-%'`;
    await admin`delete from public.project_members where project_id::text like 'd9200000-%'`;
    await admin`delete from public.projects where id::text like 'd9200000-%'`;
    await admin`delete from auth.users where id::text like 'd9100000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seedProject(projectId: string) {
  await admin`
    insert into auth.users(id,email) values
      ('d9100000-0000-0000-0000-000000000001','unified-race-leader@example.test'),
      ('d9100000-0000-0000-0000-000000000002','unified-race-assignee@example.test'),
      ('d9100000-0000-0000-0000-000000000003','unified-race-assignee2@example.test')
  `;
  await admin`
    insert into public.projects(
      id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
    ) values(
      ${projectId}::uuid,'Unified race',now()+interval '30 days',
      'd9100000-0000-0000-0000-000000000001',
      'd9100000-0000-0000-0000-000000000001',
      1,'weighted','active'
    )
  `;
  await admin`
    insert into public.project_members(
      project_id,user_id,role,member_state,is_observer,version
    ) values
      (${projectId}::uuid,'d9100000-0000-0000-0000-000000000001','leader','active',false,1),
      (${projectId}::uuid,'d9100000-0000-0000-0000-000000000002','member','active',false,1),
      (${projectId}::uuid,'d9100000-0000-0000-0000-000000000003','member','active',false,1)
  `;
}

beforeEach(async () => {
  await cleanup();
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("unified task submission concurrency", () => {
  test("serializes competing submissions so only one review round is created", async () => {
    const projectId = "d9200000-0000-0000-0000-000000000001";
    const taskId = "d9300000-0000-0000-0000-000000000001";
    await seedProject(projectId);
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        accepted_at,assignment_state,version
      ) values(
        ${taskId}::uuid,${projectId}::uuid,'Submit race',
        'd9100000-0000-0000-0000-000000000001',
        'd9100000-0000-0000-0000-000000000002',
        now()+interval '10 days','in_progress',2,now(),'assigned',1
      )
    `;

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const invoke = (sql: Sql, requestId: string, text: string) =>
      asAuthenticated(
        sql,
        "d9100000-0000-0000-0000-000000000002",
        (tx) => tx`
          select public.cmd_submit_task_for_review(
            ${projectId}::uuid,${taskId}::uuid,${text},
            array[]::uuid[],${requestId}::uuid,1
          ) as result
        `,
      );

    const results = await Promise.all([
      invoke(a, "d9900000-0000-0000-0000-000000000001", "Submission A"),
      invoke(b, "d9900000-0000-0000-0000-000000000002", "Submission B"),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const rounds = await admin<{ count: number; text: string | null }[]>`
      select count(*)::integer as count, min(submission_text_snapshot) as text
      from public.task_review_rounds where task_id=${taskId}::uuid
    `;
    expect(rounds[0]!.count).toBe(1);
    expect(["Submission A", "Submission B"]).toContain(rounds[0]!.text);

    const events = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.business_events
      where request_id in (
        'd9900000-0000-0000-0000-000000000001',
        'd9900000-0000-0000-0000-000000000002'
      )
    `;
    expect(events[0]!.count).toBe(1);
  });

  test("serializes submission against a required-type edit without mixed state", async () => {
    const projectId = "d9200000-0000-0000-0000-000000000002";
    const taskId = "d9300000-0000-0000-0000-000000000002";
    await seedProject(projectId);
    await admin`
      insert into public.tasks(
        id,project_id,title,description,created_by,assignee_id,deadline_at,status,
        weight,accepted_at,assignment_state,version,required_submission_file_type
      ) values(
        ${taskId}::uuid,${projectId}::uuid,'Requirement race','Keep coherent',
        'd9100000-0000-0000-0000-000000000001',
        'd9100000-0000-0000-0000-000000000002',
        now()+interval '10 days','in_progress',2,now(),'assigned',1,null
      )
    `;

    const [task] = await admin<{ deadline_at: string }[]>`
      select deadline_at::text from public.tasks where id=${taskId}::uuid
    `;
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });

    const results = await Promise.all([
      asAuthenticated(
        a,
        "d9100000-0000-0000-0000-000000000002",
        (tx) => tx`
          select public.cmd_submit_task_for_review(
            ${projectId}::uuid,${taskId}::uuid,'Text before requirement race',
            array[]::uuid[],'d9900000-0000-0000-0000-000000000003',1
          ) as result
        `,
      ),
      asAuthenticated(
        b,
        "d9100000-0000-0000-0000-000000000001",
        (tx) => tx`
          select public.cmd_edit_task(
            ${projectId}::uuid,${taskId}::uuid,
            'd9900000-0000-0000-0000-000000000004',1,
            'Requirement race','Keep coherent',${task!.deadline_at}::timestamptz,
            2::smallint,'pdf'
          ) as result
        `,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(["STALE_VERSION", "CONFIRMATION_REQUIRED"]).toContain(
      results.find((result) => !result.ok)?.code,
    );

    const [state] = await admin<
      {
        status: string;
        required_submission_file_type: string | null;
        round_count: number;
        round_requirement: string | null;
      }[]
    >`
      select
        t.status,
        t.required_submission_file_type,
        count(rr.id)::integer as round_count,
        min(rr.required_submission_file_type_snapshot) as round_requirement
      from public.tasks t
      left join public.task_review_rounds rr on rr.task_id=t.id
      where t.id=${taskId}::uuid
      group by t.id
    `;

    if (state!.round_count === 1) {
      expect(state).toMatchObject({
        status: "awaiting_review",
        required_submission_file_type: null,
        round_requirement: null,
      });
    } else {
      expect(state).toMatchObject({
        status: "in_progress",
        required_submission_file_type: "pdf",
        round_count: 0,
      });
    }
  });

  test("serializes downstream submission against upstream approval", async () => {
    const projectId = "d9200000-0000-0000-0000-000000000003";
    const upstreamTaskId = "d9300000-0000-0000-0000-000000000003";
    const downstreamTaskId = "d9300000-0000-0000-0000-000000000004";
    const upstreamRoundId = "d9700000-0000-0000-0000-000000000001";
    await seedProject(projectId);

    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        accepted_at,assignment_state,version
      ) values
      (
        ${upstreamTaskId}::uuid,${projectId}::uuid,'Upstream',
        'd9100000-0000-0000-0000-000000000001',
        'd9100000-0000-0000-0000-000000000002',
        now()+interval '8 days','awaiting_review',2,now(),'assigned',2
      ),
      (
        ${downstreamTaskId}::uuid,${projectId}::uuid,'Downstream',
        'd9100000-0000-0000-0000-000000000001',
        'd9100000-0000-0000-0000-000000000003',
        now()+interval '10 days','in_progress',2,now(),'assigned',1
      )
    `;
    await admin`
      insert into public.task_review_rounds(
        id,project_id,task_id,round_number,submission_text_snapshot,
        submitted_by,submitted_at,state,version
      ) values(
        ${upstreamRoundId}::uuid,${projectId}::uuid,${upstreamTaskId}::uuid,
        1,'Upstream result',
        'd9100000-0000-0000-0000-000000000002',now(),'pending',1
      )
    `;
    await admin`
      insert into public.task_dependencies(
        project_id,upstream_task_id,downstream_task_id,created_by
      ) values(
        ${projectId}::uuid,${upstreamTaskId}::uuid,${downstreamTaskId}::uuid,
        'd9100000-0000-0000-0000-000000000001'
      )
    `;

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const [reviewResult, submitResult] = await Promise.all([
      asAuthenticated(
        a,
        "d9100000-0000-0000-0000-000000000001",
        (tx) => tx`
          select public.cmd_review_task_submission(
            ${projectId}::uuid,${upstreamTaskId}::uuid,${upstreamRoundId}::uuid,
            'approve',null,'d9900000-0000-0000-0000-000000000005',1
          ) as result
        `,
      ),
      asAuthenticated(
        b,
        "d9100000-0000-0000-0000-000000000003",
        (tx) => tx`
          select public.cmd_submit_task_for_review(
            ${projectId}::uuid,${downstreamTaskId}::uuid,'Downstream result',
            array[]::uuid[],'d9900000-0000-0000-0000-000000000006',1
          ) as result
        `,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(reviewResult.ok).toBe(true);
    if (!submitResult.ok) {
      expect(submitResult.code).toBe("INVALID_TRANSITION");
      expect(submitResult.details?.reason).toBe("upstream_tasks_incomplete");
    }

    const [state] = await admin<
      {
        upstream_status: string;
        downstream_status: string;
        downstream_rounds: number;
      }[]
    >`
      select
        upstream.status as upstream_status,
        downstream.status as downstream_status,
        (
          select count(*)::integer
          from public.task_review_rounds rr
          where rr.task_id=downstream.id
        ) as downstream_rounds
      from public.tasks upstream
      join public.tasks downstream
        on downstream.id=${downstreamTaskId}::uuid
      where upstream.id=${upstreamTaskId}::uuid
    `;

    expect(state!.upstream_status).toBe("completed");
    if (state!.downstream_rounds === 1) {
      expect(submitResult.ok).toBe(true);
      expect(state!.downstream_status).toBe("awaiting_review");
    } else {
      expect(state!.downstream_rounds).toBe(0);
      expect(state!.downstream_status).toBe("in_progress");
    }
  });
});
