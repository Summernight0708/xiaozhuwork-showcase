import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

// Never run this destructive local fixture suite against hosted/shared databases.
const databaseUrl =
  process.env.XIAOZHUWORK_CALENDAR_TEST_DATABASE_URL ??
  "postgresql://postgres:postgres@127.0.0.1:55452/postgres";
const parsedUrl = new URL(databaseUrl);
if (
  !["127.0.0.1", "localhost"].includes(parsedUrl.hostname) ||
  !(
    ["55452", "58452"].includes(parsedUrl.port) ||
    (process.env.XIAOZHUWORK_G_INTEGRATION_TEST === "1" &&
      parsedUrl.port === "55512" &&
      parsedUrl.pathname === "/postgres")
  )
) {
  throw new Error(
    "E concurrency tests require an isolated local port (55452/58452)",
  );
}
const sql = postgres(databaseUrl, { max: 8 });
const leader = "e5100000-0000-0000-0000-000000000001";
const member = "e5100000-0000-0000-0000-000000000002";
const project = "e5200000-0000-0000-0000-000000000001";
let originalReleaseFunction = "";
let freshSecret: string | null = null;
type Result = {
  ok: boolean;
  code?: string;
  data?: { token?: string | null; id?: string; version?: number };
  replayed?: boolean;
};

async function asActor(
  actor: string,
  command: (tx: TransactionSql) => PromiseLike<readonly { result: Result }[]>,
): Promise<Result> {
  return sql.begin(async (tx): Promise<Result> => {
    await tx`select set_config('request.jwt.claim.sub', ${actor}, true)`;
    await tx.unsafe("set local role authenticated");
    return (await command(tx))[0]!.result;
  });
}

async function clean() {
  // Fixture IDs are isolated to this local E database.
  await sql.begin(async (tx) => {
    await tx.unsafe("set local session_replication_role = replica");
    await tx`delete from public.business_events where project_id = ${project}::uuid`;
    await tx`delete from public.command_requests where project_id = ${project}::uuid`;
    await tx`delete from public.project_calendar_subscriptions where project_id = ${project}::uuid`;
    await tx`delete from public.tasks where project_id = ${project}::uuid`;
    await tx`delete from public.project_members where project_id = ${project}::uuid`;
    await tx`delete from public.projects where id = ${project}::uuid`;
    await tx`delete from public.account_entitlements where user_id in (${leader}::uuid,${member}::uuid)`;
    await tx`delete from auth.users where id in (${leader}::uuid,${member}::uuid)`;
  });
}

beforeAll(async () => {
  const definition = await sql<{ def: string }[]>`
    select pg_get_functiondef('private.capability_is_released(text)'::regprocedure) as def
  `;
  originalReleaseFunction = definition[0]!.def;
  await clean();
  await sql`insert into auth.users(id,email) values
    (${leader}::uuid,'phase2-e-concurrent-leader@example.test'),
    (${member}::uuid,'phase2-e-concurrent-member@example.test')`;
  await sql`insert into public.projects(id,name,leader_id,created_by,deadline_at)
    values (${project}::uuid,'Calendar concurrency',${leader}::uuid,${leader}::uuid,now()+interval '120 days')`;
  await sql`insert into public.project_members(project_id,user_id,role,member_state) values
    (${project}::uuid,${leader}::uuid,'leader','active'),
    (${project}::uuid,${member}::uuid,'member','active')`;
  await sql`insert into public.account_entitlements(
    user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
  ) values (${leader}::uuid,'pro','active',now()-interval '1 day',
    now()+interval '30 days',now(),${leader}::uuid,'test',1)`;
  await sql`insert into public.tasks(project_id,title,deadline_at,status)
    values (${project}::uuid,'Concurrent deadline',now()+interval '10 days','not_started')`;
  await sql.unsafe(`create or replace function private.capability_is_released(p_capability text)
    returns boolean language sql immutable security definer set search_path = ''
    as $$ select p_capability in ('external_integrations','file_full_history',
      'file_batch_rollback','file_version_compare','project_recovery_point') $$;`);
}, 90_000);

afterAll(async () => {
  try {
    if (originalReleaseFunction) await sql.unsafe(originalReleaseFunction);
    await clean();
  } finally {
    await sql.end();
  }
}, 90_000);

describe("E: concurrent mint/revoke, replay and live authorization", () => {
  test("two concurrent identical requests create one row and only one first-response secret", async () => {
    const requestId = "e5400000-0000-0000-0000-000000000001";
    const make = () =>
      asActor(
        leader,
        (tx) => tx`select
      public.cmd_create_calendar_feed_subscription(
        ${project}::uuid,${requestId}::uuid,1,false) as result`,
      );
    const responses = await Promise.all([make(), make()]);
    expect(responses.every((r) => r.ok)).toBe(true);
    const tokens = responses.map((r) => r.data?.token).filter(Boolean);
    expect(tokens).toHaveLength(1);
    expect(tokens[0]).toMatch(/^[a-f0-9]{64}$/);
    freshSecret = tokens[0] as string;
    expect(responses.filter((r) => r.replayed === true)).toHaveLength(1);
    expect(
      await sql`select id from public.project_calendar_subscriptions
      where project_id = ${project}::uuid`,
    ).toHaveLength(1);
    const serialized = JSON.stringify(
      await sql`select result from public.command_requests
      where project_id = ${project}::uuid`,
    );
    expect(serialized).not.toContain(tokens[0]);
    const wrong = await asActor(
      leader,
      (tx) => tx`select
      public.cmd_create_calendar_feed_subscription(
        ${project}::uuid,${requestId}::uuid,1,true) as result`,
    );
    expect(wrong.code).toBe("IDEMPOTENCY_KEY_REUSED");
    const forbidden = await asActor(
      member,
      (tx) => tx`select
      public.cmd_create_calendar_feed_subscription(
        ${project}::uuid,'e5400000-0000-0000-0000-000000000002'::uuid,2,false) as result`,
    );
    expect(forbidden.code).toBe("NOT_FOUND_OR_NOT_AUTHORIZED");
  });
  test("simultaneous revocations serialize and disable all future GETs", async () => {
    const rows = await sql<
      { token_hash: Buffer; id: string }[]
    >`select token_hash,id
      from public.project_calendar_subscriptions where project_id = ${project}::uuid`;
    const { token_hash: hash, id } = rows[0]!;
    expect(hash.length).toBe(32);
    expect(freshSecret).not.toBeNull();
    const before =
      await sql`select public.phase2_calendar_feed_lookup(${freshSecret}) as feed`;
    expect(before[0]!.feed).not.toBeNull();
    const req = "e5400000-0000-0000-0000-000000000003";
    const revoke = () =>
      asActor(
        leader,
        (tx) => tx`select
      public.cmd_revoke_calendar_feed_subscription(
        ${project}::uuid,${id}::uuid,${req}::uuid,1) as result`,
      );
    const responses = await Promise.all([revoke(), revoke()]);
    expect(responses.every((r) => r.ok)).toBe(true);
    expect(responses.filter((r) => r.replayed === true)).toHaveLength(1);
    expect(
      (
        await sql`select revoked_at from public.project_calendar_subscriptions
      where id = ${id}::uuid`
      )[0]!.revoked_at,
    ).not.toBeNull();
    // Use the actual ephemeral token, not its stored hash, to prove revocation.
    const look =
      await sql`select public.phase2_calendar_feed_lookup(${freshSecret}) as feed`;
    expect(look[0]!.feed).toBeNull();
  });
});
