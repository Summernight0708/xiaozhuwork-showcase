begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function('public','get_task_file_history',array['uuid','integer','integer'],'file history reader exists');
select has_function('public','cmd_batch_rollback_task_files',array['uuid','uuid','integer','jsonb'],'batch rollback RPC exists');
select ok(has_function_privilege('authenticated','public.get_task_file_history(uuid,integer,integer)','EXECUTE'),'authenticated can read file history through RPC');
select ok(not has_function_privilege('anon','public.get_task_file_history(uuid,integer,integer)','EXECUTE'),'anon cannot read file history');
select ok(has_function_privilege('authenticated','public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)','EXECUTE'),'authenticated can request batch rollback through RPC');
select ok(not has_function_privilege('anon','public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)','EXECUTE'),'anon cannot request batch rollback');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='file_upload_reservations' and indexname='file_upload_reservations_live_object_path_unique'),'live upload paths stay unique');

insert into auth.users(id,email) values
('e1000000-0000-0000-0000-000000000001','history-leader@example.test'),
('e1000000-0000-0000-0000-000000000002','history-assignee@example.test'),
('e1000000-0000-0000-0000-000000000003','history-creator@example.test'),
('e1000000-0000-0000-0000-000000000004','history-member@example.test'),
('e1000000-0000-0000-0000-000000000005','history-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values
('e2000000-0000-0000-0000-000000000001','History project',now()+interval '10 days','e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1),
('e2000000-0000-0000-0000-000000000002','Other project',now()+interval '10 days','e1000000-0000-0000-0000-000000000005','e1000000-0000-0000-0000-000000000005',1);

insert into public.project_members(project_id,user_id,role,member_state) values
('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','leader','active'),
('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','member','active'),
('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003','member','active'),
('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000004','member','active'),
('e2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000005','leader','active');

insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'e1000000-0000-0000-0000-000000000001','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'e1000000-0000-0000-0000-000000000001','test',1
);

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,is_direct_assignment,accepted_at,assignment_state,version)
values
('e3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','History task','e1000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',1,false,now(),'assigned',1),
('e3000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','Second history task','e1000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',1,false,now(),'assigned',1);

insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values
('e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','new_file',null,null,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000001/report.pdf','report.pdf','application/pdf',100,'finalized',now(),2),
('e4000000-0000-0000-0000-000000000004','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002','new_file',null,null,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000004/second.txt','second.txt','text/plain',50,'finalized',now(),2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values
('e5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','report.pdf','e1000000-0000-0000-0000-000000000002',3),
('e5000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002','second.txt','e1000000-0000-0000-0000-000000000002',2);

insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values
('e4000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003','new_version','e5000000-0000-0000-0000-000000000001',1,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000002/report-v2.pdf','report-v2.pdf','application/pdf',200,'finalized',now(),2),
('e4000000-0000-0000-0000-000000000003','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003','new_version','e5000000-0000-0000-0000-000000000001',2,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000003/report-v3.pdf','report-v3.pdf','application/pdf',300,'finalized',now(),2),
('e4000000-0000-0000-0000-000000000005','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002','new_version','e5000000-0000-0000-0000-000000000002',1,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000005/second-v2.txt','second-v2.txt','text/plain',60,'finalized',now(),2);

insert into public.task_file_versions(id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by)
values
('e6000000-0000-0000-0000-000000000001','e5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',1,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000001/report.pdf','report.pdf','application/pdf',100,repeat('a',64),'e1000000-0000-0000-0000-000000000002'),
('e6000000-0000-0000-0000-000000000002','e5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',2,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000002/report-v2.pdf','report-v2.pdf','application/pdf',200,repeat('b',64),'e1000000-0000-0000-0000-000000000003'),
('e6000000-0000-0000-0000-000000000003','e5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000003',3,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000003/report-v3.pdf','report-v3.pdf','application/pdf',300,repeat('c',64),'e1000000-0000-0000-0000-000000000003'),
('e6000000-0000-0000-0000-000000000004','e5000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000004',1,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000004/second.txt','second.txt','text/plain',50,repeat('d',64),'e1000000-0000-0000-0000-000000000002'),
('e6000000-0000-0000-0000-000000000005','e5000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002','e4000000-0000-0000-0000-000000000005',2,'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000005/second-v2.txt','second-v2.txt','text/plain',60,repeat('e',64),'e1000000-0000-0000-0000-000000000002');

update public.task_files set current_version_id='e6000000-0000-0000-0000-000000000003' where id='e5000000-0000-0000-0000-000000000001';
update public.task_files set current_version_id='e6000000-0000-0000-0000-000000000005' where id='e5000000-0000-0000-0000-000000000002';

create temporary table rollback_results(label text primary key,result jsonb);
grant all on rollback_results to authenticated;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
insert into rollback_results values('history-unauth',public.get_task_file_history('e5000000-0000-0000-0000-000000000001',2,null));
reset role;
select is((select result->>'code' from rollback_results where label='history-unauth'),'UNAUTHENTICATED','history reader requires auth uid');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into rollback_results values('history-outsider',public.get_task_file_history('e5000000-0000-0000-0000-000000000001',2,null));
reset role;
select is((select result->>'code' from rollback_results where label='history-outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','history hides private files from outsiders');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into rollback_results values('history-page-one',public.get_task_file_history('e5000000-0000-0000-0000-000000000001',2,null));
insert into rollback_results values('history-page-two',public.get_task_file_history('e5000000-0000-0000-0000-000000000001',2,2));
insert into rollback_results values('rollback-ordinary-member',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000001',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',3))));
reset role;
select is((select result->>'ok' from rollback_results where label='history-page-one'),'true','active member can read history');
select is((select result#>>'{data,versions,0,versionNumber}' from rollback_results where label='history-page-one'),'3','history page is newest first');
select is((select result#>>'{data,versions,1,versionNumber}' from rollback_results where label='history-page-one'),'2','history page has stable second row');
select is((select result#>>'{data,versions,0,versionNumber}' from rollback_results where label='history-page-two'),'1','beforeVersion pagination is stable');
select is((select result->>'code' from rollback_results where label='rollback-ordinary-member'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-task actor cannot rollback even when member');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into rollback_results values('rollback-stale-project',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000002',99,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',3))));
insert into rollback_results values('rollback-stale-file',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000003',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',99))));
insert into rollback_results values('rollback-invalid-batch',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000004',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',3),jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000002','restoreVersionId','00000000-0000-0000-0000-000000000000','expectedVersion',2))));
select is((select result->>'code' from rollback_results where label='rollback-invalid-batch'),'NOT_FOUND_OR_NOT_AUTHORIZED','invalid item rejects whole batch');
select is((select version from public.task_files where id='e5000000-0000-0000-0000-000000000001'),3,'invalid batch does not partially rollback first file');
insert into rollback_results values('rollback-ok',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000005',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',3),jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000002','restoreVersionId','e6000000-0000-0000-0000-000000000004','expectedVersion',2))));
insert into rollback_results values('rollback-replay',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000005',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000001','expectedVersion',3),jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000002','restoreVersionId','e6000000-0000-0000-0000-000000000004','expectedVersion',2))));
insert into rollback_results values('rollback-reuse',public.cmd_batch_rollback_task_files('e2000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000005',1,jsonb_build_array(jsonb_build_object('fileId','e5000000-0000-0000-0000-000000000001','restoreVersionId','e6000000-0000-0000-0000-000000000002','expectedVersion',4))));
reset role;

select is((select result->>'code' from rollback_results where label='rollback-stale-project'),'STALE_VERSION','project expected version is checked');
select is((select result->>'code' from rollback_results where label='rollback-stale-file'),'STALE_VERSION','file expected version is checked');
select is((select result->>'ok' from rollback_results where label='rollback-ok'),'true','batch rollback succeeds');
select is((select version from public.task_files where id='e5000000-0000-0000-0000-000000000001'),4,'first file version advances after rollback');
select is((select version from public.task_files where id='e5000000-0000-0000-0000-000000000002'),3,'second file version advances after rollback');
select is((select count(*)::integer from public.task_file_versions where file_id='e5000000-0000-0000-0000-000000000001'),4,'rollback appends first file version');
select is((select restored_from_version_id from public.task_file_versions where file_id='e5000000-0000-0000-0000-000000000001' and version_number=4),'e6000000-0000-0000-0000-000000000001'::uuid,'rollback records provenance');
select is((select object_path from public.task_file_versions where file_id='e5000000-0000-0000-0000-000000000001' and version_number=4),(select object_path from public.task_file_versions where id='e6000000-0000-0000-0000-000000000001'),'rollback reuses immutable object reference');
select is((select result->>'replayed' from rollback_results where label='rollback-replay'),'true','same request id and payload replays');
select is((select result->>'code' from rollback_results where label='rollback-reuse'),'IDEMPOTENCY_KEY_REUSED','same request id with different payload is rejected');
select is((select count(*)::integer from public.business_events where request_id='e9000000-0000-0000-0000-000000000005' and event_type='task_file_version_rolled_back'),2,'rollback emits one audit event per file');
select is((select count(*)::integer from public.command_requests where request_id='e9000000-0000-0000-0000-000000000005' and command_name='cmd_batch_rollback_task_files'),1,'rollback command is stored once');

select * from finish();
rollback;
