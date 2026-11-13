begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Owner tests still exercise the unreleased -> released transition after G publishes.
-- Keep this override transaction-local; ROLLBACK restores the migrated release allowlist.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select coalesce(p_capability = any(array[
    'file_full_history','file_batch_rollback','file_version_compare','project_recovery_point'
  ]::text[]), false);
$$;
revoke all on function private.capability_is_released(text)
  from public, anon, authenticated, service_role;


select has_table('public','project_permission_delegations','D delegation table exists');
select has_function('private','phase2_can_delegate_project_action',
  array['uuid','uuid','text'],'D private permission helper exists');
select has_function('public','cmd_set_project_permission_delegation',
  array['uuid','uuid','text','boolean','integer','uuid'],'D controlled command exists');
select has_function('public','get_project_permission_delegations',
  array['uuid'],'D scoped read RPC exists');
select ok(not private.capability_is_released('advanced_permissions'),
  'D never publishes advanced_permissions in business migration');
select ok(not has_table_privilege('authenticated','public.project_permission_delegations','INSERT'),
  'authenticated cannot insert delegation rows directly');
select ok(not has_table_privilege('authenticated','public.project_permission_delegations','UPDATE'),
  'authenticated cannot revoke delegation rows directly');
select ok(not has_function_privilege('authenticated',
  'private.phase2_can_delegate_project_action(uuid,uuid,text)','EXECUTE'),
  'private helper is not directly executable by authenticated');
select ok(not private.capability_is_released('arbitrary_code'),
  'unknown capability is closed');

insert into auth.users(id,email)
select ('a1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       'p2-d-'||i||'@example.test'
from generate_series(1,12) s(i);
update public.profiles set display_name='P2 D tester',real_name='P2 Name',
  student_number='P2 Student'
where id::text like 'a1100000-0000-0000-0000-%';

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values
('a2100000-0000-0000-0000-000000000001','D Pro',now()+interval '25 days',
 'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',1),
('a2100000-0000-0000-0000-000000000002','D Free',now()+interval '25 days',
 'a1100000-0000-0000-0000-000000000008','a1100000-0000-0000-0000-000000000008',1);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer)
values
('a3100000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','leader','active',false),
('a3100000-0000-0000-0000-000000000002','a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002','member','active',false),
('a3100000-0000-0000-0000-000000000003','a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003','member','active',false),
('a3100000-0000-0000-0000-000000000004','a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000004','admin','active',false),
('a3100000-0000-0000-0000-000000000005','a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000005','observer','active',true),
('a3100000-0000-0000-0000-000000000008','a2100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000008','leader','active',false),
('a3100000-0000-0000-0000-000000000009','a2100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000009','member','active',false);
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values('a1100000-0000-0000-0000-000000000001','pro','active',
  now()-interval '1 day',now()+interval '25 days',now(),
  'a1100000-0000-0000-0000-000000000001','test',1);

create temporary table d_results(label text primary key,result jsonb);
grant all on d_results to authenticated;

-- Production state: Pro alone is not enough; template releases belong to G.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into d_results values('unreleased',
  public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'code' from d_results where label='unreleased'),
  'CAPABILITY_NOT_AVAILABLE','unreleased Pro delegation is rejected');
select is((select count(*)::int from public.project_permission_delegations),0,
  'unreleased command creates no delegation');

-- Test-only release simulation rolls back with this test transaction.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select p_capability=any(array[
    'file_full_history','file_batch_rollback','file_version_compare',
    'project_recovery_point','advanced_permissions'
  ]::text[]);
$$;

-- Even after release, Free projects cannot grant a template.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000008',true);
set local role authenticated;
insert into d_results values('free',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000002',
    'a3100000-0000-0000-0000-000000000009',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000002'));
reset role;
select is((select result->>'code' from d_results where label='free'),
  'CAPABILITY_REQUIRES_PRO','released template still requires Pro/Grace');

-- Admin, member, observer, outsider and invalid template are denied.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into d_results values('admin-grant',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000003'));
reset role;
select is((select result->>'code' from d_results where label='admin-grant'),
  'NOT_FOUND_OR_NOT_AUTHORIZED','admin cannot grant templates');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into d_results values('self-grant',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000004'));
reset role;
select is((select result->>'code' from d_results where label='self-grant'),
  'NOT_FOUND_OR_NOT_AUTHORIZED','member cannot self-escalate');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into d_results values('observer-grant',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000005'));
insert into d_results values('observer-read',
 public.get_project_permission_delegations('a2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'code' from d_results where label='observer-grant'),
  'NOT_AUTHORIZED','observer cannot manage templates');
select is((select jsonb_array_length(result->'data'->'delegations')
  from d_results where label='observer-read'),0,'observer sees empty assignments');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000006',true);
set local role authenticated;
insert into d_results values('outsider-read',
 public.get_project_permission_delegations('a2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'code' from d_results where label='outsider-read'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot enumerate permission assignments');

-- Grant to two distinct members, then verify version, audit and idempotency.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into d_results values('bad-template',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'arbitrary_role',true,1,
    'a4100000-0000-0000-0000-000000000006'));
insert into d_results values('grant-invite',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000007'));
insert into d_results values('grant-intake',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000003',
    'intake_reviewer',true,1,
    'a4100000-0000-0000-0000-000000000008'));
insert into d_results values('replay',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',true,1,
    'a4100000-0000-0000-0000-000000000007'));
insert into d_results values('reused-key',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',false,1,
    'a4100000-0000-0000-0000-000000000007'));
insert into d_results values('stale',
 public.cmd_set_project_permission_delegation(
    'a2100000-0000-0000-0000-000000000001',
    'a3100000-0000-0000-0000-000000000002',
    'invitation_coordinator',false,1,
    'a4100000-0000-0000-0000-000000000009'));
insert into d_results values('leader-read',
 public.get_project_permission_delegations('a2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'code' from d_results where label='bad-template'),
  'VALIDATION_FAILED','invalid template rejected');
select is((select result->>'ok' from d_results where label='grant-invite'),
  'true','leader grants invite template');
select is((select result->>'ok' from d_results where label='grant-intake'),
  'true','leader grants intake template');
select is((select result->>'replayed' from d_results where label='replay'),
  'true','same request replays');
select is((select result->>'code' from d_results where label='reused-key'),
  'IDEMPOTENCY_KEY_REUSED','request id cannot be used for distinct payload');
select is((select result->>'code' from d_results where label='stale'),
  'STALE_VERSION','membership version rejects stale update');
select is((select result->'data'->>'membershipVersion' from d_results where label='grant-invite'),
  '2','membership version increments on grant');
select is((select jsonb_array_length(result->'data'->'delegations')
  from d_results where label='leader-read'),2,'leader reads both assigned templates');
select is((select count(*)::int from public.business_events
  where event_type='project_permission_delegation_granted'),2,'grant audit event not duplicated');
select is((select role from public.project_members
  where id='a3100000-0000-0000-0000-000000000002'),
  'member','grant does not change base role');
select ok(private.phase2_can_delegate_project_action(
    'a2100000-0000-0000-0000-000000000001',
    'a1100000-0000-0000-0000-000000000002',
    'project_invite_manage') is false,
 'private helper rejects mismatched auth.uid even with delegation');

-- Invite management and join review operate through the existing RPC kernel.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into d_results values('member-read',
 public.get_project_permission_delegations('a2100000-0000-0000-0000-000000000001'));
insert into d_results values('created-invite',
 public.cmd_create_project_invite(
   'a2100000-0000-0000-0000-000000000001',
   'a4100000-0000-0000-0000-000000000010',1,'approval',7,6));
reset role;
select is((select jsonb_array_length(result->'data'->'delegations')
  from d_results where label='member-read'),1,'member sees only own template');
select is((select result->>'ok' from d_results where label='created-invite'),
 'true','invitation coordinator invokes original invitation creation RPC');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into d_results values('renewed-invite',
 public.cmd_renew_project_invite(
   'a2100000-0000-0000-0000-000000000001',
   (select (result->'data'->>'invitationId')::uuid from d_results where label='created-invite'),
   'a4100000-0000-0000-0000-000000000011',1,7));
insert into d_results values('revoked-invite',
 public.cmd_revoke_project_invite(
   'a2100000-0000-0000-0000-000000000001',
   (select (result->'data'->>'invitationId')::uuid from d_results where label='created-invite'),
   'a4100000-0000-0000-0000-000000000012',2));
reset role;
select is((select result->>'ok' from d_results where label='renewed-invite'),
 'true','invitation coordinator renews invitation');
select is((select result->>'ok' from d_results where label='revoked-invite'),
 'true','invitation coordinator revokes invitation');

insert into public.project_invitations(
  id,project_id,created_by,token_hash,mode,expires_at,max_uses
) values
('a5100000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000001',
 'a1100000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('d-intake-token','utf8'),'sha256'),
 'approval',now()+interval '5 days',10);
insert into public.project_join_requests(id,invitation_id,project_id,user_id,state)
values
('a6100000-0000-0000-0000-000000000001','a5100000-0000-0000-0000-000000000001',
 'a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000010','pending'),
('a6100000-0000-0000-0000-000000000002','a5100000-0000-0000-0000-000000000001',
 'a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000011','pending');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into d_results values('intake-approved',
 public.cmd_review_project_join_request(
   'a2100000-0000-0000-0000-000000000001',
   'a6100000-0000-0000-0000-000000000001','approve',
   'a4100000-0000-0000-0000-000000000013',1));
insert into d_results values('intake-rejected',
 public.cmd_review_project_join_request(
   'a2100000-0000-0000-0000-000000000001',
   'a6100000-0000-0000-0000-000000000002','reject',
   'a4100000-0000-0000-0000-000000000014',1));
reset role;
select is((select result->>'ok' from d_results where label='intake-approved'),
 'true','intake reviewer can approve through final P1 RPC');
select is((select result->>'ok' from d_results where label='intake-rejected'),
 'true','intake reviewer can reject through final P1 RPC');
select is((select event_type from public.business_events
  where request_id='a4100000-0000-0000-0000-000000000013'),
 'project_join_request_approved','intake emits original review audit event');
select is((select count(*)::int from public.project_members
  where project_id='a2100000-0000-0000-0000-000000000001'
  and user_id='a1100000-0000-0000-0000-000000000010'),1,
  'approval adds exactly one member');

-- Revocation is effective without reload or reconnect.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into d_results values('revoke-coordinator',
 public.cmd_set_project_permission_delegation(
   'a2100000-0000-0000-0000-000000000001',
   'a3100000-0000-0000-0000-000000000002',
   'invitation_coordinator',false,2,
   'a4100000-0000-0000-0000-000000000015'));
reset role;
select is((select result->>'ok' from d_results where label='revoke-coordinator'),
  'true','leader revokes template');
select is((select count(*)::int from public.project_permission_delegations
 where revoked_at is null and membership_id='a3100000-0000-0000-0000-000000000002'),0,
 'revoked assignment has no active row');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into d_results values('invite-after-revoke',
 public.cmd_create_project_invite(
   'a2100000-0000-0000-0000-000000000001',
   'a4100000-0000-0000-0000-000000000016',2,'approval',7,6));
reset role;
select is((select result->>'code' from d_results where label='invite-after-revoke'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','revocation rejects next invite command immediately');

-- An observer who retains an assignment record never has delegated powers.
update public.project_members set role='observer',is_observer=true,version=version+1
where id='a3100000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into d_results values('intake-after-observer',
 public.cmd_review_project_join_request(
   'a2100000-0000-0000-0000-000000000001',
   'a6100000-0000-0000-0000-000000000002','reject',
   'a4100000-0000-0000-0000-000000000017',2));
reset role;
select is((select result->>'code' from d_results where label='intake-after-observer'),
 'NOT_AUTHORIZED','observer transition kills delegated review');
select is((select count(*)::int from public.project_permission_delegations
  where membership_id='a3100000-0000-0000-0000-000000000003'
    and revoked_at is null),1,'inactive delegation record preserved');

-- Pro -> Grace retains effective delegation. After the final historical Pro source
-- is removed, Grace -> Free immediately suspends without deleting rows.
update public.account_entitlements set expires_at=now()-interval '1 minute'
where user_id='a1100000-0000-0000-0000-000000000001';
select is((select state from private.resolve_project_entitlement('a2100000-0000-0000-0000-000000000001',transaction_timestamp())),
 'grace','recent source expiry enters Grace');
select ok(private.project_has_capability('a2100000-0000-0000-0000-000000000001','advanced_permissions'),
 'Grace retains released delegation capability');
delete from public.account_entitlements where user_id='a1100000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into d_results values('downgrade-read',
 public.get_project_permission_delegations('a2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->'data'->'capability'->>'effective'
  from d_results where label='downgrade-read'),'false',
  'Free downgrade suspends template effectiveness');
select ok((select bool_and((e->>'effective')::boolean=false)
  from d_results r, jsonb_array_elements(r.result->'data'->'delegations') e
  where r.label='downgrade-read'), 'all preserved assignments are ineffective on Free');

select * from finish();
rollback;
