begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','project_recovery_points','recovery point metadata table exists');
select has_table('public','project_recovery_point_file_items','recovery point file item table exists');
select has_table('public','project_recovery_point_restore_items','recovery point restore item table exists');
select has_function(
  'public','cmd_create_project_recovery_point',
  array['uuid','uuid','integer','text'],
  'recovery point create RPC exists'
);
select has_function(
  'public','cmd_restore_project_recovery_point',
  array['uuid','uuid','uuid','integer'],
  'recovery point restore RPC exists'
);
select ok(not has_table_privilege('authenticated','public.project_recovery_points','INSERT'),'browser cannot directly create recovery points');
select ok(has_table_privilege('authenticated','public.project_recovery_points','SELECT'),'members can read recovery point metadata');

insert into auth.users(id,email) values
 ('d1100000-0000-0000-0000-000000000001','recovery-leader@example.test'),
 ('d1100000-0000-0000-0000-000000000002','recovery-member@example.test'),
 ('d1100000-0000-0000-0000-000000000003','recovery-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values(
 'd2100000-0000-0000-0000-000000000001','Recovery',now()+interval '20 days',
 'd1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(project_id,user_id,role,member_state,is_observer,version) values
 ('d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('d2100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002','member','active',false,1);

insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
 'd1100000-0000-0000-0000-000000000001','pro','active',
 now()-interval '1 day',now()+interval '30 days',now(),
 'd1100000-0000-0000-0000-000000000001','test',1
);

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,completed_at,version) values
 ('d3100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','Done','d1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002',now()+interval '5 days','completed',1,'assigned',now(),now(),4),
 ('d3100000-0000-0000-0000-000000000002','d2100000-0000-0000-0000-000000000001','Open','d1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002',now()+interval '6 days','in_progress',1,'assigned',now(),null,2);

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
values('d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000001');

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('d4100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002','new_file',null,null,'recovery/v1.pdf','report.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values('d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','report.pdf','d1100000-0000-0000-0000-000000000002',2);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values
 ('d6100000-0000-0000-0000-000000000001','d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001',1,'recovery/v1.pdf','report.pdf','application/pdf',100,repeat('a',64),'d1100000-0000-0000-0000-000000000002');
update public.task_files set current_version_id='d6100000-0000-0000-0000-000000000001' where id='d5100000-0000-0000-0000-000000000001';

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('d4100000-0000-0000-0000-000000000002','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002','new_version','d5100000-0000-0000-0000-000000000001',1,'recovery/v2.pdf','report.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('d4100000-0000-0000-0000-000000000003','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000002','new_version','d5100000-0000-0000-0000-000000000001',2,'recovery/v3.pdf','report.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values
 ('d6100000-0000-0000-0000-000000000002','d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002',2,'recovery/v2.pdf','report.pdf','application/pdf',100,repeat('b',64),'d1100000-0000-0000-0000-000000000002'),
 ('d6100000-0000-0000-0000-000000000003','d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000003',3,'recovery/v3.pdf','report.pdf','application/pdf',100,repeat('c',64),'d1100000-0000-0000-0000-000000000002');
update public.task_files set current_version_id='d6100000-0000-0000-0000-000000000002' where id='d5100000-0000-0000-0000-000000000001';
insert into public.task_file_final_designations(file_version_id,file_id,project_id,task_id,is_final,version,marked_by,marked_at,updated_by)
values('d6100000-0000-0000-0000-000000000002','d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001',true,1,'d1100000-0000-0000-0000-000000000001',now(),'d1100000-0000-0000-0000-000000000001');

insert into public.task_review_rounds(
 id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,state,decision,
 reviewed_by,reviewed_at,version,submission_text_snapshot
) values(
 'd7100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d3100000-0000-0000-0000-000000000001',1,
 'd6100000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000002','approved','approve',
 'd1100000-0000-0000-0000-000000000001',now(),1,'approved snapshot'
);

create temporary table recovery_results(label text primary key,result jsonb);
grant all on recovery_results to authenticated;

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into recovery_results values('create',public.cmd_create_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000001',1,'before risky edits'
));
insert into recovery_results values('create-replay',public.cmd_create_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000001',1,'before risky edits'
));
reset role;

select is((select result->>'ok' from recovery_results where label='create'),'true','leader creates recovery point');
select is((select result->>'replayed' from recovery_results where label='create-replay'),'true','create recovery point replays');
select is((select count(*)::integer from public.project_recovery_points where project_id='d2100000-0000-0000-0000-000000000001'),1,'create stores one recovery point');
select is((select count(*)::integer from public.project_recovery_point_file_items where captured_file_version_id='d6100000-0000-0000-0000-000000000002'),1,'create captures current file version pointer');
select is((select captured_final_designation_version from public.project_recovery_point_file_items where captured_file_version_id='d6100000-0000-0000-0000-000000000002'),1,'create captures formal designation version');

update public.task_files set current_version_id='d6100000-0000-0000-0000-000000000003',version=3 where id='d5100000-0000-0000-0000-000000000001';
update public.task_file_final_designations
set is_final=false,marked_by=null,marked_at=null,updated_by='d1100000-0000-0000-0000-000000000001',version=2
where file_version_id='d6100000-0000-0000-0000-000000000002';
update public.tasks set status='blocked',blocked_reason='must not restore',version=5 where id='d3100000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into recovery_results values('member-restore-denied',public.cmd_restore_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001',
 (select id from public.project_recovery_points where project_id='d2100000-0000-0000-0000-000000000001'),
 'd9100000-0000-0000-0000-000000000002',1
));
reset role;
select is((select result->>'code' from recovery_results where label='member-restore-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','member cannot restore recovery point');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into recovery_results values('restore-stale',public.cmd_restore_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001',
 (select id from public.project_recovery_points where project_id='d2100000-0000-0000-0000-000000000001'),
 'd9100000-0000-0000-0000-000000000003',999
));
insert into recovery_results values('restore',public.cmd_restore_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001',
 (select id from public.project_recovery_points where project_id='d2100000-0000-0000-0000-000000000001'),
 'd9100000-0000-0000-0000-000000000004',1
));
insert into recovery_results values('restore-replay',public.cmd_restore_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001',
 (select id from public.project_recovery_points where project_id='d2100000-0000-0000-0000-000000000001'),
 'd9100000-0000-0000-0000-000000000004',1
));
reset role;

select is((select result->>'code' from recovery_results where label='restore-stale'),'STALE_VERSION','restore rejects stale project version');
select is((select result->>'ok' from recovery_results where label='restore'),'true','leader restores recovery point');
select is((select result->>'replayed' from recovery_results where label='restore-replay'),'true','restore recovery point replays');
select is((
  select restored_from_version_id::text
  from public.task_file_versions
  where id=(select current_version_id from public.task_files where id='d5100000-0000-0000-0000-000000000001')
),'d6100000-0000-0000-0000-000000000002','restore points logical file to appended copy-forward version');
select is((
  select count(*)::integer
  from public.task_file_versions
  where file_id='d5100000-0000-0000-0000-000000000001'
    and restored_from_version_id='d6100000-0000-0000-0000-000000000002'
),1,'restore records one copied source version');
select is((
  select object_path
  from public.task_file_versions
  where restored_from_version_id='d6100000-0000-0000-0000-000000000002'
),'recovery/v2.pdf','restore reuses immutable storage object reference');
select is((
  select d.is_final
  from public.task_file_final_designations d
  join public.task_file_versions fv on fv.id=d.file_version_id
  where fv.restored_from_version_id='d6100000-0000-0000-0000-000000000002'
),true,'restore reapplies captured formal designation onto copy-forward version');
select is((select status from public.tasks where id='d3100000-0000-0000-0000-000000000002'),'blocked','restore does not alter task state');
select is((select count(*)::integer from public.task_dependencies where project_id='d2100000-0000-0000-0000-000000000001'),1,'restore does not alter dependency state');
select is((select state from public.task_review_rounds where id='d7100000-0000-0000-0000-000000000001'),'approved','restore does not alter review/submission state');
select is((select count(*)::integer from public.business_events where project_id='d2100000-0000-0000-0000-000000000001' and event_type in ('project_recovery_point_created','project_recovery_point_restored')),2,'recovery commands are audited');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into recovery_results values('outsider-denied',public.cmd_create_project_recovery_point(
 'd2100000-0000-0000-0000-000000000001','d9100000-0000-0000-0000-000000000005',2,'outsider'
));
reset role;
select is((select result->>'code' from recovery_results where label='outsider-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','unknown actor gets no UUID probing signal');

select * from finish();
rollback;
