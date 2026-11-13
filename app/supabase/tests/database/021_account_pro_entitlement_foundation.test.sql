begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','account_entitlements','account entitlement source of truth exists');
select has_table('public','account_entitlement_audit','account entitlement audit exists');
select has_table('public','project_pro_grace','project grace facts exist');
select has_table('private','account_entitlement_service_commands','account entitlement service ledger exists');

select has_function('private','assert_no_legacy_project_pro',array[]::text[],'legacy Pro guard exists');
select has_function('private','is_account_pro',array['uuid','timestamp with time zone'],'account Pro helper exists');
select has_function('private','account_entitlement_state',array['uuid','timestamp with time zone'],'account state helper exists');
select has_function('private','project_has_active_account_pro_source',array['uuid','timestamp with time zone'],'project account source helper exists');
select has_function('private','project_last_account_pro_source_end',array['uuid','timestamp with time zone'],'project source end helper exists');
select has_function('private','has_project_level_pro_grant',array['uuid','timestamp with time zone'],'future project grant seam exists');
select has_function('private','resolve_project_entitlement',array['uuid','timestamp with time zone'],'project resolver exists');
select has_function('private','project_member_limit',array['uuid','timestamp with time zone'],'member limit helper exists');
select has_function('private','project_concurrent_task_limit',array['uuid','timestamp with time zone'],'task limit helper exists');
select has_function('private','account_active_free_project_count',array['uuid','timestamp with time zone'],'account Free project counter exists');
select has_function('private','account_can_add_free_project',array['uuid','timestamp with time zone'],'account Free project admission helper exists');
select has_function('private','project_has_capability',array['uuid','text'],'capability helper exists');
select has_function('public','get_my_account_entitlement',array[]::text[],'safe account entitlement getter exists');
select has_function('public','get_project_entitlement',array['uuid'],'effective project entitlement getter exists');
select has_function(
  'public','cmd_set_account_entitlement_service',
  array['uuid','uuid','text','text','timestamp with time zone','timestamp with time zone','integer','uuid','text','text'],
  'service-only account entitlement command exists'
);

select ok(
  (select relrowsecurity from pg_class where oid='public.account_entitlements'::regclass),
  'account_entitlements has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.account_entitlement_audit'::regclass),
  'account_entitlement_audit has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.project_pro_grace'::regclass),
  'project_pro_grace has RLS enabled'
);

select ok(not has_table_privilege('authenticated','public.account_entitlements','SELECT'),'browser cannot select account entitlement rows directly');
select ok(not has_table_privilege('authenticated','public.account_entitlements','INSERT'),'browser cannot insert account entitlement rows');
select ok(not has_table_privilege('authenticated','public.account_entitlements','UPDATE'),'browser cannot update account entitlement rows');
select ok(not has_table_privilege('service_role','public.account_entitlements','UPDATE'),'service role must use account command');
select ok(not has_table_privilege('authenticated','public.account_entitlement_audit','SELECT'),'browser cannot inspect account audit rows');
select ok(not has_table_privilege('service_role','public.account_entitlement_audit','INSERT'),'service role cannot forge account audit directly');
select ok(not has_table_privilege('authenticated','public.project_pro_grace','SELECT'),'browser cannot inspect project grace rows directly');
select ok(not has_table_privilege('service_role','public.project_pro_grace','UPDATE'),'service role cannot mutate grace directly');

select ok(not has_function_privilege('public','public.get_my_account_entitlement()','EXECUTE'),'PUBLIC cannot call account entitlement getter');
select ok(not has_function_privilege('anon','public.get_my_account_entitlement()','EXECUTE'),'anon cannot call account entitlement getter');
select ok(has_function_privilege('authenticated','public.get_my_account_entitlement()','EXECUTE'),'authenticated can call account entitlement getter');
select ok(not has_function_privilege('authenticated','public.cmd_set_account_entitlement_service(uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,integer,uuid,text,text)','EXECUTE'),'browser cannot mutate account entitlement');
select ok(has_function_privilege('service_role','public.cmd_set_account_entitlement_service(uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,integer,uuid,text,text)','EXECUTE'),'service role can use account entitlement command');
select ok(not has_function_privilege('service_role','public.cmd_set_project_entitlement_service(uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text,text)','EXECUTE'),'legacy project grant command is retired');
select ok(
  not exists(
    select 1 from pg_trigger
    where tgrelid='public.projects'::regclass
      and tgname='projects_initialize_entitlement'
      and not tgisinternal
  ),
  'new projects no longer initialize legacy project entitlement rows'
);

insert into auth.users(id,email) values
 ('b1100000-0000-0000-0000-000000000001','p0-leader@example.test'),
 ('b1100000-0000-0000-0000-000000000002','p0-member@example.test'),
 ('b1100000-0000-0000-0000-000000000003','p0-observer@example.test'),
 ('b1100000-0000-0000-0000-000000000004','p0-second-pro@example.test'),
 ('b1100000-0000-0000-0000-000000000005','p0-free@example.test'),
 ('b1100000-0000-0000-0000-000000000006','p0-service-target@example.test'),
 ('b1100000-0000-0000-0000-000000000007','p0-grace-member@example.test'),
 ('b1100000-0000-0000-0000-000000000008','p0-other-leader@example.test'),
 ('b1100000-0000-0000-0000-000000000009','p0-counter@example.test');

insert into public.projects(
 id,name,timezone,deadline_at,contribution_mode,auto_penalty_enabled,
 require_real_name,require_student_number,leader_id,created_by,version
) values
 ('b2100000-0000-0000-0000-000000000001','P0 primary','Asia/Shanghai',now()+interval '20 days','weighted',false,false,false,'b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',1),
 ('b2100000-0000-0000-0000-000000000002','Observer source check','Asia/Shanghai',now()+interval '20 days','weighted',false,false,false,'b1100000-0000-0000-0000-000000000008','b1100000-0000-0000-0000-000000000008',1),
 ('b2100000-0000-0000-0000-000000000003','Dynamic grace','Asia/Shanghai',now()+interval '20 days','weighted',false,false,false,'b1100000-0000-0000-0000-000000000008','b1100000-0000-0000-0000-000000000008',1),
 ('b2100000-0000-0000-0000-000000000004','Membership grace','Asia/Shanghai',now()+interval '20 days','weighted',false,false,false,'b1100000-0000-0000-0000-000000000008','b1100000-0000-0000-0000-000000000008',1),
 ('b2100000-0000-0000-0000-000000000005','Service cancellation grace','Asia/Shanghai',now()+interval '20 days','weighted',false,false,false,'b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',1);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('b3100000-0000-0000-0000-000000000001','b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000002','b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000002','member','active',false,1),
 ('b3100000-0000-0000-0000-000000000003','b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000003','observer','active',true,1),
 ('b3100000-0000-0000-0000-000000000012','b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000004','member','active',false,1),
 ('b3100000-0000-0000-0000-000000000004','b2100000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000008','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000005','b2100000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000003','observer','active',true,1),
 ('b3100000-0000-0000-0000-000000000006','b2100000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000008','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000007','b2100000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000007','member','active',false,1),
 ('b3100000-0000-0000-0000-000000000008','b2100000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000008','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000009','b2100000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000007','member','active',false,1),
 ('b3100000-0000-0000-0000-000000000010','b2100000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000011','b2100000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000006','member','active',false,1);

select is(
  (select count(*)::integer from public.project_entitlements where project_id in (
    'b2100000-0000-0000-0000-000000000001',
    'b2100000-0000-0000-0000-000000000002',
    'b2100000-0000-0000-0000-000000000003',
    'b2100000-0000-0000-0000-000000000004',
    'b2100000-0000-0000-0000-000000000005'
  )),
  0,
  'new projects create no legacy entitlement rows'
);

create temporary table p0_results(label text primary key,result jsonb);
grant all on p0_results to authenticated, service_role;

-- Account getter: Free with no row.
select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into p0_results values('account-free',public.get_my_account_entitlement());
reset role;
select is((select result->>'plan' from p0_results where label='account-free'),'free','no account row is Free');
select is((select result->>'state' from p0_results where label='account-free'),'free','no account row has free state');
select is((select (result->>'version')::integer from p0_results where label='account-free'),0,'no account row uses version zero');

-- Account getter: scheduled / active / expired / cancelled are derived, not persisted as extra statuses.
insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,note,version
) values (
 'b1100000-0000-0000-0000-000000000002','pro','active',now()+interval '1 day',now()+interval '10 days',
 now(),'b1100000-0000-0000-0000-000000000001','test','scheduled',1
);

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p0_results values('account-scheduled',public.get_my_account_entitlement());
reset role;
select is((select result->>'plan' from p0_results where label='account-scheduled'),'free','scheduled account is effectively Free');
select is((select result->>'state' from p0_results where label='account-scheduled'),'scheduled','future Pro reports scheduled');

update public.account_entitlements
set starts_at=now()-interval '1 day', expires_at=now()+interval '10 days', version=2
where user_id='b1100000-0000-0000-0000-000000000002';
set local role authenticated;
insert into p0_results values('account-active',public.get_my_account_entitlement());
reset role;
select is((select result->>'plan' from p0_results where label='account-active'),'pro','active account is Pro');
select is((select result->>'state' from p0_results where label='account-active'),'active','active account reports active');

update public.account_entitlements
set expires_at=now()-interval '1 second', version=3
where user_id='b1100000-0000-0000-0000-000000000002';
set local role authenticated;
insert into p0_results values('account-expired',public.get_my_account_entitlement());
reset role;
select is((select result->>'plan' from p0_results where label='account-expired'),'free','expired account is effectively Free');
select is((select result->>'state' from p0_results where label='account-expired'),'expired','expired account reports expired');

update public.account_entitlements
set status='cancelled', expires_at=now()+interval '10 days', version=4
where user_id='b1100000-0000-0000-0000-000000000002';
set local role authenticated;
insert into p0_results values('account-cancelled',public.get_my_account_entitlement());
reset role;
select is((select result->>'plan' from p0_results where label='account-cancelled'),'free','cancelled account is effectively Free');
select is((select result->>'state' from p0_results where label='account-cancelled'),'cancelled','cancelled account reports cancelled');
select ok(not ((select result from p0_results where label='account-cancelled') ? 'grantSource'),'account getter does not leak grant source');
select ok(not ((select result from p0_results where label='account-cancelled') ? 'note'),'account getter does not leak operator note');

-- Project resolver: qualifying roles provide Pro, observer does not.
update public.account_entitlements
set status='active', starts_at=now()-interval '1 day', expires_at=now()+interval '10 days', version=5
where user_id='b1100000-0000-0000-0000-000000000002';

insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values
 ('b1100000-0000-0000-0000-000000000003','pro','active',now()-interval '1 day',now()+interval '10 days',now(),'b1100000-0000-0000-0000-000000000001','test',1),
 ('b1100000-0000-0000-0000-000000000004','pro','active',now()-interval '1 day',now()+interval '10 days',now(),'b1100000-0000-0000-0000-000000000001','test',1);

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p0_results values('project-member-pro',public.get_project_entitlement('b2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'plan' from p0_results where label='project-member-pro'),'pro','active Pro member makes project Pro');
select is((select result->>'state' from p0_results where label='project-member-pro'),'active','member Pro project state is active');
select is((select result->>'source' from p0_results where label='project-member-pro'),'account_member','member Pro source is redacted to account_member');
select ok(not ((select result from p0_results where label='project-member-pro') ? 'version'),'project getter exposes no legacy writable version');
select ok(not ((select result from p0_results where label='project-member-pro') ? 'expiresAt'),'project getter exposes no account source expiry');

-- Losing one of multiple qualifying Pro sources must not start grace.
update public.account_entitlements
set expires_at=now()-interval '1 second', version=6
where user_id='b1100000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p0_results values('project-one-source-expired',public.get_project_entitlement('b2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'state' from p0_results where label='project-one-source-expired'),'active','project stays active while another qualifying Pro source remains');
select is((select count(*)::integer from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000001'),0,'losing one of multiple Pro sources does not create grace');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000008',true);
set local role authenticated;
insert into p0_results values('project-observer-pro',public.get_project_entitlement('b2100000-0000-0000-0000-000000000002'));
reset role;
select is((select result->>'plan' from p0_results where label='project-observer-pro'),'free','observer Pro does not make project Pro');
select is((select result->>'source' from p0_results where label='project-observer-pro'),'none','observer Pro is not a project source');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into p0_results values('project-non-member',public.get_project_entitlement('b2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'code' from p0_results where label='project-non-member'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-member cannot read project entitlement');

-- Natural expiry derives grace without cron.
insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
 'b1100000-0000-0000-0000-000000000007','pro','active',now()-interval '10 days',now()-interval '1 day',
 now()-interval '10 days','b1100000-0000-0000-0000-000000000001','test',1
);
select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000008',true);
set local role authenticated;
insert into p0_results values('project-natural-grace',public.get_project_entitlement('b2100000-0000-0000-0000-000000000003'));
reset role;
select is((select result->>'state' from p0_results where label='project-natural-grace'),'grace','natural expiry produces grace without cron');
select is((select result->>'source' from p0_results where label='project-natural-grace'),'grace','natural expiry source is grace');
select ok((select result->>'graceExpiresAt' from p0_results where label='project-natural-grace') is not null,'natural grace exposes its end time');

update public.account_entitlements
set expires_at=now()-interval '4 days'
where user_id='b1100000-0000-0000-0000-000000000007';
set local role authenticated;
insert into p0_results values('project-grace-ended',public.get_project_entitlement('b2100000-0000-0000-0000-000000000003'));
reset role;
select is((select result->>'state' from p0_results where label='project-grace-ended'),'free','grace ends automatically after three days');

-- Persisted old grace never masks a new active source.
insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values('b2100000-0000-0000-0000-000000000001',now()-interval '1 day',now()+interval '2 days','account_expired',1);
select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p0_results values('project-active-over-grace',public.get_project_entitlement('b2100000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'state' from p0_results where label='project-active-over-grace'),'active','active source outranks persisted grace');

-- Service-only command: create, replay, reuse, stale, update and cancel.
set local role service_role;
insert into p0_results values('service-grant',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000001',
 'pro','active','2026-01-01T00:00:00Z','2027-12-31T00:00:00Z',0,
 'b1100000-0000-0000-0000-000000000001','test','first grant'
));
insert into p0_results values('service-grant-replay',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000001',
 'pro','active','2026-01-01T00:00:00Z','2027-12-31T00:00:00Z',0,
 'b1100000-0000-0000-0000-000000000001','test','first grant'
));
insert into p0_results values('service-reuse',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000001',
 'pro','active','2026-01-01T00:00:00Z','2027-12-31T00:00:00Z',0,
 'b1100000-0000-0000-0000-000000000001','test','changed payload'
));
insert into p0_results values('service-stale',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000002',
 'pro','active','2026-01-01T00:00:00Z','2028-12-31T00:00:00Z',0,
 'b1100000-0000-0000-0000-000000000001','test','stale update'
));
insert into p0_results values('service-update',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000003',
 'pro','active','2026-01-01T00:00:00Z','2028-12-31T00:00:00Z',1,
 'b1100000-0000-0000-0000-000000000001','test','extend'
));
insert into p0_results values('service-cancel',public.cmd_set_account_entitlement_service(
 'b1100000-0000-0000-0000-000000000006',
 'b9100000-0000-0000-0000-000000000004',
 'pro','cancelled','2026-01-01T00:00:00Z','2028-12-31T00:00:00Z',2,
 'b1100000-0000-0000-0000-000000000001','test','manual cancel'
));
reset role;

select is((select result->>'ok' from p0_results where label='service-grant'),'true','service grant succeeds');
select is((select result->>'replayed' from p0_results where label='service-grant-replay'),'true','identical service request replays');
select is((select result->>'code' from p0_results where label='service-reuse'),'IDEMPOTENCY_KEY_REUSED','service request id cannot be reused with different payload');
select is((select result->>'code' from p0_results where label='service-stale'),'STALE_VERSION','stale account mutation is rejected');
select is((select (result->>'currentVersion')::integer from p0_results where label='service-stale'),1,'stale response exposes current version');
select is((select (result->'data'->>'version')::integer from p0_results where label='service-update'),2,'valid account update increments version');
select is((select (result->'data'->>'version')::integer from p0_results where label='service-cancel'),3,'cancellation increments version');
select is((select status from public.account_entitlements where user_id='b1100000-0000-0000-0000-000000000006'),'cancelled','cancellation persists cancelled status');
select ok((select expires_at <= now() from public.account_entitlements where user_id='b1100000-0000-0000-0000-000000000006'),'cancellation shrinks effective expiry to cancellation time');
select is((select count(*)::integer from public.account_entitlement_audit where user_id='b1100000-0000-0000-0000-000000000006'),3,'grant update and cancel append exactly three audit facts');
select is((select count(*)::integer from public.account_entitlement_audit where request_id='b9100000-0000-0000-0000-000000000001'),1,'service replay creates one audit fact');
select is((select state from private.account_entitlement_state('b1100000-0000-0000-0000-000000000006',now())),'cancelled','cancelled service entitlement is not active');
select is((select state from private.resolve_project_entitlement('b2100000-0000-0000-0000-000000000005',now())),'grace','cancelling final account source creates project grace');

-- Membership source loss creates or preserves grace.
update public.account_entitlements
set status='active',starts_at=now()-interval '2 days',expires_at=now()+interval '10 days',version=2
where user_id='b1100000-0000-0000-0000-000000000007';
update public.project_members
set role='observer',is_observer=true,version=version+1
where id='b3100000-0000-0000-0000-000000000009';
select is((select state from private.resolve_project_entitlement('b2100000-0000-0000-0000-000000000004',now())),'grace','last Pro member becoming observer creates grace');
select is((select reason from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000004'),'member_became_observer','observer transition records stable grace reason');

update public.project_members
set role='member',is_observer=false,version=version+1
where id='b3100000-0000-0000-0000-000000000009';
update public.project_pro_grace
set started_at=now()-interval '1 day',expires_at=now()+interval '2 days'
where project_id='b2100000-0000-0000-0000-000000000004';
update public.project_members
set role='observer',is_observer=true,version=version+1
where id='b3100000-0000-0000-0000-000000000009';
select ok(
  (select expires_at >= now()+interval '2 days 23 hours' from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000004'),
  'a genuinely restored active source earns a fresh full grace when lost again'
);

-- Active voluntary leave of the last qualifying Pro member starts a full grace window.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values(
 'b2100000-0000-0000-0000-000000000006','Voluntary leave grace',now()+interval '10 days',
 'b1100000-0000-0000-0000-000000000008','b1100000-0000-0000-0000-000000000008',1
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('b3100000-0000-0000-0000-000000000013','b2100000-0000-0000-0000-000000000006','b1100000-0000-0000-0000-000000000008','leader','active',false,1),
 ('b3100000-0000-0000-0000-000000000014','b2100000-0000-0000-0000-000000000006','b1100000-0000-0000-0000-000000000004','member','active',false,1);
update public.project_members
set member_state='left',departed_at=now(),version=version+1
where id='b3100000-0000-0000-0000-000000000014';
select is((select state from private.resolve_project_entitlement('b2100000-0000-0000-0000-000000000006',now())),'grace','last active Pro member leaving starts grace');
select is((select reason from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000006'),'member_left','voluntary leave records member_left grace reason');

-- An expired account member leaving during dynamic grace preserves the original grace end instead of restarting it.
update public.account_entitlements
set status='active',starts_at=now()-interval '10 days',expires_at=now()-interval '1 day',version=3
where user_id='b1100000-0000-0000-0000-000000000007';
update public.project_members
set role='member',is_observer=false,member_state='active',departed_at=null,version=version+1
where id='b3100000-0000-0000-0000-000000000007';
delete from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000003';
update public.project_members
set member_state='left',departed_at=now(),version=version+1
where id='b3100000-0000-0000-0000-000000000007';
select ok(
  abs(extract(epoch from (
    (select expires_at from public.project_pro_grace where project_id='b2100000-0000-0000-0000-000000000003')
    - ((select expires_at from public.account_entitlements where user_id='b1100000-0000-0000-0000-000000000007') + interval '3 days')
  ))) < 1,
  'membership loss during natural grace preserves the original expiry'
);

-- Limits and capability foundation.
select is(private.project_member_limit('b2100000-0000-0000-0000-000000000002',now()),8,'Free project member limit is 8');
select is(private.project_concurrent_task_limit('b2100000-0000-0000-0000-000000000002',now()),20,'Free project concurrent task limit is 20');
select is(private.project_member_limit('b2100000-0000-0000-0000-000000000001',now()),20,'Pro project member limit is 20');
select is(private.project_concurrent_task_limit('b2100000-0000-0000-0000-000000000001',now()),100,'Pro project concurrent task limit is 100');
select ok(private.project_has_capability('b2100000-0000-0000-0000-000000000001','file_full_history'),'released file capability is available for Pro');
select ok(not private.project_has_capability('b2100000-0000-0000-0000-000000000001','unknown_capability'),'unknown capability fails closed');

-- Account active Free project count includes observer participation, excludes archived and Pro/Grace projects.
insert into public.projects(id,name,deadline_at,leader_id,created_by,archived_at,version) values
 ('b2200000-0000-0000-0000-000000000001','Count 1',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1),
 ('b2200000-0000-0000-0000-000000000002','Count 2',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1),
 ('b2200000-0000-0000-0000-000000000003','Count 3',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1),
 ('b2200000-0000-0000-0000-000000000004','Count 4',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1),
 ('b2200000-0000-0000-0000-000000000005','Count 5',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1),
 ('b2200000-0000-0000-0000-000000000006','Archived',now()+interval '10 days','b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001',null,1);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('b3200000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000002','b2200000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000003','b2200000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000004','b2200000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000005','b2200000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000006','b2200000-0000-0000-0000-000000000006','b1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3200000-0000-0000-0000-000000000007','b2200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000009','observer','active',true,1),
 ('b3200000-0000-0000-0000-000000000008','b2200000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000009','observer','active',true,1),
 ('b3200000-0000-0000-0000-000000000009','b2200000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000009','observer','active',true,1),
 ('b3200000-0000-0000-0000-000000000010','b2200000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000009','observer','active',true,1),
 ('b3200000-0000-0000-0000-000000000011','b2200000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000009','observer','active',true,1),
 ('b3200000-0000-0000-0000-000000000012','b2200000-0000-0000-0000-000000000006','b1100000-0000-0000-0000-000000000009','observer','active',true,1);
-- Historical member records predate archiving.
update public.projects set archived_at=now()
where id='b2200000-0000-0000-0000-000000000006';

select is(private.account_active_free_project_count('b1100000-0000-0000-0000-000000000009',now()),5,'active Free count includes observer memberships and excludes archived projects');
select ok(not private.account_can_add_free_project('b1100000-0000-0000-0000-000000000009',now()),'Free account at five active Free projects cannot add another Free project');

insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values(
 'b1100000-0000-0000-0000-000000000009','pro','active',now()-interval '1 day',now()+interval '10 days',
 now(),'b1100000-0000-0000-0000-000000000001','test',1
);
select ok(private.account_can_add_free_project('b1100000-0000-0000-0000-000000000009',now()),'active Pro account is not blocked by Free account project quota');

-- Audit is append-only.
select throws_ok(
  $$update public.account_entitlement_audit set note='forged' where user_id='b1100000-0000-0000-0000-000000000006'$$,
  '55000',
  'Account entitlement audit is immutable',
  'account audit updates are rejected'
);
select throws_ok(
  $$delete from public.account_entitlement_audit where user_id='b1100000-0000-0000-0000-000000000006'$$,
  '55000',
  'Account entitlement audit is immutable',
  'account audit deletes are rejected'
);

-- Legacy project Pro migration guard fails closed on every historical/effective shape.
insert into public.project_entitlements(
 project_id,plan,status,starts_at,expires_at,granted_at,grant_source,version
) values(
 'b2100000-0000-0000-0000-000000000002','free','active',
 now()-interval '1 day',null,now(),'legacy_free_fixture',1
);
select lives_ok(
  $$select private.assert_no_legacy_project_pro()$$,
  'legacy Free-only rows do not block the migration guard'
);

update public.project_entitlements
set plan='early_access_pro',status='active',starts_at=now()-interval '1 day',expires_at=now()+interval '1 day'
where project_id='b2100000-0000-0000-0000-000000000002';
select throws_ok(
  $$select private.assert_no_legacy_project_pro()$$,
  'P0001',
  'LEGACY_PROJECT_PRO_FOUND',
  'active legacy Early Access Pro fails closed'
);

update public.project_entitlements
set status='cancelled',starts_at=now()-interval '2 days',expires_at=now()+interval '1 day'
where project_id='b2100000-0000-0000-0000-000000000002';
select throws_ok(
  $$select private.assert_no_legacy_project_pro()$$,
  'P0001',
  'LEGACY_PROJECT_PRO_FOUND',
  'cancelled legacy Early Access Pro fails closed'
);

update public.project_entitlements
set status='active',starts_at=now()-interval '2 days',expires_at=now()-interval '1 day'
where project_id='b2100000-0000-0000-0000-000000000002';
select throws_ok(
  $$select private.assert_no_legacy_project_pro()$$,
  'P0001',
  'LEGACY_PROJECT_PRO_FOUND',
  'expired legacy Early Access Pro fails closed'
);

update public.project_entitlements
set status='active',starts_at=now()+interval '1 day',expires_at=now()+interval '2 days'
where project_id='b2100000-0000-0000-0000-000000000002';
select throws_ok(
  $$select private.assert_no_legacy_project_pro()$$,
  'P0001',
  'LEGACY_PROJECT_PRO_FOUND',
  'future legacy Early Access Pro fails closed'
);

delete from public.project_entitlements where project_id='b2100000-0000-0000-0000-000000000002';

select * from finish();
rollback;
