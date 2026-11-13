begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public','cmd_update_project_settings',
  array['uuid','uuid','integer','text','text','text','timestamp with time zone','text','text','boolean','boolean','boolean','timestamp with time zone','boolean'],
  'controlled project settings RPC exists'
);
select ok(not has_table_privilege('authenticated','public.projects','UPDATE'),'browser cannot directly update projects');

insert into auth.users(id,email) values
 ('d1100000-0000-0000-0000-000000000001','settings-leader@example.test'),
 ('d1100000-0000-0000-0000-000000000002','settings-admin@example.test'),
 ('d1100000-0000-0000-0000-000000000003','settings-member@example.test'),
 ('d1100000-0000-0000-0000-000000000004','settings-observer@example.test');

insert into public.projects(
 id,name,course_name,description,timezone,deadline_at,contribution_mode,auto_penalty_enabled,
 require_real_name,require_student_number,leader_id,created_by,version
) values(
 'd2100000-0000-0000-0000-000000000001','Old name',null,null,'Asia/Shanghai',now()+interval '20 days',
 'weighted',false,false,false,'d1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('d3100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('d3100000-0000-0000-0000-000000000002','d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002','admin','active',false,1),
 ('d3100000-0000-0000-0000-000000000003','d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000003','member','active',false,1),
 ('d3100000-0000-0000-0000-000000000004','d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000004','observer','active',true,1);

insert into public.projects(
 id,name,timezone,deadline_at,contribution_mode,auto_penalty_enabled,
 require_real_name,require_student_number,leader_id,created_by,version
) values(
 'd2100000-0000-0000-0000-000000000002','Expired active project','Asia/Shanghai',now()-interval '1 day',
 'weighted',false,false,false,'d1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('d3100000-0000-0000-0000-000000000005','d2100000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000001','leader','active',false,1);

create temporary table settings_rpc_results(label text primary key,result jsonb);
grant all on settings_rpc_results to authenticated;

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into settings_rpc_results values('metadata',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000001',1,
 'Renamed project','Course X','Description',now()+interval '22 days','Asia/Tokyo','weighted',false,false,false
));
insert into settings_rpc_results values('metadata-replay',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000001',1,
 'Renamed project','Course X','Description',now()+interval '22 days','Asia/Tokyo','weighted',false,false,false
));
insert into settings_rpc_results values('metadata-reuse',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000001',1,
 'Different','Course X','Description',now()+interval '22 days','Asia/Tokyo','weighted',false,false,false
));
insert into settings_rpc_results values('mode-before-tasks',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000002',2,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,false,false
));
insert into settings_rpc_results values('expired-metadata',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000002','d9100000-0000-0000-0000-000000000012',1,
 'Expired renamed',null,'Metadata correction',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000002'),
 'Asia/Shanghai','weighted',false,false,false
));
reset role;

select is((select result->>'ok' from settings_rpc_results where label='metadata'),'true','leader updates safe project metadata');
select is((select result->>'replayed' from settings_rpc_results where label='metadata-replay'),'true','project settings command replays');
select is((select result->>'code' from settings_rpc_results where label='metadata-reuse'),'IDEMPOTENCY_KEY_REUSED','project settings rejects request id reuse');
select is((select name from public.projects where id='d2100000-0000-0000-0000-000000000001'),'Renamed project','name persists');
select is((select timezone from public.projects where id='d2100000-0000-0000-0000-000000000001'),'Asia/Tokyo','timezone persists as display rule');
select is((select contribution_mode from public.projects where id='d2100000-0000-0000-0000-000000000001'),'facts_only','leader may change contribution mode before any task exists');
select is((select result->>'ok' from settings_rpc_results where label='expired-metadata'),'true','active project with elapsed existing deadline still allows safe metadata correction');
select is((select name from public.projects where id='d2100000-0000-0000-0000-000000000002'),'Expired renamed','elapsed-deadline metadata correction persists');
select is((select version from public.projects where id='d2100000-0000-0000-0000-000000000001'),3,'settings changes advance project version');

insert into public.tasks(id,project_id,title,created_by,deadline_at,status,weight,assignment_state,version)
values(
 'd4100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001',
 'Existing task','d1100000-0000-0000-0000-000000000003',now()+interval '10 days',
 'not_started',null,'claimable',1
);

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into settings_rpc_results values('mode-after-task',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000003',3,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','weighted',false,false,false
));
insert into settings_rpc_results values('raise-identity',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000004',3,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,true,false
));
insert into settings_rpc_results values('enable-penalty',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000005',3,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',true,false,false
));
insert into settings_rpc_results values('short-deadline',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000006',3,
 'Renamed project','Course X','Description',now()+interval '5 days',
 'Asia/Tokyo','facts_only',false,false,false
));
insert into settings_rpc_results values('bad-timezone',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000007',3,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Mars/Olympus','facts_only',false,false,false
));
insert into settings_rpc_results values('stale',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000008',2,
 'Renamed project','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,false,false
));
reset role;

select is((select result->>'code' from settings_rpc_results where label='mode-after-task'),'CONFIRMATION_REQUIRED','contribution mode freezes behind governance once tasks exist');
select is((select result->>'field' from settings_rpc_results where label='mode-after-task'),'contributionMode','mode governance identifies field');
select is((select result->>'code' from settings_rpc_results where label='raise-identity'),'CONFIRMATION_REQUIRED','raising identity requirements after joins needs unanimous confirmation');
select is((select result->>'code' from settings_rpc_results where label='enable-penalty'),'FEATURE_DISABLED','auto penalty remains disabled until the penalty system exists');
select is((select result->>'code' from settings_rpc_results where label='short-deadline'),'VALIDATION_FAILED','project deadline cannot move before an existing task deadline');
select is((select result->>'field' from settings_rpc_results where label='short-deadline'),'deadlineAt','deadline protection identifies field');
select is((select result->>'code' from settings_rpc_results where label='bad-timezone'),'VALIDATION_FAILED','timezone must be an IANA timezone');
select is((select result->>'code' from settings_rpc_results where label='stale'),'STALE_VERSION','project settings use optimistic concurrency');
select is((select result->>'currentVersion' from settings_rpc_results where label='stale'),'3','stale settings response returns project version');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into settings_rpc_results values('admin-denied',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000009',3,
 'Admin edit','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,false,false
));
reset role;
select is((select result->>'code' from settings_rpc_results where label='admin-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','admin does not receive governance-sensitive project settings power');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into settings_rpc_results values('observer-denied',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000010',3,
 'Observer edit','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,false,false
));
reset role;
select is((select result->>'code' from settings_rpc_results where label='observer-denied'),'NOT_AUTHORIZED','observer is read-only');

update public.projects set lifecycle_state='contribution_review',version=version+1 where id='d2100000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into settings_rpc_results values('review-lock',public.cmd_update_project_settings(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000011',4,
 'No late edits','Course X','Description',(select deadline_at from public.projects where id='d2100000-0000-0000-0000-000000000001'),
 'Asia/Tokyo','facts_only',false,false,false
));
reset role;
select is((select result->>'code' from settings_rpc_results where label='review-lock'),'PROJECT_NOT_ACTIVE','project settings freeze when contribution review starts');

select is((select count(*)::integer from public.business_events where event_type='project_settings_updated' and project_id='d2100000-0000-0000-0000-000000000001'),2,'successful settings changes are audited');

select * from finish();
rollback;
