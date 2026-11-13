begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_table('public','task_share_rejections','immutable rejection audit exists');
select has_function('public','cmd_reject_task_shares',array['uuid','uuid','text','uuid','integer'],
 'rejection RPC installed');
select ok(not has_table_privilege('authenticated','public.task_share_rejections','INSERT')
 and not has_table_privilege('authenticated','public.task_share_rejections','UPDATE'),
 'clients cannot forge or rewrite rejection audit');

insert into auth.users(id,email) values
 ('e7100000-0000-0000-0000-000000000001','e-reject-primary@example.test'),
 ('e7100000-0000-0000-0000-000000000002','e-reject-member@example.test');
insert into public.projects(id,name,deadline_at,leader_id,created_by,contribution_mode)
 values ('e7200000-0000-0000-0000-000000000001','E rejection',
 now()+interval '14 days','e7100000-0000-0000-0000-000000000001',
 'e7100000-0000-0000-0000-000000000001','weighted');
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
 ('e7200000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000001','leader','active',false),
 ('e7200000-0000-0000-0000-000000000001','e7100000-0000-0000-0000-000000000002','member','active',false);
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,
 weight,accepted_at,completed_at,assignment_state,version)
 values ('e7300000-0000-0000-0000-000000000001','e7200000-0000-0000-0000-000000000001',
 'Collaborative task','e7100000-0000-0000-0000-000000000001',
 'e7100000-0000-0000-0000-000000000001',now()+interval '6 days',
 'completed',4,now()-interval '2 days',now()-interval '1 day','assigned',1);
insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
 values('e7200000-0000-0000-0000-000000000001','e7300000-0000-0000-0000-000000000001',
 'e7100000-0000-0000-0000-000000000002','accepted',now());
create temporary table e_reject_results(label text primary key,result jsonb);
grant all on e_reject_results to authenticated;

select set_config('request.jwt.claim.sub','e7100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into e_reject_results values('proposal',public.cmd_propose_task_shares(
 'e7200000-0000-0000-0000-000000000001','e7300000-0000-0000-0000-000000000001',
 '[{"userId":"e7100000-0000-0000-0000-000000000001","shareBps":7000},{"userId":"e7100000-0000-0000-0000-000000000002","shareBps":3000}]',
 'e7400000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'ok' from e_reject_results where label='proposal'),'true','primary creates proposal');

select set_config('request.jwt.claim.sub','e7100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into e_reject_results values('reject',public.cmd_reject_task_shares(
 'e7200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from e_reject_results where label='proposal'),
 'I did more than thirty percent',
 'e7400000-0000-0000-0000-000000000002',1));
reset role;
select is((select result->>'ok' from e_reject_results where label='reject'),'true','member may reject with reason');
select is((select status from public.task_share_proposals where task_id='e7300000-0000-0000-0000-000000000001'),'superseded','rejected proposal superseded');
select is((select reason from public.task_share_rejections where proposal_id in (select id from public.task_share_proposals where task_id='e7300000-0000-0000-0000-000000000001')),'I did more than thirty percent','reason immutable');
select is((select count(*)::integer from public.task_contribution_ledger where task_id='e7300000-0000-0000-0000-000000000001'),0,'rejected shares do not become ledger');
select is((select shares_ready from public.project_contribution_share_readiness where project_id='e7200000-0000-0000-0000-000000000001'),false,'report readiness blocked');

select set_config('request.jwt.claim.sub','e7100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into e_reject_results values('revision',public.cmd_propose_task_shares(
 'e7200000-0000-0000-0000-000000000001','e7300000-0000-0000-0000-000000000001',
 '[{"userId":"e7100000-0000-0000-0000-000000000001","shareBps":6000},{"userId":"e7100000-0000-0000-0000-000000000002","shareBps":4000}]',
 'e7400000-0000-0000-0000-000000000003',2));
reset role;
select is((select result->>'ok' from e_reject_results where label='revision'),'true','primary may propose revised shares');
select is((select max(revision) from public.task_share_proposals where task_id='e7300000-0000-0000-0000-000000000001'),2,'rejection history preserved');
select is((select count(*)::integer from public.task_contribution_ledger where task_id='e7300000-0000-0000-0000-000000000001'),0,'revision requires fresh confirmation');
select * from finish();
rollback;
