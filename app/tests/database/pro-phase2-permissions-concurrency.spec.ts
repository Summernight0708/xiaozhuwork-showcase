import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const url = process.env.SUPABASE_DB_URL ?? "";
const gIsolated =
  process.env.XIAOZHUWORK_G_INTEGRATION_TEST === "1" &&
  /^postgres(?:ql)?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):55512\/postgres$/.test(
    url ?? "",
  );
if (
  !gIsolated &&
  (!url ||
    !/^postgres(?:ql)?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):55442\//.test(url))
) {
  throw Error("Explicit isolated D localhost:55442 database is required");
}
const admin = postgres(url, { max: 4 });
const uid = (i: number) =>
  "b1100000-0000-0000-0000-" + String(i).padStart(12, "0");
const project = "b2100000-0000-0000-0000-000000000001";
const membership = "b3100000-0000-0000-0000-000000000002";
const invitation = "b4100000-0000-0000-0000-000000000001";
const join = (i: number) =>
  "b5100000-0000-0000-0000-" + String(i).padStart(12, "0");
const request = (i: number) =>
  "b6100000-0000-0000-0000-" + String(i).padStart(12, "0");
type Result = { ok: boolean; code?: string; replayed?: boolean };

async function asUser(
  sql: Sql,
  actor: string,
  statement: string,
  parameters: (string | number | boolean)[],
): Promise<Result> {
  return sql.begin(async (tx: TransactionSql) => {
    await tx.unsafe("select set_config('request.jwt.claim.sub',$1,true)", [
      actor,
    ]);
    await tx.unsafe("set local role authenticated");
    const rows = await tx.unsafe<{ result: Result }[]>(statement, parameters);
    return rows[0]!.result;
  });
}

const grant = (
  sql: Sql,
  actor: string,
  enabled: boolean,
  version: number,
  key: string,
) =>
  asUser(
    sql,
    actor,
    "select public.cmd_set_project_permission_delegation($1,$2,'intake_reviewer',$3,$4,$5) as result",
    [project, membership, enabled, version, key],
  );
const review = (sql: Sql, target: string, key: string) =>
  asUser(
    sql,
    uid(2),
    "select public.cmd_review_project_join_request($1,$2,'approve',$3,1) as result",
    [project, target, key],
  );
let savedRelease: string | undefined;

async function clearFixtures() {
  await admin.begin(async (tx) => {
    await tx.unsafe("set local session_replication_role = replica");
    await tx.unsafe(
      "delete from public.project_permission_delegations where project_id=$1",
      [project],
    );
    await tx.unsafe("delete from public.business_events where project_id=$1", [
      project,
    ]);
    await tx.unsafe("delete from public.command_requests where project_id=$1", [
      project,
    ]);
    await tx.unsafe(
      "delete from public.project_join_requests where project_id=$1",
      [project],
    );
    await tx.unsafe(
      "delete from public.project_invitations where project_id=$1",
      [project],
    );
    await tx.unsafe("delete from public.project_members where project_id=$1", [
      project,
    ]);
    await tx.unsafe("delete from public.projects where id=$1", [project]);
    await tx.unsafe(
      "delete from public.account_entitlements where user_id=$1",
      [uid(1)],
    );
    await tx.unsafe(
      "delete from public.account_entitlement_audit where user_id=$1",
      [uid(1)],
    );
    await tx.unsafe("delete from auth.users where id::text like 'b1100000-%'");
  });
}

beforeAll(async () => {
  const original = await admin.unsafe<{ value: string }[]>(
    "select pg_get_functiondef('private.capability_is_released(text)'::regprocedure) as value",
  );
  savedRelease = original[0]!.value;
  await clearFixtures();
  await admin.unsafe(
    "insert into auth.users(id,email) select ('b1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid, 'd-concurrency-'||i||'@example.test' from generate_series(1,65) s(i)",
  );
  await admin.unsafe(
    "update public.profiles set display_name='D Concurrent',real_name='D Tester',student_number='D' where id::text like 'b1100000-%'",
  );
  await admin.unsafe(
    "insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values($1,'D concurrency',now()+interval '30 days',$2,$2,1)",
    [project, uid(1)],
  );
  await admin.unsafe(
    "insert into public.project_members(id,project_id,user_id,role,member_state) values('b3100000-0000-0000-0000-000000000001',$1,$2,'leader','active'),($3,$1,$4,'member','active')",
    [project, uid(1), membership, uid(2)],
  );
  await admin.unsafe(
    "insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version) values($1,'pro','active',now()-interval '1 day',now()+interval '30 days',now(),$1,'test',1)",
    [uid(1)],
  );
  // This release simulation exists only inside the isolated D test DB, never in Git migrations.
  await admin.unsafe(
    "create or replace function private.capability_is_released(p_capability text) returns boolean language sql immutable security definer set search_path = '' as $$ select p_capability=any(array['file_full_history','file_batch_rollback','file_version_compare','project_recovery_point','advanced_permissions']::text[]); $$",
  );
});

afterAll(async () => {
  try {
    if (savedRelease) await admin.unsafe(savedRelease);
    await clearFixtures();
  } finally {
    await admin.end();
  }
});

describe("D delegated permission concurrency", () => {
  test("two grants use one membership version and produce one audit event", async () => {
    const a = postgres(url, { max: 1 }),
      b = postgres(url, { max: 1 });
    try {
      const results = await Promise.all([
        grant(a, uid(1), true, 1, request(1)),
        grant(b, uid(1), true, 1, request(2)),
      ]);
      expect(results.filter((v) => v.ok)).toHaveLength(1);
      expect(results.filter((v) => v.code === "STALE_VERSION")).toHaveLength(1);
      const key = results[0]!.ok ? request(1) : request(2);
      expect(await grant(a, uid(1), true, 1, key)).toMatchObject({
        ok: true,
        replayed: true,
      });
      const rows = await admin.unsafe<{ count: number; audit: number }[]>(
        "select (select count(*)::int from public.project_permission_delegations where project_id=$1 and revoked_at is null) as count,(select count(*)::int from public.business_events where project_id=$1 and event_type='project_permission_delegation_granted') as audit",
        [project],
      );
      expect(rows[0]).toMatchObject({ count: 1, audit: 1 });
    } finally {
      await Promise.all([a.end(), b.end()]);
    }
  });

  test("delegated reviewers cannot race past the last Pro member slot", async () => {
    await admin.unsafe(
      "insert into public.project_members(project_id,user_id,role,member_state) select $1,('b1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'member','active' from generate_series(3,19) s(i)",
      [project],
    );
    await admin.unsafe(
      "insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at,max_uses,version) values($1,$2,$3,extensions.digest(convert_to('d-concurrency-invite','utf8'),'sha256'),'approval',now()+interval '6 days',10,1)",
      [invitation, project, uid(1)],
    );
    await admin.unsafe(
      "insert into public.project_join_requests(id,invitation_id,project_id,user_id,state) values($1,$3,$4,$5,'pending'),($2,$3,$4,$6,'pending')",
      [join(1), join(2), invitation, project, uid(20), uid(21)],
    );
    const a = postgres(url, { max: 1 }),
      b = postgres(url, { max: 1 });
    try {
      const answers = await Promise.all([
        review(a, join(1), request(3)),
        review(b, join(2), request(4)),
      ]);
      expect(answers.filter((x) => x.ok)).toHaveLength(1);
      expect(answers.find((x) => !x.ok)?.code).toBe(
        "PROJECT_MEMBER_LIMIT_REACHED",
      );
      const row = await admin.unsafe<{ total: number }[]>(
        "select count(*)::int as total from public.project_members where project_id=$1 and member_state='active'",
        [project],
      );
      expect(row[0]!.total).toBe(20);
    } finally {
      await Promise.all([a.end(), b.end()]);
    }
  });

  test("grant-vs-revoke race rejects one stale version and never duplicates active rows", async () => {
    const a = postgres(url, { max: 1 }),
      b = postgres(url, { max: 1 });
    try {
      const answers = await Promise.all([
        grant(a, uid(1), false, 2, request(5)),
        grant(b, uid(1), true, 2, request(6)),
      ]);
      // Grant can be a version-preserving no-op if it acquires the lock first.
      // Both success is valid only in that order: revocation must still win.
      expect(answers[0]!.ok).toBe(true);
      expect(answers[1]!.ok || answers[1]!.code === "STALE_VERSION").toBe(true);
      const row = await admin.unsafe<{ total: number }[]>(
        "select count(*)::int as total from public.project_permission_delegations where project_id=$1 and membership_id=$2 and revoked_at is null",
        [project, membership],
      );
      expect(row[0]!.total).toBe(0);
    } finally {
      await Promise.all([a.end(), b.end()]);
    }
  });
});
