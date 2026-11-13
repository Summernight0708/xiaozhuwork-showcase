import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });
const leaderId = "fb000000-0000-0000-0000-000000000001";
const memberId = "fb000000-0000-0000-0000-000000000002";
const projectId = "fb100000-0000-0000-0000-000000000001";
const requestId = "fb200000-0000-0000-0000-000000000001";

type RpcResult = { ok: boolean; replayed: boolean };

async function asAuthenticated(
  sql: Sql,
  userId: string,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: RpcResult }[]>,
) {
  return sql.begin(async (tx) => {
    await tx`select set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx.unsafe("set local role authenticated");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}

beforeAll(async () => {
  await admin`
    insert into auth.users(id,email) values
    (${leaderId},'notification-concurrency-leader@example.test'),
    (${memberId},'notification-concurrency-member@example.test')
  `;
  await admin`
    insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
    values(${projectId},'Notification concurrency',now()+interval '20 days','weighted',${leaderId},${leaderId},1)
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state) values
    (${projectId},${leaderId},'leader','active'),
    (${projectId},${memberId},'member','active')
  `;
});

afterAll(async () => {
  try {
    await admin`alter table public.business_events disable trigger business_events_immutable`;
    await admin`delete from public.business_events where project_id=${projectId}`;
    await admin`delete from public.command_requests where project_id=${projectId}`;
    await admin`delete from public.projects where id=${projectId}`;
    await admin`delete from auth.users where id in (${leaderId},${memberId})`;
  } finally {
    await admin`alter table public.business_events enable trigger business_events_immutable`;
    await admin.end();
  }
});

describe("notification idempotency under concurrency", () => {
  test("two concurrent identical command replays create one assignment notification", async () => {
    const deadline = new Date(Date.now() + 5 * 86_400_000).toISOString();
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const call = (sql: Sql) =>
      asAuthenticated(
        sql,
        leaderId,
        (tx) =>
          tx`select public.cmd_create_task(
            ${projectId},${requestId},1,'Concurrent direct assignment',null,
            ${deadline},3::smallint,'direct',${memberId}
          ) as result`,
      );

    const results = await Promise.all([call(connectionA), call(connectionB)]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(results.every((result) => result.ok)).toBe(true);
    expect(results.map((result) => result.replayed).sort()).toEqual([
      false,
      true,
    ]);

    const notifications = await admin<{ count: number }[]>`
      select count(*)::integer as count
      from public.notifications
      where recipient_id=${memberId} and notification_type='task_assignment'
    `;
    expect(notifications[0]!.count).toBe(1);
  });
});
