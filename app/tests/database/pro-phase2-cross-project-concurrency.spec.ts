import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// Only the standalone F stack on the reserved local Postgres port is valid.
const dbUrl = process.env.F_TEST_DB_URL ?? "";
const gIsolated =
  process.env.XIAOZHUWORK_G_INTEGRATION_TEST === "1" &&
  /^postgres(?:ql)?:\/\/[^@]+@(?:127\.0\.0\.1|localhost):55512\/postgres$/.test(
    dbUrl,
  );
const suite = describe.skipIf(
  !gIsolated && !/^postgres(?:ql)?:\/\/[^ ]+:55462\/postgres$/.test(dbUrl),
);
const admin = dbUrl ? postgres(dbUrl, { max: 6 }) : null;
const actor = "63000000-0000-0000-0000-000000000001";
const leader = "63000000-0000-0000-0000-000000000002";
const project = "64000000-0000-0000-0000-000000000001";
const project2 = "64000000-0000-0000-0000-000000000002";

async function asActor(fn: (tx: TransactionSql) => PromiseLike<unknown>) {
  if (!admin) throw new Error("No F test DB");
  return admin.begin(async (tx) => {
    await tx.unsafe("select set_config('request.jwt.claim.sub',$1,true)", [
      actor,
    ]);
    await tx.unsafe("set local role authenticated");
    return fn(tx);
  });
}

suite("F isolated DB membership/concurrency", () => {
  beforeAll(async () => {
    if (!admin) throw new Error("F database is missing");
    // Remove any fixture leftovers from an interrupted prior run. Project deletion
    // cascades membership and avoids the deferred active-leader integrity trigger.
    await admin.unsafe(
      "delete from public.account_entitlements where user_id=$1",
      [actor],
    );
    await admin.unsafe("delete from public.projects where id in ($1,$2)", [
      project,
      project2,
    ]);
    await admin.unsafe("delete from auth.users where id in ($1,$2)", [
      actor,
      leader,
    ]);

    await admin.unsafe(
      "insert into auth.users(id,email) values($1,$2),($3,$4)",
      [
        actor,
        "f-concurrent-pro@example.test",
        leader,
        "f-concurrent-leader@example.test",
      ],
    );
    await admin.unsafe(
      "insert into public.projects(id,name,deadline_at,leader_id,created_by) values($1,'F concurrency one',now()+interval '30 days',$3,$3),($2,'F concurrency two',now()+interval '30 days',$3,$3)",
      [project, project2, leader],
    );
    await admin.unsafe(
      "insert into public.project_members(project_id,user_id,role,member_state) values($1,$3,'leader','active'),($2,$3,'leader','active'),($1,$4,'member','active'),($2,$4,'member','active')",
      [project, project2, leader, actor],
    );
    await admin.unsafe(
      "insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version) values($1,'pro','active',now()-interval '1 day',now()+interval '7 days',now(),$2,'test',1)",
      [actor, leader],
    );
    await admin.unsafe(
      "create or replace function private.capability_is_released(p_capability text) returns boolean language sql immutable security definer set search_path = '' as $$ select p_capability = any(array['file_full_history','file_batch_rollback','file_version_compare','project_recovery_point','cross_project_overview','cross_project_analytics']::text[]) $$",
    );
  });

  afterAll(async () => {
    if (!admin) return;
    try {
      await admin.unsafe(
        "create or replace function private.capability_is_released(p_capability text) returns boolean language sql immutable security definer set search_path = '' as $$ select coalesce(p_capability = any(array['file_full_history','file_batch_rollback','file_version_compare','project_recovery_point']::text[]),false) $$",
      );
      await admin.unsafe(
        "delete from public.account_entitlements where user_id=$1",
        [actor],
      );
      await admin.unsafe("delete from public.projects where id in ($1,$2)", [
        project,
        project2,
      ]);
      await admin.unsafe("delete from auth.users where id in ($1,$2)", [
        actor,
        leader,
      ]);
    } finally {
      await admin.end({ timeout: 5 });
    }
  });

  it("parallel account-authorized reads never leak another project", async () => {
    const results = await Promise.all(
      Array.from({ length: 16 }, () =>
        asActor(async (tx) => {
          const row = await tx.unsafe(
            "select public.get_my_cross_project_access(array[$1::uuid,$2::uuid]) as result",
            [project, project2],
          );
          return row[0]!.result;
        }),
      ),
    );
    for (const raw of results) {
      const result = raw as { ok: boolean; projectIds: string[] };
      expect(result.ok).toBe(true);
      expect(result.projectIds).toEqual([project, project2]);
    }
  });

  it("concurrent membership revocation invalidates a previously valid selection", async () => {
    const check = async () =>
      asActor(
        async (tx) =>
          (
            await tx.unsafe(
              "select public.get_my_cross_project_access(array[$1::uuid,$2::uuid]) as result",
              [project, project2],
            )
          )[0]!.result,
      ) as Promise<{ ok: boolean; code?: string }>;
    expect((await check()).ok).toBe(true);
    await admin!.unsafe(
      "update public.project_members set member_state='removed',departed_at=now() where project_id=$1 and user_id=$2",
      [project2, actor],
    );
    const after = await check();
    expect(after.ok).toBe(false);
    expect(after.code).toBe("NOT_FOUND_OR_NOT_AUTHORIZED");
  });
});
