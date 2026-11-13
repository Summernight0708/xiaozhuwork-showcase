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


select has_table('public', 'project_calendar_subscriptions', 'E subscription table exists');
select has_function('public', 'cmd_create_calendar_feed_subscription',
  array['uuid','uuid','integer','boolean'], 'mint RPC exists');
select has_function('public', 'cmd_revoke_calendar_feed_subscription',
  array['uuid','uuid','uuid','integer'], 'revoke RPC exists');
select has_function('public', 'get_project_calendar_subscriptions',
  array['uuid'], 'metadata RPC exists');
select has_function('public', 'phase2_calendar_feed_lookup',
  array['text'], 'service-only lookup exists');
select ok((select relrowsecurity from pg_class where oid = 'public.project_calendar_subscriptions'::regclass),
  'RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.project_calendar_subscriptions', 'SELECT'),
  'authenticated cannot SELECT token hashes');
select ok(not has_table_privilege('authenticated', 'public.project_calendar_subscriptions', 'INSERT'),
  'authenticated cannot directly mint');
select ok(not has_function_privilege('authenticated',
  'public.phase2_calendar_feed_lookup(text)', 'EXECUTE'),
  'authenticated cannot execute secret lookup');
select ok(has_function_privilege('service_role',
  'public.phase2_calendar_feed_lookup(text)', 'EXECUTE'),
  'service_role can execute the narrowed lookup');

insert into auth.users(id,email) values
('e1100000-0000-0000-0000-000000000001','p2e-leader@example.test'),
('e1100000-0000-0000-0000-000000000002','p2e-member@example.test'),
('e1100000-0000-0000-0000-000000000003','p2e-grace@example.test');
insert into public.projects(id,name,leader_id,created_by,deadline_at) values
('e2100000-0000-0000-0000-000000000001','E Pro',
'e1100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',now()+interval '120 days'),
('e2100000-0000-0000-0000-000000000002','E Grace',
'e1100000-0000-0000-0000-000000000003','e1100000-0000-0000-0000-000000000003',now()+interval '120 days');
insert into public.project_members(project_id,user_id,role,member_state) values
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','leader','active'),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000002','member','active'),
('e2100000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000003','leader','active');
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'e1100000-0000-0000-0000-000000000001','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'e1100000-0000-0000-0000-000000000001','test',1
);
insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version) values
('e2100000-0000-0000-0000-000000000002',now()-interval '1 hour',now()+interval '1 day','account_expired',1);
insert into public.tasks(project_id,title,deadline_at,status) values
('e2100000-0000-0000-0000-000000000001','E Sensitive Name',now()+interval '10 days','not_started'),
('e2100000-0000-0000-0000-000000000001','E Completed',now()+interval '11 days','completed'),
('e2100000-0000-0000-0000-000000000002','E Other Project',now()+interval '12 days','not_started');

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
select is(
  (public.cmd_create_calendar_feed_subscription('e2100000-0000-0000-0000-000000000001',
    'e4100000-0000-0000-0000-000000000001',1,false)->>'code'),
  'CAPABILITY_NOT_AVAILABLE', 'closed before G release'
);
-- Simulate future G release solely in this rolled-back pgTAP transaction.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select p_capability = any(array['external_integrations','file_full_history',
    'file_batch_rollback','file_version_compare','project_recovery_point']::text[]);
$$;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000002',true);
select is(
  (public.cmd_create_calendar_feed_subscription('e2100000-0000-0000-0000-000000000001',
    'e4100000-0000-0000-0000-000000000002',1,false)->>'code'),
  'NOT_FOUND_OR_NOT_AUTHORIZED', 'member cannot mint token'
);

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
create temporary table e_issued as
  select public.cmd_create_calendar_feed_subscription(
    'e2100000-0000-0000-0000-000000000001',
    'e4100000-0000-0000-0000-000000000003',1,false) as result;
select is(result->>'ok','true','active Pro leader can mint') from e_issued;
select ok((result->'data'->>'token') ~ '^[0-9a-f]{64}$',
  'issued token contains 32 cryptographically random bytes as hex') from e_issued;
select ok(not exists(select 1 from public.command_requests cr
  where cr.project_id='e2100000-0000-0000-0000-000000000001'
  and cr.result::text like '%' || (select result->'data'->>'token' from e_issued) || '%'),
  'command result never persists plaintext token');
select ok(not exists(select 1 from public.business_events ev
  where ev.project_id='e2100000-0000-0000-0000-000000000001'
  and ev.event_data::text like '%' || (select result->'data'->>'token' from e_issued) || '%'),
  'audit never persists token');
select ok(exists(select 1 from public.project_calendar_subscriptions s
  where s.token_hash = extensions.digest(
    convert_to((select result->'data'->>'token' from e_issued),'utf8'),'sha256')),
  'only SHA256 digest is stored');
select ok((select expires_at - created_at <= interval '90 days'
  from public.project_calendar_subscriptions limit 1), 'expiry never exceeds 90 days');
select is(
 (public.cmd_create_calendar_feed_subscription(
  'e2100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000003',1,false)->'data'->>'token')::text,
 null::text, 'same request replay hides the token');
select is(
 (public.cmd_create_calendar_feed_subscription(
  'e2100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000003',1,true)->>'code'),
 'IDEMPOTENCY_KEY_REUSED', 'same request changed payload rejected');
select is(
 (public.phase2_calendar_feed_lookup((select result->'data'->>'token' from e_issued))
  ->'events'->0->>'title')::text, null::text,
 'default feed redacts task title');
select is(
 jsonb_array_length(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_issued))->'events'),
 1, 'only this project incomplete due tasks are returned');
select is(
 (public.phase2_calendar_feed_lookup(repeat('f',64)) is null)::text, 'true',
 'guessed token has no readable events');

select is(
 (public.cmd_revoke_calendar_feed_subscription(
   'e2100000-0000-0000-0000-000000000001',
   (select (result->'data'->>'id')::uuid from e_issued),
   'e4100000-0000-0000-0000-000000000004',1)->>'ok'),
 'true', 'leader can revoke subscription');
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_issued)) is null,
  'revoked token is unusable immediately');
select is(
 (public.cmd_revoke_calendar_feed_subscription(
   'e2100000-0000-0000-0000-000000000001',
   (select (result->'data'->>'id')::uuid from e_issued),
   'e4100000-0000-0000-0000-000000000004',1)->>'replayed'),
 'true', 'revoke is idempotent');
select is(
 (public.get_project_calendar_subscriptions(
   'e2100000-0000-0000-0000-000000000001')
    ->'data'->'subscriptions'->0 ? 'token_hash')::text,
 'false', 'metadata API never exposes token hash');
-- Renew with an entirely new secret, and verify explicit title opt-in.
create temporary table e_titles as
  select public.cmd_create_calendar_feed_subscription(
    'e2100000-0000-0000-0000-000000000001',
    'e4100000-0000-0000-0000-000000000005',2,true) as result;
select is(result->>'ok','true','new subscription after revocation can be issued') from e_titles;
select is(
  (public.phase2_calendar_feed_lookup((select result->'data'->>'token' from e_titles))
    ->'events'->0->>'title')::text,
  'E Sensitive Name', 'explicit title opt-in allows only task title');
select is(
 (public.cmd_create_calendar_feed_subscription(
  'e2100000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000006',1,false)->>'code'),
 'STALE_VERSION', 'stale project version rejected on mint');
-- Existing member promotion/delegation does not substitute for active issuer leadership.
update public.project_members set member_state='left', departed_at=now()
  where user_id='e1100000-0000-0000-0000-000000000001'
    and project_id='e2100000-0000-0000-0000-000000000001';
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_titles)) is null,
  'leader leaving project immediately invalidates feed');
update public.project_members set member_state='active', departed_at=null
  where user_id='e1100000-0000-0000-0000-000000000001'
    and project_id='e2100000-0000-0000-0000-000000000001';

-- Bound at most 500 events and mark truncation, never claim complete sync.
insert into public.tasks(project_id,title,deadline_at,status)
  select 'e2100000-0000-0000-0000-000000000001'::uuid,
    'Due task '||g::text, now()+interval '40 days','not_started'
  from generate_series(1,501) g;
select is(jsonb_array_length(
  public.phase2_calendar_feed_lookup((select result->'data'->>'token' from e_titles))
    ->'events'),500,'feed enforces hard 500 event limit');
select is(
 (public.phase2_calendar_feed_lookup((select result->'data'->>'token' from e_titles))
    ->>'truncated'),'true', '501+ tasks explicitly marked truncated');

-- A Grace project remains available until Grace ends, then immediately fails.
select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000003',true);
create temporary table e_grace as
  select public.cmd_create_calendar_feed_subscription(
    'e2100000-0000-0000-0000-000000000002',
    'e4100000-0000-0000-0000-000000000007',1,false) as result;
select is(result->>'ok','true','Grace leader may mint while released') from e_grace;
select is(jsonb_array_length(
  public.phase2_calendar_feed_lookup((select result->'data'->>'token' from e_grace))
    ->'events'),1,'Grace feed has own project events only');
update public.project_pro_grace set expires_at=transaction_timestamp()-interval '1 second'
  where project_id='e2100000-0000-0000-0000-000000000002';
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_grace)) is null,
  'Grace expiration instantly revokes future feed access');

-- Free after Grace cannot sign a new subscription, even with a fresh request ID.
select is(
 (public.cmd_create_calendar_feed_subscription(
    'e2100000-0000-0000-0000-000000000002',
    'e4100000-0000-0000-0000-000000000008',2,false)->>'code'),
 'CAPABILITY_REQUIRES_PRO', 'expired Grace fails new mint');
-- A previously authorized token expires independently of role/feature changes.
update public.project_calendar_subscriptions
  set created_at=transaction_timestamp()-interval '90 days',
      expires_at=transaction_timestamp()-interval '1 day'
  where id=(select (result->'data'->>'id')::uuid from e_titles);
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_titles)) is null,
  'expired token cannot fetch events');
select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
create temporary table e_gate as
  select public.cmd_create_calendar_feed_subscription(
    'e2100000-0000-0000-0000-000000000001',
    'e4100000-0000-0000-0000-000000000009',
    (select version from public.projects
      where id='e2100000-0000-0000-0000-000000000001'),false) as result;
select is(result->>'ok','true','fresh token available before feature disabled') from e_gate;
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_gate)) is not null,
  'fresh token can fetch before release gate closes');

-- Privileged service lookup must honor a subsequently disabled capability.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select p_capability = 'file_full_history';
$$;
select ok(public.phase2_calendar_feed_lookup(
  (select result->'data'->>'token' from e_gate)) is null,
  'disabling release gate immediately stops all calendar reads');


select * from finish();
rollback;
