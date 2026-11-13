import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 8 });
const PROJECT_ID = "e2200000-0000-0000-0000-000000000001";
const LEADER_ID = "e1200000-0000-0000-0000-000000000001";
const ACTOR_ID = "e1200000-0000-0000-0000-000000000002";

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
  data?: {
    objectPath?: string;
    reservationId?: string;
    rolledBack?: Array<{ newFileVersionId: string }>;
  };
};

async function asAuthenticated(
  sql: Sql,
  userId: string,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
) {
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
) {
  return sql.begin(async (tx): Promise<RpcResult> => {
    await tx.unsafe("set local role service_role");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.business_events where project_id=${PROJECT_ID}`;
    await admin`delete from public.command_requests where project_id=${PROJECT_ID}`;
    await admin`delete from public.task_file_versions where project_id=${PROJECT_ID}`;
    await admin`delete from public.task_files where project_id=${PROJECT_ID}`;
    await admin`delete from public.file_upload_reservations where project_id=${PROJECT_ID}`;
    await admin`delete from public.tasks where project_id=${PROJECT_ID}`;
    await admin`delete from public.project_members where project_id=${PROJECT_ID}`;
    await admin`delete from public.account_entitlements where user_id in (${LEADER_ID},${ACTOR_ID})`;
    await admin`delete from public.projects where id=${PROJECT_ID}`;
    await admin`delete from auth.users where id in (${LEADER_ID},${ACTOR_ID})`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

async function seedFile(suffix: string) {
  const taskId = `e3300000-0000-0000-0000-000000000${suffix}`;
  const fileId = `e5500000-0000-0000-0000-000000000${suffix}`;
  const reservation1 = `e4400000-0000-0000-0000-000000001${suffix}`;
  const reservation2 = `e4400000-0000-0000-0000-000000002${suffix}`;
  const version1 = `e6600000-0000-0000-0000-000000001${suffix}`;
  const version2 = `e6600000-0000-0000-0000-000000002${suffix}`;

  await admin`
    insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      is_direct_assignment,accepted_at,assignment_state,version
    ) values(
      ${taskId},${PROJECT_ID},${"Rollback race " + suffix},${ACTOR_ID},${ACTOR_ID},
      now()+interval '5 days','in_progress',1,false,now(),'assigned',1
    )
  `;
  await admin`
    insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
    values(${fileId},${PROJECT_ID},${taskId},'report.txt',${ACTOR_ID},2)
  `;
  await admin`
    insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
      object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
    ) values
      (${reservation1},${PROJECT_ID},${taskId},${ACTOR_ID},'new_file',null,null,
       ${`pending/${PROJECT_ID}/${reservation1}/report.txt`},'report.txt','text/plain',10,'finalized',now(),2),
      (${reservation2},${PROJECT_ID},${taskId},${ACTOR_ID},'new_version',${fileId},1,
       ${`pending/${PROJECT_ID}/${reservation2}/report-v2.txt`},'report-v2.txt','text/plain',20,'finalized',now(),2)
  `;
  await admin`
    insert into public.task_file_versions(
      id,file_id,project_id,task_id,reservation_id,version_number,object_path,
      original_name,mime_type,size_bytes,sha256_hex,uploaded_by
    ) values
      (${version1},${fileId},${PROJECT_ID},${taskId},${reservation1},1,
       ${`pending/${PROJECT_ID}/${reservation1}/report.txt`},'report.txt','text/plain',10,${"a".repeat(64)},${ACTOR_ID}),
      (${version2},${fileId},${PROJECT_ID},${taskId},${reservation2},2,
       ${`pending/${PROJECT_ID}/${reservation2}/report-v2.txt`},'report-v2.txt','text/plain',20,${"b".repeat(64)},${ACTOR_ID})
  `;
  await admin`
    update public.task_files set current_version_id=${version2} where id=${fileId}
  `;

  return { taskId, fileId, version1, version2 };
}

async function rollback(
  client: Sql,
  fileId: string,
  restoreVersionId: string,
  expectedVersion: number,
  requestId: string,
  expectedProjectVersion: number,
) {
  return asAuthenticated(
    client,
    ACTOR_ID,
    (tx) => tx`
    select public.cmd_batch_rollback_task_files(
      ${PROJECT_ID},
      ${requestId},
      ${expectedProjectVersion},
      ${tx.json([{ fileId, restoreVersionId, expectedVersion }])}::jsonb
    ) as result
  `,
  );
}

async function currentProjectVersion() {
  const rows = await admin<{ version: number }[]>`
    select version from public.projects where id=${PROJECT_ID}
  `;
  return rows[0]!.version;
}

beforeAll(async () => {
  await cleanup();
  await admin`
    insert into auth.users(id,email) values
      (${LEADER_ID},'rollback-race-leader@example.test'),
      (${ACTOR_ID},'rollback-race-actor@example.test')
  `;
  await admin`
    insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
    values(${PROJECT_ID},'Rollback race project',now()+interval '10 days',${LEADER_ID},${LEADER_ID},1)
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state) values
      (${PROJECT_ID},${LEADER_ID},'leader','active'),
      (${PROJECT_ID},${ACTOR_ID},'member','active')
  `;
  await admin`
    insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
    ) values(
      ${LEADER_ID},'pro','active',now()-interval '1 day',now()+interval '30 days',
      now(),${LEADER_ID},'test',1
    )
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("file history batch rollback concurrency", () => {
  test("concurrent identical request_id replays one append only", async () => {
    const fixture = await seedFile("001");
    const expectedProjectVersion = await currentProjectVersion();
    const clients = [postgres(databaseUrl), postgres(databaseUrl)];
    try {
      const [left, right] = await Promise.all(
        clients.map((client) =>
          rollback(
            client,
            fixture.fileId,
            fixture.version1,
            2,
            "e9900000-0000-0000-0000-000000000001",
            expectedProjectVersion,
          ),
        ),
      );
      expect([left!.ok, right!.ok]).toEqual([true, true]);
      expect([left!.replayed, right!.replayed].filter(Boolean)).toHaveLength(1);

      const counts = await admin<{ versions: number; events: number }[]>`
        select
          (select count(*)::integer from public.task_file_versions where file_id=${fixture.fileId}) as versions,
          (select count(*)::integer from public.business_events where request_id='e9900000-0000-0000-0000-000000000001') as events
      `;
      expect(counts[0]).toEqual({ versions: 3, events: 1 });
    } finally {
      await Promise.all(clients.map((client) => client.end()));
    }
  });

  test("parallel rollback attempts with the same expected version leave one winner", async () => {
    const fixture = await seedFile("002");
    const expectedProjectVersion = await currentProjectVersion();
    const clients = [postgres(databaseUrl), postgres(databaseUrl)];
    try {
      const results = await Promise.all(
        clients.map((client, index) =>
          rollback(
            client,
            fixture.fileId,
            fixture.version1,
            2,
            `e9900000-0000-0000-0000-00000000000${index + 2}`,
            expectedProjectVersion,
          ),
        ),
      );
      expect(results.filter((result) => result.ok)).toHaveLength(1);
      expect(
        results.filter((result) => result.code === "STALE_VERSION"),
      ).toHaveLength(1);

      const rows = await admin<{ version: number; versions: number }[]>`
        select
          (select version from public.task_files where id=${fixture.fileId}) as version,
          (select count(*)::integer from public.task_file_versions where file_id=${fixture.fileId}) as versions
      `;
      expect(rows[0]).toEqual({ version: 3, versions: 3 });
    } finally {
      await Promise.all(clients.map((client) => client.end()));
    }
  });

  test("upload finalization and rollback use the same logical file expected version", async () => {
    const fixture = await seedFile("003");
    const reserveResult = await asAuthenticated(
      admin,
      ACTOR_ID,
      (tx) => tx`
      select public.cmd_reserve_task_file_upload(
        ${PROJECT_ID},${fixture.taskId},'e9900000-0000-0000-0000-000000000004',
        2,'new_version',${fixture.fileId},'upload-race.txt','text/plain',30
      ) as result
    `,
    );
    expect(reserveResult.ok).toBe(true);
    const reservationId = reserveResult.data?.reservationId as string;
    const objectPath = reserveResult.data?.objectPath as string;
    await admin`
      insert into storage.objects(bucket_id,name,owner_id,metadata)
      values('teamup-files',${objectPath},${ACTOR_ID},'{"size":30,"mimetype":"text/plain"}'::jsonb)
    `;

    const clients = [postgres(databaseUrl), postgres(databaseUrl)];
    const expectedProjectVersion = await currentProjectVersion();
    try {
      const [finalizeResult, rollbackResult] = await Promise.all([
        asServiceRole(
          clients[0]!,
          (tx) => tx`
          select public.cmd_finalize_task_file_upload_service(
            ${ACTOR_ID},${reservationId},'e9900000-0000-0000-0000-000000000005',
            1,'text/plain',30,${"c".repeat(64)}
          ) as result
        `,
        ),
        rollback(
          clients[1]!,
          fixture.fileId,
          fixture.version1,
          2,
          "e9900000-0000-0000-0000-000000000006",
          expectedProjectVersion,
        ),
      ]);

      expect(
        [finalizeResult.ok, rollbackResult.ok].filter(Boolean),
      ).toHaveLength(1);
      expect(
        [finalizeResult.code, rollbackResult.code].filter(
          (code) => code === "STALE_VERSION",
        ),
      ).toHaveLength(1);
      const rows = await admin<{ version: number; versions: number }[]>`
        select
          (select version from public.task_files where id=${fixture.fileId}) as version,
          (select count(*)::integer from public.task_file_versions where file_id=${fixture.fileId}) as versions
      `;
      expect(rows[0]).toEqual({ version: 3, versions: 3 });
    } finally {
      await Promise.all(clients.map((client) => client.end()));
    }
  });
});
