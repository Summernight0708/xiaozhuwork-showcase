begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('be100000-0000-0000-0000-000000000001','g-active-leader@example.test'),
 ('be100000-0000-0000-0000-000000000002','g-pending-member@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
values('be200000-0000-0000-0000-000000000001','G responsibility safety',
 now()+interval '15 days','be100000-0000-0000-0000-000000000001',
 'be100000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values
 ('be200000-0000-0000-0000-000000000001','be100000-0000-0000-0000-000000000001','leader','active'),
 ('be200000-0000-0000-0000-000000000001','be100000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,assignment_state)
values('be300000-0000-0000-0000-000000000001',
 'be200000-0000-0000-0000-000000000001','Active leader task',
 'be100000-0000-0000-0000-000000000001',
 'be100000-0000-0000-0000-000000000001',now()+interval '7 days','in_progress','assigned');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until)
values('be100000-0000-0000-0000-000000000002','pending',1,1,now(),now()+interval '30 days');
select throws_ok(
 $$update public.tasks set assignee_id='be100000-0000-0000-0000-000000000002'
 where id='be300000-0000-0000-0000-000000000001'$$,
 '42501','ACCOUNT_ACCESS_DISABLED','leader cannot assign new responsibility to pending account');
select throws_ok(
 $$insert into public.task_collaborators(project_id,task_id,user_id,state)
 values('be200000-0000-0000-0000-000000000001',
 'be300000-0000-0000-0000-000000000001',
 'be100000-0000-0000-0000-000000000002','pending')$$,
 '42501','ACCOUNT_ACCESS_DISABLED','leader cannot invite pending collaborator');
select lives_ok(
 $$update public.tasks set title='Valid leader edit'
 where id='be300000-0000-0000-0000-000000000001'$$,
 'ordinary active actor can still edit existing task');
update public.account_lifecycle_requests
 set state='canceled',canceled_at=now(),version=2
 where user_id='be100000-0000-0000-0000-000000000002';
select lives_ok(
 $$insert into public.task_collaborators(project_id,task_id,user_id,state)
 values('be200000-0000-0000-0000-000000000001',
 'be300000-0000-0000-0000-000000000001',
 'be100000-0000-0000-0000-000000000002','pending')$$,
 'recovered account can be invited again');
select * from finish();
rollback;
