import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

// Explicitly opt in to a disposable, fully migrated instance. Never touch the shared DB.
const isolatedUrl = process.env.XIAOZHUWORK_ARCHIVE_ISOLATED_DB_URL;
const db = isolatedUrl ? postgres(isolatedUrl, { max: 8 }) : null;

const actor = "b4100000-0000-0000-0000-000000000001";
const target = "b4200000-0000-0000-0000-000000000001";
const req = (i: number) =>
  `b4300000-0000-0000-0000-${String(i).padStart(12, "0")}`;

async function callAsUser(query: string, values: Array<string | number> = []) {
  if (!db) throw new Error("isolation required");
  return db.begin(async (tx) => {
    await tx`select set_config('request.jwt.claim.sub', ${actor}, true)`;
    await tx.unsafe("set local role authenticated");
    const rows = await tx.unsafe(query, values);
    return rows[0]?.result as {
      ok: boolean;
      code?: string;
      replayed?: boolean;
    };
  });
}

describe.skipIf(!isolatedUrl)("B archive quota concurrency (isolated)", () => {
  beforeAll(async () => {
    if (!db) return;
    await db`insert into auth.users(id,email) values(${actor},'b-archive-concurrent@example.test')`;
    for (let i = 1; i <= 4; i++) {
      const id = `b4400000-0000-0000-0000-${String(i).padStart(12, "0")}`;
      await db`
        insert into public.projects(id,name,deadline_at,leader_id,created_by)
        values(${id}, ${`B active ${i}`}, now()+interval '30 days', ${actor}, ${actor})
      `;
      await db`
        insert into public.project_members(project_id,user_id,role,member_state)
        values(${id},${actor},'leader','active')
      `;
    }
    await db`
      insert into public.projects(id,name,deadline_at,leader_id,created_by)
      values(${target},'B target',now()+interval '30 days',${actor},${actor})
    `;
    await db`
      insert into public.project_members(project_id,user_id,role,member_state)
      values(${target},${actor},'leader','active')
    `;
  });

  afterAll(async () => {
    await db?.end();
  });

  test("duplicate archive request produces one cycle and only one event", async () => {
    const query =
      "select public.cmd_archive_project($1::uuid,$2::text,$3::uuid,$4::integer) as result";
    const [a, b] = await Promise.all([
      callAsUser(query, [target, "Finished", req(1), 1]),
      callAsUser(query, [target, "Finished", req(1), 1]),
    ]);
    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect([a.replayed, b.replayed].filter(Boolean)).toHaveLength(1);
    const rows = await db!`
      select count(*)::integer as n from public.project_archive_cycles
      where project_id=${target}
    `;
    expect(rows[0]?.n).toBe(1);
  });

  test("restore versus new Free project cannot admit six active Free projects", async () => {
    const [restore, create] = await Promise.all([
      callAsUser(
        "select public.cmd_restore_project($1::uuid,$2::uuid,$3::integer) as result",
        [target, req(2), 2],
      ),
      callAsUser(
        "select public.cmd_create_project(p_request_id=>$1::uuid,p_expected_version=>0,p_name=>'B concurrent new',p_deadline_at=>now()+interval '30 days') as result",
        [req(3)],
      ),
    ]);
    expect([restore, create].filter((result) => result.ok)).toHaveLength(1);
    const count = await db!`
      select private.account_active_free_project_count(${actor},transaction_timestamp()) as n
    `;
    expect(count[0]?.n).toBe(5);
    expect([restore, create].find((result) => !result.ok)?.code).toBe(
      "ACTIVE_FREE_PROJECT_LIMIT_REACHED",
    );
  });
});
