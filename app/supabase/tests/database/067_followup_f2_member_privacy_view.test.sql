begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_view('public','project_members_visible','member privacy view exists');
select ok(not has_column_privilege('authenticated','public.project_members','display_name_snapshot','SELECT'),'raw snapshot cannot be read via Data API');
select ok(has_column_privilege('authenticated','public.project_members','project_id','SELECT'),'raw membership metadata still accessible');
select ok(not has_column_privilege('authenticated','public.contribution_items','member_user_id','SELECT'),'raw legacy contributor UUID inaccessible');
select ok(not has_column_privilege('authenticated','public.contribution_report_member_ledger_entries','member_user_id','SELECT'),'raw G contributor UUID inaccessible');

insert into auth.users(id,email) values
 ('f6700000-0000-0000-0000-000000000001','privacy-leader@example.test'),
 ('f6700000-0000-0000-0000-000000000002','privacy-pending@example.test'),
 ('f6700000-0000-0000-0000-000000000003','privacy-outsider@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
 values('f6800000-0000-0000-0000-000000000001','Privacy project',
 now()+interval '7 days','f6700000-0000-0000-0000-000000000001',
 'f6700000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state,is_observer,display_name_snapshot)
 values
 ('f6800000-0000-0000-0000-000000000001','f6700000-0000-0000-0000-000000000001',
 'leader','active',false,'Active Leader'),
 ('f6800000-0000-0000-0000-000000000001','f6700000-0000-0000-0000-000000000002',
 'member','active',false,'Private Pending Member');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until)
 values('f6700000-0000-0000-0000-000000000002',
 'pending',1,1,now()-interval '1 day',now()+interval '29 days');

-- Avoid role-switching pgtap, insert into a temp table while under auth and
-- assert captured results after returning to the test runner's privileged role.
create temp table f2_member_capture(id uuid, display_name_snapshot text);
grant all on f2_member_capture to authenticated;
select set_config('request.jwt.claim.sub','f6700000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f2_member_capture
 select id,display_name_snapshot from public.project_members_visible where project_id='f6800000-0000-0000-0000-000000000001';
reset role;
select is((select display_name_snapshot from f2_member_capture where id=(
 select id from public.project_members where user_id='f6700000-0000-0000-0000-000000000002')),'已注销成员','member view masks other user pending deletion');
select is((select display_name_snapshot from f2_member_capture where id=(
 select id from public.project_members where user_id='f6700000-0000-0000-0000-000000000001')),'Active Leader','active member retains display name');
select is((select display_name_snapshot from public.project_members where user_id='f6700000-0000-0000-0000-000000000002'),'Private Pending Member','historical audit snapshot remains preserved');

truncate f2_member_capture;
select set_config('request.jwt.claim.sub','f6700000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f2_member_capture
 select id,display_name_snapshot from public.project_members_visible where project_id='f6800000-0000-0000-0000-000000000001';
reset role;
select is((select count(*)::integer from f2_member_capture),0,'outsider cannot enumerate project membership');

select is(private.f2_mask_report_members('[{"memberUserId":"f6700000-0000-0000-0000-000000000002","memberDisplayName":"Private Pending Member","contributionValueAuthority":"4.0000"}]'::jsonb)->0->'memberUserId','null'::jsonb,'report removes member UUID for pending deletion');
select is(private.f2_mask_report_members('[{"memberUserId":"f6700000-0000-0000-0000-000000000002","memberDisplayName":"Private Pending Member","contributionValueAuthority":"4.0000"}]'::jsonb)->0->>'contributionValueAuthority','4.0000','report amount unchanged');

select * from finish();
rollback;
