begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('b1000000-0000-0000-0000-000000000001','closure-leader@example.test'),
 ('b1000000-0000-0000-0000-000000000002','closure-member@example.test'),
 ('b1000000-0000-0000-0000-000000000003','closure-applicant@example.test');

insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version,lifecycle_state)
values('b2000000-0000-0000-0000-000000000001','Frozen project',now()+interval '10 days','weighted',
       'b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',5,'contribution_review');
insert into public.project_members(project_id,user_id,role,member_state) values
 ('b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','leader','active'),
 ('b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,completed_at,version)
values('b3000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','Frozen task',
       'b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002',
       now()+interval '2 days','completed',2,'assigned',now()-interval '2 hours',now()-interval '1 hour',1);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at,version)
values
 ('b4000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',
  extensions.digest(convert_to('closure-direct','utf8'),'sha256'),'direct',now()+interval '7 days',1),
 ('b4000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',
  extensions.digest(convert_to('closure-approval','utf8'),'sha256'),'approval',now()+interval '7 days',1);
insert into public.project_join_requests(id,invitation_id,project_id,user_id,state,version)
values('b5000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000002',
       'b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','pending',1);

create temporary table closure_results(label text primary key,result jsonb);
grant all on closure_results to authenticated;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into closure_results values
 ('new-task',public.cmd_create_task('b2000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000001',5,'Late task',null,now()+interval '1 day',1::smallint,'claimable',null)),
 ('new-invite',public.cmd_create_project_invite('b2000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000002',5,'direct',7,1)),
 ('approve-pending',public.cmd_review_project_join_request('b2000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-000000000001','approve','b6000000-0000-0000-0000-000000000003',1));
reset role;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into closure_results values
 ('direct-join',public.cmd_join_project_via_invite('closure-direct','b6000000-0000-0000-0000-000000000004',1));
reset role;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into closure_results values
 ('reserve-file',public.cmd_reserve_task_file_upload(
  'b2000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000005',1,'new_file',null,'late.txt','text/plain',20));
reset role;

select is((select result->>'code' from closure_results where label='new-task'),'PROJECT_NOT_ACTIVE','contribution review blocks new tasks');
select is((select result->>'code' from closure_results where label='new-invite'),'PROJECT_NOT_ACTIVE','contribution review blocks new invitations');
select is((select result->>'code' from closure_results where label='approve-pending'),'PROJECT_NOT_ACTIVE','contribution review blocks approving pending membership');
select is((select result->>'code' from closure_results where label='direct-join'),'PROJECT_NOT_ACTIVE','contribution review blocks direct membership');
select is((select result->>'code' from closure_results where label='reserve-file'),'PROJECT_NOT_ACTIVE','contribution review blocks new file reservations');
select is((select count(*)::integer from public.tasks where project_id='b2000000-0000-0000-0000-000000000001'),1,'closure failures create no extra task');
select is((select count(*)::integer from public.project_members where project_id='b2000000-0000-0000-0000-000000000001'),2,'closure failures create no extra member');
select is((select count(*)::integer from public.file_upload_reservations where project_id='b2000000-0000-0000-0000-000000000001'),0,'closure failures create no upload reservation');
select is((select count(*)::integer from public.business_events where request_id in (
 'b6000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000002',
 'b6000000-0000-0000-0000-000000000003','b6000000-0000-0000-0000-000000000004',
 'b6000000-0000-0000-0000-000000000005')),0,'closure failures emit no business events');

-- New Day 4 RPC NULLs are decoded as stable domain failures.
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select lives_ok($$select public.cmd_create_contribution_report('b2000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000006',null)$$,'NULL expected version returns a domain result');
select lives_ok($$select public.cmd_review_task_submission('b2000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001',null,null,null,'b6000000-0000-0000-0000-000000000007',null)$$,'NULL review inputs return a domain result');
reset role;

-- Read RLS hides Day 4 closure tables from outsiders.
insert into public.contribution_reports(id,project_id,state,contribution_mode,source_project_version,eligible_member_count,required_confirmation_count,created_by,version)
values('b7000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','draft','weighted',5,2,2,'b1000000-0000-0000-0000-000000000001',1);
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is((select count(*)::integer from public.contribution_reports where id='b7000000-0000-0000-0000-000000000001'),0,'outsider cannot read contribution report row');
select throws_ok($$update public.contribution_reports set version=99 where id='b7000000-0000-0000-0000-000000000001'$$,'42501',null,'authenticated cannot bypass report command by table DML');
reset role;

-- Active-project NULL enum inputs must return stable domain failures, not raw
-- NOT NULL/CHECK exceptions through SECURITY DEFINER functions.
insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('b2000000-0000-0000-0000-000000000002','Active NULL boundary',now()+interval '10 days','weighted',
       'b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
 ('b2000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001','leader','active'),
 ('b2000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('b3000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002','NULL status task',
       'b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002',
       now()+interval '5 days','in_progress',1,'assigned',now(),1);
create temporary table closure_null_results(label text primary key,result jsonb);
grant all on closure_null_results to authenticated;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select lives_ok(
  $$insert into closure_null_results values('invite-mode',public.cmd_create_project_invite(
    'b2000000-0000-0000-0000-000000000002','b6000000-0000-0000-0000-000000000008',1,null,null,null))$$,
  'NULL invite mode returns a domain result'
);
select lives_ok(
  $$insert into closure_null_results values('assignment-mode',public.cmd_create_task(
    'b2000000-0000-0000-0000-000000000002','b6000000-0000-0000-0000-000000000009',1,
    'NULL assignment mode',null,now()+interval '1 day',1::smallint,null,null))$$,
  'NULL assignment mode returns a domain result'
);
select lives_ok(
  $$insert into closure_null_results values('null-request',public.cmd_create_project_invite(
    'b2000000-0000-0000-0000-000000000002',null,1,'direct',null,null))$$,
  'NULL request id returns a domain result'
);
select lives_ok(
  $$insert into closure_null_results values('create-project-null-request',public.cmd_create_project(
    null,0,'Should not be created',now()+interval '5 days',null,null,null,'weighted',false,false))$$,
  'NULL create-project request id returns a domain result'
);
reset role;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select lives_ok(
  $$insert into closure_null_results values('task-status',public.cmd_update_task_progress(
    'b2000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000002',
    'b6000000-0000-0000-0000-000000000010',1,null,'still working',null))$$,
  'NULL task status returns a domain result'
);
reset role;

select is((select result->>'code' from closure_null_results where label='invite-mode'),'VALIDATION_FAILED','NULL invite mode is a stable validation failure');
select is((select result->>'code' from closure_null_results where label='assignment-mode'),'VALIDATION_FAILED','NULL assignment mode is a stable validation failure');
select is((select result->>'code' from closure_null_results where label='task-status'),'VALIDATION_FAILED','NULL task status is a stable validation failure');
select is((select result->>'code' from closure_null_results where label='null-request'),'VALIDATION_FAILED','NULL request id is a stable validation failure');
select is((select result->>'code' from closure_null_results where label='create-project-null-request'),'VALIDATION_FAILED','NULL create-project request id is a stable validation failure');
select is((select count(*)::integer from public.projects where name='Should not be created'),0,'NULL create-project request id creates no project');

select * from finish();
rollback;
