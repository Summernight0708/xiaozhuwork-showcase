import postgres, { type TransactionSql } from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const databaseUrl = process.env.SUPABASE_DB_URL;
if (
  !databaseUrl ||
  !new URL(databaseUrl).pathname.endsWith("/xiaozhuwork_e_ad119898")
) {
  throw new Error(
    "E concurrency tests require the explicitly isolated xiaozhuwork_e_ad119898 DB; never run on shared DB",
  );
}
const db = postgres(databaseUrl, { max: 4 });
const projectId = "e6200000-0000-0000-0000-000000000001";
const leader = "e6100000-0000-0000-0000-000000000001";
const member = "e6100000-0000-0000-0000-000000000002";
const tasks = [
  "e6300000-0000-0000-0000-000000000001",
  "e6300000-0000-0000-0000-000000000002",
];
type Result = {
  ok: boolean;
  replayed?: boolean;
  code?: string;
  data?: { proposalId?: string };
};

async function callAs(
  uid: string,
  query: (tx: TransactionSql) => PromiseLike<readonly { result: Result }[]>,
): Promise<Result> {
  return db.begin(async (tx) => {
    await tx`select set_config('request.jwt.claim.sub', ${uid}, true)`;
    await tx.unsafe("set local role authenticated");
    const rows = await query(tx);
    return rows[0]!.result;
  });
}
const shares = [
  { userId: leader, shareBps: 6500 },
  { userId: member, shareBps: 3500 },
];
async function propose(taskId: string, requestId: string) {
  return callAs(
    leader,
    (tx) => tx`
    select public.cmd_propose_task_shares(
      ${projectId}::uuid, ${taskId}::uuid, ${tx.json(shares)},
      ${requestId}::uuid, 1
    ) as result
  `,
  );
}

beforeAll(async () => {
  await db`insert into auth.users(id,email) values
    (${leader}, 'e-concurrency-leader@example.test'),
    (${member}, 'e-concurrency-member@example.test')`;
  await db`insert into public.projects(id,name,deadline_at,leader_id,created_by,contribution_mode)
    values(${projectId}, 'E concurrency isolated', now()+interval '20 days', ${leader}, ${leader}, 'weighted')`;
  await db`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
    values(${projectId}, ${leader}, 'leader', 'active', false),
    (${projectId}, ${member}, 'member', 'active', false)`;
  for (const taskId of tasks) {
    await db`insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,
      weight,accepted_at,completed_at,assignment_state)
      values(${taskId},${projectId},'Race task',${leader},${leader},
      now()+interval '10 days','completed',4,now()-interval '1 day',now(),'assigned')`;
    await db`insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
      values(${projectId},${taskId},${member},'accepted',now())`;
  }
}, 30000);

afterAll(async () => {
  await db.end();
});

describe("E governance isolation and concurrency", () => {
  it("one committed proposal for concurrent same idempotency key", async () => {
    const requestId = "e6400000-0000-0000-0000-000000000001";
    const results = await Promise.all([
      propose(tasks[0]!, requestId),
      propose(tasks[0]!, requestId),
    ]);
    expect(results.every((r) => r.ok)).toBe(true);
    expect(results.map((r) => r.replayed).sort()).toEqual([false, true]);
    const [row] = await db<
      { n: number }[]
    >`select count(*)::int n from public.task_share_proposals where task_id=${tasks[0]!}`;
    expect(row!.n).toBe(1);
  });

  it("two distinct concurrent proposal keys serialize with a stale-version loser", async () => {
    const results = await Promise.all([
      propose(tasks[1]!, "e6400000-0000-0000-0000-000000000002"),
      propose(tasks[1]!, "e6400000-0000-0000-0000-000000000003"),
    ]);
    expect(results.filter((r) => r.ok)).toHaveLength(1);
    expect(results.find((r) => !r.ok)?.code).toBe("STALE_VERSION");
    const [row] = await db<
      { n: number }[]
    >`select count(*)::int n from public.task_share_proposals where task_id=${tasks[1]!}`;
    expect(row!.n).toBe(1);
  });

  it("two service consumers atomically assess only one penalty", async () => {
    await db`
      insert into public.task_responsibility_epochs(
        id,project_id,task_id,responsible_user_id,accepted_at,
        effective_start_at,effective_deadline_at,free_abandon_until,
        deadline_revision,blocked_exempt,weight_snapshot,
        expected_share_bps_snapshot,shares_confirmed,
        accepted_expected_contribution,project_contribution_mode,
        auto_penalty_enabled_snapshot,trigger_source
      ) values(
        'e6500000-0000-0000-0000-000000000001',
        ${projectId},${tasks[0]!},${leader},
        '2026-10-09T00:00:00Z','2026-10-09T00:00:00Z',
        '2026-10-10T00:00:00Z','2026-10-09T02:24:00Z',
        1,false,4,6500,true,2.6000,'weighted',true,'concurrency_fixture'
      )
    `;
    const [event] = await db<{ id: string }[]>`
      insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data)
      values(${projectId},${leader},'task_first_submitted_late','task',${tasks[0]!},
        'e6400000-0000-0000-0000-000000000004',
        ${db.json({
          schemaVersion: 1,
          policyVersion: 1,
          occurrenceKey: `task:${tasks[0]!}:first_late`,
          occurredAt: "2026-10-10T02:24:00Z",
          aggregateVersion: 2,
          taskId: tasks[0],
          responsibleUserId: leader,
          responsibilityEpochId: "e6500000-0000-0000-0000-000000000001",
          effectiveStartAt: "2026-10-09T00:00:00Z",
          effectiveDeadlineAt: "2026-10-10T00:00:00Z",
          acceptedAt: "2026-10-09T00:00:00Z",
          freeAbandonUntil: "2026-10-09T02:24:00Z",
          firstSubmittedAt: "2026-10-10T02:24:00Z",
          blockedExempt: false,
          weightSnapshot: 4,
          expectedShareBpsSnapshot: 6500,
          acceptedExpectedContribution: "2.6000",
          projectContributionMode: "weighted",
          autoPenaltyEnabledSnapshot: true,
          triggerSource: "first_submission",
        })}) returning id::text
    `;
    async function consume() {
      return db.begin(async (tx) => {
        await tx`select set_config('request.jwt.claim.role', 'service_role', true)`;
        await tx.unsafe("set local role service_role");
        const [row] = await tx<
          { result: { ok: boolean; replayed: boolean } }[]
        >`
          select public.process_contribution_penalty_event_service(${event!.id}::bigint) as result`;
        return row!.result;
      });
    }
    const results = await Promise.all([consume(), consume()]);
    expect(results.every((r) => r.ok)).toBe(true);
    expect(results.filter((r) => r.replayed)).toHaveLength(1);
    const [row] = await db<
      { count: number }[]
    >`select count(*)::int as count from public.contribution_penalties
      where project_id=${projectId}`;
    expect(row!.count).toBe(1);
  });
});
