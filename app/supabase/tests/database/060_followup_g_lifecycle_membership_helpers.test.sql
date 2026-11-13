begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('bd100000-0000-0000-0000-000000000001','g-helper-account@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
values ('bd200000-0000-0000-0000-000000000001','G helpers',
 now()+interval '10 days','bd100000-0000-0000-0000-000000000001',
 'bd100000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values ('bd200000-0000-0000-0000-000000000001',
 'bd100000-0000-0000-0000-000000000001','leader','active');
select set_config('request.jwt.claim.sub','bd100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select ok(public.is_active_project_member('bd200000-0000-0000-0000-000000000001'),
 'active user can resolve membership');
reset role;
insert into public.account_lifecycle_requests(user_id,state,generation,version,
 requested_at,cancel_until)
values('bd100000-0000-0000-0000-000000000001','pending',1,1,
 now(),now()+interval '30 days');
select ok(not private.is_active_leader(
 'bd200000-0000-0000-0000-000000000001',
 'bd100000-0000-0000-0000-000000000001'),
 'old pending leader JWT denied');
select ok(not private.is_active_non_observer_member(
 'bd200000-0000-0000-0000-000000000001',
 'bd100000-0000-0000-0000-000000000001'),
 'pending member denied');
select set_config('request.jwt.claim.sub','bd100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select ok(not public.is_active_project_member(
 'bd200000-0000-0000-0000-000000000001'),
 'public security definer membership reader fails closed');
select is(public.get_account_lifecycle_status()#>>'{data,state}','pending',
 'pending status remains observable for cancellation');
reset role;
select * from finish();
rollback;
