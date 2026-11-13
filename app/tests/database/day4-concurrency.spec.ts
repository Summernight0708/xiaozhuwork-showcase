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

async function asServiceRole(
  sql: Sql,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
): Promise<RpcResult> {
  return sql.begin(async (tx): Promise<RpcResult> => {
    await tx.unsafe("set local role service_role");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`
      delete from storage.objects
      where bucket_id = 'teamup-files' and name like 'pending/c2000000-%'
    `;
    await admin`
      delete from public.business_events
      where project_id::text like 'c2000000-%'
         or request_id::text like 'c9000000-%'
    `;
    await admin`
      delete from public.command_requests
      where project_id::text like 'c2000000-%'
         or request_id::text like 'c9000000-%'
    `;
    await admin`delete from public.contribution_confirmations where project_id::text like 'c2000000-%'`;
    await admin`delete from public.contribution_items where project_id::text like 'c2000000-%'`;
    await admin`delete from public.contribution_reports where project_id::text like 'c2000000-%'`;
    await admin`delete from public.task_review_rounds where project_id::text like 'c2000000-%'`;
    await admin`delete from public.task_file_versions where project_id::text like 'c2000000-%'`;
    await admin`delete from public.task_files where project_id::text like 'c2000000-%'`;
    await admin`delete from public.file_upload_reservations where project_id::text like 'c2000000-%'`;
    await admin`delete from public.task_assignment_offers where project_id::text like 'c2000000-%'`;
    await admin`delete from public.task_dependencies where project_id::text like 'c2000000-%'`;
    await admin`delete from public.tasks where project_id::text like 'c2000000-%'`;
    await admin`delete from public.project_join_requests where project_id::text like 'c2000000-%'`;
    await admin`delete from public.project_invitations where project_id::text like 'c2000000-%'`;
    await admin`delete from public.project_members where project_id::text like 'c2000000-%'`;
    await admin`delete from public.projects where id::text like 'c2000000-%'`;
    await admin`delete from public.profiles where id::text like 'c1000000-%'`;
    await admin`delete from auth.users where id::text like 'c1000000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function waitForBlockedQueries(fragment: string, expected: number) {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const rows = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from pg_stat_activity
      where datname=current_database()
        and pid <> pg_backend_pid()
        and state='active'
        and wait_event_type='Lock'
        and query like ${`%${fragment}%`}
    `;
    if (rows[0]!.count >= expected) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(
    `Timed out waiting for ${expected} blocked ${fragment} queries`,
  );
}

beforeAll(async () => {
  await cleanup();
  await admin`
    insert into auth.users(id,email) values
      ('c1000000-0000-0000-0000-000000000001','day4-race-leader@example.test'),
      ('c1000000-0000-0000-0000-000000000002','day4-race-member@example.test'),
      ('c1000000-0000-0000-0000-000000000003','day4-race-member2@example.test'),
      ('c1000000-0000-0000-0000-000000000004','day4-race-member3@example.test')
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("strict Day 4 concurrency", () => {
  test("serializes two decisions for the same review round", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values (
        'c2000000-0000-0000-0000-000000000001',
        'Review race',
        now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        1
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state) values
        ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','leader','active'),
        ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        is_direct_assignment,accepted_at,assignment_state,version
      ) values (
        'c3000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'Review race task',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',
        now()+interval '5 days',
        'awaiting_review',
        1,
        false,
        now(),
        'assigned',
        2
      )
    `;
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,object_path,original_name,
        declared_mime_type,declared_size_bytes,state,expires_at,version
      ) values (
        'c4000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',
        'new_file',
        'pending/c2000000-0000-0000-0000-000000000001/c4000000-0000-0000-0000-000000000001/report.pdf',
        'report.pdf',
        'application/pdf',
        100,
        'finalized',
        now()+interval '1 hour',
        2
      )
    `;
    await admin`
      insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
      values (
        'c5000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        'report.pdf',
        'c1000000-0000-0000-0000-000000000002',
        1
      )
    `;
    await admin`
      insert into public.task_file_versions(
        id,file_id,project_id,task_id,reservation_id,version_number,object_path,
        original_name,mime_type,size_bytes,sha256_hex,uploaded_by
      ) values (
        'c6000000-0000-0000-0000-000000000001',
        'c5000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        'c4000000-0000-0000-0000-000000000001',
        1,
        'pending/c2000000-0000-0000-0000-000000000001/c4000000-0000-0000-0000-000000000001/report.pdf',
        'report.pdf',
        'application/pdf',
        100,
        ${"a".repeat(64)},
        'c1000000-0000-0000-0000-000000000002'
      )
    `;
    await admin`
      update public.task_files
      set current_version_id='c6000000-0000-0000-0000-000000000001'
      where id='c5000000-0000-0000-0000-000000000001'
    `;
    await admin`
      insert into public.task_review_rounds(
        id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,version
      ) values (
        'c7000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000001',
        'c3000000-0000-0000-0000-000000000001',
        1,
        'c6000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',
        1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "c1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_review_task_submission(
          'c2000000-0000-0000-0000-000000000001',
          'c3000000-0000-0000-0000-000000000001',
          'c7000000-0000-0000-0000-000000000001',
          'approve',
          null,
          'c9000000-0000-0000-0000-000000000001',
          1
        ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "c1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_review_task_submission(
          'c2000000-0000-0000-0000-000000000001',
          'c3000000-0000-0000-0000-000000000001',
          'c7000000-0000-0000-0000-000000000001',
          'request_changes',
          'Concurrent change request',
          'c9000000-0000-0000-0000-000000000002',
          1
        ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const eventRows = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.business_events
      where request_id in (
        'c9000000-0000-0000-0000-000000000001',
        'c9000000-0000-0000-0000-000000000002'
      )
    `;
    expect(eventRows[0]!.count).toBe(1);
  });

  test("serializes two confirmations for the same contribution report version", async () => {
    await admin`
      insert into public.projects(
        id,name,deadline_at,leader_id,created_by,version,lifecycle_state
      ) values (
        'c2000000-0000-0000-0000-000000000002',
        'Contribution race',
        now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        4,
        'contribution_review'
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state) values
        ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001','leader','active'),
        ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000002','member','active'),
        ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003','member','active')
    `;
    await admin`
      insert into public.contribution_reports(
        id,project_id,state,contribution_mode,source_project_version,
        eligible_member_count,required_confirmation_count,created_by,version
      ) values (
        'c8000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000002',
        'draft',
        'weighted',
        3,
        3,
        2,
        'c1000000-0000-0000-0000-000000000001',
        1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "c1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_confirm_contribution_report(
          'c2000000-0000-0000-0000-000000000002',
          'c8000000-0000-0000-0000-000000000001',
          'c9000000-0000-0000-0000-000000000003',
          1
        ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "c1000000-0000-0000-0000-000000000002",
        (tx) =>
          tx`select public.cmd_confirm_contribution_report(
          'c2000000-0000-0000-0000-000000000002',
          'c8000000-0000-0000-0000-000000000001',
          'c9000000-0000-0000-0000-000000000004',
          1
        ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const confirmations = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.contribution_confirmations
      where report_id='c8000000-0000-0000-0000-000000000001'
    `;
    expect(confirmations[0]!.count).toBe(1);
  });

  test("serializes two finalizations against the same logical file version", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values (
        'c2000000-0000-0000-0000-000000000003',
        'File race',
        now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        1
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state) values
        ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000001','leader','active'),
        ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000004','member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        is_direct_assignment,accepted_at,assignment_state,version
      ) values (
        'c3000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000003',
        'File race task',
        'c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000004',
        now()+interval '5 days',
        'in_progress',
        1,
        false,
        now(),
        'assigned',
        1
      )
    `;
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,object_path,original_name,
        declared_mime_type,declared_size_bytes,state,expires_at,version
      ) values (
        'c4000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000003',
        'c1000000-0000-0000-0000-000000000004',
        'new_file',
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000003/base.pdf',
        'base.pdf',
        'application/pdf',
        10,
        'finalized',
        now()+interval '1 hour',
        2
      )
    `;
    await admin`
      insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
      values (
        'c5000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000003',
        'base.pdf',
        'c1000000-0000-0000-0000-000000000004',
        1
      )
    `;
    await admin`
      insert into public.task_file_versions(
        id,file_id,project_id,task_id,reservation_id,version_number,object_path,
        original_name,mime_type,size_bytes,sha256_hex,uploaded_by
      ) values (
        'c6000000-0000-0000-0000-000000000003',
        'c5000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000003',
        'c4000000-0000-0000-0000-000000000003',
        1,
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000003/base.pdf',
        'base.pdf',
        'application/pdf',
        10,
        ${"b".repeat(64)},
        'c1000000-0000-0000-0000-000000000004'
      )
    `;
    await admin`
      update public.task_files
      set current_version_id='c6000000-0000-0000-0000-000000000003'
      where id='c5000000-0000-0000-0000-000000000003'
    `;
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
        object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
      ) values
      (
        'c4000000-0000-0000-0000-000000000004',
        'c2000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000003',
        'c1000000-0000-0000-0000-000000000004',
        'new_version',
        'c5000000-0000-0000-0000-000000000003',
        1,
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000004/a.pdf',
        'a.pdf',
        'application/pdf',
        20,
        'reserved',
        now()+interval '1 hour',
        1
      ),
      (
        'c4000000-0000-0000-0000-000000000005',
        'c2000000-0000-0000-0000-000000000003',
        'c3000000-0000-0000-0000-000000000003',
        'c1000000-0000-0000-0000-000000000004',
        'new_version',
        'c5000000-0000-0000-0000-000000000003',
        1,
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000005/b.pdf',
        'b.pdf',
        'application/pdf',
        20,
        'reserved',
        now()+interval '1 hour',
        1
      )
    `;
    await admin`
      insert into storage.objects(bucket_id,name,owner_id,metadata) values
      (
        'teamup-files',
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000004/a.pdf',
        'c1000000-0000-0000-0000-000000000004',
        jsonb_build_object('size',20,'mimetype','application/pdf')
      ),
      (
        'teamup-files',
        'pending/c2000000-0000-0000-0000-000000000003/c4000000-0000-0000-0000-000000000005/b.pdf',
        'c1000000-0000-0000-0000-000000000004',
        jsonb_build_object('size',20,'mimetype','application/pdf')
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asServiceRole(
        connectionA,
        (tx) =>
          tx`select public.cmd_finalize_task_file_upload_service(
          'c1000000-0000-0000-0000-000000000004',
          'c4000000-0000-0000-0000-000000000004',
          'c9000000-0000-0000-0000-000000000005',
          1,
          'application/pdf',
          20,
          ${"c".repeat(64)}
        ) as result`,
      ),
      asServiceRole(
        connectionB,
        (tx) =>
          tx`select public.cmd_finalize_task_file_upload_service(
          'c1000000-0000-0000-0000-000000000004',
          'c4000000-0000-0000-0000-000000000005',
          'c9000000-0000-0000-0000-000000000006',
          1,
          'application/pdf',
          20,
          ${"d".repeat(64)}
        ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const versions = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.task_file_versions
      where file_id='c5000000-0000-0000-0000-000000000003'
    `;
    expect(versions[0]!.count).toBe(2);
    const eventRows = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.business_events
      where request_id in (
        'c9000000-0000-0000-0000-000000000005',
        'c9000000-0000-0000-0000-000000000006'
      )
    `;
    expect(eventRows[0]!.count).toBe(1);
  });

  test("replays one concurrent identical file finalization exactly", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'c2000000-0000-0000-0000-000000000004','Finalize replay race',now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state) values
        ('c2000000-0000-0000-0000-000000000004','c1000000-0000-0000-0000-000000000001','leader','active'),
        ('c2000000-0000-0000-0000-000000000004','c1000000-0000-0000-0000-000000000002','member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        is_direct_assignment,accepted_at,assignment_state,version
      ) values(
        'c3000000-0000-0000-0000-000000000004','c2000000-0000-0000-0000-000000000004',
        'Finalize replay task','c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',1,
        false,now(),'assigned',1
      )
    `;
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,object_path,original_name,
        declared_mime_type,declared_size_bytes,state,expires_at,version
      ) values(
        'c4000000-0000-0000-0000-000000000006','c2000000-0000-0000-0000-000000000004',
        'c3000000-0000-0000-0000-000000000004','c1000000-0000-0000-0000-000000000002',
        'new_file',
        'pending/c2000000-0000-0000-0000-000000000004/c4000000-0000-0000-0000-000000000006/replay.pdf',
        'replay.pdf','application/pdf',20,'reserved',now()+interval '1 hour',1
      )
    `;
    await admin`
      insert into storage.objects(bucket_id,name,owner_id,metadata) values(
        'teamup-files',
        'pending/c2000000-0000-0000-0000-000000000004/c4000000-0000-0000-0000-000000000006/replay.pdf',
        'c1000000-0000-0000-0000-000000000002',
        jsonb_build_object('size',20,'mimetype','application/pdf')
      )
    `;

    const blocker = postgres(databaseUrl, { max: 1 });
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    let releaseBlocker!: () => void;
    const release = new Promise<void>((resolve) => {
      releaseBlocker = resolve;
    });
    let projectLocked!: () => void;
    const locked = new Promise<void>((resolve) => {
      projectLocked = resolve;
    });
    const blockingTransaction = blocker.begin(async (tx) => {
      await tx`select id from public.projects where id='c2000000-0000-0000-0000-000000000004' for update`;
      projectLocked();
      await release;
    });
    await locked;

    const finalize = (sql: Sql) =>
      asServiceRole(
        sql,
        (tx) =>
          tx`select public.cmd_finalize_task_file_upload_service(
          'c1000000-0000-0000-0000-000000000002',
          'c4000000-0000-0000-0000-000000000006',
          'c9000000-0000-0000-0000-000000000007',
          1,
          'application/pdf',
          20,
          ${"e".repeat(64)}
        ) as result`,
      );
    const pendingA = finalize(connectionA);
    const pendingB = finalize(connectionB);
    await waitForBlockedQueries("cmd_finalize_task_file_upload_service", 2);
    releaseBlocker();
    const results = await Promise.all([pendingA, pendingB]);
    await blockingTransaction;
    await Promise.all([blocker.end(), connectionA.end(), connectionB.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.filter((result) => result.replayed)).toHaveLength(1);
    expect({ ...results[0], replayed: false }).toEqual({
      ...results[1],
      replayed: false,
    });
    const rows = await admin<
      { versions: number; events: number; commands: number }[]
    >`
      select
        (select count(*)::integer from public.task_file_versions
          where reservation_id='c4000000-0000-0000-0000-000000000006') as versions,
        (select count(*)::integer from public.business_events
          where request_id='c9000000-0000-0000-0000-000000000007') as events,
        (select count(*)::integer from public.command_requests
          where request_id='c9000000-0000-0000-0000-000000000007') as commands
    `;
    expect(rows[0]).toEqual({ versions: 1, events: 1, commands: 1 });
  });
  test("serializes contribution-report creation against a concurrent task create", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'c2000000-0000-0000-0000-000000000005','Report task race',now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state)
      values('c2000000-0000-0000-0000-000000000005','c1000000-0000-0000-0000-000000000001','leader','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        assignment_state,accepted_at,first_submitted_at,completed_at,version
      ) values(
        'c3000000-0000-0000-0000-000000000005','c2000000-0000-0000-0000-000000000005',
        'Completed before race','c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',now()+interval '5 days','completed',1,
        'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const deadline = new Date(Date.now() + 4 * 86_400_000).toISOString();
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "c1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_create_contribution_report(
          'c2000000-0000-0000-0000-000000000005',
          'c9000000-0000-0000-0000-000000000008',
          1
        ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "c1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_create_task(
          'c2000000-0000-0000-0000-000000000005',
          'c9000000-0000-0000-0000-000000000009',
          1,
          'Concurrent late task',
          null,
          ${deadline},
          1::smallint,
          'claimable',
          null
        ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    const state = await admin<
      {
        lifecycle_state: string;
        reports: number;
        late_tasks: number;
        events: number;
      }[]
    >`
      select p.lifecycle_state,
        (select count(*)::integer from public.contribution_reports where project_id=p.id) as reports,
        (select count(*)::integer from public.tasks where project_id=p.id and title='Concurrent late task') as late_tasks,
        (select count(*)::integer from public.business_events
          where request_id in ('c9000000-0000-0000-0000-000000000008','c9000000-0000-0000-0000-000000000009')) as events
      from public.projects p where p.id='c2000000-0000-0000-0000-000000000005'
    `;
    expect(state[0]!.reports + state[0]!.late_tasks).toBe(1);
    expect(state[0]!.events).toBe(state[0]!.reports === 1 ? 2 : 1);
    expect(state[0]!.lifecycle_state).toBe(
      state[0]!.reports === 1 ? "contribution_review" : "active",
    );
  });

  test("serializes project storage quota across concurrent reservations", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'c2000000-0000-0000-0000-000000000006','Storage quota race',now()+interval '10 days',
        'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(project_id,user_id,role,member_state) values
        ('c2000000-0000-0000-0000-000000000006','c1000000-0000-0000-0000-000000000001','leader','active'),
        ('c2000000-0000-0000-0000-000000000006','c1000000-0000-0000-0000-000000000002','member','active')
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
        assignment_state,accepted_at,version
      ) values(
        'c3000000-0000-0000-0000-000000000006','c2000000-0000-0000-0000-000000000006',
        'Quota race task','c1000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',1,
        'assigned',now(),1
      )
    `;

    for (let index = 0; index < 9; index += 1) {
      const suffix = index.toString().padStart(12, "0");
      const reservationId = `d4000000-0000-0000-0000-${suffix}`;
      const fileId = `d5000000-0000-0000-0000-${suffix}`;
      const versionId = `d6000000-0000-0000-0000-${suffix}`;
      const objectPath = `pending/c2000000-0000-0000-0000-000000000006/${reservationId}/history-${index}.pdf`;
      await admin`
        insert into public.file_upload_reservations(
          id,project_id,task_id,actor_id,mode,object_path,original_name,
          declared_mime_type,declared_size_bytes,state,expires_at,version
        ) values(
          ${reservationId},'c2000000-0000-0000-0000-000000000006',
          'c3000000-0000-0000-0000-000000000006','c1000000-0000-0000-0000-000000000002',
          'new_file',${objectPath},${`history-${index}.pdf`},'application/pdf',52428800,
          'finalized',now()-interval '1 hour',2
        )
      `;
      await admin`
        insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
        values(${fileId},'c2000000-0000-0000-0000-000000000006',
          'c3000000-0000-0000-0000-000000000006',${`history-${index}.pdf`},
          'c1000000-0000-0000-0000-000000000002',1)
      `;
      await admin`
        insert into public.task_file_versions(
          id,file_id,project_id,task_id,reservation_id,version_number,object_path,
          original_name,mime_type,size_bytes,sha256_hex,uploaded_by
        ) values(
          ${versionId},${fileId},'c2000000-0000-0000-0000-000000000006',
          'c3000000-0000-0000-0000-000000000006',${reservationId},1,${objectPath},
          ${`history-${index}.pdf`},'application/pdf',52428800,${"f".repeat(64)},
          'c1000000-0000-0000-0000-000000000002'
        )
      `;
      await admin`update public.task_files set current_version_id=${versionId} where id=${fileId}`;
    }

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const reserve = (sql: Sql, requestId: string, name: string) =>
      asAuthenticated(
        sql,
        "c1000000-0000-0000-0000-000000000002",
        (tx) =>
          tx`select public.cmd_reserve_task_file_upload(
          'c2000000-0000-0000-0000-000000000006',
          'c3000000-0000-0000-0000-000000000006',
          ${requestId},
          1,
          'new_file',
          null,
          ${name},
          'application/pdf',
          8388608
        ) as result`,
      );
    const results = await Promise.all([
      reserve(
        connectionA,
        "c9000000-0000-0000-0000-000000000010",
        "quota-a.pdf",
      ),
      reserve(
        connectionB,
        "c9000000-0000-0000-0000-000000000011",
        "quota-b.pdf",
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "STORAGE_QUOTA_EXCEEDED",
    );
    const rows = await admin<{ reservations: number; events: number }[]>`
      select
        (select count(*)::integer from public.file_upload_reservations
          where project_id='c2000000-0000-0000-0000-000000000006'
            and state='reserved') as reservations,
        (select count(*)::integer from public.business_events
          where request_id in ('c9000000-0000-0000-0000-000000000010','c9000000-0000-0000-0000-000000000011')) as events
    `;
    expect(rows[0]).toEqual({ reservations: 1, events: 1 });
  });
});
