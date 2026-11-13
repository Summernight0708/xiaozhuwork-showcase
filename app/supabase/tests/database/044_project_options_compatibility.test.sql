begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select is((select count(*)::integer from pg_proc where pronamespace='public'::regnamespace and proname='cmd_create_project'),1,'one create-project signature, no ambiguous overload');
select is((select count(*)::integer from pg_proc where pronamespace='public'::regnamespace and proname='cmd_update_project_settings'),1,'one settings signature, no ambiguous overload');
select ok(not has_function_privilege('anon','public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean)','EXECUTE'),'anonymous cannot create projects');
select ok(has_function_privilege('authenticated','public.cmd_update_project_settings(uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean,timestamptz,boolean)','EXECUTE'),'authenticated retains settings RPC grant');

insert into auth.users(id,email) values
 ('f1100000-0000-0000-0000-000000000001','compat-leader@example.test'),
 ('f1100000-0000-0000-0000-000000000002','compat-admin@example.test'),
 ('f1100000-0000-0000-0000-000000000003','compat-member@example.test'),
 ('f1100000-0000-0000-0000-000000000004','compat-observer@example.test');
create temporary table compat_results(label text primary key,result jsonb);
grant all on compat_results to authenticated;
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into compat_results values ('legacy-create',public.cmd_create_project(
 'f9100000-0000-0000-0000-000000000001',0,'Legacy call',now()+interval '20 days'
));
insert into compat_results values ('configured-create',public.cmd_create_project(
 p_request_id=>'f9100000-0000-0000-0000-000000000002',p_name=>'Configured project',
 p_deadline_at=>now()+interval '20 days',p_contribution_mode=>'facts_only',p_allow_member_task_creation=>false
));
reset role;
select is((select result->>'ok' from compat_results where label='legacy-create'),'true','old positional create call succeeds');
select ok((select allow_member_task_creation from public.projects where id=(select (result#>>'{data,projectId}')::uuid from compat_results where label='legacy-create')),'old calls default to member creation enabled');
select is((select contribution_mode from public.projects where id=(select (result#>>'{data,projectId}')::uuid from compat_results where label='legacy-create')),'weighted','old calls default to weighted mode');
select is((select result->>'ok' from compat_results where label='configured-create'),'true','create accepts both disabled settings');

create function pg_temp.compat_project() returns uuid language sql as $$
 select (result#>>'{data,projectId}')::uuid from compat_results where label='configured-create'
$$;
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
select pg_temp.compat_project(),id,role,'active',role='observer' from (values
 ('f1100000-0000-0000-0000-000000000002'::uuid,'admin'),
 ('f1100000-0000-0000-0000-000000000003'::uuid,'member'),
 ('f1100000-0000-0000-0000-000000000004'::uuid,'observer')
) members(id,role);

create function pg_temp.compat_settings(p_allow boolean default null,p_mode text default 'facts_only',p_expected integer default 1,p_request uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.cmd_update_project_settings(
   p_project_id=>p.id,p_request_id=>p_request,p_expected_version=>p_expected,
   p_name=>p.name,p_course_name=>p.course_name,p_description=>p.description,
   p_deadline_at=>p.deadline_at,p_timezone=>p.timezone,p_contribution_mode=>p_mode,
   p_auto_penalty_enabled=>p.auto_penalty_enabled,p_require_real_name=>p.require_real_name,
   p_require_student_number=>p.require_student_number,p_allow_member_task_creation=>p_allow
 ) from public.projects p where p.id=pg_temp.compat_project()
$$;

set local role authenticated;
insert into compat_results values ('old-settings',public.cmd_update_project_settings(
 pg_temp.compat_project(),'f9100000-0000-0000-0000-000000000003',1,'Configured project',null,null,
 now()+interval '20 days','Asia/Shanghai','facts_only',false,false,false
));
reset role;
select is((select result->>'ok' from compat_results where label='old-settings'),'true','legacy settings call is still accepted');
select ok(not (select allow_member_task_creation from public.projects where id=pg_temp.compat_project()),'omitted option does not re-enable member creation');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(pg_temp.compat_settings(true)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','admin cannot change project options');
reset role;
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is(pg_temp.compat_settings(true)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','member cannot change project options');
reset role;
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is(pg_temp.compat_settings(true)->>'code','NOT_AUTHORIZED','observer cannot change project options');
reset role;

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(pg_temp.compat_settings(true,'weighted',0)->>'code','STALE_VERSION','settings toggle honors expected version');
select is(pg_temp.compat_settings(true,'weighted',1,'f9100000-0000-0000-0000-000000000004')->>'ok','true','leader switches both options before tasks');
select is(pg_temp.compat_settings(true,'weighted',1,'f9100000-0000-0000-0000-000000000004')->>'replayed','true','toggle replay is idempotent');
select is(pg_temp.compat_settings(false,'weighted',1,'f9100000-0000-0000-0000-000000000004')->>'code','IDEMPOTENCY_KEY_REUSED','changed toggle payload cannot reuse request id');
reset role;
select ok((select event_data->'changedFields' @> '["allowMemberTaskCreation","contributionMode"]'::jsonb from public.business_events where project_id=pg_temp.compat_project() and event_type='project_settings_updated'),'audit names both changed fields');

set local role authenticated;
select is(pg_temp.compat_settings(false,'facts_only',2)->>'ok','true','leader can switch both options back before tasks');
insert into compat_results values ('leader-task',public.cmd_create_task(
 pg_temp.compat_project(),'f9100000-0000-0000-0000-000000000005',3,'Facts-only task',null,now()+interval '2 days'
));
reset role;
select is((select result->>'ok' from compat_results where label='leader-task'),'true','leader creates tasks with member creation disabled');
select ok((select weight is null from public.tasks where project_id=pg_temp.compat_project()),'facts-only task persists without star weight');
set local role authenticated;
select is(pg_temp.compat_settings(false,'weighted',4)->>'code','CONFIRMATION_REQUIRED','any task locks contribution mode');
select is(pg_temp.compat_settings(true,'facts_only',4)->>'ok','true','member creation remains changeable after tasks');
reset role;
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is(public.cmd_create_task(pg_temp.compat_project(),gen_random_uuid(),5,'Member after re-enable',null,now()+interval '2 days')->>'ok','true','member can create after re-enable');
reset role;
select * from finish();
rollback;
