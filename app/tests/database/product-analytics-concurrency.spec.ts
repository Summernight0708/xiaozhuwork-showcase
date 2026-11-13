import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const databaseUrl =
  process.env.SUPABASE_DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const admin = postgres(databaseUrl, { max: 4 });

const projectId = "a8421000-0000-0000-0000-000000000001";
const actorA = "a8420000-0000-0000-0000-000000000001";
const actorB = "a8420000-0000-0000-0000-000000000002";

async function cleanup() {
  await admin.unsafe("set session_replication_role = replica");
  try {
    await admin`delete from private.analytics_event_actor_eligibility where project_id=${projectId}`;
    await admin`delete from public.business_events where project_id=${projectId}`;
    await admin`delete from public.project_members where project_id=${projectId}`;
    await admin`delete from public.projects where id=${projectId}`;
    await admin`delete from auth.users where id in (${actorA},${actorB})`;
  } finally {
    await admin.unsafe("set session_replication_role = origin");
  }
}

beforeAll(async () => {
  await cleanup();
  await admin`
    insert into auth.users(id,email) values
      (${actorA},'analytics-race-a@example.test'),
      (${actorB},'analytics-race-b@example.test')
  `;
  await admin`
    insert into public.projects(id,name,deadline_at,leader_id,created_by)
    values(${projectId},'Analytics race',now()+interval '30 days',${actorA},${actorA})
  `;
  await admin`
    insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
      (${projectId},${actorA},'leader','active',false),
      (${projectId},${actorB},'member','active',false)
  `;
});

afterAll(async () => {
  try {
    await cleanup();
  } finally {
    await admin.end();
  }
});

describe("product analytics concurrency", () => {
  test("concurrent effective events keep actor counts distinct", async () => {
    const a = postgres(databaseUrl, { max: 1 });
    const b = postgres(databaseUrl, { max: 1 });

    try {
      await Promise.all([
        a`
          insert into public.business_events(
            project_id,actor_id,event_type,entity_type,event_data,created_at
          )
          select
            ${projectId},${actorA},'task_created','analytics_concurrency',
            jsonb_build_object('n',g),
            '2026-11-02 02:00:00+00'::timestamptz + (g || ' milliseconds')::interval
          from generate_series(1,50) g
        `,
        b`
          insert into public.business_events(
            project_id,actor_id,event_type,entity_type,event_data,created_at
          )
          select
            ${projectId},${actorB},'task_claimed','analytics_concurrency',
            jsonb_build_object('n',g),
            '2026-11-02 02:00:00+00'::timestamptz + (g || ' milliseconds')::interval
          from generate_series(1,50) g
        `,
      ]);
    } finally {
      await Promise.all([a.end(), b.end()]);
    }

    const [snapshot] = await admin<
      {
        rows: number;
        actors: number;
      }[]
    >`
      select count(*)::integer as rows,
             count(distinct actor_user_id)::integer as actors
      from private.analytics_event_actor_eligibility
      where project_id=${projectId} and actor_was_eligible
    `;
    expect(snapshot).toEqual({ rows: 100, actors: 2 });

    const [facts] = await admin<{ value: Record<string, unknown> }[]>`
      select private.analytics_project_facts_v1(
        ${projectId},'2026-11-09 00:00:00+00'::timestamptz
      ) as value
    `;
    expect(facts?.value.activatedAt).toBeTruthy();

    const [wacp] = await admin<{ value: number }[]>`
      select private.analytics_wacp_v1('2026-11-02'::date) as value
    `;
    expect(wacp?.value).toBe(1);
  });
});
