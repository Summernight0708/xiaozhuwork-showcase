begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
('f1000000-0000-0000-0000-000000000001','f-leader@example.test'),
('f1000000-0000-0000-0000-000000000002','f-member@example.test'),
('f1000000-0000-0000-0000-000000000003','f-other@example.test');
update public.profiles set display_name='Lifecycle Member'
  where id::text like 'f1000000-0000-0000-0000-%';
-- Synthetic live GoTrue sessions; sensitive lifecycle RPCs reject legacy JWTs.
insert into auth.sessions(id,user_id)
 select id,id from auth.users where id::text like 'f1000000-0000-0000-0000-%';
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('f2000000-0000-0000-0000-000000000001','Lifecycle Test',
  now()+interval '180 days','f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values
('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','leader','active','Leader'),
('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','member','active','Member');
create temporary table f_results (name text primary key, result jsonb);
grant all on f_results to authenticated,anon,service_role;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"f1000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
insert into f_results values('leader-blocked',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000001',0));
reset role;
select is((select result->>'code' from f_results where name='leader-blocked'),
  'ACCOUNT_DELETION_BLOCKED','active leader must transfer responsibility');
select is((select count(*)::int from public.account_lifecycle_requests
  where user_id='f1000000-0000-0000-0000-000000000001'),0,
  'blocked request does not lock or delete user');

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"session_id":"f1000000-0000-0000-0000-000000000002"}',true);
set local role authenticated;
insert into f_results values('request',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000002',0));
insert into f_results values('replay',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000002',0));
insert into f_results values('stale',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000003',0));
insert into f_results values('key-reuse',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000002',1));
insert into f_results values('status',public.get_account_lifecycle_status());
reset role;

select is((select result->>'ok' from f_results where name='request'),
  'true','member can request account deletion');
select is((select result->>'replayed' from f_results where name='replay'),
  'true','same request ID and payload is idempotent');
select is((select result->>'code' from f_results where name='stale'),
  'STALE_VERSION','stale expectedVersion rejected');
select is((select result->>'code' from f_results where name='key-reuse'),
  'IDEMPOTENCY_KEY_REUSED','same request ID with changed version rejected');
select is((select result->'data'->>'state' from f_results where name='status'),
  'pending','status is account scoped');
select ok((select cancel_until>now()+interval '29 days' from public.account_lifecycle_requests
  where user_id='f1000000-0000-0000-0000-000000000002'),
  'database time defines the 30 day cancellation window');
select is((select count(*)::int from public.business_events
  where event_type='account_deletion_requested' and actor_id='f1000000-0000-0000-0000-000000000002'),
  1,'single immutable event for one request');
select ok(not has_table_privilege('authenticated','public.account_lifecycle_requests','UPDATE'),
  'normal users cannot edit lifecycle state directly');
select ok(not has_function_privilege('authenticated','public.lifecycle_worker_tick(integer)','EXECUTE'),
  'authenticated users cannot invoke worker');
select ok(not has_function_privilege('anon','public.lifecycle_worker_tick(integer)','EXECUTE'),
  'anonymous users cannot invoke worker');

-- Business read privileges are cut off even for previously issued JWTs.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::int from public.projects
  where id='f2000000-0000-0000-0000-000000000001'),
  0,'pending account is denied direct project reads');
insert into f_results values('cancel',public.cmd_cancel_account_deletion(
  'f3000000-0000-0000-0000-000000000004',1));
insert into f_results values('cancel-replay',public.cmd_cancel_account_deletion(
  'f3000000-0000-0000-0000-000000000004',1));
reset role;
select is((select result->>'ok' from f_results where name='cancel'),
  'true','original account can cancel during window');
select is((select result->>'replayed' from f_results where name='cancel-replay'),
  'true','cancel is idempotent');
select is((select state from public.account_lifecycle_requests
  where user_id='f1000000-0000-0000-0000-000000000002'),
  'canceled','state is canceled and history retained');
select is((select count(*)::int from public.projects
  where id='f2000000-0000-0000-0000-000000000001'),
  1,'cancellation has not destroyed shared project');

-- Cycle fixture exercises F before B is integrated and rolls back with this test.
do $$
begin
  if to_regclass('public.project_archive_cycles') is null then
    create table public.project_archive_cycles (
      project_id uuid not null references public.projects(id),
      generation integer not null,
      version integer not null,
      archived_at timestamptz not null,
      retain_until timestamptz not null,
      recovery_until timestamptz not null,
      restored_at timestamptz,
      primary key(project_id,generation)
    );
  end if;
end;
$$;
update public.projects set archived_at=now()-interval '360 days'
  where id='f2000000-0000-0000-0000-000000000001';
-- F-alone fixture is retained for standalone execution, while G uses B's
-- actual archive cycle schema, including its immutable reason/version fields.
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema='public'
       and table_name='project_archive_cycles'
       and column_name='archive_reason'
  ) then
    insert into public.project_archive_cycles(
      project_id,generation,version,archived_at,
      archive_reason,archived_project_version,
      retain_until,recovery_until,restored_at
    )
    select id,1,1,archived_at,'G isolated retention verification',version,
      now()+interval '5 days',now()+interval '35 days',null
    from public.projects where id='f2000000-0000-0000-0000-000000000001';
  else
    insert into public.project_archive_cycles(
      project_id,generation,version,archived_at,
      retain_until,recovery_until,restored_at
    )
    select id,1,1,archived_at,now()+interval '5 days',now()+interval '35 days',null
    from public.projects where id='f2000000-0000-0000-0000-000000000001';
  end if;
end;
$$;

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f_results values('retention-1',public.lifecycle_worker_tick(20));
insert into f_results values('retention-2',public.lifecycle_worker_tick(20));
reset role;
select is((select count(*)::int from public.project_retention_notices
 where project_id='f2000000-0000-0000-0000-000000000001'),1,
  'same archive generation emits a preexpiry notice only once');
select is((select count(*)::int from public.notifications
 where project_id='f2000000-0000-0000-0000-000000000001'
   and notification_type='project_retention'),2,
  'both active members receive one notice');
select is((select count(*)::int from private.project_purge_queue),0,
  'before recovery deadline no project purge candidate is created');
select is((select count(*)::int from public.projects
  where id='f2000000-0000-0000-0000-000000000001'),1,
  'worker never hard deletes active historical data');

-- A projectless account can request deletion without an invented project audit event.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"session_id":"f1000000-0000-0000-0000-000000000003"}',true);
set local role authenticated;
insert into f_results values('projectless',public.cmd_request_account_deletion(
  'f3000000-0000-0000-0000-000000000005',0));
reset role;
select is((select result->>'ok' from f_results where name='projectless'),'true',
  'projectless account can request its own deletion');
select is((select count(*)::int from private.account_lifecycle_audit
  where user_id='f1000000-0000-0000-0000-000000000003' and action='requested'),
  1,'projectless request leaves a private immutable audit');
select ok(not has_function_privilege('authenticated',
  'public.lifecycle_record_auth_revocation(uuid,integer)','EXECUTE'),
  'browser cannot certify completed Auth revocation');

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select ok(public.lifecycle_record_auth_revocation(
  'f1000000-0000-0000-0000-000000000003',1),
  'only service role can record a genuine external Auth revocation');
reset role;

-- Database time, not caller-provided time, determines the cancellation deadline.
update public.account_lifecycle_requests set
  requested_at=now()-interval '40 days',
  cancel_until=now()-interval '10 days'
where user_id='f1000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f_results values('expired',public.cmd_cancel_account_deletion(
  'f3000000-0000-0000-0000-000000000006',1));
reset role;
-- Once the trusted Auth service certifies revocation, the ordinary RPC
-- deliberately denies cancellation: G must provide the separate verified OTP path.
select is((select result->>'code' from f_results where name='expired'),
  'RETENTION_WINDOW_EXPIRED','expired cancellation rejects with database deadline');

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f_results values('expired-worker',public.lifecycle_worker_tick(20));
insert into f_results values('expired-worker-replay',public.lifecycle_worker_tick(20));
reset role;
select is((select state from public.account_lifecycle_requests
  where user_id='f1000000-0000-0000-0000-000000000003'),'blocked',
  'without global snapshot audit worker fails closed instead of claiming anonymization');
select is((select count(*)::int from private.account_lifecycle_audit
  where user_id='f1000000-0000-0000-0000-000000000003'
    and action='redaction_blocked'),1,
  'crash-safe repeated worker does not duplicate redaction-blocked audits');
select is((select result->'account'->>'irreversibleDeletes'
  from f_results where name='expired-worker'),'0',
  'service worker does not perform unsafe irreversible delete');
select is((select count(*)::int from auth.users
  where id='f1000000-0000-0000-0000-000000000003'),1,
  'Auth record is never hard-deleted by lifecycle worker');

select * from finish();
rollback;
