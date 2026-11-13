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
    await admin`delete from public.business_events where project_id::text like 'a2000000-%'`;
    await admin`delete from public.command_requests where project_id::text like 'a2000000-%'`;
    await admin`delete from public.task_file_final_designations where project_id::text like 'a2000000-%'`;
    await admin`delete from public.task_file_versions where project_id::text like 'a2000000-%'`;
    await admin`delete from public.task_files where project_id::text like 'a2000000-%'`;
    await admin`delete from public.file_upload_reservations where project_id::text like 'a2000000-%'`;
    await admin`delete from public.task_review_rounds where project_id::text like 'a2000000-%'`;
    await admin`delete from public.task_assignment_offers where project_id::text like 'a2000000-%'`;
    await admin`delete from public.tasks where project_id::text like 'a2000000-%'`;
    await admin`delete from public.project_members where project_id::text like 'a2000000-%'`;
    await admin`delete from public.projects where id::text like 'a2000000-%'`;
    await admin`delete from auth.users where id::text like 'a1000000-%'`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
  await admin`
    insert into auth.users(id,email) values
      ('a1000000-0000-0000-0000-000000000001','cap-race-leader@example.test'),
      ('a1000000-0000-0000-0000-000000000002','cap-race-a@example.test'),
      ('a1000000-0000-0000-0000-000000000003','cap-race-b@example.test'),
      ('a1000000-0000-0000-0000-000000000004','cap-race-c@example.test')
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("capability command concurrency", () => {
  test("serializes concurrent leadership transfers and preserves exactly one leader", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000001','Leadership race',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
        ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','leader','active',false,1),
        ('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','member','active',false,1),
        ('a3000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003','member','active',false,1)
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_transfer_project_leadership(
            'a2000000-0000-0000-0000-000000000001',
            'a3000000-0000-0000-0000-000000000002',
            'a9000000-0000-0000-0000-000000000001',1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_transfer_project_leadership(
            'a2000000-0000-0000-0000-000000000001',
            'a3000000-0000-0000-0000-000000000003',
            'a9000000-0000-0000-0000-000000000002',1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe(
      "NOT_FOUND_OR_NOT_AUTHORIZED",
    );

    const rows = await admin<
      { leaders: number; leader_id: string; version: number }[]
    >`
      select
        (select count(*)::integer from public.project_members pm
          where pm.project_id=p.id and pm.role='leader' and pm.member_state='active') as leaders,
        p.leader_id::text as leader_id,
        p.version
      from public.projects p
      where p.id='a2000000-0000-0000-0000-000000000001'
    `;
    expect(rows[0]!.leaders).toBe(1);
    expect([
      "a1000000-0000-0000-0000-000000000002",
      "a1000000-0000-0000-0000-000000000003",
    ]).toContain(rows[0]!.leader_id);
    expect(rows[0]!.version).toBe(2);
  });

  test("serializes concurrent role edits with optimistic membership versions", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000002','Role race',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
        ('a3000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','leader','active',false,1),
        ('a3000000-0000-0000-0000-000000000005','a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000004','member','active',false,1)
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_update_project_member_role(
            'a2000000-0000-0000-0000-000000000002',
            'a3000000-0000-0000-0000-000000000005','admin',
            'a9000000-0000-0000-0000-000000000003',1
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_update_project_member_role(
            'a2000000-0000-0000-0000-000000000002',
            'a3000000-0000-0000-0000-000000000005','observer',
            'a9000000-0000-0000-0000-000000000004',1
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(2);

    const rows = await admin<
      {
        role: string;
        is_observer: boolean;
        version: number;
        project_version: number;
      }[]
    >`
      select pm.role,pm.is_observer,pm.version,p.version as project_version
      from public.project_members pm
      join public.projects p on p.id=pm.project_id
      where pm.id='a3000000-0000-0000-0000-000000000005'
    `;
    expect(rows[0]!.version).toBe(2);
    expect(rows[0]!.project_version).toBe(2);
    expect(rows[0]!.is_observer).toBe(rows[0]!.role === "observer");
  });

  test("database constraint rejects deleting the last active leader", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000003','Leader guard',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
      values(
        'a3000000-0000-0000-0000-000000000006','a2000000-0000-0000-0000-000000000003',
        'a1000000-0000-0000-0000-000000000001','leader','active',false,1
      )
    `;

    await expect(
      admin.begin(async (tx) => {
        await tx`
          delete from public.project_members
          where id='a3000000-0000-0000-0000-000000000006'
        `;
      }),
    ).rejects.toThrow(/exactly one active leader/i);
  });
  test("serializes concurrent task edits on the task version", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000004','Task edit race',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
      values(
        'a3000000-0000-0000-0000-000000000007','a2000000-0000-0000-0000-000000000004',
        'a1000000-0000-0000-0000-000000000001','leader','active',false,1
      )
    `;
    await admin`
      insert into public.tasks(id,project_id,title,created_by,deadline_at,status,weight,assignment_state,version)
      values(
        'a4000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000004',
        'Before','a1000000-0000-0000-0000-000000000001',now()+interval '5 days','not_started',2,'claimable',1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_edit_task(
            'a2000000-0000-0000-0000-000000000004',
            'a4000000-0000-0000-0000-000000000001',
            'a9000000-0000-0000-0000-000000000005',1,
            'Edit A',null,
            (select deadline_at from public.tasks where id='a4000000-0000-0000-0000-000000000001'),
            2::smallint
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_edit_task(
            'a2000000-0000-0000-0000-000000000004',
            'a4000000-0000-0000-0000-000000000001',
            'a9000000-0000-0000-0000-000000000006',1,
            'Edit B',null,
            (select deadline_at from public.tasks where id='a4000000-0000-0000-0000-000000000001'),
            2::smallint
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(2);
    const rows = await admin<{ version: number }[]>`
      select version from public.tasks where id='a4000000-0000-0000-0000-000000000001'
    `;
    expect(rows[0]!.version).toBe(2);
  });

  test("serializes concurrent first final-file designations", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000005','Final race',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
      values(
        'a3000000-0000-0000-0000-000000000008','a2000000-0000-0000-0000-000000000005',
        'a1000000-0000-0000-0000-000000000001','leader','active',false,1
      )
    `;
    await admin`
      insert into public.tasks(
        id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,completed_at,version
      ) values(
        'a4000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000005',
        'Done','a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',
        now()+interval '5 days','completed',2,'assigned',now()-interval '2 days',now()-interval '1 day',1
      )
    `;
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,
        declared_size_bytes,state,expires_at,version
      ) values(
        'a5000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',
        'a4000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001',
        'new_file','pending/a2/final-race.txt','final-race.txt','text/plain',10,'finalized',now()+interval '1 day',2
      )
    `;
    await admin`
      insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
      values(
        'a6000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',
        'a4000000-0000-0000-0000-000000000002','final-race.txt','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.task_file_versions(
        id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
        mime_type,size_bytes,sha256_hex,uploaded_by
      ) values(
        'a7000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000005','a4000000-0000-0000-0000-000000000002',
        'a5000000-0000-0000-0000-000000000001',1,'pending/a2/final-race.txt','final-race.txt',
        'text/plain',10,repeat('d',64),'a1000000-0000-0000-0000-000000000001'
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_set_task_file_version_final(
            'a2000000-0000-0000-0000-000000000005',
            'a7000000-0000-0000-0000-000000000001',
            'a9000000-0000-0000-0000-000000000007',0,true
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_set_task_file_version_final(
            'a2000000-0000-0000-0000-000000000005',
            'a7000000-0000-0000-0000-000000000001',
            'a9000000-0000-0000-0000-000000000008',0,true
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(1);
    const rows = await admin<{ is_final: boolean; version: number }[]>`
      select is_final,version
      from public.task_file_final_designations
      where file_version_id='a7000000-0000-0000-0000-000000000001'
    `;
    expect(rows).toEqual([{ is_final: true, version: 1 }]);
  });

  test("serializes concurrent project-settings updates", async () => {
    await admin`
      insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
      values(
        'a2000000-0000-0000-0000-000000000006','Settings race',now()+interval '10 days',
        'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1
      )
    `;
    await admin`
      insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
      values(
        'a3000000-0000-0000-0000-000000000009','a2000000-0000-0000-0000-000000000006',
        'a1000000-0000-0000-0000-000000000001','leader','active',false,1
      )
    `;

    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        connectionA,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_update_project_settings(
            'a2000000-0000-0000-0000-000000000006',
            'a9000000-0000-0000-0000-000000000009',1,
            'Settings A',null,null,
            (select deadline_at from public.projects where id='a2000000-0000-0000-0000-000000000006'),
            'Asia/Shanghai','weighted',false,false,false
          ) as result`,
      ),
      asAuthenticated(
        connectionB,
        "a1000000-0000-0000-0000-000000000001",
        (tx) =>
          tx`select public.cmd_update_project_settings(
            'a2000000-0000-0000-0000-000000000006',
            'a9000000-0000-0000-0000-000000000010',1,
            'Settings B',null,null,
            (select deadline_at from public.projects where id='a2000000-0000-0000-0000-000000000006'),
            'Asia/Shanghai','weighted',false,false,false
          ) as result`,
      ),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");
    expect(results.find((result) => !result.ok)?.currentVersion).toBe(2);
    const rows = await admin<{ version: number; name: string }[]>`
      select version,name from public.projects
      where id='a2000000-0000-0000-0000-000000000006'
    `;
    expect(rows[0]!.version).toBe(2);
    expect(["Settings A", "Settings B"]).toContain(rows[0]!.name);
  });
});
