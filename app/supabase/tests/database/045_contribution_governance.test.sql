begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_share_proposals','share proposals installed');
select has_table('public','task_contribution_ledger','authoritative immutable ledger installed');
select has_table('public','contribution_penalties','immutable penalty ledger installed');
select has_function('public','cmd_propose_task_shares',array['uuid','uuid','jsonb','uuid','integer'],'public propose RPC installed');
select has_function('public','cmd_confirm_task_shares',array['uuid','uuid','uuid','integer'],'public confirm RPC installed');
select ok(not has_table_privilege('authenticated','public.task_contribution_ledger','UPDATE')
 and not has_table_privilege('authenticated','public.contribution_penalties','DELETE'),
 'authenticated clients cannot tamper with ledger');
select ok(not has_function_privilege('authenticated','private.process_contribution_penalty_event(bigint)','EXECUTE'),
 'only service role can consume penalty events');

insert into auth.users(id,email) values
 ('e5100000-0000-0000-0000-000000000001','e-contrib-main@example.test'),
 ('e5100000-0000-0000-0000-000000000002','e-contrib-collab@example.test'),
 ('e5100000-0000-0000-0000-000000000003','e-contrib-observer@example.test'),
 ('e5100000-0000-0000-0000-000000000004','e-contrib-outsider@example.test'),
 ('e5100000-0000-0000-0000-000000000005','e-contrib-voter@example.test');
insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode)
 values ('e5200000-0000-0000-0000-000000000001','E contribution pgTAP',
 now()+interval '14 days','e5100000-0000-0000-0000-000000000001',
 'e5100000-0000-0000-0000-000000000001',1,'weighted');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values
 ('e5200000-0000-0000-0000-000000000001','e5100000-0000-0000-0000-000000000001','leader','active',false),
 ('e5200000-0000-0000-0000-000000000001','e5100000-0000-0000-0000-000000000002','member','active',false),
 ('e5200000-0000-0000-0000-000000000001','e5100000-0000-0000-0000-000000000003','observer','active',true),
 ('e5200000-0000-0000-0000-000000000001','e5100000-0000-0000-0000-000000000005','member','active',false);
insert into public.tasks(id,project_id,title,assignee_id,created_by,deadline_at,status,weight,
 accepted_at,completed_at,assignment_state,version)
 values ('e5300000-0000-0000-0000-000000000001','e5200000-0000-0000-0000-000000000001',
 'Two-person 4-star task','e5100000-0000-0000-0000-000000000001',
 'e5100000-0000-0000-0000-000000000001',now()+interval '10 days','completed',4,
 now()-interval '2 days',now()-interval '1 day','assigned',1);
insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
 values ('e5200000-0000-0000-0000-000000000001','e5300000-0000-0000-0000-000000000001',
 'e5100000-0000-0000-0000-000000000002','accepted',now());

create temporary table e_results(label text primary key, result jsonb);
grant all on e_results to authenticated,service_role;

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into e_results values('invalid',public.cmd_propose_task_shares(
 'e5200000-0000-0000-0000-000000000001','e5300000-0000-0000-0000-000000000001',
 '[{"userId":"e5100000-0000-0000-0000-000000000001","shareBps":6500},{"userId":"e5100000-0000-0000-0000-000000000002","shareBps":4500}]',
 'e5400000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'code' from e_results where label='invalid'),
 'VALIDATION_FAILED','11000 bps rejected');
select is((select count(*)::integer from public.task_share_proposals),0,'bad proposal does not enter history');

set local role authenticated;
insert into e_results values('duplicate',public.cmd_propose_task_shares(
 'e5200000-0000-0000-0000-000000000001','e5300000-0000-0000-0000-000000000001',
 '[{"userId":"e5100000-0000-0000-0000-000000000001","shareBps":6500},{"userId":"e5100000-0000-0000-0000-000000000001","shareBps":3500}]',
 'e5400000-0000-0000-0000-000000000002',1));
reset role;
select is((select result->>'code' from e_results where label='duplicate'),
 'VALIDATION_FAILED','duplicate participant rejected');

set local role authenticated;
insert into e_results values('proposed',public.cmd_propose_task_shares(
 'e5200000-0000-0000-0000-000000000001','e5300000-0000-0000-0000-000000000001',
 '[{"userId":"e5100000-0000-0000-0000-000000000001","shareBps":6500},{"userId":"e5100000-0000-0000-0000-000000000002","shareBps":3500}]',
 'e5400000-0000-0000-0000-000000000003',1));
reset role;
select is((select result->>'ok' from e_results where label='proposed'),'true','6500/3500 proposal accepted');
select is((select count(*)::integer from public.task_contribution_ledger),0,'unconfirmed proposal creates no formal ledger');
select is((select sum(amount)::numeric(12,4)::text from public.task_share_allocations),'4.0000','task contribution pool conserved');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into e_results values('observer',public.cmd_confirm_task_shares(
 'e5200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from e_results where label='proposed'),
 'e5400000-0000-0000-0000-000000000004',1));
reset role;
select is((select result->>'code' from e_results where label='observer'),
 'NOT_AUTHORIZED','observer cannot confirm other participant share');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into e_results values('confirm-primary',public.cmd_confirm_task_shares(
 'e5200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from e_results where label='proposed'),
 'e5400000-0000-0000-0000-000000000005',1));
reset role;
select is((select result->>'ok' from e_results where label='confirm-primary'),'true','primary can confirm own allocation');
select is((select count(*)::integer from public.task_contribution_ledger),0,'not formal after single confirmation');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into e_results values('confirm-collab',public.cmd_confirm_task_shares(
 'e5200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,proposalId}')::uuid from e_results where label='proposed'),
 'e5400000-0000-0000-0000-000000000006',2));
reset role;
select is((select result->>'ok' from e_results where label='confirm-collab'),'true','accepted collaborator confirms own allocation');
select is((select count(*)::integer from public.task_contribution_ledger),2,'formal ledger generated once all confirmed');
select is((select sum(amount)::numeric(12,4)::text from public.task_authoritative_contributions),
 '4.0000','confirmed ledger conserves whole four-star pool');
select is((select amount::text from public.task_authoritative_contributions
 where member_user_id='e5100000-0000-0000-0000-000000000001'),'2.6000','65% is 2.6000');
select is((select amount::text from public.task_authoritative_contributions
 where member_user_id='e5100000-0000-0000-0000-000000000002'),'1.4000','35% is 1.4000');

-- Synthetic C authority fixture: the isolated E test uses a completed
-- responsibility epoch that had explicit pre-acceptance 65% consent.
insert into public.task_responsibility_epochs(
 id,project_id,task_id,responsible_user_id,accepted_at,
 effective_start_at,effective_deadline_at,free_abandon_until,
 deadline_revision,blocked_exempt,weight_snapshot,
 expected_share_bps_snapshot,shares_confirmed,accepted_expected_contribution,
 project_contribution_mode,auto_penalty_enabled_snapshot,trigger_source)
values('e5500000-0000-0000-0000-000000000001',
 'e5200000-0000-0000-0000-000000000001',
 'e5300000-0000-0000-0000-000000000001',
 'e5100000-0000-0000-0000-000000000001',
 '2026-10-09T00:00:00Z','2026-10-09T00:00:00Z',
 '2026-10-10T00:00:00Z','2026-10-09T02:24:00Z',
 1,false,4,6500,true,2.6000,'weighted',true,'fixture_signed_acceptance');
-- C-compatible *isolated fixture*, not real producer wiring.
insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data)
 values ('e5200000-0000-0000-0000-000000000001','e5100000-0000-0000-0000-000000000001',
  'task_first_submitted_late','task','e5300000-0000-0000-0000-000000000001',
  'e5400000-0000-0000-0000-000000000020',
  jsonb_build_object('schemaVersion',1,'policyVersion',1,
    'occurrenceKey','task:e5300000-0000-0000-0000-000000000001:first_late',
    'occurredAt','2026-10-10T02:24:00Z','aggregateVersion',2,
    'taskId','e5300000-0000-0000-0000-000000000001',
    'responsibleUserId','e5100000-0000-0000-0000-000000000001',
    'responsibilityEpochId','e5500000-0000-0000-0000-000000000001',
    'effectiveStartAt','2026-10-09T00:00:00Z',
    'effectiveDeadlineAt','2026-10-10T00:00:00Z',
    'acceptedAt','2026-10-09T00:00:00Z',
    'freeAbandonUntil','2026-10-09T02:24:00Z',
    'firstSubmittedAt','2026-10-10T02:24:00Z',
    'blockedExempt',false,'weightSnapshot',4,
    'expectedShareBpsSnapshot',6500,'acceptedExpectedContribution','2.6000',
    'projectContributionMode','weighted','autoPenaltyEnabledSnapshot',true,
    'triggerSource','first_submission'));
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into e_results
 select 'penalty-first',public.process_contribution_penalty_event_service(
  (select id from public.business_events where request_id='e5400000-0000-0000-0000-000000000020' and event_type='task_first_submitted_late'));
reset role;
select is((select result->>'disposition' from e_results where label='penalty-first'),'assessed',
 'service consumer calculates C source event');
select is((select amount::text from public.contribution_penalties),'-0.2600',
 'exact 10% late boundary results in 10% penalty');
set local role service_role;
insert into e_results
 select 'penalty-replay',public.process_contribution_penalty_event_service(
  (select id from public.business_events where request_id='e5400000-0000-0000-0000-000000000020' and event_type='task_first_submitted_late'));
reset role;
select is((select result->>'replayed' from e_results where label='penalty-replay'),'true','same source event replay idempotent');
select is((select count(*)::integer from public.contribution_penalties),1,'one penalty for one source event');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into e_results values('foreign-appeal',public.cmd_appeal_contribution_penalty(
 'e5200000-0000-0000-0000-000000000001',
 (select id from public.contribution_penalties limit 1),'Not mine',
 'e5400000-0000-0000-0000-000000000030',1));
reset role;
select is((select result->>'code' from e_results where label='foreign-appeal'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','non-affected member cannot impersonate appellant');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into e_results values('appeal',public.cmd_appeal_contribution_penalty(
 'e5200000-0000-0000-0000-000000000001',
 (select id from public.contribution_penalties limit 1),'Actual responsibility was shorter',
 'e5400000-0000-0000-0000-000000000031',1));
reset role;
select is((select result->>'ok' from e_results where label='appeal'),'true','affected member may appeal');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into e_results values('vote-one',public.cmd_resolve_contribution_appeal(
 'e5200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,appealId}')::uuid from e_results where label='appeal'),
 '{"decision":"revoke"}','e5400000-0000-0000-0000-000000000032',1));
reset role;
select is((select result#>>'{data,passed}' from e_results where label='vote-one'),'false',
 'single vote of two eligible is not a majority');
select is((select count(*)::integer from public.contribution_penalty_adjustments),0,
 'one vote cannot alter immutable penalty');

select set_config('request.jwt.claim.sub','e5100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into e_results values('vote-two',public.cmd_resolve_contribution_appeal(
 'e5200000-0000-0000-0000-000000000001',
 (select (result#>>'{data,appealId}')::uuid from e_results where label='appeal'),
 '{"decision":"revoke"}','e5400000-0000-0000-0000-000000000033',2));
reset role;
select is((select result#>>'{data,passed}' from e_results where label='vote-two'),'true',
 'strict unaffected majority resolves appeal');
select is((select signed_delta::text from public.contribution_penalty_adjustments),'0.2600',
 'append-only signed delta offsets original penalty');
select is((select amount::text from public.contribution_penalties),'-0.2600',
 'original penalty is not rewritten');
select is((select amount::text from public.project_contribution_balances
 where member_user_id='e5100000-0000-0000-0000-000000000001'),'2.6000',
 'balances sum original, penalty, and delta');

select * from finish();
rollback;
