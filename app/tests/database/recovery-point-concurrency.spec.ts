import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });

const leaderId = "ee100000-0000-0000-0000-000000000001";
const projectId = "ee200000-0000-0000-0000-000000000001";
const taskId = "ee300000-0000-0000-0000-000000000001";
const fileId = "ee400000-0000-0000-0000-000000000001";
const v1 = "ee500000-0000-0000-0000-000000000001";
const v2 = "ee500000-0000-0000-0000-000000000002";

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

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.project_recovery_point_restore_items where project_id=${projectId}`;
    await admin`delete from public.project_recovery_point_file_items where project_id=${projectId}`;
    await admin`delete from public.project_recovery_points where project_id=${projectId}`;
    await admin`delete from public.task_file_final_designations where project_id=${projectId}`;
    await admin`delete from public.business_events where project_id=${projectId}`;
    await admin`delete from public.command_requests where project_id=${projectId}`;
    await admin`delete from public.task_file_versions where project_id=${projectId}`;
    await admin`delete from public.task_files where project_id=${projectId}`;
    await admin`delete from public.file_upload_reservations where project_id=${projectId}`;
    await admin`delete from public.tasks where project_id=${projectId}`;
    await admin`delete from public.project_members where project_id=${projectId}`;
    await admin`delete from public.account_entitlements where user_id=${leaderId}`;
    await admin`delete from public.projects where id=${projectId}`;
    await admin`delete from auth.users where id=${leaderId}`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seedRecoveryFixture() {
  await admin`insert into auth.users(id,email) values(${leaderId},'recovery-race-leader@example.test')`;
  await admin`
    insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
    values(${projectId},'Recovery race',now()+interval '20 days',${leaderId},${leaderId},1)
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state,is_observer,version)
    values(${projectId},${leaderId},'leader','active',false,1)
  `;
  await admin`
    insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values(
      ${leaderId},'pro','active',now()-interval '1 day',now()+interval '30 days',
      now(),${leaderId},'test',1
    )
  `;
  await admin`
    insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      assignment_state,accepted_at,completed_at,version
    ) values(
      ${taskId},${projectId},'Deliverable',${leaderId},${leaderId},
      now()+interval '5 days','completed',1,'assigned',now(),now(),1
    )
  `;
  await admin`
    insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,object_path,original_name,
      declared_mime_type,declared_size_bytes,state,expires_at,version
    ) values(
      'ee600000-0000-0000-0000-000000000001',${projectId},${taskId},${leaderId},
      'new_file','recovery-race/v1.pdf','race.pdf','application/pdf',100,
      'finalized',now()+interval '1 hour',2
    )
  `;
  await admin`
    insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
    values(${fileId},${projectId},${taskId},'race.pdf',${leaderId},1)
  `;
  await admin`
    insert into public.task_file_versions(
      id,file_id,project_id,task_id,reservation_id,version_number,object_path,
      original_name,mime_type,size_bytes,sha256_hex,uploaded_by
    ) values(
      ${v1},${fileId},${projectId},${taskId},'ee600000-0000-0000-0000-000000000001',
      1,'recovery-race/v1.pdf','race.pdf','application/pdf',100,${"a".repeat(64)},${leaderId}
    )
  `;
  await admin`update public.task_files set current_version_id=${v1} where id=${fileId}`;

  const create = await asAuthenticated(
    admin,
    leaderId,
    (tx) => tx`select public.cmd_create_project_recovery_point(
      ${projectId},'ee900000-0000-0000-0000-000000000001',1,'race baseline'
    ) as result`,
  );
  expect(create.ok).toBe(true);

  await admin`
    insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
      object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
    ) values(
      'ee600000-0000-0000-0000-000000000002',${projectId},${taskId},${leaderId},
      'new_version',${fileId},1,'recovery-race/v2.pdf','race.pdf',
      'application/pdf',100,'finalized',now()+interval '1 hour',2
    )
  `;
  await admin`
    insert into public.task_file_versions(
      id,file_id,project_id,task_id,reservation_id,version_number,object_path,
      original_name,mime_type,size_bytes,sha256_hex,uploaded_by
    ) values(
      ${v2},${fileId},${projectId},${taskId},'ee600000-0000-0000-0000-000000000002',
      2,'recovery-race/v2.pdf','race.pdf','application/pdf',100,${"b".repeat(64)},${leaderId}
    )
  `;
  await admin`update public.task_files set current_version_id=${v2},version=2 where id=${fileId}`;
}

beforeAll(async () => {
  await cleanup();
  await seedRecoveryFixture();
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("recovery point concurrency", () => {
  test("serializes competing restores against the same project version", async () => {
    const recoveryRows = await admin<{ recovery_point_id: string }[]>`
      select id::text as recovery_point_id
      from public.project_recovery_points
      where project_id=${projectId}
    `;
    const recoveryPointId = recoveryRows[0]?.recovery_point_id;
    if (!recoveryPointId) {
      throw new Error("Expected recovery point fixture to exist");
    }

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const restore = (sql: Sql, requestId: string) =>
      asAuthenticated(
        sql,
        leaderId,
        (tx) => tx`select public.cmd_restore_project_recovery_point(
          ${projectId},${recoveryPointId},${requestId},1
        ) as result`,
      );

    const results = await Promise.all([
      restore(a, "ee900000-0000-0000-0000-000000000002"),
      restore(b, "ee900000-0000-0000-0000-000000000003"),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const [state] = await admin<
      {
        restored_versions: number;
        restore_events: number;
        project_version: number;
      }[]
    >`
      select
        (select count(*)::integer
          from public.task_file_versions
          where file_id=${fileId} and restored_from_version_id=${v1}) as restored_versions,
        (select count(*)::integer
          from public.business_events
          where project_id=${projectId}
            and event_type='project_recovery_point_restored') as restore_events,
        (select version from public.projects where id=${projectId}) as project_version
    `;

    expect(state).toEqual({
      restored_versions: 1,
      restore_events: 1,
      project_version: 2,
    });
  });
});
