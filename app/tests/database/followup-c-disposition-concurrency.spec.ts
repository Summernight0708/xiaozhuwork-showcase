import { randomUUID } from "node:crypto";
import postgres, { type Sql, type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const db: Sql = postgres(databaseUrl, { max: 6 });
const leader = randomUUID();
const outsider = randomUUID();
const project = randomUUID();
const task = randomUUID();
const abandonTask = randomUUID();
const emptyTask = randomUUID();
const cancel1 = randomUUID();
const cancel2 = randomUUID();

async function asUser(
  uid: string,
  query: (
    tx: TransactionSql,
  ) => PromiseLike<readonly { result: Record<string, unknown> }[]>,
) {
  return db.begin(async (tx) => {
    await tx.unsafe("select set_config('request.jwt.claim.sub', $1, true)", [
      uid,
    ]);
    await tx.unsafe("set local role authenticated");
    const rows = await query(tx);
    return rows[0]?.result;
  });
}

beforeAll(async () => {
  await db.unsafe("insert into auth.users (id,email) values ($1,$2),($3,$4)", [
    leader,
    "c-" + leader + "@example.test",
    outsider,
    "c-" + outsider + "@example.test",
  ]);
  await db.unsafe(
    "insert into public.projects (id,name,deadline_at,leader_id,created_by) values ($1,'C concurrency test',now()+interval '30 days',$2,$2)",
    [project, leader],
  );
  await db.unsafe(
    "insert into public.project_members (project_id,user_id,role,member_state) values ($1,$2,'leader','active')",
    [project, leader],
  );
  await db.unsafe(
    "insert into public.tasks (id,project_id,title,created_by,deadline_at) values ($1,$2,'cancel race',$3,now()+interval '5 days')",
    [task, project, leader],
  );
  await db.unsafe(
    "insert into public.tasks (id,project_id,title,created_by,assignee_id,assignment_state,accepted_at,status,deadline_at) values ($1,$2,'abandon race',$3,$3,'assigned',now()-interval '1 day','in_progress',now()+interval '5 days')",
    [abandonTask, project, leader],
  );
  await db.unsafe(
    "insert into public.tasks (id,project_id,title,created_by,deadline_at) values ($1,$2,'empty task',$3,now()+interval '5 days')",
    [emptyTask, project, leader],
  );
  const sql =
    "select private.followup_open_responsibility_epoch($1::uuid,$2::uuid,$3::uuid,(select accepted_at from public.tasks where id=$2::uuid),'test_acceptance') as id";
  const rows = await db.unsafe(sql, [project, abandonTask, leader]);
  const retried = await db.unsafe(sql, [project, abandonTask, leader]);
  expect(rows[0]?.id).toBeTruthy();
  expect(retried[0]?.id).toBe(rows[0]?.id);
});
afterAll(async () => {
  try {
    await db.unsafe(
      "alter table public.business_events disable trigger business_events_immutable",
    );
    await db.unsafe(
      "delete from public.business_events where project_id=$1::uuid",
      [project],
    );
    await db.unsafe(
      "delete from public.task_first_submission_facts where project_id=$1::uuid",
      [project],
    );
    await db.unsafe(
      "delete from public.task_responsibility_epochs where project_id=$1::uuid",
      [project],
    );
    await db.unsafe(
      "delete from public.command_requests where project_id=$1::uuid",
      [project],
    );
    await db.unsafe("delete from public.projects where id=$1::uuid", [project]);
    await db.unsafe("delete from auth.users where id in ($1::uuid,$2::uuid)", [
      leader,
      outsider,
    ]);
  } finally {
    await db
      .unsafe(
        "alter table public.business_events enable trigger business_events_immutable",
      )
      .catch(() => {});
    await db.end();
  }
});

describe("C disposition concurrency", () => {
  it("rejects an outsider", async () => {
    const result = await asUser(outsider, (tx) =>
      tx.unsafe(
        "select public.cmd_cancel_task($1::uuid,$2::uuid,$3,$4::uuid,1) as result",
        [project, task, "forbidden", randomUUID()],
      ),
    );
    expect(result?.code).toBe("NOT_FOUND_OR_NOT_AUTHORIZED");
  });
  it("serializes cancellation and emits one occurrence", async () => {
    const [first, second] = await Promise.all(
      [cancel1, cancel2].map((requestId) =>
        asUser(leader, (tx) =>
          tx.unsafe(
            "select public.cmd_cancel_task($1::uuid,$2::uuid,$3,$4::uuid,1) as result",
            [project, task, "requirements changed", requestId],
          ),
        ),
      ),
    );
    expect([first?.ok, second?.ok].filter(Boolean)).toHaveLength(1);
    expect([first?.code, second?.code]).toContain("STALE_VERSION");
    const events = await db.unsafe(
      "select id from public.business_events where project_id=$1::uuid and event_type='task_canceled'",
      [project],
    );
    expect(events).toHaveLength(1);
    const winner = first?.ok ? cancel1 : cancel2;
    const replay = await asUser(leader, (tx) =>
      tx.unsafe(
        "select public.cmd_cancel_task($1::uuid,$2::uuid,$3,$4::uuid,1) as result",
        [project, task, "requirements changed", winner],
      ),
    );
    expect(replay?.ok).toBe(true);
    expect(replay?.replayed).toBe(true);
  });
  it("safely deletes a truly empty task once", async () => {
    const req = randomUUID();
    const result = await asUser(leader, (tx) =>
      tx.unsafe(
        "select public.cmd_delete_empty_task($1::uuid,$2::uuid,$3::uuid,1) as result",
        [project, emptyTask, req],
      ),
    );
    expect(result?.ok).toBe(true);
    const deleted = await db.unsafe(
      "select id from public.tasks where id=$1::uuid",
      [emptyTask],
    );
    expect(deleted).toHaveLength(0);
    const replay = await asUser(leader, (tx) =>
      tx.unsafe(
        "select public.cmd_delete_empty_task($1::uuid,$2::uuid,$3::uuid,1) as result",
        [project, emptyTask, req],
      ),
    );
    expect(replay?.ok).toBe(true);
    expect(replay?.replayed).toBe(true);
  });
  it("does not duplicate one responsibility abandon epoch", async () => {
    const [first, second] = await Promise.all(
      [randomUUID(), randomUUID()].map((requestId) =>
        asUser(leader, (tx) =>
          tx.unsafe(
            "select public.cmd_abandon_task_responsibility($1::uuid,$2::uuid,$3,$4::uuid,1) as result",
            [project, abandonTask, "cannot continue", requestId],
          ),
        ),
      ),
    );
    expect([first?.ok, second?.ok].filter(Boolean)).toHaveLength(1);
    const events = await db.unsafe(
      "select id from public.business_events where project_id=$1::uuid and event_type='task_responsibility_abandoned'",
      [project],
    );
    expect(events).toHaveLength(1);
  });
});
