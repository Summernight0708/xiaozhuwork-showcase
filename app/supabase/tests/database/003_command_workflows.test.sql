begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'leader@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'member@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'target@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'outsider@example.test');
update public.profiles set display_name = 'User', real_name = 'Real User', student_number = 'S1';

create temporary table rpc_results (label text primary key, result jsonb);
grant all on rpc_results to authenticated, anon;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('create-project', public.cmd_create_project(
  '20000000-0000-0000-0000-000000000001', 0, 'Day 4 Team', now() + interval '14 days',
  'Course', 'Description', 'Asia/Shanghai', 'weighted', true, true
));
reset role;

select is((select result->>'ok' from rpc_results where label='create-project'), 'true', 'project creation succeeds');
select is((select result->>'aggregateType' from rpc_results where label='create-project'), 'project', 'project creation returns project aggregate');
select is((select result->>'aggregateVersion' from rpc_results where label='create-project'), '1', 'new project starts at version one');
select is((select count(*)::integer from public.projects where created_by='10000000-0000-0000-0000-000000000001'), 1, 'project row created once');
select is((select count(*)::integer from public.project_members where role='leader' and member_state='active' and user_id='10000000-0000-0000-0000-000000000001'), 1, 'leader membership created');
select is((select count(*)::integer from public.business_events where actor_id='10000000-0000-0000-0000-000000000001'), 1, 'project creation emits one event');
select is((select count(*)::integer from public.command_requests where state='completed' and actor_id='10000000-0000-0000-0000-000000000001'), 1, 'project command completes ledger row');

set local role authenticated;
insert into rpc_results values ('create-project-replay', public.cmd_create_project(
  '20000000-0000-0000-0000-000000000001', 0, 'Day 4 Team', now() + interval '14 days',
  'Course', 'Description', 'Asia/Shanghai', 'weighted', true, true
));
reset role;
select is((select result->>'replayed' from rpc_results where label='create-project-replay'), 'true', 'identical create project replays');
select is((select count(*)::integer from public.projects where created_by='10000000-0000-0000-0000-000000000001'), 1, 'replay does not duplicate project');
select is((select count(*)::integer from public.business_events where actor_id='10000000-0000-0000-0000-000000000001'), 1, 'replay does not duplicate event');

set local role authenticated;
insert into rpc_results values ('create-project-key-reuse', public.cmd_create_project(
  '20000000-0000-0000-0000-000000000001', 0, 'Different Name', now() + interval '14 days',
  'Course', 'Description', 'Asia/Shanghai', 'weighted', true, true
));
reset role;
select is((select result->>'code' from rpc_results where label='create-project-key-reuse'), 'IDEMPOTENCY_KEY_REUSED', 'different payload rejects reused key');

set local role authenticated;
insert into rpc_results values ('bad-ddl', public.cmd_create_project(
  '20000000-0000-0000-0000-000000000002', 0, 'Expired', now() - interval '1 hour', null, null, null, null, null, null
));
reset role;
select is((select result->>'code' from rpc_results where label='bad-ddl'), 'DDL_NOT_IN_FUTURE', 'project deadline must be future');
select is((select count(*)::integer from public.business_events where actor_id='10000000-0000-0000-0000-000000000001'), 1, 'domain failure emits no event');

select (result->'data'->>'projectId')::uuid as project_id from rpc_results where label='create-project' \gset

set local role authenticated;
insert into rpc_results values ('create-invite', public.cmd_create_project_invite(
  :'project_id', '20000000-0000-0000-0000-000000000003', 1, 'direct', null, 2
));
reset role;
select is((select result->>'ok' from rpc_results where label='create-invite'), 'true', 'leader creates direct invitation');
select ok((select result->'data' ? 'token' from rpc_results where label='create-invite'), 'invite result returns original token');
select is((select result->'data'->>'invitationVersion' from rpc_results where label='create-invite'), '1', 'new invitation starts at version one');
select ok((select expires_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour' from public.project_invitations where id=(select (result#>>'{data,invitationId}')::uuid from rpc_results where label='create-invite')), 'default invitation expiry is seven days');
select ok(not exists(select 1 from public.project_invitations where token_hash::text like '%' || (select result->'data'->>'token' from rpc_results where label='create-invite') || '%'), 'invitation table never stores original token');
select ok(not exists(select 1 from public.business_events where event_data::text like '%' || (select result->'data'->>'token' from rpc_results where label='create-invite') || '%'), 'event never stores original token');
select ok((select result::text like '%' || (select result->'data'->>'token' from rpc_results where label='create-invite') || '%' from public.command_requests where command_name='cmd_create_project_invite' and request_id='20000000-0000-0000-0000-000000000003'), 'protected ledger retains returned token for replay');

select result->'data'->>'token' as invite_token from rpc_results where label='create-invite' \gset
select (result->'data'->>'invitationId')::uuid as invitation_id from rpc_results where label='create-invite' \gset

set local role anon;
insert into rpc_results values ('preview', public.preview_project_invite(:'invite_token'));
reset role;
select is((select result->>'projectName' from rpc_results where label='preview'), 'Day 4 Team', 'anonymous preview exposes allowlisted project name');
select is((select result->>'available' from rpc_results where label='preview'), 'true', 'new invite is available');
select ok(not (select result ? 'token' or result ? 'tokenHash' or result ? 'members' from rpc_results where label='preview'), 'preview does not expose token hash or members');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values ('direct-join', public.cmd_join_project_via_invite(
  :'invite_token', '20000000-0000-0000-0000-000000000004', 1
));
reset role;
select is((select result->'data'->>'outcome' from rpc_results where label='direct-join'), 'joined', 'direct invitation creates membership');
select is((select uses_count from public.project_invitations where id=:'invitation_id'), 1, 'direct join consumes one use');
select is((select version from public.project_invitations where id=:'invitation_id'), 2, 'direct join advances invitation version');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('create-approval-invite', public.cmd_create_project_invite(
  :'project_id', '20000000-0000-0000-0000-000000000005', 2, 'approval', 1, 1
));
reset role;
select result->'data'->>'token' as approval_token from rpc_results where label='create-approval-invite' \gset
select (result->'data'->>'invitationId')::uuid as approval_invitation_id from rpc_results where label='create-approval-invite' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
insert into rpc_results values ('approval-join', public.cmd_join_project_via_invite(
  :'approval_token', '20000000-0000-0000-0000-000000000006', 0
));
reset role;
select is((select result->'data'->>'outcome' from rpc_results where label='approval-join'), 'pending_approval', 'approval invitation creates pending request');
select is((select uses_count from public.project_invitations where id=:'approval_invitation_id'), 0, 'pending request does not consume use');
select is((select version from public.project_invitations where id=:'approval_invitation_id'), 1, 'pending request does not version invitation');
select is((select display_name_snapshot from public.project_join_requests where project_id=:'project_id' and user_id='10000000-0000-0000-0000-000000000003' and state='pending'), 'User', 'pending request captures applicant display name');
select (result->'data'->>'joinRequestId')::uuid as join_request_id from rpc_results where label='approval-join' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('approve-join', public.cmd_review_project_join_request(
  :'project_id', :'join_request_id', 'approve', '20000000-0000-0000-0000-000000000007', 1
));
reset role;
select is((select result->'data'->>'state' from rpc_results where label='approve-join'), 'approved', 'leader approves pending request');
select is((select uses_count from public.project_invitations where id=:'approval_invitation_id'), 1, 'approval consumes invitation use');
select is((select count(*)::integer from public.project_members where project_id=:'project_id' and member_state='active'), 3, 'approval adds active member');

set local role authenticated;
insert into rpc_results values ('create-task', public.cmd_create_task(
  :'project_id', '20000000-0000-0000-0000-000000000008', 3, 'Claim me', null,
  now() + interval '2 days', 3::smallint, 'claimable', null
));
reset role;
select is((select result->>'ok' from rpc_results where label='create-task'), 'true', 'active member creates weighted claimable task');
select (result->'data'->>'taskId')::uuid as task_id from rpc_results where label='create-task' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values ('claim-task', public.cmd_claim_task(
  :'project_id', :'task_id', '20000000-0000-0000-0000-000000000009', 1
));
reset role;
select is((select result->>'ok' from rpc_results where label='claim-task'), 'true', 'active member claims task');
select is((select assignment_state from public.tasks where id=:'task_id'), 'assigned', 'claimed task is assigned');
select is((select status from public.tasks where id=:'task_id'), 'in_progress', 'claimed task starts in progress');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
insert into rpc_results values ('claim-loser', public.cmd_claim_task(
  :'project_id', :'task_id', '20000000-0000-0000-0000-000000000010', 1
));
reset role;
select is((select result->>'code' from rpc_results where label='claim-loser'), 'TASK_ALREADY_CLAIMED', 'second claimant loses deterministically');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values ('progress', public.cmd_update_task_progress(
  :'project_id', :'task_id', '20000000-0000-0000-0000-000000000011', 2,
  'blocked', 'Waiting for data', 'Dataset unavailable'
));
reset role;
select is((select result->'data'->>'status' from rpc_results where label='progress'), 'blocked', 'assignee updates blocked progress');
select is((select progress_text from public.tasks where id=:'task_id'), 'Waiting for data', 'progress text persists');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('direct-task', public.cmd_create_task(
  :'project_id', '20000000-0000-0000-0000-000000000012', 4, 'Offer me', null,
  now() + interval '2 days', 2::smallint, 'direct', '10000000-0000-0000-0000-000000000003'
));
reset role;
select is((select result->>'ok' from rpc_results where label='direct-task'), 'true', 'direct assignment creates task and offer');
select (result->'data'->>'taskId')::uuid as offered_task_id from rpc_results where label='direct-task' \gset
select (result->'data'->>'assignmentOfferId')::uuid as offer_id from rpc_results where label='direct-task' \gset
select is((select assignment_state from public.tasks where id=:'offered_task_id'), 'pending_acceptance', 'direct task waits for acceptance');
select ok((select assignee_id is null from public.tasks where id=:'offered_task_id'), 'direct task has no assignee before acceptance');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
insert into rpc_results values ('accept-offer', public.cmd_respond_to_task_assignment(
  :'project_id', :'offered_task_id', :'offer_id', 'accept',
  '20000000-0000-0000-0000-000000000013', 1
));
reset role;
select is((select result->'data'->>'outcome' from rpc_results where label='accept-offer'), 'accepted', 'offer target accepts');
select is((select assignment_state from public.tasks where id=:'offered_task_id'), 'assigned', 'accepted offer assigns task');
select is((select assignee_id::text from public.tasks where id=:'offered_task_id'), '10000000-0000-0000-0000-000000000003', 'accepted offer writes assignee');

set local role authenticated;
insert into rpc_results values ('accept-offer-replay', public.cmd_respond_to_task_assignment(
  :'project_id', :'offered_task_id', :'offer_id', 'accept',
  '20000000-0000-0000-0000-000000000013', 1
));
reset role;
select is((select result->>'replayed' from rpc_results where label='accept-offer-replay'), 'true', 'accepted offer command replays after state transition');
select is((select count(*)::integer from public.business_events where request_id='20000000-0000-0000-0000-000000000013'), 1, 'offer replay emits no duplicate event');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values ('stale-progress', public.cmd_update_task_progress(
  :'project_id', :'task_id', '20000000-0000-0000-0000-000000000014', 2,
  'in_progress', 'Should not persist', null
));
reset role;
select is((select result->>'code' from rpc_results where label='stale-progress'), 'STALE_VERSION', 'stale progress update is rejected');
select is((select progress_text from public.tasks where id=:'task_id'), 'Waiting for data', 'stale progress has no state side effect');
select is((select count(*)::integer from public.business_events where request_id='20000000-0000-0000-0000-000000000014'), 0, 'stale progress emits no event');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('bad-invite-range', public.cmd_create_project_invite(
  :'project_id', '20000000-0000-0000-0000-000000000015', 5, 'direct', 31, null
));
insert into rpc_results values ('bad-weight', public.cmd_create_task(
  :'project_id', '20000000-0000-0000-0000-000000000016', 5, 'Missing weight', null,
  now() + interval '2 days', null, 'claimable', null
));
reset role;
select is((select result->>'code' from rpc_results where label='bad-invite-range'), 'VALIDATION_FAILED', 'invite expiry range is enforced');
select is((select result->>'code' from rpc_results where label='bad-weight'), 'VALIDATION_FAILED', 'weighted project requires task weight');
select is((select version from public.projects where id=:'project_id'), 5, 'failed commands do not advance project version');
select is((select count(*)::integer from public.business_events where request_id in ('20000000-0000-0000-0000-000000000015','20000000-0000-0000-0000-000000000016')), 0, 'validation failures emit no events');

set local role authenticated;
insert into rpc_results values ('revocable-invite', public.cmd_create_project_invite(
  :'project_id', '20000000-0000-0000-0000-000000000017', 5, 'approval', 7, null
));
reset role;
select result->'data'->>'token' as revocable_token from rpc_results where label='revocable-invite' \gset
select (result->'data'->>'invitationId')::uuid as revocable_invitation_id from rpc_results where label='revocable-invite' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
set local role authenticated;
insert into rpc_results values ('revocable-request', public.cmd_join_project_via_invite(
  :'revocable_token', '20000000-0000-0000-0000-000000000018', 0
));
reset role;
select (result->'data'->>'joinRequestId')::uuid as revocable_request_id from rpc_results where label='revocable-request' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('revoke-invite', public.cmd_revoke_project_invite(
  :'project_id', :'revocable_invitation_id', '20000000-0000-0000-0000-000000000019', 1
));
reset role;
select is((select result->'data'->>'canceledJoinRequestCount' from rpc_results where label='revoke-invite'), '1', 'revocation reports canceled pending request');
select is((select state from public.project_join_requests where id=:'revocable_request_id'), 'canceled', 'revocation cancels pending join request');
select is((select version from public.project_join_requests where id=:'revocable_request_id'), 2, 'revocation versions canceled join request');
select is((select count(*)::integer from public.business_events where request_id='20000000-0000-0000-0000-000000000019'), 2, 'revocation emits invitation and cancellation events in one command');

set local role anon;
insert into rpc_results values ('revoked-preview', public.preview_project_invite(:'revocable_token'));
reset role;
select is((select result->>'available' from rpc_results where label='revoked-preview'), 'false', 'revoked invitation previews as unavailable');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values ('rejectable-task', public.cmd_create_task(
  :'project_id', '20000000-0000-0000-0000-000000000020', 6, 'Reject me', null,
  now() + interval '2 days', 1::smallint, 'direct', '10000000-0000-0000-0000-000000000002'
));
reset role;
select (result->'data'->>'taskId')::uuid as rejectable_task_id from rpc_results where label='rejectable-task' \gset
select (result->'data'->>'assignmentOfferId')::uuid as rejectable_offer_id from rpc_results where label='rejectable-task' \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values ('reject-offer', public.cmd_respond_to_task_assignment(
  :'project_id', :'rejectable_task_id', :'rejectable_offer_id', 'reject',
  '20000000-0000-0000-0000-000000000021', 1
));
reset role;
select is((select result->'data'->>'outcome' from rpc_results where label='reject-offer'), 'rejected', 'offer target may reject');
select is((select assignment_state from public.tasks where id=:'rejectable_task_id'), 'claimable', 'rejected offer returns task to claimable');
select ok((select assignee_id is null from public.tasks where id=:'rejectable_task_id'), 'rejected offer leaves task unassigned');

-- Every public write command must replay its original result before re-evaluating stale state.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into rpc_results values
  ('replay-create-invite', public.cmd_create_project_invite(:'project_id','20000000-0000-0000-0000-000000000003',1,'direct',null,2)),
  ('replay-create-approval-invite', public.cmd_create_project_invite(:'project_id','20000000-0000-0000-0000-000000000005',2,'approval',1,1)),
  ('replay-approve-join', public.cmd_review_project_join_request(:'project_id',:'join_request_id','approve','20000000-0000-0000-0000-000000000007',1)),
  ('replay-create-task', public.cmd_create_task(:'project_id','20000000-0000-0000-0000-000000000008',3,'Claim me',null,now()+interval '2 days',3::smallint,'claimable',null)),
  ('replay-revoke', public.cmd_revoke_project_invite(:'project_id',:'revocable_invitation_id','20000000-0000-0000-0000-000000000019',1));
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into rpc_results values
  ('replay-direct-join', public.cmd_join_project_via_invite(:'invite_token','20000000-0000-0000-0000-000000000004',1)),
  ('replay-claim', public.cmd_claim_task(:'project_id',:'task_id','20000000-0000-0000-0000-000000000009',1)),
  ('replay-progress', public.cmd_update_task_progress(:'project_id',:'task_id','20000000-0000-0000-0000-000000000011',2,'blocked','Waiting for data','Dataset unavailable')),
  ('replay-reject-offer', public.cmd_respond_to_task_assignment(:'project_id',:'rejectable_task_id',:'rejectable_offer_id','reject','20000000-0000-0000-0000-000000000021',1));
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
insert into rpc_results values ('replay-approval-join', public.cmd_join_project_via_invite(:'approval_token','20000000-0000-0000-0000-000000000006',0));
reset role;
select is((select count(*)::integer from rpc_results where label like 'replay-%' and result->>'replayed'='true'),10,'all command variants replay their stored result');
select is((select count(distinct command_name)::integer from public.command_requests where result->>'ok'='true' and actor_id in ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003')),9,'success coverage includes all nine write command names');

create function pg_temp.capture_jsonb(p_sql text)
returns jsonb language plpgsql as $$
declare v_result jsonb;
begin
  execute p_sql into v_result;
  return v_result;
exception when others then
  return jsonb_build_object('sqlError', true, 'sqlState', sqlstate);
end;
$$;

insert into public.projects (id,name,deadline_at,leader_id,created_by,version) values
  ('31000000-0000-0000-0000-000000000001','Null action review',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000002','Null action offer',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000003','Null invite version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000004','Null revoke version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000005','Null join version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000006','Null review version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000007','Null task version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000008','Null claim version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-000000000009','Null offer version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-00000000000a','Null progress version',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-00000000000b','Unauthorized invite',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-00000000000c','Pending direct join',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1),
  ('31000000-0000-0000-0000-00000000000d','Non assignee progress',now()+interval '20 days','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1);

insert into public.project_members (project_id,user_id,role,member_state)
select id,'10000000-0000-0000-0000-000000000001','leader','active'
from public.projects where id::text like '31000000-0000-0000-0000-0000000000%';
insert into public.project_members (project_id,user_id,role,member_state) values
  ('31000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000002','member','active'),
  ('31000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000002','member','active'),
  ('31000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000002','member','active'),
  ('31000000-0000-0000-0000-00000000000d','10000000-0000-0000-0000-000000000002','member','active');

insert into public.project_invitations (id,project_id,created_by,token_hash,mode,expires_at) values
  ('32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('null-action-review','utf8'),'sha256'),'approval',now()+interval '7 days'),
  ('32000000-0000-0000-0000-000000000004','31000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('null-revoke-version','utf8'),'sha256'),'direct',now()+interval '7 days'),
  ('32000000-0000-0000-0000-000000000005','31000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('null-join-version','utf8'),'sha256'),'direct',now()+interval '7 days'),
  ('32000000-0000-0000-0000-000000000006','31000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('null-review-version','utf8'),'sha256'),'approval',now()+interval '7 days'),
  ('32000000-0000-0000-0000-00000000000c','31000000-0000-0000-0000-00000000000c','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('pending-approval-token','utf8'),'sha256'),'approval',now()+interval '7 days'),
  ('32000000-0000-0000-0000-00000000000d','31000000-0000-0000-0000-00000000000c','10000000-0000-0000-0000-000000000001',extensions.digest(convert_to('pending-direct-token','utf8'),'sha256'),'direct',now()+interval '7 days');

insert into public.project_join_requests (id,invitation_id,project_id,user_id) values
  ('33000000-0000-0000-0000-000000000001','32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004'),
  ('33000000-0000-0000-0000-000000000006','32000000-0000-0000-0000-000000000006','31000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000004'),
  ('33000000-0000-0000-0000-00000000000c','32000000-0000-0000-0000-00000000000c','31000000-0000-0000-0000-00000000000c','10000000-0000-0000-0000-000000000003');

insert into public.tasks (id,project_id,title,created_by,deadline_at,status,weight,assignment_state,assignee_id,accepted_at) values
  ('34000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000002','Null action offer','10000000-0000-0000-0000-000000000001',now()+interval '5 days','not_started',1,'pending_acceptance',null,null),
  ('34000000-0000-0000-0000-000000000008','31000000-0000-0000-0000-000000000008','Null claim version','10000000-0000-0000-0000-000000000001',now()+interval '5 days','not_started',1,'claimable',null,null),
  ('34000000-0000-0000-0000-000000000009','31000000-0000-0000-0000-000000000009','Null offer version','10000000-0000-0000-0000-000000000001',now()+interval '5 days','not_started',1,'pending_acceptance',null,null),
  ('34000000-0000-0000-0000-00000000000a','31000000-0000-0000-0000-00000000000a','Null progress version','10000000-0000-0000-0000-000000000001',now()+interval '5 days','in_progress',1,'assigned','10000000-0000-0000-0000-000000000002',now()),
  ('34000000-0000-0000-0000-00000000000d','31000000-0000-0000-0000-00000000000d','Non assignee progress','10000000-0000-0000-0000-000000000001',now()+interval '5 days','in_progress',1,'assigned','10000000-0000-0000-0000-000000000002',now());
insert into public.task_assignment_offers (id,task_id,project_id,target_user_id,created_by) values
  ('35000000-0000-0000-0000-000000000002','34000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001'),
  ('35000000-0000-0000-0000-000000000009','34000000-0000-0000-0000-000000000009','31000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rpc_results values ('null-review-action',public.cmd_review_project_join_request('31000000-0000-0000-0000-000000000001','33000000-0000-0000-0000-000000000001',null,'40000000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'code' from rpc_results where label='null-review-action'),'VALIDATION_FAILED','NULL review action is validation failure');
select is((select state from public.project_join_requests where id='33000000-0000-0000-0000-000000000001'),'pending','NULL review action has no request state side effect');
select is((select count(*)::integer from public.business_events where request_id='40000000-0000-0000-0000-000000000001'),0,'NULL review action emits no event');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into rpc_results values ('null-offer-action',public.cmd_respond_to_task_assignment('31000000-0000-0000-0000-000000000002','34000000-0000-0000-0000-000000000002','35000000-0000-0000-0000-000000000002',null,'40000000-0000-0000-0000-000000000002',1));
reset role;
select is((select result->>'code' from rpc_results where label='null-offer-action'),'VALIDATION_FAILED','NULL offer action is validation failure');
select is((select state from public.task_assignment_offers where id='35000000-0000-0000-0000-000000000002'),'pending','NULL offer action has no offer state side effect');
select is((select assignment_state from public.tasks where id='34000000-0000-0000-0000-000000000002'),'pending_acceptance','NULL offer action has no task state side effect');
select is((select count(*)::integer from public.business_events where request_id='40000000-0000-0000-0000-000000000002'),0,'NULL offer action emits no event');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rpc_results values
  ('null-expected-create-project',public.cmd_create_project('41000000-0000-0000-0000-000000000001',null,'Must not exist',now()+interval '10 days',null,null,null,null,null,null)),
  ('null-expected-create-invite',public.cmd_create_project_invite('31000000-0000-0000-0000-000000000003','41000000-0000-0000-0000-000000000002',null,'direct',7,null)),
  ('null-expected-revoke',public.cmd_revoke_project_invite('31000000-0000-0000-0000-000000000004','32000000-0000-0000-0000-000000000004','41000000-0000-0000-0000-000000000003',null)),
  ('null-expected-review',public.cmd_review_project_join_request('31000000-0000-0000-0000-000000000006','33000000-0000-0000-0000-000000000006','reject','41000000-0000-0000-0000-000000000005',null)),
  ('null-expected-create-task',public.cmd_create_task('31000000-0000-0000-0000-000000000007','41000000-0000-0000-0000-000000000006',null,'Must not exist',null,now()+interval '5 days',1::smallint,'claimable',null));
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into rpc_results values ('null-expected-join',public.cmd_join_project_via_invite('null-join-version','41000000-0000-0000-0000-000000000004',null));
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into rpc_results values
  ('null-expected-claim',public.cmd_claim_task('31000000-0000-0000-0000-000000000008','34000000-0000-0000-0000-000000000008','41000000-0000-0000-0000-000000000007',null)),
  ('null-expected-respond',public.cmd_respond_to_task_assignment('31000000-0000-0000-0000-000000000009','34000000-0000-0000-0000-000000000009','35000000-0000-0000-0000-000000000009','accept','41000000-0000-0000-0000-000000000008',null)),
  ('null-expected-progress',public.cmd_update_task_progress('31000000-0000-0000-0000-00000000000a','34000000-0000-0000-0000-00000000000a','41000000-0000-0000-0000-000000000009',null,'blocked','Must not persist','Must not persist'));
reset role;

select is((select count(*)::integer from rpc_results where label like 'null-expected-%' and result->>'ok'='true'),0,'all nine write RPCs reject NULL expected_version');
select is((select count(*)::integer from public.business_events where request_id::text like '41000000-0000-0000-0000-00000000000%'),0,'NULL expected_version commands emit no events');
select is((select count(*)::integer from public.command_requests where request_id::text like '41000000-0000-0000-0000-00000000000%' and state='completed' and result->>'ok'='false'),9,'NULL expected_version failures complete nine ledger rows');
select ok(not exists(select 1 from public.projects where name='Must not exist'),'NULL create project has no state side effect');
select is((select version from public.projects where id='31000000-0000-0000-0000-000000000003'),1,'NULL invite expected version does not advance project');
select ok((select revoked_at is null from public.project_invitations where id='32000000-0000-0000-0000-000000000004'),'NULL revoke expected version does not revoke');
select ok(not private.is_active_member('31000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000004'),'NULL join expected version does not add member');
select is((select state from public.project_join_requests where id='33000000-0000-0000-0000-000000000006'),'pending','NULL review expected version leaves request pending');
select is((select count(*)::integer from public.tasks where project_id='31000000-0000-0000-0000-000000000007'),0,'NULL create task expected version creates no task');
select is((select assignment_state from public.tasks where id='34000000-0000-0000-0000-000000000008'),'claimable','NULL claim expected version leaves task claimable');
select is((select state from public.task_assignment_offers where id='35000000-0000-0000-0000-000000000009'),'pending','NULL respond expected version leaves offer pending');
select ok((select progress_text is null from public.tasks where id='34000000-0000-0000-0000-00000000000a'),'NULL progress expected version leaves progress unchanged');

create temporary table null_request_probe (result jsonb);
insert into null_request_probe values (pg_temp.capture_jsonb($call$select public.cmd_create_project(null,0,'Null request must not exist',now()+interval '10 days',null,null,null,null,null,null)$call$));
select ok((select result->>'sqlError'='true' or result->>'ok'='false' from null_request_probe),'NULL request_id is rejected or returns failure');
select ok(not exists(select 1 from public.projects where name='Null request must not exist'),'NULL request_id has no project side effect');
select is((select count(*)::integer from public.business_events where request_id is null and event_type='project_created'),0,'NULL request_id emits no project event');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into rpc_results values
  ('unauthorized-invite-first',public.cmd_create_project_invite('31000000-0000-0000-0000-00000000000b','42000000-0000-0000-0000-000000000001',1,'direct',7,null)),
  ('unauthorized-invite-replay',public.cmd_create_project_invite('31000000-0000-0000-0000-00000000000b','42000000-0000-0000-0000-000000000001',1,'direct',7,null)),
  ('unauthorized-invite-reuse',public.cmd_create_project_invite('31000000-0000-0000-0000-00000000000b','42000000-0000-0000-0000-000000000001',1,'approval',7,null)),
  ('non-assignee-first',public.cmd_update_task_progress('31000000-0000-0000-0000-00000000000d','34000000-0000-0000-0000-00000000000d','42000000-0000-0000-0000-000000000002',1,'in_progress','No access',null)),
  ('non-assignee-replay',public.cmd_update_task_progress('31000000-0000-0000-0000-00000000000d','34000000-0000-0000-0000-00000000000d','42000000-0000-0000-0000-000000000002',1,'in_progress','No access',null)),
  ('non-assignee-reuse',public.cmd_update_task_progress('31000000-0000-0000-0000-00000000000d','34000000-0000-0000-0000-00000000000d','42000000-0000-0000-0000-000000000002',1,'blocked','Different payload','Blocked'));
reset role;
select is((select result->>'code' from rpc_results where label='unauthorized-invite-first'),'NOT_FOUND_OR_NOT_AUTHORIZED','unauthorized invite creation returns cached domain failure');
select is((select result->>'replayed' from rpc_results where label='unauthorized-invite-replay'),'true','unauthorized invite failure replays');
select is((select result->>'code' from rpc_results where label='unauthorized-invite-reuse'),'IDEMPOTENCY_KEY_REUSED','unauthorized invite different payload rejects key reuse');
select is((select result->>'code' from rpc_results where label='non-assignee-first'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-assignee progress returns cached domain failure');
select is((select result->>'replayed' from rpc_results where label='non-assignee-replay'),'true','non-assignee progress failure replays');
select is((select result->>'code' from rpc_results where label='non-assignee-reuse'),'IDEMPOTENCY_KEY_REUSED','non-assignee progress different payload rejects key reuse');
select is((select count(*)::integer from public.command_requests where request_id in ('42000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000002') and state='completed' and result->>'ok'='false'),2,'authorization failures are stored as completed ledger results');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into rpc_results values ('pending-direct-join',public.cmd_join_project_via_invite('pending-direct-token','43000000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->'data'->>'outcome' from rpc_results where label='pending-direct-join'),'joined','direct join succeeds for user with pending approval request');
select is((select state from public.project_join_requests where id='33000000-0000-0000-0000-00000000000c'),'canceled','direct join cancels prior pending request');
select is((select version from public.project_join_requests where id='33000000-0000-0000-0000-00000000000c'),2,'direct join versions canceled pending request');
select is((select array_agg(event_seq order by event_seq)::text from public.business_events where request_id='43000000-0000-0000-0000-000000000001'),'{1,2}','direct join emits complete ordered cancellation and membership events');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rpc_results values ('review-after-direct',pg_temp.capture_jsonb($call$select public.cmd_review_project_join_request('31000000-0000-0000-0000-00000000000c','33000000-0000-0000-0000-00000000000c','approve','43000000-0000-0000-0000-000000000002',2)$call$));
reset role;
select is((select result->>'code' from rpc_results where label='review-after-direct'),'ALREADY_MEMBER','review after direct join returns structured ALREADY_MEMBER');
select is((select count(*)::integer from public.command_requests where request_id='43000000-0000-0000-0000-000000000002' and state='completed' and result->>'code'='ALREADY_MEMBER'),1,'review ALREADY_MEMBER failure is cached');
select is((select count(*)::integer from public.business_events where request_id='43000000-0000-0000-0000-000000000002'),0,'review after direct join emits no event');

select throws_ok(
  $$update public.business_events set event_type='tampered' where true$$,
  '55000', 'Business events are immutable', 'events remain immutable'
);

select * from finish();
rollback;
