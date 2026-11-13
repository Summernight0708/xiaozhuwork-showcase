begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, email)
select ('50000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       'boundary-' || i || '@example.test'
from generate_series(1, 15) as s(i);
update public.profiles set display_name='Boundary User', real_name='Boundary Real', student_number='B1';

create temporary table boundary_results (label text primary key, result jsonb);
grant all on boundary_results to authenticated, anon;

-- facts_only accepts no weight, rejects a supplied weight, and enforces the project deadline.
insert into public.projects (id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values ('61000000-0000-0000-0000-000000000001','Facts only',now()+interval '10 days','facts_only','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state)
values ('61000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','leader','active');
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into boundary_results values
('facts-task-ok',public.cmd_create_task('61000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000001',1,'Facts task',null,now()+interval '2 days',null,'claimable',null)),
('facts-task-weight',public.cmd_create_task('61000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000002',2,'Weighted facts task',null,now()+interval '2 days',1::smallint,'claimable',null)),
('task-after-project',public.cmd_create_task('61000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000003',2,'Late task',null,now()+interval '11 days',null,'claimable',null));
reset role;
select is((select result->>'ok' from boundary_results where label='facts-task-ok'),'true','facts_only task without weight succeeds');
select is((select result->>'code' from boundary_results where label='facts-task-weight'),'VALIDATION_FAILED','facts_only rejects task weight');
select is((select result->>'code' from boundary_results where label='task-after-project'),'DDL_NOT_IN_FUTURE','task deadline cannot exceed project deadline');
select is((select version from public.projects where id='61000000-0000-0000-0000-000000000001'),2,'failed task commands do not advance project version');

-- Required identity fields are enforced before direct membership.
insert into public.projects (id,name,deadline_at,require_real_name,require_student_number,leader_id,created_by)
values ('61000000-0000-0000-0000-000000000002','Identity project',now()+interval '10 days',true,true,'50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values ('61000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001','leader','active');
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values ('63000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001',extensions.digest(convert_to('identity-token','utf8'),'sha256'),'direct',now()+interval '7 days');
update public.profiles set real_name=null, student_number=null where id='50000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into boundary_results values ('identity-missing',public.cmd_join_project_via_invite('identity-token','62000000-0000-0000-0000-000000000004',1));
reset role;
select is((select result->>'code' from boundary_results where label='identity-missing'),'CONFIRMATION_REQUIRED','required identity blocks join');
select is((select result->>'field' from boundary_results where label='identity-missing'),'realName','identity failure identifies first missing field');

-- Existing approval applications survive natural expiry and can still be approved.
insert into public.projects (id,name,deadline_at,leader_id,created_by)
values ('61000000-0000-0000-0000-000000000003','Expiry approval',now()+interval '10 days','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values ('61000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001','leader','active');
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values ('63000000-0000-0000-0000-000000000003','61000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001',extensions.digest(convert_to('expiry-token','utf8'),'sha256'),'approval',now()+interval '1 day');
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into boundary_results values ('expiry-apply',public.cmd_join_project_via_invite('expiry-token','62000000-0000-0000-0000-000000000005',0));
reset role;
select (result->'data'->>'joinRequestId')::uuid as expiry_request_id from boundary_results where label='expiry-apply' \gset
update public.project_invitations set expires_at=now()-interval '1 hour' where id='63000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into boundary_results values ('expiry-approve',public.cmd_review_project_join_request('61000000-0000-0000-0000-000000000003',:'expiry_request_id','approve','62000000-0000-0000-0000-000000000006',1));
reset role;
select is((select result->>'ok' from boundary_results where label='expiry-approve'),'true','pending application remains approvable after natural expiry');

-- max uses and member capacity are enforced under the project/invitation locks.
insert into public.projects (id,name,deadline_at,leader_id,created_by)
values ('61000000-0000-0000-0000-000000000004','Max uses',now()+interval '10 days','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'),
       ('61000000-0000-0000-0000-000000000005','Member cap',now()+interval '10 days','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state) values
('61000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-000000000001','leader','active'),
('61000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-000000000001','leader','active');
insert into public.project_members(project_id,user_id,role,member_state)
select '61000000-0000-0000-0000-000000000005',('50000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,'member','active'
from generate_series(2,8) s(i);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at,max_uses) values
('63000000-0000-0000-0000-000000000004','61000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-000000000001',extensions.digest(convert_to('max-token','utf8'),'sha256'),'direct',now()+interval '7 days',1),
('63000000-0000-0000-0000-000000000005','61000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-000000000001',extensions.digest(convert_to('cap-token','utf8'),'sha256'),'direct',now()+interval '7 days',null);
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into boundary_results values ('max-first',public.cmd_join_project_via_invite('max-token','62000000-0000-0000-0000-000000000007',1));
reset role;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into boundary_results values ('max-second',public.cmd_join_project_via_invite('max-token','62000000-0000-0000-0000-000000000008',2));
reset role;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000009',true);
set local role authenticated;
insert into boundary_results values ('member-cap',public.cmd_join_project_via_invite('cap-token','62000000-0000-0000-0000-000000000009',1));
reset role;
select is((select result->>'code' from boundary_results where label='max-second'),'INVITE_EXHAUSTED','invitation max uses is enforced');
select is((select result->>'code' from boundary_results where label='member-cap'),'PROJECT_MEMBER_LIMIT_REACHED','eight-member project cap is enforced');

-- Active task and active project caps are enforced.
insert into public.projects(id,name,deadline_at,leader_id,created_by) values
('61000000-0000-0000-0000-000000000006','Task cap',now()+interval '10 days','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values ('61000000-0000-0000-0000-000000000006','50000000-0000-0000-0000-000000000001','leader','active');
insert into public.tasks(project_id,title,created_by,deadline_at,weight)
select '61000000-0000-0000-0000-000000000006','Existing task '||i,'50000000-0000-0000-0000-000000000001',now()+interval '2 days',1
from generate_series(1,20) s(i);
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into boundary_results values ('task-cap',public.cmd_create_task('61000000-0000-0000-0000-000000000006','62000000-0000-0000-0000-00000000000a',1,'Twenty first',null,now()+interval '2 days',1::smallint,'claimable',null));
reset role;
select is((select result->>'code' from boundary_results where label='task-cap'),'CONCURRENT_TASK_LIMIT_REACHED','twenty-active-task project cap is enforced');

insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('61000000-0000-0000-0000-00000000000'||substr('789ab',i,1))::uuid,'Cap project '||i,now()+interval '10 days','50000000-0000-0000-0000-000000000010','50000000-0000-0000-0000-000000000010'
from generate_series(1,5) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select id,'50000000-0000-0000-0000-000000000010','leader','active' from public.projects where created_by='50000000-0000-0000-0000-000000000010';
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000010',true);
set local role authenticated;
insert into boundary_results values ('project-cap',public.cmd_create_project('62000000-0000-0000-0000-00000000000b',0,'Sixth project',now()+interval '10 days',null,null,null,null,null,null));
reset role;
select is((select result->>'code' from boundary_results where label='project-cap'),'ACTIVE_FREE_PROJECT_LIMIT_REACHED','five-active-project account cap is enforced');
select ok(not exists(select 1 from public.projects where name='Sixth project'),'project cap failure has no state side effect');

-- Progress validation, unauthenticated rejection, RLS, and direct-write denial.
insert into public.projects(id,name,deadline_at,leader_id,created_by) values
('61000000-0000-0000-0000-00000000000c','Progress security',now()+interval '10 days','50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state) values
('61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000001','leader','active'),
('61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000011','member','active');
insert into public.tasks(id,project_id,title,created_by,deadline_at,status,weight,assignment_state,assignee_id,accepted_at)
values ('64000000-0000-0000-0000-00000000000c','61000000-0000-0000-0000-00000000000c','Progress task','50000000-0000-0000-0000-000000000001',now()+interval '2 days','in_progress',1,'assigned','50000000-0000-0000-0000-000000000011',now());
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000011',true);
set local role authenticated;
insert into boundary_results values ('blocked-no-reason',public.cmd_update_task_progress('61000000-0000-0000-0000-00000000000c','64000000-0000-0000-0000-00000000000c','62000000-0000-0000-0000-00000000000c',1,'blocked','Blocked update',null));
reset role;
select is((select result->>'code' from boundary_results where label='blocked-no-reason'),'VALIDATION_FAILED','blocked progress requires a reason');
select is((select count(*)::integer from public.business_events where request_id='62000000-0000-0000-0000-00000000000c'),0,'invalid blocked progress emits no event');

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
insert into boundary_results values ('unauthenticated',public.cmd_create_project('62000000-0000-0000-0000-00000000000d',0,'No auth',now()+interval '2 days',null,null,null,null,null,null));
reset role;
select is((select result->>'code' from boundary_results where label='unauthenticated'),'UNAUTHENTICATED','write RPC rejects missing auth uid');

insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values ('63000000-0000-0000-0000-00000000000c','61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000001',extensions.digest(convert_to('rls-token','utf8'),'sha256'),'approval',now()+interval '7 days');
insert into public.project_join_requests(id,invitation_id,project_id,user_id,display_name_snapshot)
values ('65000000-0000-0000-0000-00000000000c','63000000-0000-0000-0000-00000000000c','61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000012','Applicant');
insert into public.task_assignment_offers(id,task_id,project_id,target_user_id,created_by)
values ('66000000-0000-0000-0000-00000000000c','64000000-0000-0000-0000-00000000000c','61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000012','50000000-0000-0000-0000-000000000001');

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is((select display_name_snapshot from public.project_join_requests_visible where id='65000000-0000-0000-0000-00000000000c'),'Applicant','leader can read the applicant display-name snapshot');
select is((select count(*)::integer from public.profiles where id='50000000-0000-0000-0000-000000000012'),0,'leader still cannot read the applicant profile');
reset role;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000012',true);
set local role authenticated;
select is((select count(*)::integer from public.project_join_requests_visible where id='65000000-0000-0000-0000-00000000000c'),1,'join applicant can read own request');
select is((select count(*)::integer from public.task_assignment_offers where id='66000000-0000-0000-0000-00000000000c'),1,'offer target can read own offer');
reset role;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000013',true);
set local role authenticated;
select is((select count(*)::integer from public.project_join_requests_visible where id='65000000-0000-0000-0000-00000000000c'),0,'outsider cannot read join request');
select is((select count(*)::integer from public.task_assignment_offers where id='66000000-0000-0000-0000-00000000000c'),0,'outsider cannot read assignment offer');
select throws_ok($$insert into public.project_join_requests(invitation_id,project_id,user_id) values('63000000-0000-0000-0000-00000000000c','61000000-0000-0000-0000-00000000000c','50000000-0000-0000-0000-000000000013')$$,'42501',null,'authenticated client cannot directly insert join request');
select throws_ok($$update public.tasks set progress_text='bypass' where id='64000000-0000-0000-0000-00000000000c'$$,'42501',null,'authenticated client cannot directly update core task');
reset role;

-- Every successful command-backed mutation has an ordered event linked to its ledger row.
select ok(not exists(
  select 1 from public.business_events e
  left join public.command_requests c on c.id=e.command_request_id
  where e.command_request_id is not null and (c.id is null or e.request_id is distinct from c.request_id or e.event_seq is null)
),'business events remain linked to their command request and sequence');
select ok(not exists(
  select 1 from public.command_requests c
  where c.state='completed' and c.result->>'ok'='true'
    and not exists(select 1 from public.business_events e where e.command_request_id=c.id)
),'every successful write command emits at least one linked event');

select * from finish();
rollback;
