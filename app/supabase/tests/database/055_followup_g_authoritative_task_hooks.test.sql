begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- A genuine existing assignment update, not fabricated E JSON, creates C's epoch.
insert into auth.users(id,email) values
 ('ab100000-0000-0000-0000-000000000001','g-responsible@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
values('ab200000-0000-0000-0000-000000000001','G epoch transitions',
 now()+interval '10 days',
 'ab100000-0000-0000-0000-000000000001',
 'ab100000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values('ab200000-0000-0000-0000-000000000001',
 'ab100000-0000-0000-0000-000000000001','leader','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,assignment_state)
values('ab300000-0000-0000-0000-000000000001',
 'ab200000-0000-0000-0000-000000000001','Acceptance hook',
 'ab100000-0000-0000-0000-000000000001',
 'ab100000-0000-0000-0000-000000000001',
 now()+interval '7 days','in_progress','assigned');
update public.tasks set accepted_at=now()-interval '1 hour'
where id='ab300000-0000-0000-0000-000000000001';
select is(
 (select count(*)::integer from public.task_responsibility_epochs
  where task_id='ab300000-0000-0000-0000-000000000001' and closed_at is null),
 1,'acceptance transition records exactly one current C epoch');
select is(
 (select count(*)::integer from public.task_responsibility_epochs
  where task_id='ab300000-0000-0000-0000-000000000001'
  and expected_share_bps_snapshot is null and shares_confirmed is false),
 1,'G never fabricates an unconfirmed expected share');
update public.tasks set accepted_at=accepted_at+interval '1 minute',version=version+1
where id='ab300000-0000-0000-0000-000000000001';
select is(
 (select count(*)::integer from public.task_responsibility_epochs
  where task_id='ab300000-0000-0000-0000-000000000001'),
 2,'reaccepted responsibility closes previous epoch');
select is(
 (select count(*)::integer from public.task_responsibility_epochs
  where task_id='ab300000-0000-0000-0000-000000000001' and closed_at is not null),
 1,'superseded epoch remains auditable');
-- An existing authoritative submission RPC emits the event and records C's
-- first submission fact in the same transaction, without client-provided snapshots.
select set_config('request.jwt.claim.sub','ab100000-0000-0000-0000-000000000001',true);
set local role authenticated;
create temp table g_submission_result(payload jsonb);
insert into g_submission_result(payload)
select public.cmd_submit_task_for_review(
 'ab200000-0000-0000-0000-000000000001',
 'ab300000-0000-0000-0000-000000000001','G real first text submission',
 '{}'::uuid[],'ab400000-0000-0000-0000-000000000001',2
);
reset role;
select is((select payload->>'ok' from g_submission_result),'true',
 'actual first submission command succeeds');
select is((select count(*)::integer from public.task_first_submission_facts
 where task_id='ab300000-0000-0000-0000-000000000001'),1,
 'first task submission fact derived automatically from authoritative event');
select is((select count(*)::integer from public.business_events
 where project_id='ab200000-0000-0000-0000-000000000001'
 and event_type='task_submitted_for_review'),1,
 'one canonical first-review submission event');

select * from finish();
rollback;
