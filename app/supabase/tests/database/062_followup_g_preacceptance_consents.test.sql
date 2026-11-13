begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('bf100000-0000-0000-0000-000000000001','g-penalty-optin-leader@example.test'),
 ('bf100000-0000-0000-0000-000000000002','g-penalty-optin-member@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
values('bf200000-0000-0000-0000-000000000001','G explicit penalty agreement',
 now()+interval '12 days',
 'bf100000-0000-0000-0000-000000000001',
 'bf100000-0000-0000-0000-000000000001','weighted');
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
 ('bf200000-0000-0000-0000-000000000001',
  'bf100000-0000-0000-0000-000000000001','leader','active',false),
 ('bf200000-0000-0000-0000-000000000001',
  'bf100000-0000-0000-0000-000000000002','member','active',false);
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_set_project_auto_penalty_policy(
 'bf200000-0000-0000-0000-000000000001',true,
 'bf400000-0000-0000-0000-000000000001',1)->>'code','CONSENT_REQUIRED',
 'project penalty cannot enable without member agreement');
select is(public.cmd_consent_auto_penalty_policy(
 'bf200000-0000-0000-0000-000000000001',
 'bf400000-0000-0000-0000-000000000002',1)->>'ok','true',
 'leader independently consents to policy v1');
reset role;
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(public.cmd_consent_auto_penalty_policy(
 'bf200000-0000-0000-0000-000000000001',
 'bf400000-0000-0000-0000-000000000003',1)->>'ok','true',
 'member independently consents to policy v1');
reset role;
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_set_project_auto_penalty_policy(
 'bf200000-0000-0000-0000-000000000001',true,
 'bf400000-0000-0000-0000-000000000004',1)->>'ok','true',
 'leader enables penalty only after all participants consent');
reset role;
insert into public.tasks(id,project_id,title,created_by,assignee_id,
 deadline_at,status,weight,assignment_state,version)
values ('bf300000-0000-0000-0000-000000000001',
 'bf200000-0000-0000-0000-000000000001','Explicit share first',
 'bf100000-0000-0000-0000-000000000001',
 'bf100000-0000-0000-0000-000000000001',
 now()+interval '8 days','not_started',4,'pending_acceptance',1),
 ('bf300000-0000-0000-0000-000000000002',
 'bf200000-0000-0000-0000-000000000001','No silent 100pct',
 'bf100000-0000-0000-0000-000000000001',
 'bf100000-0000-0000-0000-000000000001',
 now()+interval '8 days','not_started',3,'pending_acceptance',1);
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_consent_task_expected_share(
 'bf200000-0000-0000-0000-000000000001',
 'bf300000-0000-0000-0000-000000000001',
 10000,'bf400000-0000-0000-0000-000000000005',1)->>'ok','true',
 'assignee explicitly consents before acceptance');
reset role;
update public.tasks set accepted_at=now(),status='in_progress',
 assignment_state='assigned',version=2
where id='bf300000-0000-0000-0000-000000000001';
select is((select expected_share_bps_snapshot from public.task_responsibility_epochs
 where task_id='bf300000-0000-0000-0000-000000000001' and closed_at is null),
 10000,'accepted epoch stores explicit 100% not inferred');
select is((select accepted_expected_contribution::text
 from public.task_responsibility_epochs
 where task_id='bf300000-0000-0000-0000-000000000001' and closed_at is null),
 '4.0000','accepted amount frozen to task weight');
select ok((select shares_confirmed from public.task_responsibility_epochs
 where task_id='bf300000-0000-0000-0000-000000000001' and closed_at is null),
 'explicit share is confirmed during genuine acceptance');
update public.tasks set accepted_at=now(),status='in_progress',
 assignment_state='assigned',version=2
where id='bf300000-0000-0000-0000-000000000002';
select ok(not (select shares_confirmed from public.task_responsibility_epochs
 where task_id='bf300000-0000-0000-0000-000000000002' and closed_at is null),
 'no consent means no penalty-eligible snapshot');
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_consent_task_expected_share(
 'bf200000-0000-0000-0000-000000000001',
 'bf300000-0000-0000-0000-000000000001',
 10000,'bf400000-0000-0000-0000-000000000006',2)->>'code',
 'CONSENT_MUST_PRECEDE_ACCEPTANCE',
 'retroactive share consent is forbidden');
reset role;
insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
values('bf200000-0000-0000-0000-000000000001',
 'bf300000-0000-0000-0000-000000000001',
 'bf100000-0000-0000-0000-000000000002','accepted',now());
select ok((select blocked_exempt from public.task_responsibility_epochs
 where task_id='bf300000-0000-0000-0000-000000000001' and closed_at is null),
 'new teammate invalidates previously consented epoch for penalty purposes');
select * from finish();
rollback;
