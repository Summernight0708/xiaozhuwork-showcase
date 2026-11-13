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

select has_column('public','file_upload_reservations','reserved_envelope_bytes',
  'A reservation persists its immutable full envelope');
select has_function('private','phase2_project_storage_usage',array['uuid','uuid'],
  'physical usage function exists');
select has_function('private','phase2_upload_file_limit',array['uuid'],
  'single-object limit function exists');
select has_function('private','phase2_project_storage_limit',array['uuid'],
  'project storage limit function exists');
select has_function('public','get_project_storage_usage',array['uuid'],
  'member-only capacity endpoint exists');
select has_function('private','phase2_reap_expired_uploads',array['timestamp with time zone','integer'],
  'bounded cleanup function exists');
select ok(not has_function_privilege('authenticated',
  'private.phase2_project_storage_usage(uuid,uuid)','EXECUTE'),
  'authenticated cannot directly query physical bytes');
select ok(not has_function_privilege('authenticated',
  'private.phase2_reap_expired_uploads(timestamptz,integer)','EXECUTE'),
  'authenticated cannot reap another project');
select ok(has_function_privilege('service_role',
  'private.phase2_reap_expired_uploads(timestamptz,integer)','EXECUTE'),
  'service role may run cleanup');

insert into auth.users(id,email) values
('a1100000-0000-0000-0000-000000000001','p2a-free@example.test'),
('a1100000-0000-0000-0000-000000000002','p2a-pro@example.test'),
('a1100000-0000-0000-0000-000000000003','p2a-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
('a2100000-0000-0000-0000-000000000001','P2 A Free',now()+interval '12 days',
 'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',1),
('a2100000-0000-0000-0000-000000000002','P2 A Pro',now()+interval '12 days',
 'a1100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','leader','active'),
('a2100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','leader','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values
('a3100000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000001','Free task',
 'a1100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001',
 now()+interval '8 days','in_progress',1,'assigned',now(),1),
('a3100000-0000-0000-0000-000000000002','a2100000-0000-0000-0000-000000000002','Pro task',
 'a1100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',
 now()+interval '8 days','in_progress',1,'assigned',now(),1);
insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version)
values('a1100000-0000-0000-0000-000000000002','pro','active',
 now()-interval '1 day',now()+interval '30 days',now(),
 'a1100000-0000-0000-0000-000000000002','test',1);

select is(private.phase2_upload_file_limit('a2100000-0000-0000-0000-000000000001'),
 52428800::bigint,'Free single-object ceiling is 50 MiB');
select is(private.phase2_upload_file_limit('a2100000-0000-0000-0000-000000000002'),
 52428800::bigint,'Unreleased Pro large upload must remain 50 MiB');
select is(private.phase2_project_storage_limit('a2100000-0000-0000-0000-000000000001'),
 536870912::bigint,'Free physical quota remains 0.5 GiB');
select is(private.phase2_project_storage_limit('a2100000-0000-0000-0000-000000000002'),
 536870912::bigint,'Unreleased Pro physical quota remains 0.5 GiB');

create temporary table p2a_results(label text primary key,result jsonb);
grant all on p2a_results to authenticated,service_role;

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p2a_results values('pro_unreleased',public.cmd_reserve_task_file_upload(
 'a2100000-0000-0000-0000-000000000002','a3100000-0000-0000-0000-000000000002',
 'a4100000-0000-0000-0000-000000000001',1,'new_file',null,
 'large.pdf','application/pdf',52428801));
reset role;
select is((select result->>'code' from p2a_results where label='pro_unreleased'),
 'STORAGE_QUOTA_EXCEEDED','Pro 51 MiB is denied until G releases the capability');
select is((select result->'details'->>'scope' from p2a_results where label='pro_unreleased'),
 'file','unreleased file quota denial reports scope=file');

-- A-only simulation; rollback discards this function replacement.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select coalesce(p_capability = any(array[
   'file_full_history','file_batch_rollback','file_version_compare','project_recovery_point',
   'file_large_upload','project_storage_quota'
  ]::text[]),false);
$$;
select is(private.phase2_upload_file_limit('a2100000-0000-0000-0000-000000000002'),
 209715200::bigint,'Released Pro single-object ceiling is 200 MiB');
select is(private.phase2_project_storage_limit('a2100000-0000-0000-0000-000000000002'),
 5368709120::bigint,'Released Pro physical quota is 5 GiB');
select is(private.phase2_upload_file_limit('a2100000-0000-0000-0000-000000000001'),
 52428800::bigint,'Free remains at 50 MiB after release');
select is(private.phase2_project_storage_limit('a2100000-0000-0000-0000-000000000001'),
 536870912::bigint,'Free remains at 0.5 GiB after release');

-- Historical rollback and recovery-point replicas reuse one physical path.
insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values('a5100000-0000-0000-0000-000000000001',
 'a2100000-0000-0000-0000-000000000002',
 'a3100000-0000-0000-0000-000000000002',
 'history.txt','a1100000-0000-0000-0000-000000000002',2);
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
 object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values
('a6100000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000002',
 'a3100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',
 'new_file',null,null,
 'pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000001/history.txt',
 'history.txt','text/plain',123,'finalized',now()+interval '15 minutes',2),
('a6100000-0000-0000-0000-000000000002','a2100000-0000-0000-0000-000000000002',
 'a3100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',
 'new_version','a5100000-0000-0000-0000-000000000001',1,
 'pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000001/history.txt',
 'history.txt','text/plain',123,'finalized',now()+interval '15 minutes',2);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,
 object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by,restored_from_version_id)
values
('a7100000-0000-0000-0000-000000000001','a5100000-0000-0000-0000-000000000001',
 'a2100000-0000-0000-0000-000000000002','a3100000-0000-0000-0000-000000000002',
 'a6100000-0000-0000-0000-000000000001',1,
 'pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000001/history.txt',
 'history.txt','text/plain',123,repeat('a',64),'a1100000-0000-0000-0000-000000000002',null),
('a7100000-0000-0000-0000-000000000002','a5100000-0000-0000-0000-000000000001',
 'a2100000-0000-0000-0000-000000000002','a3100000-0000-0000-0000-000000000002',
 'a6100000-0000-0000-0000-000000000002',2,
 'pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000001/history.txt',
 'history.txt','text/plain',123,repeat('a',64),'a1100000-0000-0000-0000-000000000002','a7100000-0000-0000-0000-000000000001');

select is(private.phase2_project_storage_usage('a2100000-0000-0000-0000-000000000002'),
 123::bigint,'two immutable rollback versions charge one 123-byte physical object');

-- An unuploaded live reservation charges its original full tier envelope.
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,state,expires_at,version,reserved_envelope_bytes)
values
('a6100000-0000-0000-0000-000000000003','a2100000-0000-0000-0000-000000000002',
 'a3100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',
 'new_file','pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000003/pending.pdf',
 'pending.pdf','application/pdf',100,'reserved',now()+interval '15 minutes',1,209715200),
('a6100000-0000-0000-0000-000000000004','a2100000-0000-0000-0000-000000000002',
 'a3100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002',
 'new_file','pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000004/expired.pdf',
 'expired.pdf','application/pdf',100,'reserved',now()-interval '1 minute',1,209715200);
select is(private.phase2_project_storage_usage('a2100000-0000-0000-0000-000000000002'),
 209715323::bigint,'active unuploaded envelope charged fully, expired unuploaded zero');
select is(private.phase2_project_storage_usage(
 'a2100000-0000-0000-0000-000000000002',
 'a6100000-0000-0000-0000-000000000003'),
 123::bigint,'finalize exclusion excludes exactly one live envelope');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p2a_results values('pro_200',public.cmd_reserve_task_file_upload(
 'a2100000-0000-0000-0000-000000000002','a3100000-0000-0000-0000-000000000002',
 'a4100000-0000-0000-0000-000000000002',1,'new_file',null,
 'large.pdf','application/pdf',209715200));
insert into p2a_results values('pro_over',public.cmd_reserve_task_file_upload(
 'a2100000-0000-0000-0000-000000000002','a3100000-0000-0000-0000-000000000002',
 'a4100000-0000-0000-0000-000000000003',1,'new_file',null,
 'large.pdf','application/pdf',209715201));
reset role;
select diag('Pro 200 reservation: ' || (select result::text from p2a_results where label='pro_200'));
select is((select result->>'ok' from p2a_results where label='pro_200'),'true',
 'released Pro can reserve a 200 MiB object');
select is((select result->>'code' from p2a_results where label='pro_over'),
 'STORAGE_QUOTA_EXCEEDED','200 MiB +1 rejects at reservation');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p2a_results values('outsider_usage',
 public.get_project_storage_usage('a2100000-0000-0000-0000-000000000002'));
reset role;
select is((select result->>'code' from p2a_results where label='outsider_usage'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','nonmember cannot inspect project bytes');

select is((select count(*)::integer from public.task_file_versions v
 where v.project_id='a2100000-0000-0000-0000-000000000002'),2,
 'quota enforcement never adds versions before successful finalize');

-- Atomic batch rollback/recovery may append finalized reservations referring to
-- existing 200 MiB objects without ever creating a new live upload envelope.
select lives_ok($$
  insert into public.file_upload_reservations (
    id,project_id,task_id,actor_id,mode,object_path,original_name,
    declared_mime_type,declared_size_bytes,state,expires_at,version
  ) values (
    'a6100000-0000-0000-0000-000000000099',
    'a2100000-0000-0000-0000-000000000002',
    'a3100000-0000-0000-0000-000000000002',
    'a1100000-0000-0000-0000-000000000002',
    'new_file','pending/a2100000-0000-0000-0000-000000000002/a6100000-0000-0000-0000-000000000099/restored.pdf',
    'restored.pdf','application/pdf',209715200,'finalized',now(),1
  )
$$,'200 MiB immutable-history restore may create finalized reservation without speculative envelope');

select * from finish();
rollback;
