/* global process, console */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import postgres from "postgres";

const dbUrl = process.env.SUPABASE_DB_URL;
if (
  !dbUrl ||
  !/^postgresql:\/\/postgres:postgres@127\.0\.0\.1:55812\/postgres\?sslmode=disable$/.test(
    dbUrl,
  )
) {
  throw new Error(
    "G concurrency test requires the exact isolated 55812 postgres",
  );
}
const db = postgres(dbUrl, { max: 6, ssl: false, connect_timeout: 6 });
const leader = randomUUID(),
  collaborator = randomUUID();
const project = randomUUID(),
  task = randomUUID();
const request = randomUUID();
const input = [
  { userId: leader, shareBps: 6500 },
  { userId: collaborator, shareBps: 3500 },
];
const asUser = async (userId, query) =>
  db.begin(async (tx) => {
    await tx`select set_config('request.jwt.claim.sub', ${userId}, true)`;
    await tx.unsafe("set local role authenticated");
    return await query(tx);
  });

try {
  await db`insert into auth.users(id,email) values
    (${leader}::uuid,${"g-conc-" + leader + "@example.test"}),
    (${collaborator}::uuid,${"g-conc-" + collaborator + "@example.test"})`;
  await db`insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
    values(${project}::uuid,'G real simultaneous 65/35',now()+interval '14 days',
    ${leader}::uuid,${leader}::uuid,'weighted')`;
  await db`insert into public.project_members(project_id,user_id,role,member_state,is_observer)
    values(${project}::uuid,${leader}::uuid,'leader','active',false),
          (${project}::uuid,${collaborator}::uuid,'member','active',false)`;
  await db`insert into public.tasks(id,project_id,title,assignee_id,created_by,deadline_at,
    status,weight,accepted_at,completed_at,assignment_state,version)
    values(${task}::uuid,${project}::uuid,'G concurrent accepted task',
      ${leader}::uuid,${leader}::uuid,now()+interval '8 days',
      'completed',4,now()-interval '3 days',now()-interval '1 day','assigned',1)`;
  await db`insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
    values(${project}::uuid,${task}::uuid,${collaborator}::uuid,'accepted',now())`;

  async function propose() {
    const rows = await asUser(
      leader,
      (tx) => tx`
      select public.cmd_propose_task_shares(${project}::uuid,${task}::uuid,
        ${tx.json(input)},${request}::uuid,1) as result`,
    );
    return rows[0].result;
  }
  const [a, b] = await Promise.all([propose(), propose()]);
  assert.equal(a.ok, true, JSON.stringify(a));
  assert.equal(b.ok, true, JSON.stringify(b));
  assert.notEqual(
    a.replayed,
    b.replayed,
    "exactly one proposal is new; other replays",
  );
  const proposalId = a.data.proposalId;
  const proposedCount =
    await db`select count(*)::int as total from public.task_share_proposals
    where project_id=${project}::uuid and task_id=${task}::uuid`;
  assert.equal(
    proposedCount[0].total,
    1,
    "concurrent retry created one proposal",
  );
  async function confirm(userId, id, version) {
    const rows = await asUser(
      userId,
      (tx) => tx`
      select public.cmd_confirm_task_shares(
        ${project}::uuid,${proposalId}::uuid,${id}::uuid,${version}) as result`,
    );
    assert.equal(rows[0].result.ok, true, JSON.stringify(rows[0].result));
  }
  await confirm(leader, randomUUID(), 1);
  await confirm(collaborator, randomUUID(), 2);
  const sums = await db`select sum(amount)::numeric(12,4)::text as amount,
    count(*)::int as count from public.task_authoritative_contributions
    where project_id=${project}::uuid`;
  assert.equal(sums[0].amount, "4.0000");
  assert.equal(sums[0].count, 2);
  console.log(
    "PASS isolated two-connection retry race: one proposal, two confirmations, 4.0000 pool",
  );
} finally {
  await db.end({ timeout: 5 });
}
