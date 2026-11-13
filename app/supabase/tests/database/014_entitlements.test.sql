begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','project_entitlements','legacy project entitlement history table is retained');
select has_table('public','project_entitlement_audit','legacy project entitlement audit table is retained');
select has_function('public','get_project_entitlement',array['uuid'],'project entitlement reader remains at the stable RPC name');
select has_function(
  'public','cmd_set_project_entitlement_service',
  array['uuid','uuid','text','text','timestamp with time zone','timestamp with time zone','uuid','text','text'],
  'legacy project entitlement command remains present for migration history compatibility'
);

select ok(not has_function_privilege('public','public.get_project_entitlement(uuid)','EXECUTE'),'PUBLIC cannot read project entitlement');
select ok(not has_function_privilege('anon','public.get_project_entitlement(uuid)','EXECUTE'),'anon cannot read project entitlement');
select ok(has_function_privilege('authenticated','public.get_project_entitlement(uuid)','EXECUTE'),'authenticated can use the effective project entitlement reader');

select ok(
  not has_function_privilege(
    'service_role',
    'public.cmd_set_project_entitlement_service(uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text,text)',
    'EXECUTE'
  ),
  'legacy direct project Pro grant command is retired for service operators'
);

select ok(not has_table_privilege('authenticated','public.project_entitlements','INSERT'),'browser still cannot insert legacy entitlement history');
select ok(not has_table_privilege('authenticated','public.project_entitlements','UPDATE'),'browser still cannot update legacy entitlement history');
select ok(not has_table_privilege('authenticated','public.project_entitlement_audit','SELECT'),'browser still cannot inspect legacy operator audit facts');

insert into auth.users(id,email) values
 ('f1100000-0000-0000-0000-000000000001','legacy-ent-leader@example.test');

insert into public.projects(
 id,name,timezone,deadline_at,contribution_mode,auto_penalty_enabled,
 require_real_name,require_student_number,leader_id,created_by,version
) values (
 'f2100000-0000-0000-0000-000000000001','Legacy entitlement retirement','Asia/Shanghai',
 now()+interval '20 days','weighted',false,false,false,
 'f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',1
);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version)
values(
 'f3100000-0000-0000-0000-000000000001','f2100000-0000-0000-0000-000000000001',
 'f1100000-0000-0000-0000-000000000001','leader','active',false,1
);

select is(
  (select count(*)::integer from public.project_entitlements where project_id='f2100000-0000-0000-0000-000000000001'),
  0,
  'new projects no longer receive legacy Free entitlement rows'
);

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
create temporary table legacy_entitlement_result as
select public.get_project_entitlement('f2100000-0000-0000-0000-000000000001') as result;
reset role;

select is(
  (select result->>'plan' from legacy_entitlement_result),
  'free',
  'stable project entitlement RPC now derives Free without a legacy row'
);
select is(
  (select result->>'state' from legacy_entitlement_result),
  'free',
  'stable project entitlement RPC returns the new effective state contract'
);
select ok(
  not ((select result from legacy_entitlement_result) ? 'version'),
  'effective project entitlement no longer exposes legacy writable version'
);

select * from finish();
rollback;
