begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email)
values ('aa100000-0000-0000-0000-000000000001','g-archive@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
values('aa200000-0000-0000-0000-000000000001','G archive guard',
  now()+interval '20 days','aa100000-0000-0000-0000-000000000001',
  'aa100000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values ('aa200000-0000-0000-0000-000000000001',
  'aa100000-0000-0000-0000-000000000001','leader','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status)
values ('aa300000-0000-0000-0000-000000000001',
  'aa200000-0000-0000-0000-000000000001','Guard task',
  'aa100000-0000-0000-0000-000000000001',
  'aa100000-0000-0000-0000-000000000001',now()+interval '10 days','in_progress');

-- Archive via real B command; verify direct writes fail even as postgres (definer).
select set_config('request.jwt.claim.sub','aa100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_archive_project(
  'aa200000-0000-0000-0000-000000000001','G readonly test',
  'aa400000-0000-0000-0000-000000000001',1)->>'ok','true',
  'leader can archive under G write barrier');
reset role;
select throws_ok(
  $$update public.tasks set title='bad' where id='aa300000-0000-0000-0000-000000000001'$$,
  'P0001','PROJECT_NOT_ACTIVE','legacy task writes blocked even for definer role');
select throws_ok(
  $$insert into public.tasks(project_id,title,created_by,deadline_at) values(
  'aa200000-0000-0000-0000-000000000001','bad',
  'aa100000-0000-0000-0000-000000000001',now()+interval '1 day')$$,
  'P0001','PROJECT_NOT_ACTIVE','legacy task insertion blocked');
select throws_ok(
  $$delete from public.tasks where id='aa300000-0000-0000-0000-000000000001'$$,
  'P0001','PROJECT_NOT_ACTIVE','legacy task deletion blocked');
select throws_ok(
  $$update public.projects set name='bad' where id='aa200000-0000-0000-0000-000000000001'$$,
  'P0001','PROJECT_NOT_ACTIVE','legacy project updates blocked');
select set_config('request.jwt.claim.sub','aa100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(public.cmd_restore_project('aa200000-0000-0000-0000-000000000001',
  'aa400000-0000-0000-0000-000000000002',2)->>'ok','true',
  'restore remains authorized');
reset role;
update public.tasks set title='after restore'
where id='aa300000-0000-0000-0000-000000000001';
select is((select title from public.tasks where id='aa300000-0000-0000-0000-000000000001'),
  'after restore','task writable after restoration');
select * from finish();
rollback;
