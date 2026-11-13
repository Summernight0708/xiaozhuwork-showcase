begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_function('private','f2_mask_report_members',array['jsonb'],'F2 report privacy helper exists');
select ok(not has_function_privilege('authenticated','public.get_project_report_export_f2_unmasked(uuid)','EXECUTE'),'authenticated cannot call unmasked export');
select ok(not has_function_privilege('anon','public.get_project_report_export_f2_unmasked(uuid)','EXECUTE'),'anon cannot call unmasked export');
select ok(has_function_privilege('authenticated','public.get_project_report_export(uuid)','EXECUTE'),'safe export keeps authenticated grant');
select ok(not has_function_privilege('authenticated','private.f2_mask_report_members(jsonb)','EXECUTE'),'masking helper remains private');
insert into auth.users(id,email) values
 ('f6300000-0000-0000-0000-000000000001','f2-pending@example.test'),
 ('f6300000-0000-0000-0000-000000000002','f2-canceled@example.test'),
 ('f6300000-0000-0000-0000-000000000003','f2-active@example.test');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until,canceled_at)
 values
 ('f6300000-0000-0000-0000-000000000001','pending',1,1,now()-interval '1 day',now()+interval '29 days',null),
 ('f6300000-0000-0000-0000-000000000002','canceled',1,2,now()-interval '2 days',now()+interval '28 days',now()-interval '1 day');
select is((private.f2_mask_report_members('[{"memberUserId":"f6300000-0000-0000-0000-000000000001","memberDisplayName":"Original Name","contributionValueAuthority":"2.6000"}]'::jsonb)->0->>'memberDisplayName'),'已注销成员','pending member masked');
select is((private.f2_mask_report_members('[{"memberUserId":"f6300000-0000-0000-0000-000000000001","memberDisplayName":"Original Name","contributionValueAuthority":"2.6000"}]'::jsonb)->0->>'contributionValueAuthority'),'2.6000','contribution numeric amount untouched');
select is((private.f2_mask_report_members('[{"memberUserId":"f6300000-0000-0000-0000-000000000002","memberDisplayName":"Active Again"}]'::jsonb)->0->>'memberDisplayName'),'Active Again','canceled request name remains visible');
select is((private.f2_mask_report_members('[{"memberUserId":"f6300000-0000-0000-0000-000000000003","memberDisplayName":"Active Member"}]'::jsonb)->0->>'memberDisplayName'),'Active Member','unaffected member name remains');
select is((private.f2_mask_report_members('[{"memberUserId":"malformed","memberDisplayName":"Legacy"}]'::jsonb)->0->>'memberDisplayName'),'Legacy','malformed historical ID fails safe');
select is(private.f2_mask_report_members('{"code":"DENIED"}'::jsonb)::text,'{"code": "DENIED"}','error payload unchanged');
select is((select state from public.account_lifecycle_requests where user_id='f6300000-0000-0000-0000-000000000001'),'pending','no lifecycle mutation');
select ok(not has_column_privilege('authenticated','public.contribution_items','member_display_name_snapshot','SELECT'),'legacy raw name snapshot not available to authenticated');
select ok(has_column_privilege('authenticated','public.contribution_items','share','SELECT'),'legacy numeric contribution column remains readable');
select ok(not has_column_privilege('authenticated','public.contribution_report_member_ledger_entries','member_name_snapshot','SELECT'),'G ledger raw name snapshot not available to authenticated');
select ok(has_column_privilege('authenticated','public.contribution_report_member_ledger_entries','signed_amount','SELECT'),'G ledger signed amount remains readable');

-- Authoritative RPC integration: legacy report content is still numerically
-- stable but no longer exports the pending member's immutable name snapshot.
insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
 values('f6400000-0000-0000-0000-000000000001','F2 sandbox team',
        now()+interval '10 days',
        'f6300000-0000-0000-0000-000000000003',
        'f6300000-0000-0000-0000-000000000003','weighted');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values
 ('f6400000-0000-0000-0000-000000000001','f6300000-0000-0000-0000-000000000003','leader','active',false),
 ('f6400000-0000-0000-0000-000000000001','f6300000-0000-0000-0000-000000000001','member','active',false);
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,
 status,weight,accepted_at,completed_at,assignment_state,version)
 values('f6500000-0000-0000-0000-000000000001',
 'f6400000-0000-0000-0000-000000000001','F2 completed task',
 'f6300000-0000-0000-0000-000000000003',
 'f6300000-0000-0000-0000-000000000003',
 now()+interval '3 days','completed',4,now()-interval '2 days',
 now()-interval '1 day','assigned',1);
insert into public.contribution_reports(id,project_id,state,contribution_mode,
 source_project_version,eligible_member_count,required_confirmation_count,created_by)
 values('f6600000-0000-0000-0000-000000000001',
 'f6400000-0000-0000-0000-000000000001','draft','weighted',1,2,2,
 'f6300000-0000-0000-0000-000000000003');
insert into public.contribution_items(report_id,project_id,task_id,member_user_id,
 member_display_name_snapshot,task_weight,share,contribution_value,
 task_title_snapshot,completed_at_snapshot)
 values('f6600000-0000-0000-0000-000000000001',
 'f6400000-0000-0000-0000-000000000001',
 'f6500000-0000-0000-0000-000000000001',
 'f6300000-0000-0000-0000-000000000001',
 'Original Sensitive Name',4.0000,1.0000,4.0000,'F2 completed task',now()-interval '1 day');
create temp table f2_visible_export(payload jsonb);
grant insert,select on f2_visible_export to authenticated;
select set_config('request.jwt.claim.sub','f6300000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f2_visible_export
  select public.get_project_report_export('f6600000-0000-0000-0000-000000000001');
reset role;
select is((select payload->'items'->0->>'memberDisplayName' from f2_visible_export),
 '已注销成员','actual authorized export masks immutable historical name');
select is((select payload->'items'->0->>'contributionValueAuthority' from f2_visible_export),
 '4.0000','actual authorized export preserves original contribution amount');
select is((select member_display_name_snapshot from public.contribution_items
 where report_id='f6600000-0000-0000-0000-000000000001'),
 'Original Sensitive Name','immutable raw ledger snapshot is never modified');
select * from finish();
rollback;
