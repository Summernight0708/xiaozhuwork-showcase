begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_column('public','contribution_reports','snapshot_basis','G report basis recorded');
select has_table('public','contribution_report_member_ledger_entries',
 'G report per-member ledger snapshot table exists');
select ok((select count(*)::integer from public.contribution_reports
 where state='formal' and snapshot_basis<>'legacy_single_assignee')=0,
 'existing formal historical reports retain original basis');
select ok(not has_function_privilege('authenticated',
  'public.get_project_report_export_legacy(uuid)','EXECUTE'),
 'browser cannot bypass new ledger export via legacy helper');
select ok(has_function_privilege('authenticated',
  'public.get_project_report_export(uuid)','EXECUTE'),
 'exports remain accessible through authoritative wrapper');
select ok((select count(*) from pg_trigger
  where tgname='g_report_formal_readiness_on_update')=1,
 'formalization requires additional G readiness check');

-- End-to-end weighted distribution: proposal and independent confirmation are
-- authoritative; the exported ledger must not use a single assignee fallback.
insert into auth.users(id,email) values
 ('bb100000-0000-0000-0000-000000000001','g-report-leader@example.test'),
 ('bb100000-0000-0000-0000-000000000002','g-report-collab@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
values ('bb200000-0000-0000-0000-000000000001','G team report',now()+interval '15 days',
 'bb100000-0000-0000-0000-000000000001','bb100000-0000-0000-0000-000000000001','weighted');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
values
 ('bb200000-0000-0000-0000-000000000001','bb100000-0000-0000-0000-000000000001','leader','active',false),
 ('bb200000-0000-0000-0000-000000000001','bb100000-0000-0000-0000-000000000002','member','active',false);
insert into public.tasks(id,project_id,title,assignee_id,created_by,deadline_at,status,weight,
 accepted_at,completed_at,assignment_state,version)
values('bb300000-0000-0000-0000-000000000001','bb200000-0000-0000-0000-000000000001',
 'G four-star shared task','bb100000-0000-0000-0000-000000000001',
 'bb100000-0000-0000-0000-000000000001',now()+interval '12 days','completed',4,
 now()-interval '2 days',now()-interval '1 day','assigned',1);
insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
values('bb200000-0000-0000-0000-000000000001','bb300000-0000-0000-0000-000000000001',
 'bb100000-0000-0000-0000-000000000002','accepted',now()-interval '1 day');
create temp table g_report_cmd(name text primary key,result jsonb);
grant all on g_report_cmd to authenticated;
select set_config('request.jwt.claim.sub','bb100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into g_report_cmd values ('propose',public.cmd_propose_task_shares(
 'bb200000-0000-0000-0000-000000000001','bb300000-0000-0000-0000-000000000001',
 '[{"userId":"bb100000-0000-0000-0000-000000000001","shareBps":6500},{"userId":"bb100000-0000-0000-0000-000000000002","shareBps":3500}]',
 'bb400000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'ok' from g_report_cmd where name='propose'),'true','real 65/35 proposal accepted');
select set_config('request.jwt.claim.sub','bb100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into g_report_cmd values ('confirm-leader',public.cmd_confirm_task_shares(
 'bb200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from g_report_cmd where name='propose'),
 'bb400000-0000-0000-0000-000000000002',1));
reset role;
select set_config('request.jwt.claim.sub','bb100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into g_report_cmd values ('confirm-collab',public.cmd_confirm_task_shares(
 'bb200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from g_report_cmd where name='propose'),
 'bb400000-0000-0000-0000-000000000003',2));
reset role;
select is((select result->>'ok' from g_report_cmd where name='confirm-collab'),'true',
 'collaborator explicitly confirms 35%');
select set_config('request.jwt.claim.sub','bb100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into g_report_cmd values ('report',public.cmd_create_contribution_report(
 'bb200000-0000-0000-0000-000000000001',
 'bb400000-0000-0000-0000-000000000004',
 (select version from public.projects where id='bb200000-0000-0000-0000-000000000001')));
reset role;
select is((select result->>'ok' from g_report_cmd where name='report'),'true',
 'legacy report creation RPC accepts fully confirmed G ledger');
select is((select snapshot_basis from public.contribution_reports where project_id='bb200000-0000-0000-0000-000000000001'),
 'member_ledger_v1','new report captures independent authoritative member-ledger snapshot');
select is((select count(*)::integer from public.contribution_report_member_ledger_entries
 where project_id='bb200000-0000-0000-0000-000000000001'),2,
 'new report captures two members, not single assignee');
select is((select sum(signed_amount)::numeric(12,4)::text
 from public.contribution_report_member_ledger_entries
 where project_id='bb200000-0000-0000-0000-000000000001'),
 '4.0000','four-star pool is conserved in immutable report snapshot');
select is((select signed_amount::text from public.contribution_report_member_ledger_entries
 where project_id='bb200000-0000-0000-0000-000000000001'
 and member_user_id='bb100000-0000-0000-0000-000000000001'),'2.6000',
 '65% contribution is preserved at four decimal precision');
select set_config('request.jwt.claim.sub','bb100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(jsonb_array_length(public.get_project_report_export(
 (select id from public.contribution_reports
  where project_id='bb200000-0000-0000-0000-000000000001'))->'items'),
 2,'basic and enhanced export source contains both member entries');
select is(jsonb_array_length(public.get_project_contribution_report(
 'bb200000-0000-0000-0000-000000000001')->'items'),
 2,'contribution page presents both contributors');
reset role;

select * from finish();
rollback;
