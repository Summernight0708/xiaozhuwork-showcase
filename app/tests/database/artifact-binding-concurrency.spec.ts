import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });
const leaderId = "ac100000-0000-0000-0000-000000000001";
const memberId = "ac100000-0000-0000-0000-000000000002";
const collaboratorId = "ac100000-0000-0000-0000-000000000003";
const projectId = "ac200000-0000-0000-0000-000000000001";
const upstreamTaskId = "ac300000-0000-0000-0000-000000000001";
const downstreamTaskId = "ac300000-0000-0000-0000-000000000002";
const collaboratorDownstreamTaskId = "ac300000-0000-0000-0000-000000000003";
const fileId = "ac400000-0000-0000-0000-000000000001";
const v1 = "ac500000-0000-0000-0000-000000000001";
const v2 = "ac500000-0000-0000-0000-000000000002";
const v3 = "ac500000-0000-0000-0000-000000000003";

type RpcResult = {
  ok: boolean;
  code?: string;
  replayed: boolean;
  currentVersion?: number;
  data?: { changed?: boolean; bindingVersion?: number };
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
    await admin`delete from public.notifications where project_id=${projectId}`;
    await admin`delete from private.task_artifact_binding_update_notices where binding_id in (
      select id from public.task_artifact_bindings where project_id=${projectId}
    )`;
    await admin`delete from public.task_artifact_binding_history where project_id=${projectId}`;
    await admin`delete from public.task_artifact_bindings where project_id=${projectId}`;
    await admin`delete from public.task_file_final_designations where project_id=${projectId}`;
    await admin`delete from public.business_events where project_id=${projectId}`;
    await admin`delete from public.command_requests where project_id=${projectId}`;
    await admin`delete from public.task_collaborators where project_id=${projectId}`;
    await admin`delete from public.task_file_versions where project_id=${projectId}`;
    await admin`delete from public.task_files where project_id=${projectId}`;
    await admin`delete from public.file_upload_reservations where project_id=${projectId}`;
    await admin`delete from public.task_dependencies where project_id=${projectId}`;
    await admin`delete from public.tasks where project_id=${projectId}`;
    await admin`delete from public.project_members where project_id=${projectId}`;
    await admin`delete from public.projects where id=${projectId}`;
    await admin`delete from auth.users where id in (${leaderId},${memberId},${collaboratorId})`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();

  await admin`insert into auth.users(id,email) values
    (${leaderId},'artifact-race-leader@example.test'),
    (${memberId},'artifact-race-member@example.test'),
    (${collaboratorId},'artifact-race-collaborator@example.test')`;

  await admin`
    insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
    values(${projectId},'Artifact binding race',now()+interval '20 days',
      ${leaderId},${leaderId},1)
  `;

  await admin`
    insert into public.project_members(
      project_id,user_id,role,member_state,is_observer,version
    ) values
      (${projectId},${leaderId},'leader','active',false,1),
      (${projectId},${memberId},'member','active',false,1),
      (${projectId},${collaboratorId},'member','active',false,1)
  `;

  await admin`
    insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,
      assignment_state,accepted_at,completed_at,version
    ) values
      (${upstreamTaskId},${projectId},'Upstream',${leaderId},${leaderId},
        now()+interval '5 days','completed','assigned',now(),now(),1),
      (${downstreamTaskId},${projectId},'Downstream',${leaderId},${memberId},
        now()+interval '8 days','in_progress','assigned',now(),null,1),
      (${collaboratorDownstreamTaskId},${projectId},'Collaborator downstream',${leaderId},${memberId},
        now()+interval '9 days','in_progress','assigned',now(),null,1)
  `;

  await admin`
    insert into public.task_dependencies(
      project_id,upstream_task_id,downstream_task_id,created_by
    ) values
      (${projectId},${upstreamTaskId},${downstreamTaskId},${leaderId}),
      (${projectId},${upstreamTaskId},${collaboratorDownstreamTaskId},${leaderId})
  `;

  await admin`
    insert into public.task_collaborators(
      id,project_id,task_id,user_id,user_name_snapshot,state,invited_by,
      invited_by_name_snapshot,responded_at,version
    ) values(
      'ac350000-0000-0000-0000-000000000001',${projectId},${collaboratorDownstreamTaskId},
      ${collaboratorId},'Collaborator','accepted',${leaderId},'Leader',now(),1
    )
  `;

  await admin`
    insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,object_path,original_name,
      declared_mime_type,declared_size_bytes,state,expires_at,version
    ) values(
      'ac600000-0000-0000-0000-000000000001',${projectId},${upstreamTaskId},
      ${leaderId},'new_file','artifact-race/v1.pdf','race.pdf',
      'application/pdf',100,'finalized',now()+interval '1 hour',2
    )
  `;

  await admin`
    insert into public.task_files(
      id,project_id,task_id,logical_name,created_by,version
    ) values(${fileId},${projectId},${upstreamTaskId},'race.pdf',${leaderId},1)
  `;

  await admin`
    insert into public.task_file_versions(
      id,file_id,project_id,task_id,reservation_id,version_number,object_path,
      original_name,mime_type,size_bytes,sha256_hex,uploaded_by
    ) values(
      ${v1},${fileId},${projectId},${upstreamTaskId},
      'ac600000-0000-0000-0000-000000000001',1,'artifact-race/v1.pdf',
      'race.pdf','application/pdf',100,${"a".repeat(64)},${leaderId}
    )
  `;

  await admin`
    update public.task_files set current_version_id=${v1} where id=${fileId}
  `;

  for (const [reservationId, versionId, versionNumber, previousVersion] of [
    ["ac600000-0000-0000-0000-000000000002", v2, 2, 1],
    ["ac600000-0000-0000-0000-000000000003", v3, 3, 2],
  ] as const) {
    await admin`
      insert into public.file_upload_reservations(
        id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
        object_path,original_name,declared_mime_type,declared_size_bytes,
        state,expires_at,version
      ) values(
        ${reservationId},${projectId},${upstreamTaskId},${leaderId},
        'new_version',${fileId},${previousVersion},
        ${`artifact-race/v${versionNumber}.pdf`},'race.pdf','application/pdf',
        100,'finalized',now()+interval '1 hour',2
      )
    `;

    await admin`
      insert into public.task_file_versions(
        id,file_id,project_id,task_id,reservation_id,version_number,object_path,
        original_name,mime_type,size_bytes,sha256_hex,uploaded_by
      ) values(
        ${versionId},${fileId},${projectId},${upstreamTaskId},${reservationId},
        ${versionNumber},${`artifact-race/v${versionNumber}.pdf`},'race.pdf',
        'application/pdf',100,${String(versionNumber).repeat(64)},${leaderId}
      )
    `;
  }

  await admin`
    update public.task_files set current_version_id=${v3},version=3 where id=${fileId}
  `;

  await admin`
    insert into public.task_file_final_designations(
      file_version_id,file_id,project_id,task_id,is_final,version,
      marked_by,marked_at,updated_by
    ) values
      (${v1},${fileId},${projectId},${upstreamTaskId},true,1,${leaderId},now(),${leaderId}),
      (${v2},${fileId},${projectId},${upstreamTaskId},true,1,${leaderId},now(),${leaderId}),
      (${v3},${fileId},${projectId},${upstreamTaskId},true,1,${leaderId},now(),${leaderId})
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("artifact binding concurrency", () => {
  test("concurrent previews create one light binding and one history row", async () => {
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });

    const results = await Promise.all([
      asAuthenticated(
        a,
        memberId,
        (tx) =>
          tx`select public.cmd_record_task_artifact_use(
            ${projectId},${downstreamTaskId},${v1},
            'ac900000-0000-0000-0000-000000000001'
          ) as result`,
      ),
      asAuthenticated(
        b,
        memberId,
        (tx) =>
          tx`select public.cmd_record_task_artifact_use(
            ${projectId},${downstreamTaskId},${v1},
            'ac900000-0000-0000-0000-000000000002'
          ) as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.filter((result) => result.data?.changed)).toHaveLength(1);

    const bindings = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.task_artifact_bindings
      where project_id=${projectId} and downstream_task_id=${downstreamTaskId}
    `;
    const history = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.task_artifact_binding_history
      where project_id=${projectId} and downstream_task_id=${downstreamTaskId}
    `;

    expect(bindings[0]!.count).toBe(1);
    expect(history[0]!.count).toBe(1);
  });

  test("keeps collaborator removal and binding mutation linearizable", async () => {
    const remover = postgres(databaseUrl, { max: 1 });
    const binder = postgres(databaseUrl, { max: 1 });

    const results = await Promise.all([
      asAuthenticated(
        remover,
        leaderId,
        (tx) => tx`select public.cmd_remove_task_collaborator(
          ${projectId},${collaboratorDownstreamTaskId},
          'ac350000-0000-0000-0000-000000000001',
          'ac900000-0000-0000-0000-000000000020',1
        ) as result`,
      ),
      asAuthenticated(
        binder,
        collaboratorId,
        (tx) => tx`select public.cmd_record_task_artifact_use(
          ${projectId},${collaboratorDownstreamTaskId},${v1},
          'ac900000-0000-0000-0000-000000000021'
        ) as result`,
      ),
    ]);
    await Promise.all([remover.end(), binder.end()]);

    expect(results[0]?.ok).toBe(true);
    expect(
      results[1]?.ok ||
        ["NOT_FOUND_OR_NOT_AUTHORIZED", "NOT_AUTHORIZED"].includes(
          results[1]?.code ?? "",
        ),
    ).toBe(true);

    const [relation] = await admin<{ state: string }[]>`
      select state from public.task_collaborators
      where id='ac350000-0000-0000-0000-000000000001'
    `;
    const [bindings] = await admin<{ count: number }[]>`
      select count(*)::integer as count from public.task_artifact_bindings
      where project_id=${projectId}
        and downstream_task_id=${collaboratorDownstreamTaskId}
    `;
    expect(relation?.state).toBe("removed");
    expect([0, 1]).toContain(bindings?.count);

    const afterRemoval = await asAuthenticated(
      admin,
      collaboratorId,
      (tx) => tx`select public.cmd_record_task_artifact_use(
        ${projectId},${collaboratorDownstreamTaskId},${v1},
        'ac900000-0000-0000-0000-000000000022'
      ) as result`,
    );
    expect(afterRemoval.ok).toBe(false);
    expect(["NOT_FOUND_OR_NOT_AUTHORIZED", "NOT_AUTHORIZED"]).toContain(
      afterRemoval.code,
    );
  });

  test("competing explicit switches serialize and reject the stale client", async () => {
    const strong = await asAuthenticated(
      admin,
      memberId,
      (tx) =>
        tx`select public.cmd_set_task_artifact_binding_strength(
          ${projectId},${downstreamTaskId},${v1},'strong',
          'ac900000-0000-0000-0000-000000000003',1
        ) as result`,
    );
    expect(strong.ok).toBe(true);

    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });
    const results = await Promise.all([
      asAuthenticated(
        a,
        memberId,
        (tx) =>
          tx`select public.cmd_switch_task_artifact_binding_version(
            ${projectId},${downstreamTaskId},${v2},
            'ac900000-0000-0000-0000-000000000004',2
          ) as result`,
      ),
      asAuthenticated(
        b,
        memberId,
        (tx) =>
          tx`select public.cmd_switch_task_artifact_binding_version(
            ${projectId},${downstreamTaskId},${v3},
            'ac900000-0000-0000-0000-000000000005',2
          ) as result`,
      ),
    ]);
    await Promise.all([a.end(), b.end()]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.find((result) => !result.ok)?.code).toBe("STALE_VERSION");

    const current = await admin<
      { file_version_id: string; version: number; strength: string }[]
    >`
      select file_version_id::text,version,strength
      from public.task_artifact_bindings
      where project_id=${projectId} and downstream_task_id=${downstreamTaskId}
    `;
    expect([v2, v3]).toContain(current[0]!.file_version_id);
    expect(current[0]!.version).toBe(3);
    expect(current[0]!.strength).toBe("strong");

    const history = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.task_artifact_binding_history
      where project_id=${projectId} and downstream_task_id=${downstreamTaskId}
    `;
    expect(history[0]!.count).toBe(3);
  });
});
