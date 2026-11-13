/* global process, fetch, console */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import postgres from "postgres";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbUrl = process.env.SUPABASE_DB_URL;
const reminderSecret = process.env.TASK_REMINDER_CRON_SECRET;
const penaltySecret = process.env.CONTRIBUTION_PENALTY_CRON_SECRET;
if (
  url !== "http://127.0.0.1:55811" ||
  !/^postgresql:\/\/postgres:postgres@127\.0\.0\.1:55812\/postgres\?sslmode=disable$/.test(
    dbUrl ?? "",
  ) ||
  !key ||
  !reminderSecret ||
  reminderSecret.length < 32 ||
  !penaltySecret ||
  penaltySecret.length < 32
) {
  throw new Error(
    "Unsafe worker integration environment: require dedicated G Supabase",
  );
}
const db = postgres(dbUrl, { max: 3, ssl: false });
const leader = randomUUID();
const project = randomUUID();
const reminder = randomUUID();
const future = randomUUID();
const late = randomUUID();
const malformed = randomUUID();
const scope = "g-worker-" + randomUUID();

const headers = (scheduler, header) => ({
  Authorization: `Bearer ${key}`,
  apikey: key,
  "content-type": "application/json",
  [header]: scheduler,
});

async function invoke(name, scheduler, header) {
  const response = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: headers(scheduler, header),
    body: "{}",
  });
  const result = await response.json().catch(() => ({}));
  assert.equal(
    response.status,
    200,
    `${name} HTTP ${response.status}: ${JSON.stringify(result)}`,
  );
  assert.equal(result.ok, true, `${name}: ${JSON.stringify(result)}`);
  return result;
}

try {
  await db`insert into auth.users(id,email)
    values(${leader}::uuid,${scope + "@example.test"})`;
  await db`insert into public.projects(
      id,name,deadline_at,created_by,leader_id,contribution_mode,
      auto_penalty_enabled
    ) values (
      ${project}::uuid,'G nonempty worker HTTP proof',now()+interval '12 days',
      ${leader}::uuid,${leader}::uuid,'weighted',true
    )`;
  await db`insert into public.project_members(
      project_id,user_id,role,member_state,is_observer
    ) values(${project}::uuid,${leader}::uuid,'leader','active',false)`;
  await db`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,
      status,weight,assignment_state,version
    ) values
      (${reminder}::uuid,${project}::uuid,'G due reminder at 23h',
        ${leader}::uuid,${leader}::uuid,now()+interval '23 hours',
        'in_progress',2,'assigned',1),
      (${future}::uuid,${project}::uuid,'G not-yet-due reminder',
        ${leader}::uuid,${leader}::uuid,now()+interval '3 days',
        'in_progress',2,'assigned',1)`;
  // Only one 24-hour reminder is due; future jobs stay unprocessed.
  const firstReminder = await invoke(
    "task-deadline-reminders",
    reminderSecret,
    "x-task-reminder-secret",
  );
  assert.equal(firstReminder.delivered, 1, "real due job delivered once");
  const reminderNotifications = await db`
    select task_id,recipient_id,delivered_at from public.task_reminder_jobs
    where project_id=${project}::uuid and delivered_at is not null
  `;
  assert.equal(reminderNotifications.length, 1);
  assert.equal(reminderNotifications[0].task_id, reminder);
  assert.equal(reminderNotifications[0].recipient_id, leader);
  assert.ok(reminderNotifications[0].delivered_at);
  const notificationCount = await db`
    select count(*)::int as total from public.notifications
    where project_id=${project}::uuid and notification_type='task_deadline_reminder'
  `;
  assert.equal(notificationCount[0].total, 1);
  const repeatReminder = await invoke(
    "task-deadline-reminders",
    reminderSecret,
    "x-task-reminder-secret",
  );
  assert.equal(repeatReminder.delivered, 0, "HTTP retry delivers nothing");
  const repeated = await db`
    select count(*)::int as total from public.business_events
    where project_id=${project}::uuid and event_type='task_deadline_reminder'
  `;
  assert.equal(repeated[0].total, 1, "exactly one reminder business event");
  console.log(
    "PASS A nonempty Edge HTTP: due=1, future=0, retry=0, notification=1, event=1",
  );

  // One explicit policy and expected-share consent both predate responsibility
  // acceptance, allowing G's authoritative trigger to stamp the C epoch.
  await db`
    insert into public.project_penalty_policy_consents(
      project_id,member_user_id,consented_at,request_id
    ) values(
      ${project}::uuid,${leader}::uuid,now()-interval '5 days',${randomUUID()}::uuid
    )`;
  const dueDate = new Date(Date.now() - 24 * 3600 * 1000);
  await db`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,
      status,weight,assignment_state,version
    ) values(
      ${late}::uuid,${project}::uuid,'G explicitly consented late source',
      ${leader}::uuid,${leader}::uuid,${dueDate.toISOString()},
      'not_started',4,'pending_acceptance',1
    )`;
  await db`
    insert into public.task_expected_share_consents(
      project_id,task_id,member_user_id,expected_share_bps,task_version,
      weight_snapshot,deadline_snapshot,consented_at,request_id
    ) values(
      ${project}::uuid,${late}::uuid,${leader}::uuid,10000,1,4,
      ${dueDate.toISOString()},now()-interval '5 days',${randomUUID()}::uuid
    )`;
  const acceptedAt = new Date(Date.now() - 72 * 3600 * 1000);
  await db`update public.tasks
    set accepted_at=${acceptedAt.toISOString()},
        status='in_progress',assignment_state='assigned',version=2
    where id=${late}::uuid`;
  const [epoch] = await db`
    select id,accepted_at,effective_start_at,effective_deadline_at,
      blocked_exempt,shares_confirmed,expected_share_bps_snapshot,
      accepted_expected_contribution,weight_snapshot,auto_penalty_enabled_snapshot,
      project_contribution_mode
    from public.task_responsibility_epochs
    where task_id=${late}::uuid and closed_at is null
  `;
  assert.ok(epoch, "authoritative C epoch exists");
  assert.equal(
    epoch.shares_confirmed,
    true,
    "G explicit consent stamped BEFORE acceptance",
  );
  assert.equal(epoch.expected_share_bps_snapshot, 10000);
  assert.equal(Number(epoch.accepted_expected_contribution), 4);
  assert.equal(epoch.blocked_exempt, false);
  const lateAt = new Date(
    new Date(epoch.effective_deadline_at).getTime() + 4 * 3600 * 1000,
  );
  const eventData = {
    schemaVersion: 1,
    policyVersion: 1,
    occurrenceKey: `task:${late}:first_late`,
    taskId: late,
    responsibleUserId: leader,
    responsibilityEpochId: epoch.id,
    acceptedAt: epoch.accepted_at,
    effectiveStartAt: epoch.effective_start_at,
    effectiveDeadlineAt: epoch.effective_deadline_at,
    occurredAt: lateAt.toISOString(),
    firstSubmittedAt: lateAt.toISOString(),
    blockedExempt: false,
    weightSnapshot: 4,
    expectedShareBpsSnapshot: 10000,
    acceptedExpectedContribution: "4.0000",
    projectContributionMode: "weighted",
    autoPenaltyEnabledSnapshot: true,
    triggerSource: "first_submission",
  };
  await db`
    insert into public.business_events(
      project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data
    ) values(
      ${project}::uuid,${leader}::uuid,'task_first_submitted_late',
      'task',${late}::uuid,${randomUUID()}::uuid,${db.json(eventData)}
    )`;

  // Deliberately invalid source: must be quarantined, never penalized.
  await db`insert into public.tasks(
      id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
      assignment_state
    ) values(
      ${malformed}::uuid,${project}::uuid,'G unsigned source must be quarantined',
      ${leader}::uuid,${leader}::uuid,now()+interval '4 days',
      'in_progress',2,'assigned'
    )`;
  await db`
    insert into public.business_events(
      project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data
    ) values(
      ${project}::uuid,${leader}::uuid,'task_first_submitted_late','task',
      ${malformed}::uuid,${randomUUID()}::uuid,
      ${db.json({
        schemaVersion: 1,
        policyVersion: 1,
        taskId: malformed,
        responsibleUserId: leader,
        occurrenceKey: `task:${malformed}:first_late`,
        // Intentionally missing responsibilityEpochId and signed snapshots.
      })}
    )`;
  const firstPenalty = await invoke(
    "dispatch-contribution-penalties",
    penaltySecret,
    "x-contribution-penalty-secret",
  );
  assert.equal(firstPenalty.summary.processed, 2);
  assert.equal(firstPenalty.summary.assessed, 1);
  assert.equal(firstPenalty.summary.quarantined, 1);
  const penaltyRows = await db`
    select task_id,amount::text as amount,rate::text as rate
    from public.contribution_penalties where project_id=${project}::uuid
  `;
  assert.equal(penaltyRows.length, 1);
  assert.equal(penaltyRows[0].task_id, late);
  assert.equal(penaltyRows[0].amount, "-0.4000", "4 base × 10% late penalty");
  const [fault] = await db`
    select f.last_error from private.followup_g_penalty_dispatch_faults f
    join public.business_events e on e.id=f.source_event_id
    where e.project_id=${project}::uuid and e.entity_id=${malformed}::uuid
  `;
  assert.equal(fault?.last_error, "UNVERIFIED_SOURCE_EPOCH");
  const secondPenalty = await invoke(
    "dispatch-contribution-penalties",
    penaltySecret,
    "x-contribution-penalty-secret",
  );
  assert.equal(secondPenalty.summary.processed, 0, "idempotent drain");
  const [finalPenalties] = await db`
    select count(*)::int as total from public.contribution_penalties
    where project_id=${project}::uuid
  `;
  assert.equal(finalPenalties.total, 1);
  console.log(
    "PASS E nonempty Edge HTTP: verified consent assessed -0.4000 once, unsigned source quarantined, retry=0",
  );
} finally {
  await db.end({ timeout: 5 });
}
