begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('c1100000-0000-0000-0000-000000000001','g-consent-safety-leader@example.test'),
 ('c1100000-0000-0000-0000-000000000002','g-consent-safety-original@example.test'),
 ('c1100000-0000-0000-0000-000000000003','g-consent-safety-late@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id,
 contribution_mode,auto_penalty_enabled)
values('c1200000-0000-0000-0000-000000000001','G new member consent quarantine',
 now()+interval '12 days',
 'c1100000-0000-0000-0000-000000000001',
 'c1100000-0000-0000-0000-000000000001','weighted',true);
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
 ('c1200000-0000-0000-0000-000000000001',
  'c1100000-0000-0000-0000-000000000001','leader','active',false),
 ('c1200000-0000-0000-0000-000000000001',
  'c1100000-0000-0000-0000-000000000002','member','active',false);
insert into public.project_penalty_policy_consents(
 project_id,member_user_id,consented_at,request_id)
values
 ('c1200000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001',
 now()-interval '1 day','c1400000-0000-0000-0000-000000000001'),
 ('c1200000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000002',
 now()-interval '1 day','c1400000-0000-0000-0000-000000000002');
insert into public.tasks(id,project_id,title,created_by,assignee_id,
 deadline_at,status,weight,assignment_state,version)
values ('c1300000-0000-0000-0000-000000000001',
 'c1200000-0000-0000-0000-000000000001','Before new member',
 'c1100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001',
 now()+interval '8 days','not_started',4,'pending_acceptance',1);
insert into public.task_expected_share_consents(
 project_id,task_id,member_user_id,expected_share_bps,task_version,
 weight_snapshot,deadline_snapshot,consented_at,request_id)
select t.project_id,t.id,t.assignee_id,10000,t.version,t.weight,t.deadline_at,
 now()-interval '1 hour','c1400000-0000-0000-0000-000000000003'
from public.tasks t where t.id='c1300000-0000-0000-0000-000000000001';
update public.tasks set accepted_at=now(),status='in_progress',
 assignment_state='assigned',version=2
where id='c1300000-0000-0000-0000-000000000001';
select ok((select shares_confirmed from public.task_responsibility_epochs
 where task_id='c1300000-0000-0000-0000-000000000001' and closed_at is null),
 'already confirmed pre-entry epoch remains an immutable accepted agreement');

-- A third person joins AFTER policy activation but never opted in.
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
values('c1200000-0000-0000-0000-000000000001',
 'c1100000-0000-0000-0000-000000000003','member','active',false);
insert into public.tasks(id,project_id,title,created_by,assignee_id,
 deadline_at,status,weight,assignment_state,version)
values ('c1300000-0000-0000-0000-000000000002',
 'c1200000-0000-0000-0000-000000000001','After new member',
 'c1100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001',
 now()+interval '8 days','not_started',3,'pending_acceptance',1);
insert into public.task_expected_share_consents(
 project_id,task_id,member_user_id,expected_share_bps,task_version,
 weight_snapshot,deadline_snapshot,consented_at,request_id)
select t.project_id,t.id,t.assignee_id,10000,t.version,t.weight,t.deadline_at,
 now()-interval '1 hour','c1400000-0000-0000-0000-000000000004'
from public.tasks t where t.id='c1300000-0000-0000-0000-000000000002';
update public.tasks set accepted_at=now(),status='in_progress',
 assignment_state='assigned',version=2
where id='c1300000-0000-0000-0000-000000000002';
select ok(not (select shares_confirmed from public.task_responsibility_epochs
 where task_id='c1300000-0000-0000-0000-000000000002' and closed_at is null),
 'new policy-unconsented project member blocks new epoch penalty eligibility');

insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,
 request_id,event_data)
select t.project_id,t.assignee_id,'task_first_submitted_late','task',t.id,
 'c1400000-0000-0000-0000-000000000005',
 jsonb_build_object(
  'schemaVersion',1,'policyVersion',1,
  'occurrenceKey','task:'||t.id::text||':first_late',
  'taskId',t.id,'responsibleUserId',t.assignee_id,
  'responsibilityEpochId',e.id,
  'acceptedAt',e.accepted_at,'effectiveStartAt',e.effective_start_at,
  'effectiveDeadlineAt',e.effective_deadline_at,
  'occurredAt',e.effective_deadline_at+interval '1 day',
  'firstSubmittedAt',e.effective_deadline_at+interval '1 day',
  'blockedExempt',e.blocked_exempt,
  'expectedShareBpsSnapshot',10000,
  'acceptedExpectedContribution','3.0000',
  'weightSnapshot',t.weight,'projectContributionMode','weighted',
  'autoPenaltyEnabledSnapshot',true
 )
from public.tasks t join public.task_responsibility_epochs e on e.task_id=t.id
where t.id='c1300000-0000-0000-0000-000000000002' and e.closed_at is null;

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(
 (public.process_contribution_penalty_event_service(
  (select id from public.business_events where request_id='c1400000-0000-0000-0000-000000000005')
 )->>'code'),'UNVERIFIED_CONSENT_SNAPSHOT',
 'service worker quarantines source without exact confirmed project/member consent');
reset role;
select is((select count(*)::integer from public.contribution_penalties where project_id='c1200000-0000-0000-0000-000000000001'),
 0,'unconsented project cannot incur a penalty');

select * from finish();
rollback;
