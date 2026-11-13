import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

// C tests must never fall back to another workstream's database.
const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:55432/postgres";
const admin = postgres(databaseUrl, { max: 4 });

const projectId = "c8200000-0000-4000-8000-000000000001";
const leaderId = "c8100000-0000-4000-8000-000000000001";

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from public.task_dependencies where project_id=${projectId}`;
    await admin`delete from public.tasks where project_id=${projectId}`;
    await admin`delete from public.project_members where project_id=${projectId}`;
    await admin`delete from public.projects where id=${projectId}`;
    await admin`delete from auth.users where id=${leaderId}`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
  await admin`insert into auth.users(id,email) values(${leaderId},'analytics-concurrency@example.test')`;
  await admin`
    insert into public.projects(
      id,name,timezone,start_at,deadline_at,leader_id,created_by,version
    ) values(
      ${projectId},'Analytics concurrency','UTC',
      '2026-09-01T00:00:00Z','2027-01-01T00:00:00Z',${leaderId},${leaderId},1
    )
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state,is_observer)
    values(${projectId},${leaderId},'leader','active',false)
  `;
  await admin`
    insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      assignment_state,completed_at,version,created_at
    ) values(
      'c8300000-0000-4000-8000-000000000001',${projectId},'Concurrent fact',
      ${leaderId},${leaderId},'2026-12-01T00:00:00Z','completed',3,
      'assigned','2026-10-02T02:00:00Z',1,'2026-10-02T00:00:00Z'
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

describe("project analytics concurrent reads", () => {
  test("returns identical read-only payloads for the same fixed snapshot", async () => {
    const connectionA = postgres(databaseUrl, { max: 1 });
    const connectionB = postgres(databaseUrl, { max: 1 });
    const query = (connection: ReturnType<typeof postgres>) =>
      connection<{ result: Record<string, unknown> }[]>`
        select private.phase2_project_analytics_payload(
          ${projectId},
          '2026-10-01T00:00:00Z'::timestamptz,
          '2026-10-03T00:00:00Z'::timestamptz,
          '2026-10-06T00:00:00Z'::timestamptz
        ) as result
      `;

    const [left, right] = await Promise.all([
      query(connectionA),
      query(connectionB),
    ]);
    await Promise.all([connectionA.end(), connectionB.end()]);

    expect(left[0]!.result).toEqual(right[0]!.result);
    expect(left[0]!.result).toMatchObject({
      ok: true,
      schemaVersion: 1,
      asOf: "2026-10-06T00:00:00.000000Z",
      totals: { taskTotal: 1, completedTasks: 1, completedInWindow: 1 },
    });
    const rows = await admin<{ task_count: number }[]>`
      select count(*)::integer as task_count
      from public.tasks where project_id=${projectId}
    `;
    expect(rows[0]!.task_count).toBe(1);
  });
});
