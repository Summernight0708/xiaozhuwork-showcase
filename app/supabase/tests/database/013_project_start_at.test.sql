begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column('public','projects','start_at','projects persist an optional authoritative start time');
select col_type_is('public','projects','start_at','timestamp with time zone','project start time uses timestamptz');
select has_function(
  'public','cmd_create_project',
  array['uuid','integer','text','timestamp with time zone','text','text','text','text','boolean','boolean','timestamp with time zone','boolean'],
  'create project accepts an optional start time'
);
select has_function(
  'public','cmd_update_project_settings',
  array['uuid','uuid','integer','text','text','text','timestamp with time zone','text','text','boolean','boolean','boolean','timestamp with time zone','boolean'],
  'project settings accepts an optional start time'
);

insert into auth.users(id,email)
values ('e1100000-0000-0000-0000-000000000001','project-start-leader@example.test');

create temporary table project_start_results(label text primary key,result jsonb);
grant all on project_start_results to authenticated;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into project_start_results values('create',public.cmd_create_project(
  'e9100000-0000-0000-0000-000000000001',0,'Timed project',now()+interval '20 days',
  'Course',null,'Asia/Shanghai','weighted',false,false,now()-interval '1 day'
));
insert into project_start_results values('create-invalid-start',public.cmd_create_project(
  'e9100000-0000-0000-0000-000000000002',0,'Invalid timed project',now()+interval '10 days',
  null,null,'Asia/Shanghai','weighted',false,false,now()+interval '11 days'
));
reset role;

select is((select result->>'ok' from project_start_results where label='create'),'true','project creation with start time succeeds');
select is((select result->>'code' from project_start_results where label='create-invalid-start'),'VALIDATION_FAILED','project creation rejects start time on or after deadline');
select is((select result->>'field' from project_start_results where label='create-invalid-start'),'startAt','invalid start identifies startAt');

select (result->'data'->>'projectId')::uuid as project_id
from project_start_results where label='create' \gset

select is(
  (select start_at from public.projects where id=:'project_id'),
  now()-interval '1 day',
  'create project persists start_at'
);

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into project_start_results values('update-start',public.cmd_update_project_settings(
  :'project_id','e9100000-0000-0000-0000-000000000003',1,
  'Timed project','Course',null,
  (select deadline_at from public.projects where id=:'project_id'),
  'Asia/Shanghai','weighted',false,false,false,now()-interval '2 days'
));
insert into project_start_results values('update-invalid-start',public.cmd_update_project_settings(
  :'project_id','e9100000-0000-0000-0000-000000000004',2,
  'Timed project','Course',null,
  (select deadline_at from public.projects where id=:'project_id'),
  'Asia/Shanghai','weighted',false,false,false,now()+interval '21 days'
));
insert into project_start_results values('clear-start',public.cmd_update_project_settings(
  :'project_id','e9100000-0000-0000-0000-000000000005',2,
  'Timed project','Course',null,
  (select deadline_at from public.projects where id=:'project_id'),
  'Asia/Shanghai','weighted',false,false,false,null
));
reset role;

select is((select result->>'ok' from project_start_results where label='update-start'),'true','leader can update start time');
select is((select result->>'code' from project_start_results where label='update-invalid-start'),'VALIDATION_FAILED','settings reject start time on or after deadline');
select is((select result->>'field' from project_start_results where label='update-invalid-start'),'startAt','invalid settings start identifies startAt');
select is((select result->>'ok' from project_start_results where label='clear-start'),'true','start time remains optional and can be cleared');
select is((select start_at is null from public.projects where id=:'project_id'),true,'clearing start time persists');

select * from finish();
rollback;
