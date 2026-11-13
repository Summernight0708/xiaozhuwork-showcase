begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values('bc100000-0000-0000-0000-000000000001','g-life-fence@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
values('bc200000-0000-0000-0000-000000000001','G lifecycle fence',now()+interval '10 days',
 'bc100000-0000-0000-0000-000000000001','bc100000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state)
values('bc200000-0000-0000-0000-000000000001',
 'bc100000-0000-0000-0000-000000000001','leader','active');
select ok(private.is_active_member(
 'bc200000-0000-0000-0000-000000000001',
 'bc100000-0000-0000-0000-000000000001'),'active user starts with access');
insert into public.account_lifecycle_requests(user_id,state,generation,version,
 requested_at,cancel_until)
values('bc100000-0000-0000-0000-000000000001','pending',1,1,now(),now()+interval '30 days');
select ok(not private.is_active_member(
 'bc200000-0000-0000-0000-000000000001',
 'bc100000-0000-0000-0000-000000000001'),
 'pending account denied business reads even through definer helper');
select throws_ok(
 $$insert into public.command_requests(actor_id,command_name,request_id,payload_hash,project_id)
 values('bc100000-0000-0000-0000-000000000001','cmd_edit_task',
 'bc400000-0000-0000-0000-000000000001','\\x01'::bytea,
 'bc200000-0000-0000-0000-000000000001')$$,
 '42501','ACCOUNT_ACCESS_DISABLED','existing JWT cannot claim business writes');
select lives_ok(
 $$insert into public.command_requests(actor_id,command_name,request_id,payload_hash,account_id)
 values('bc100000-0000-0000-0000-000000000001','cmd_cancel_account_deletion',
 'bc400000-0000-0000-0000-000000000002','\\x01'::bytea,
 'bc100000-0000-0000-0000-000000000001')$$,
 'cancellation path remains allowed');
update public.account_lifecycle_requests set state='canceled',canceled_at=now(),version=2
where user_id='bc100000-0000-0000-0000-000000000001';
select ok(private.is_active_member(
 'bc200000-0000-0000-0000-000000000001',
 'bc100000-0000-0000-0000-000000000001'),
 'account reaccess after legal cancellation');
select * from finish();
rollback;
