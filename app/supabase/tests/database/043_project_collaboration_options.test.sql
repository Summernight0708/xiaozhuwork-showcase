begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('e1100000-0000-0000-0000-000000000001','options-leader@example.test'),
 ('e1100000-0000-0000-0000-000000000002','options-admin@example.test'),
 ('e1100000-0000-0000-0000-000000000003','options-member@example.test'),
 ('e1100000-0000-0000-0000-000000000004','options-observer@example.test');

insert into public.projects(
 id,name,timezone,deadline_at,contribution_mode,auto_penalty_enabled,
 require_real_name,require_student_number,leader_id,created_by,version
) values (
 'e2100000-0000-0000-0000-000000000001','Options project','Asia/Shanghai',
 now()+interval '20 days','weighted',false,false,false,
 'e1100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('e3100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('e3100000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000002','admin','active',false,1),
 ('e3100000-0000-0000-0000-000000000003','e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000003','member','active',false,1),
 ('e3100000-0000-0000-0000-000000000004','e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','observer','active',true,1);

select ok((select allow_member_task_creation from public.projects where id='e2100000-0000-0000-0000-000000000001'),'existing projects default to allowing members');
create temporary table option_results(label text primary key, result jsonb);
grant all on option_results to authenticated;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into option_results values('before',public.cmd_create_task(
 'e2100000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000001',1,
 'Member allowed',null,now()+interval '2 days',2::smallint,'claimable',null,null
));
reset role;
select is((select result->>'ok' from option_results where label='before'),'true','member creates tasks by default');

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into option_results values('disable',public.cmd_update_project_settings(
 p_project_id => 'e2100000-0000-0000-0000-000000000001',
 p_request_id => 'e9100000-0000-0000-0000-000000000002',
 p_expected_version => 2,
 p_name => 'Options project',p_course_name => null,p_description => null,
 p_deadline_at => (select deadline_at from public.projects where id='e2100000-0000-0000-0000-000000000001'),
 p_timezone => 'Asia/Shanghai',p_contribution_mode => 'weighted',
 p_auto_penalty_enabled => false,p_require_real_name => false,
 p_require_student_number => false,p_allow_member_task_creation => false
));
reset role;
select is((select result->>'ok' from option_results where label='disable'),'true','leader disables member task creation');
select ok(not (select allow_member_task_creation from public.projects where id='e2100000-0000-0000-0000-000000000001'),'setting persists');

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into option_results values('member-denied',public.cmd_create_task(
 'e2100000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000003',3,
 'Member denied',null,now()+interval '2 days',2::smallint,'claimable',null,null
));
reset role;
select is((select result->>'code' from option_results where label='member-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','server refuses member even when bypassing UI');

set local role authenticated;
select is(public.cmd_create_task(
 'e2100000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000001',1,
 'Member allowed',null,now()+interval '2 days',2::smallint,'claimable',null,null
)->>'replayed','true','completed create still replays after disabling member creation');
select is(public.cmd_claim_task(
 'e2100000-0000-0000-0000-000000000001',
 (select (result#>>'{data,taskId}')::uuid from option_results where label='before'),
 'e9100000-0000-0000-0000-000000000007',1
)->>'ok','true','disabling creation does not stop members claiming existing work');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into option_results values('admin-allowed',public.cmd_create_task(
 'e2100000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000004',3,
 'Admin allowed',null,now()+interval '2 days',2::smallint,'claimable',null,null
));
reset role;
select is((select result->>'ok' from option_results where label='admin-allowed'),'true','admin retains task-creation privilege');

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into option_results values('observer-denied',public.cmd_create_task(
 'e2100000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000005',4,
 'Observer denied',null,now()+interval '2 days',2::smallint,'claimable',null,null
));
reset role;
select is((select result->>'code' from option_results where label='observer-denied'),'NOT_AUTHORIZED','observer remains read-only');

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into option_results values('enable',public.cmd_update_project_settings(
 p_project_id => 'e2100000-0000-0000-0000-000000000001',
 p_request_id => 'e9100000-0000-0000-0000-000000000006',
 p_expected_version => 4,
 p_name => 'Options project',p_course_name => null,p_description => null,
 p_deadline_at => (select deadline_at from public.projects where id='e2100000-0000-0000-0000-000000000001'),
 p_timezone => 'Asia/Shanghai',p_contribution_mode => 'weighted',
 p_auto_penalty_enabled => false,p_require_real_name => false,
 p_require_student_number => false,p_allow_member_task_creation => true
));
reset role;
select is((select result->>'ok' from option_results where label='enable'),'true','leader re-enables member task creation');

select * from finish();
rollback;
