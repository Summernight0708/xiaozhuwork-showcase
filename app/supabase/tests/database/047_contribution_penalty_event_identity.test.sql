begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email)
values ('e8100000-0000-0000-0000-000000000001','e-worker-two-events@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
values ('e8200000-0000-0000-0000-000000000001','E per-event request scoping',
 now()+interval '10 days','e8100000-0000-0000-0000-000000000001',
 'e8100000-0000-0000-0000-000000000001','weighted');
insert into public.project_members(project_id,user_id,role,member_state)
values('e8200000-0000-0000-0000-000000000001',
 'e8100000-0000-0000-0000-000000000001','leader','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
 accepted_at,completed_at,assignment_state)
values('e8300000-0000-0000-0000-000000000001',
 'e8200000-0000-0000-0000-000000000001','Penalty events',
 'e8100000-0000-0000-0000-000000000001',
 'e8100000-0000-0000-0000-000000000001',
 now()+interval '8 days','completed',4,now()-interval '2 days',now(),'assigned');

-- Synthetic signed C epoch fixture for per-source-event idempotency.
insert into public.task_responsibility_epochs(
 id,project_id,task_id,responsible_user_id,accepted_at,
 effective_start_at,effective_deadline_at,free_abandon_until,
 deadline_revision,blocked_exempt,weight_snapshot,
 expected_share_bps_snapshot,shares_confirmed,accepted_expected_contribution,
 project_contribution_mode,auto_penalty_enabled_snapshot,trigger_source)
values('e8500000-0000-0000-0000-000000000001',
 'e8200000-0000-0000-0000-000000000001',
 'e8300000-0000-0000-0000-000000000001',
 'e8100000-0000-0000-0000-000000000001',
 '2026-10-09T00:00:00Z','2026-10-09T00:00:00Z',
 '2026-10-10T00:00:00Z','2026-10-09T02:24:00Z',
 1,false,4,10000,true,4.0000,'weighted',true,'fixture_signed_acceptance');
-- Same command request, two distinct authoritative events with independent occurrence keys.
insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data)
select 'e8200000-0000-0000-0000-000000000001',
 'e8100000-0000-0000-0000-000000000001',
 kind,'task','e8300000-0000-0000-0000-000000000001',
 'e8400000-0000-0000-0000-000000000001',
 jsonb_build_object('schemaVersion',1,'policyVersion',1,
 'taskId','e8300000-0000-0000-0000-000000000001',
 'responsibleUserId','e8100000-0000-0000-0000-000000000001',
 'responsibilityEpochId','e8500000-0000-0000-0000-000000000001',
 'effectiveStartAt','2026-10-09T00:00:00Z','effectiveDeadlineAt','2026-10-10T00:00:00Z',
 'acceptedAt','2026-10-09T00:00:00Z','freeAbandonUntil','2026-10-09T02:24:00Z',
 'blockedExempt',false,'weightSnapshot',4,'expectedShareBpsSnapshot',10000,
 'acceptedExpectedContribution','4.0000','projectContributionMode','weighted',
 'autoPenaltyEnabledSnapshot',true,'aggregateVersion',2) ||
 case when kind='task_first_submitted_late' then
   jsonb_build_object('occurrenceKey','task:e8300000-0000-0000-0000-000000000001:first_late',
    'occurredAt','2026-10-10T02:24:00Z','firstSubmittedAt','2026-10-10T02:24:00Z')
 else
   jsonb_build_object('occurrenceKey','responsibility:e8500000-0000-0000-0000-000000000001:abandon',
    'occurredAt','2026-10-09T02:24:01Z')
 end
from (values ('task_first_submitted_late'),('task_responsibility_abandoned')) a(kind);

create temp table e_multi_event_result(kind text,result jsonb);
grant all on e_multi_event_result to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into e_multi_event_result(kind,result)
select event_type,public.process_contribution_penalty_event_service(id)
 from public.business_events where project_id='e8200000-0000-0000-0000-000000000001'
  and event_type in ('task_first_submitted_late','task_responsibility_abandoned')
order by id;
reset role;
select is((select count(*)::integer from e_multi_event_result where result->>'disposition'='assessed'),
 2,'two source events in one command each assessed');
select is((select count(*)::integer from public.contribution_penalties
 where project_id='e8200000-0000-0000-0000-000000000001'),2,
 'two unique penalty facts inserted');
select is((select count(*)::integer from public.business_events
 where project_id='e8200000-0000-0000-0000-000000000001'
   and event_type='contribution_penalty_assessed'),2,
 'worker command idempotency key does not collide across event_seq');
select is((select count(distinct request_id)::integer from public.business_events
 where project_id='e8200000-0000-0000-0000-000000000001'
   and event_type='contribution_penalty_assessed'),2,
 'worker keys are stable and unique per source event');
select * from finish();
rollback;
