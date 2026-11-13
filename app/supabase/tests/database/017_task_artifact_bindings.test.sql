begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_artifact_bindings','artifact binding current-state table exists');
select has_table('public','task_artifact_binding_history','artifact binding immutable history exists');
select has_function('public','get_upstream_artifacts',array['uuid'],'formal upstream artifact query boundary exists');
select has_function(
  'public','cmd_record_task_artifact_use',array['uuid','uuid','uuid','uuid'],
  'real artifact use can create an idempotent light binding'
);
select has_function(
  'public','cmd_set_task_artifact_binding_strength',
  array['uuid','uuid','uuid','text','uuid','integer'],
  'binding strength changes are explicit'
);
select has_function(
  'public','cmd_switch_task_artifact_binding_version',
  array['uuid','uuid','uuid','uuid','integer'],
  'binding version switches are explicit'
);

insert into auth.users(id,email) values
 ('a1100000-0000-0000-0000-000000000001','artifact-leader@example.test'),
 ('a1100000-0000-0000-0000-000000000002','artifact-strong@example.test'),
 ('a1100000-0000-0000-0000-000000000003','artifact-light@example.test'),
 ('a1100000-0000-0000-0000-000000000004','artifact-observer@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
 ('a1200000-0000-0000-0000-000000000001','Artifact bindings',now()+interval '30 days',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',1),
 ('a1200000-0000-0000-0000-000000000002','Other artifact project',now()+interval '30 days',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',1);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('a1210000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('a1210000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002','member','active',false,1),
 ('a1210000-0000-0000-0000-000000000003','a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003','member','active',false,1),
 ('a1210000-0000-0000-0000-000000000004','a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000004','observer','active',true,1),
 ('a1210000-0000-0000-0000-000000000005','a1200000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000001','leader','active',false,1);

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,assignment_state,accepted_at,completed_at,version
) values
 ('a1300000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','Upstream data',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
  now()+interval '10 days','completed','assigned',now(),now(),1),
 ('a1300000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000001','Strong downstream',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002',
  now()+interval '12 days','in_progress','assigned',now(),null,1),
 ('a1300000-0000-0000-0000-000000000003','a1200000-0000-0000-0000-000000000001','Light downstream',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003',
  now()+interval '13 days','in_progress','assigned',now(),null,1),
 ('a1300000-0000-0000-0000-000000000004','a1200000-0000-0000-0000-000000000001','Unrelated upstream',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
  now()+interval '9 days','completed','assigned',now(),now(),1),
 ('a1300000-0000-0000-0000-000000000005','a1200000-0000-0000-0000-000000000002','Other project task',
  'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
  now()+interval '9 days','completed','assigned',now(),now(),1);

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by) values
 ('a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000001'),
 ('a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000003','a1100000-0000-0000-0000-000000000001');

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('a1400000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001',
  'a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
  'new_file',null,null,'artifacts/data-v3.xlsx','data.xlsx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values(
 'a1500000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001',
 'a1300000-0000-0000-0000-000000000001','data.xlsx','a1100000-0000-0000-0000-000000000001',1
);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'a1600000-0000-0000-0000-000000000003','a1500000-0000-0000-0000-000000000001',
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001',
 'a1400000-0000-0000-0000-000000000001',3,'artifacts/data-v3.xlsx','data.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('a',64),
 'a1100000-0000-0000-0000-000000000001'
);
update public.task_files
set current_version_id='a1600000-0000-0000-0000-000000000003'
where id='a1500000-0000-0000-0000-000000000001';

create temporary table artifact_results(label text primary key,result jsonb);
grant all on artifact_results to authenticated;

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into artifact_results values('mark-v3',public.cmd_set_task_file_version_final(
 'a1200000-0000-0000-0000-000000000001','a1600000-0000-0000-0000-000000000003',
 'a1900000-0000-0000-0000-000000000001',0,true
));
reset role;
select is((select result->>'ok' from artifact_results where label='mark-v3'),'true','v3 can enter the formal artifact chain');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(
 (public.get_upstream_artifacts('a1300000-0000-0000-0000-000000000002')->'artifacts'->0->>'latestVersionId'),
 'a1600000-0000-0000-0000-000000000003',
 'direct downstream assignee sees the latest formal upstream version'
);
insert into artifact_results values('strong-light-create',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000002'
));
insert into artifact_results values('strong-light-replay',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000002'
));
insert into artifact_results values('strong-upgrade',public.cmd_set_task_artifact_binding_strength(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000003','strong',
 'a1900000-0000-0000-0000-000000000003',1
));
reset role;

select is((select result->>'ok' from artifact_results where label='strong-light-create'),'true','real use creates light binding');
select is((select result->>'replayed' from artifact_results where label='strong-light-replay'),'true','replayed light-use command is idempotent');
select is(
 (select count(*)::integer from public.task_artifact_bindings where downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 1,'repeated use stores one current binding'
);
select is(
 (select count(*)::integer from public.task_artifact_binding_history h
   join public.task_artifact_bindings b on b.id=h.binding_id
   where b.downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 2,'light create plus explicit strong upgrade retain two history entries'
);
select is(
 (select strength from public.task_artifact_bindings where downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 'strong','explicit chain action upgrades light to strong'
);

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into artifact_results values('light-create',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000003',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000004'
));
reset role;
select is((select result->>'ok' from artifact_results where label='light-create'),'true','second downstream can remain light-bound');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into artifact_results values('observer-rejected',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000005'
));
reset role;
select is((select result->>'code' from artifact_results where label='observer-rejected'),'NOT_AUTHORIZED','observer cannot mutate artifact bindings');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into artifact_results values('non-upstream-rejected',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000004',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000013'
));
insert into artifact_results values('cross-project-rejected',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000002','a1300000-0000-0000-0000-000000000005',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000014'
));
reset role;
select is((select result->>'code' from artifact_results where label='non-upstream-rejected'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-upstream artifact version is rejected');
select is((select result->>'code' from artifact_results where label='cross-project-rejected'),'NOT_FOUND_OR_NOT_AUTHORIZED','cross-project artifact version is rejected');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into artifact_results values('invalid-version-rejected',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000099','a1900000-0000-0000-0000-000000000015'
));
reset role;
select is((select result->>'code' from artifact_results where label='invalid-version-rejected'),'NOT_FOUND_OR_NOT_AUTHORIZED','unknown artifact version is rejected');

-- A finalized but non-formal version cannot be bound.
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values(
 'a1400000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000001',
 'a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
 'new_version','a1500000-0000-0000-0000-000000000001',3,'artifacts/data-v35.xlsx','data.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2
);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'a1600000-0000-0000-0000-000000000035','a1500000-0000-0000-0000-000000000001',
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001',
 'a1400000-0000-0000-0000-000000000002',35,'artifacts/data-v35.xlsx','data.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('b',64),
 'a1100000-0000-0000-0000-000000000001'
);

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into artifact_results values('nonformal-rejected',public.cmd_switch_task_artifact_binding_version(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000035','a1900000-0000-0000-0000-000000000006',2
));
reset role;
select is((select result->>'code' from artifact_results where label='nonformal-rejected'),'NOT_FOUND_OR_NOT_AUTHORIZED','finalized upload alone is not a formal artifact');

-- v4 becomes formal after the bindings exist.
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values(
 'a1400000-0000-0000-0000-000000000004','a1200000-0000-0000-0000-000000000001',
 'a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
 'new_version','a1500000-0000-0000-0000-000000000001',35,'artifacts/data-v4.xlsx','data.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2
);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'a1600000-0000-0000-0000-000000000004','a1500000-0000-0000-0000-000000000001',
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001',
 'a1400000-0000-0000-0000-000000000004',36,'artifacts/data-v4.xlsx','data.xlsx',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('c',64),
 'a1100000-0000-0000-0000-000000000001'
);
update public.task_files
set current_version_id='a1600000-0000-0000-0000-000000000004',version=version+1
where id='a1500000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into artifact_results values('mark-v4',public.cmd_set_task_file_version_final(
 'a1200000-0000-0000-0000-000000000001','a1600000-0000-0000-0000-000000000004',
 'a1900000-0000-0000-0000-000000000007',0,true
));
reset role;
select is((select result->>'ok' from artifact_results where label='mark-v4'),'true','new upstream version can become formal');

select is(
 (select file_version_id::text from public.task_artifact_bindings where downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 'a1600000-0000-0000-0000-000000000003',
 'strong binding never auto-upgrades'
);
select is(
 (select file_version_id::text from public.task_artifact_bindings where downstream_task_id='a1300000-0000-0000-0000-000000000003'),
 'a1600000-0000-0000-0000-000000000003',
 'light binding never auto-upgrades'
);
select is(
 (select count(*)::integer from public.notifications
   where recipient_id='a1100000-0000-0000-0000-000000000002'
     and notification_type='artifact_binding_update'),
 1,'strong binding gets exactly one global update notification'
);
select is(
 (select count(*)::integer from public.notifications
   where recipient_id='a1100000-0000-0000-0000-000000000003'
     and notification_type='artifact_binding_update'),
 0,'light binding gets no global update notification'
);
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(
 (select public.resolve_notification_target(id)->>'routeName'
  from public.notifications
  where recipient_id='a1100000-0000-0000-0000-000000000002'
    and notification_type='artifact_binding_update'
  limit 1),
 'task-detail','strong-binding notification targets downstream task detail'
);
reset role;

-- Merely opening the newer version records use but does not switch an existing binding.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into artifact_results values('preview-v4-no-switch',public.cmd_record_task_artifact_use(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000004','a1900000-0000-0000-0000-000000000008'
));
reset role;
select is((select result->'data'->>'changed' from artifact_results where label='preview-v4-no-switch'),'false','previewing newer version does not mutate current binding');
select is(
 (select file_version_id::text from public.task_artifact_bindings where downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 'a1600000-0000-0000-0000-000000000003',
 'newer preview leaves v3 current'
);

-- Unmark/re-mark the same v4 must not create a notification storm.
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into artifact_results values('unmark-v4',public.cmd_set_task_file_version_final(
 'a1200000-0000-0000-0000-000000000001','a1600000-0000-0000-0000-000000000004',
 'a1900000-0000-0000-0000-000000000009',1,false
));
insert into artifact_results values('remark-v4',public.cmd_set_task_file_version_final(
 'a1200000-0000-0000-0000-000000000001','a1600000-0000-0000-0000-000000000004',
 'a1900000-0000-0000-0000-000000000010',2,true
));
reset role;
select is(
 (select count(*)::integer from public.notifications
   where recipient_id='a1100000-0000-0000-0000-000000000002'
     and notification_type='artifact_binding_update'),
 1,'same binding + same newer version notifies only once'
);

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into artifact_results values('switch-v4',public.cmd_switch_task_artifact_binding_version(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000004','a1900000-0000-0000-0000-000000000011',2
));
insert into artifact_results values('stale-switch',public.cmd_switch_task_artifact_binding_version(
 'a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002',
 'a1600000-0000-0000-0000-000000000003','a1900000-0000-0000-0000-000000000012',2
));
reset role;
select is((select result->>'ok' from artifact_results where label='switch-v4'),'true','explicit switch upgrades current binding');
select is((select result->>'code' from artifact_results where label='stale-switch'),'STALE_VERSION','stale expected binding version is rejected');
select is(
 (select count(*)::integer from public.task_artifact_binding_history h
   join public.task_artifact_bindings b on b.id=h.binding_id
   where b.downstream_task_id='a1300000-0000-0000-0000-000000000002'),
 3,'binding history retains create, strength change, and version switch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
select throws_ok(
 $$update public.task_artifact_bindings set strength='light' where downstream_task_id='a1300000-0000-0000-0000-000000000002'$$,
 '42501',null,'browser cannot directly mutate binding facts'
);
reset role;

select * from finish();
rollback;
