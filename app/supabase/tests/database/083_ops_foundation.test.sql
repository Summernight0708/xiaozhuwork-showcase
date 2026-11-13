begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('private','ops_admins','ops admins live in private schema');
select has_table('private','ops_admin_audit','ops admin changes are audited');
select has_table('private','ops_access_audit','account support reads are audited');

select ok(not has_table_privilege('anon','private.ops_admins','SELECT'),'anon cannot read ops admins');
select ok(not has_table_privilege('authenticated','private.ops_admins','SELECT'),'authenticated cannot read ops admins');
select ok(not has_table_privilege('service_role','private.ops_admins','SELECT'),'service role uses RPC boundary');
select ok(not has_table_privilege('service_role','private.ops_access_audit','SELECT'),'service role cannot browse support audit directly');

select ok(has_function_privilege('service_role','public.ops_assert_access_service(uuid)','EXECUTE'),'service role can assert ops access');
select ok(not has_function_privilege('authenticated','public.ops_assert_access_service(uuid)','EXECUTE'),'browser cannot assert ops access directly');
select ok(has_function_privilege('service_role','public.ops_get_account_support_summary_service(uuid,text,uuid)','EXECUTE'),'service role can run audited lookup');
select ok(not has_function_privilege('anon','public.ops_get_account_support_summary_service(uuid,text,uuid)','EXECUTE'),'anon cannot run lookup');

insert into auth.users(id,email,email_confirmed_at,created_at,last_sign_in_at) values
('0a000000-0000-0000-0000-000000000001','ops-admin@example.test',now()-interval '10 days',now()-interval '10 days',now()-interval '1 hour'),
('0a000000-0000-0000-0000-000000000002','disabled-ops@example.test',now()-interval '9 days',now()-interval '9 days',now()-interval '2 hours'),
('0b000000-0000-0000-0000-000000000001','target.exact@example.test',now()-interval '8 days',now()-interval '8 days',now()-interval '3 hours'),
('0b000000-0000-0000-0000-000000000002','target.extra@example.test',now()-interval '7 days',now()-interval '7 days',now()-interval '4 hours');

insert into private.ops_admins(user_id,enabled,created_at,created_by) values
('0a000000-0000-0000-0000-000000000001',true,now()-interval '2 days','0a000000-0000-0000-0000-000000000001'),
('0a000000-0000-0000-0000-000000000002',false,now()-interval '2 days','0a000000-0000-0000-0000-000000000001');

insert into public.projects(id,name,deadline_at,leader_id,created_by,lifecycle_state,completed_at) values
('0c000000-0000-0000-0000-000000000001','OPS_SECRET_ACTIVE_PROJECT',now()+interval '30 days','0b000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000001','active',null),
('0c000000-0000-0000-0000-000000000002','OPS_SECRET_COMPLETED_PROJECT',now()-interval '1 day','0b000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000001','completed',now()-interval '1 day');

insert into public.project_members(project_id,user_id,role,member_state,is_observer,joined_at,departed_at,display_name_snapshot) values
('0c000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000001','leader','active',false,now()-interval '8 days',null,'OPS SECRET USER NAME'),
('0c000000-0000-0000-0000-000000000002','0b000000-0000-0000-0000-000000000001','leader','left',false,now()-interval '8 days',now()-interval '1 day','OPS SECRET USER NAME');

insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until,updated_at)
values('0b000000-0000-0000-0000-000000000001','pending',1,1,now()-interval '1 day',now()+interval '29 days',now()-interval '1 day');

insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,granted_at,grant_source,version)
values('0b000000-0000-0000-0000-000000000001','pro','active',now()-interval '2 days',now()+interval '28 days',now()-interval '2 days','test',1);

insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,event_data,created_at) values
('0c000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000001','task_submitted','task','0d000000-0000-0000-0000-000000000001','{"taskTitle":"OPS_SECRET_TASK_TITLE","fileName":"OPS_SECRET_FILE.pdf"}'::jsonb,now()-interval '10 minutes'),
('0c000000-0000-0000-0000-000000000001','0b000000-0000-0000-0000-000000000001','task_completed','task','0d000000-0000-0000-0000-000000000001','{"body":"OPS_SECRET_SUBMISSION_BODY"}'::jsonb,now()-interval '5 minutes');

create temp table ops_results(label text primary key,result jsonb);
grant all on ops_results to service_role;
select set_config('request.jwt.claim.role','',true);
set local role service_role;
insert into ops_results values('enabled',public.ops_assert_access_service('0a000000-0000-0000-0000-000000000001'));
insert into ops_results values('disabled',public.ops_assert_access_service('0a000000-0000-0000-0000-000000000002'));
insert into ops_results values('normal-user',public.ops_assert_access_service('0b000000-0000-0000-0000-000000000001'));
insert into ops_results values(
  'email',
  public.ops_get_account_support_summary_service(
    '0a000000-0000-0000-0000-000000000001',
    'target.exact@example.test',
    '0e000000-0000-0000-0000-000000000001'
  )
);
insert into ops_results values(
  'uuid',
  public.ops_get_account_support_summary_service(
    '0a000000-0000-0000-0000-000000000001',
    '0b000000-0000-0000-0000-000000000001',
    '0e000000-0000-0000-0000-000000000002'
  )
);
insert into ops_results values(
  'partial-email',
  public.ops_get_account_support_summary_service(
    '0a000000-0000-0000-0000-000000000001',
    'target',
    '0e000000-0000-0000-0000-000000000003'
  )
);
insert into ops_results values(
  'wildcard-email',
  public.ops_get_account_support_summary_service(
    '0a000000-0000-0000-0000-000000000001',
    '%@example.test',
    '0e000000-0000-0000-0000-000000000006'
  )
);
insert into ops_results values(
  'missing-email',
  public.ops_get_account_support_summary_service(
    '0a000000-0000-0000-0000-000000000001',
    'missing@example.test',
    '0e000000-0000-0000-0000-000000000004'
  )
);
reset role;

select is((select result->>'ok' from ops_results where label='enabled'),'true','enabled ops admin is authorized');
select is((select result->>'code' from ops_results where label='disabled'),'FORBIDDEN','disabled ops admin is rejected');
select is((select result->>'code' from ops_results where label='normal-user'),'FORBIDDEN','normal XiaozhuWork user is not ops admin');

select is((select result->>'ok' from ops_results where label='email'),'true','exact email lookup succeeds');
select is((select result->'data'->>'schemaVersion' from ops_results where label='email'),'1','L1 DTO schema version is frozen');
select is((select result->'data'->>'userId' from ops_results where label='email'),'0b000000-0000-0000-0000-000000000001','exact email resolves target');
select is((select result->'data'->>'accountState' from ops_results where label='email'),'pending','account lifecycle state is reported');
select is((select result->'data'->>'activeProjectCount' from ops_results where label='email'),'1','active project count excludes completed or inactive membership');
select is((select result->'data'->>'historicalProjectCount' from ops_results where label='email'),'2','historical project count includes prior membership');
select is((select result->'data'->>'plan' from ops_results where label='email'),'pro','plan reuses entitlement state');
select is((select result->'data'->>'entitlementState' from ops_results where label='email'),'active','entitlement state is reported');
select ok((select result->'data' ? 'proExpiresAt' from ops_results where label='email'),'pro expiry field is present');
select is(jsonb_array_length((select result->'data'->'recentActivity' from ops_results where label='email')),2,'recent activity is bounded to event facts');
select ok(
  (select (result->'data'->'recentActivity'->0) ? 'eventType'
       and (result->'data'->'recentActivity'->0) ? 'at'
       and not ((result->'data'->'recentActivity'->0) ? 'eventData')
   from ops_results where label='email'),
  'recent activity exposes only event type and time'
);

select is((select result->'data'->>'userId' from ops_results where label='uuid'),'0b000000-0000-0000-0000-000000000001','exact UUID lookup resolves target');
select is((select result->>'code' from ops_results where label='partial-email'),'VALIDATION_FAILED','partial email search is rejected');
select is((select result->>'code' from ops_results where label='wildcard-email'),'VALIDATION_FAILED','wildcard email search is rejected');
select is((select result->>'code' from ops_results where label='missing-email'),'NOT_FOUND','missing exact email is not found');

select is(
  (select count(*)::integer from private.ops_access_audit
   where operator_user_id='0a000000-0000-0000-0000-000000000001'
     and target_user_id='0b000000-0000-0000-0000-000000000001'
     and action='account_support_view'),
  2,
  'each successful L1 view is audited'
);
select ok(
  not exists(
    select 1 from private.ops_access_audit
    where request_id in (
      '0e000000-0000-0000-0000-000000000003',
      '0e000000-0000-0000-0000-000000000004'
    )
  ),
  'rejected lookups do not create false view audits'
);
select ok(
  (select result::text not like '%OPS_SECRET_ACTIVE_PROJECT%'
      and result::text not like '%OPS_SECRET_COMPLETED_PROJECT%'
      and result::text not like '%OPS_SECRET_TASK_TITLE%'
      and result::text not like '%OPS_SECRET_FILE.pdf%'
      and result::text not like '%OPS_SECRET_SUBMISSION_BODY%'
      and result::text not like '%OPS SECRET USER NAME%'
   from ops_results where label='email'),
  'L1 DTO contains no project task file body or profile content'
);

select throws_ok(
  $$update private.ops_access_audit set action='tampered' where true$$,
  '55000','OPS_AUDIT_IMMUTABLE','support access audit is immutable'
);
select throws_ok(
  $$delete from private.ops_admin_audit where true$$,
  '55000','OPS_AUDIT_IMMUTABLE','ops admin audit is immutable'
);

create function private.test_fail_ops_access_audit()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  raise exception using errcode='55000', message='OPS_AUDIT_FORCED_FAILURE';
end;
$$;
create trigger test_fail_ops_access_audit
before insert on private.ops_access_audit
for each row execute function private.test_fail_ops_access_audit();

select set_config('request.jwt.claim.role','',true);
set local role service_role;
select throws_ok(  $$select public.ops_get_account_support_summary_service(
      '0a000000-0000-0000-0000-000000000001',
      'target.exact@example.test',
      '0e000000-0000-0000-0000-000000000005'
    )$$,
  '55000','OPS_AUDIT_FORCED_FAILURE',
  'audit failure is fail closed'
);
reset role;

select set_config('request.jwt.claim.role','',true);
set local role service_role;
insert into ops_results values('service-role-without-legacy-claim',public.ops_assert_access_service('0a000000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'ok' from ops_results where label='service-role-without-legacy-claim'),'true','service_role grant works without legacy JWT claim');
select * from finish();
rollback;
