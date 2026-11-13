begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Schema, constraints, RLS, bucket, and public interfaces.
select has_table('public', 'file_upload_reservations', 'file upload reservations table exists');
select has_table('public', 'task_files', 'task files table exists');
select has_table('public', 'task_file_versions', 'task file versions table exists');
select ok((select relrowsecurity from pg_class where oid='public.file_upload_reservations'::regclass), 'reservations enable RLS');
select ok((select relrowsecurity from pg_class where oid='public.task_files'::regclass), 'task files enable RLS');
select ok((select relrowsecurity from pg_class where oid='public.task_file_versions'::regclass), 'task file versions enable RLS');
select has_column('public','file_upload_reservations','target_file_id','reservation stores optional target file');
select has_column('public','file_upload_reservations','object_path','reservation stores object path');
select has_column('public','file_upload_reservations','state','reservation stores lifecycle state');
select has_column('public','file_upload_reservations','version','reservation is versioned');
select has_column('public','task_files','current_version_id','logical file points at current version');
select has_column('public','task_file_versions','restored_from_version_id','version reserves restore provenance');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='file_upload_reservations' and indexdef ilike '%unique%object_path%'), 'reservation object paths are unique');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='task_file_versions' and indexdef ilike '%unique%file_id%version_number%'), 'version numbers are unique per logical file');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='task_file_versions' and indexdef ilike '%unique%object_path%'), 'finalized object paths are unique');
select ok(exists(select 1 from pg_indexes where schemaname='public' and tablename='task_file_versions' and indexdef ilike '%unique%reservation_id%'), 'a reservation can create at most one version');
select is((select count(*)::integer from storage.buckets where id='teamup-files' and name='teamup-files' and public=false), 1, 'teamup-files bucket exists and is private');

select has_function('public','cmd_reserve_task_file_upload',array['uuid','uuid','uuid','integer','text','uuid','text','text','bigint'],'reserve file upload RPC exists');
select has_function('public','cmd_finalize_task_file_upload_service',array['uuid','uuid','uuid','integer','text','bigint','text'],'service finalize RPC exists');
select has_function('public','cmd_reject_task_file_upload_service',array['uuid','uuid','uuid','integer','text'],'service reject RPC exists');
select has_function('public','get_task_files',array['uuid'],'file metadata reader exists');

select ok(not has_function_privilege('public','public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)','EXECUTE'),'PUBLIC cannot reserve uploads');
select ok(not has_function_privilege('anon','public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)','EXECUTE'),'anon cannot reserve uploads');
select ok(has_function_privilege('authenticated','public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)','EXECUTE'),'authenticated can reserve uploads');
select ok(not has_function_privilege('service_role','public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)','EXECUTE'),'service role has no client reserve grant');

select ok(not has_function_privilege('public','public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)','EXECUTE'),'PUBLIC cannot finalize');
select ok(not has_function_privilege('anon','public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)','EXECUTE'),'anon cannot finalize');
select ok(not has_function_privilege('authenticated','public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)','EXECUTE'),'authenticated cannot finalize');
select ok(has_function_privilege('service_role','public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)','EXECUTE'),'service role can finalize');
select ok(not has_function_privilege('authenticated','public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)','EXECUTE'),'authenticated cannot reject');
select ok(has_function_privilege('service_role','public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)','EXECUTE'),'service role can reject');
select ok(not has_function_privilege('anon','public.get_task_files(uuid)','EXECUTE'),'anon cannot read file metadata');
select ok(has_function_privilege('authenticated','public.get_task_files(uuid)','EXECUTE'),'authenticated can read file metadata');

select ok(not has_table_privilege('authenticated','public.file_upload_reservations','INSERT'),'clients cannot directly insert reservations');
select ok(not has_table_privilege('authenticated','public.file_upload_reservations','UPDATE'),'clients cannot directly update reservations');
select ok(not has_table_privilege('authenticated','public.task_files','INSERT'),'clients cannot directly insert files');
select ok(not has_table_privilege('authenticated','public.task_files','UPDATE'),'clients cannot directly update files');
select ok(not has_table_privilege('authenticated','public.task_file_versions','INSERT'),'clients cannot directly insert versions');
select ok(not has_table_privilege('authenticated','public.task_file_versions','UPDATE'),'clients cannot directly update versions');
select ok(exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd='INSERT' and roles @> array['authenticated'::name]), 'Storage has authenticated reservation insert policy');
select ok(exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd='SELECT' and roles @> array['authenticated'::name]), 'Storage has authenticated finalized read policy');
select ok(not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd='UPDATE' and roles @> array['authenticated'::name] and (qual ilike '%teamup-files%' or with_check ilike '%teamup-files%')), 'Storage has no teamup-files authenticated update policy');
select ok(not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd='DELETE' and roles @> array['authenticated'::name] and qual ilike '%teamup-files%'), 'Storage has no teamup-files authenticated delete policy');

-- Shared fixtures.
insert into auth.users(id,email) values
('70000000-0000-0000-0000-000000000001','files-leader@example.test'),
('70000000-0000-0000-0000-000000000002','files-assignee@example.test'),
('70000000-0000-0000-0000-000000000003','files-creator@example.test'),
('70000000-0000-0000-0000-000000000004','files-member@example.test'),
('70000000-0000-0000-0000-000000000005','files-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('71000000-0000-0000-0000-000000000001','Files project',now()+interval '10 days','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','leader','active'),
('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','member','active'),
('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000003','member','active'),
('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000004','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('72000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','File task','70000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000002',now()+interval '3 days','in_progress',1,'assigned',now(),1);

create temporary table file_results(label text primary key,result jsonb);
grant all on file_results to authenticated, service_role;

-- Authentication and role authorization.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
insert into file_results values('unauth',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000001',1,'new_file',null,'notes.txt','text/plain',12));
reset role;
select is((select result->>'code' from file_results where label='unauth'),'UNAUTHENTICATED','reserve requires auth uid');

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into file_results values('outsider',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000002',1,'new_file',null,'notes.txt','text/plain',12));
reset role;
select is((select result->>'code' from file_results where label='outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-member cannot reserve');

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into file_results values('ordinary-member',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000003',1,'new_file',null,'notes.txt','text/plain',12));
reset role;
select is((select result->>'code' from file_results where label='ordinary-member'),'NOT_FOUND_OR_NOT_AUTHORIZED','ordinary member without task role cannot reserve');

-- Input validation, optimistic versioning, quota, and idempotency.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values
('bad-mode',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000004',1,'replace',null,'notes.txt','text/plain',12)),
('bad-target',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000005',1,'new_file','74000000-0000-0000-0000-000000000001','notes.txt','text/plain',12)),
('bad-name',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000006',1,'new_file',null,'../escape.txt','text/plain',12)),
('bad-type',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000007',1,'new_file',null,'payload.html','text/html',12)),
('oversize',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000008',1,'new_file',null,'large.pdf','application/pdf',52428801)),
('stale',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000009',99,'new_file',null,'notes.txt','text/plain',12));
reset role;
select is((select result->>'code' from file_results where label='bad-mode'),'VALIDATION_FAILED','invalid mode is rejected');
select is((select result->>'code' from file_results where label='bad-target'),'VALIDATION_FAILED','new file cannot specify target');
select is((select result->>'code' from file_results where label='bad-name'),'VALIDATION_FAILED','unsafe filename is rejected');
select is((select result->>'code' from file_results where label='bad-type'),'FILE_TYPE_NOT_ALLOWED','disallowed declared MIME is rejected');
select is((select result->>'code' from file_results where label='oversize'),'STORAGE_QUOTA_EXCEEDED','single file cap is enforced');
select is((select result->>'code' from file_results where label='stale'),'STALE_VERSION','task optimistic version is enforced');

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('reserve-one',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000010',1,'new_file',null,'My report.pdf','application/pdf',1024));
insert into file_results values('reserve-replay',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000010',1,'new_file',null,'My report.pdf','application/pdf',1024));
insert into file_results values('reserve-reuse',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000010',1,'new_file',null,'different.pdf','application/pdf',1024));
reset role;
select is((select result->>'ok' from file_results where label='reserve-one'),'true','authorized assignee can reserve');
select ok((select result->'data'->>'objectPath' from file_results where label='reserve-one') like 'pending/71000000-0000-0000-0000-000000000001/%/My_report.pdf','server generates deterministic safe pending path');
select is((select result->'data'->>'objectPath' from file_results where label='reserve-replay'),(select result->'data'->>'objectPath' from file_results where label='reserve-one'),'replay returns identical object path');
select is((select result->>'replayed' from file_results where label='reserve-replay'),'true','exact replay is marked replayed');
select is((select result->>'code' from file_results where label='reserve-reuse'),'IDEMPOTENCY_KEY_REUSED','same request id with different payload is rejected');
select is((select count(*)::integer from public.file_upload_reservations where actor_id='70000000-0000-0000-0000-000000000002' and original_name='My report.pdf'),1,'replay creates only one reservation');
select is((select count(*)::integer from public.business_events where request_id='73000000-0000-0000-0000-000000000010'),1,'replay emits one event set');

-- Project quota includes live reservations.
insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select '71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/71000000-0000-0000-0000-000000000001/'||gen_random_uuid()||'/quota-'||i||'.pdf',
       'quota-'||i||'.pdf','application/pdf',50*1024*1024,'reserved',now()+interval '10 minutes',1
from generate_series(1,10) s(i);
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('project-quota',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000011',1,'new_file',null,'quota-over.pdf','application/pdf',13*1024*1024));
reset role;
select is((select result->>'code' from file_results where label='project-quota'),'STORAGE_QUOTA_EXCEEDED','project quota counts unexpired reservations');
delete from public.file_upload_reservations where original_name like 'quota-%';

-- Storage insertion is limited to the exact live reservation path and pending objects are unreadable.
select result->'data'->>'reservationId' as reserve_id, result->'data'->>'objectPath' as reserve_path
from file_results where label='reserve-one' \gset
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into storage.objects(bucket_id,name,owner_id,metadata) values('teamup-files',:'reserve_path','70000000-0000-0000-0000-000000000002','{"size":1024,"mimetype":"application/pdf"}'::jsonb);
select is((select count(*)::integer from storage.objects where bucket_id='teamup-files' and name=:'reserve_path'),0,'pending object cannot be read by uploader');
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id) values('teamup-files','pending/71000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000000/unreserved.pdf','70000000-0000-0000-0000-000000000002')$$,'42501',null,'unreserved object path cannot be inserted');
reset role;

-- Finalization validates actor and byte facts and creates immutable history.
set local role service_role;
insert into file_results values('actor-mismatch',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'reserve_id','73000000-0000-0000-0000-000000000012',1,'application/pdf',1024,repeat('a',64)));
insert into file_results values('finalize-one',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reserve_id','73000000-0000-0000-0000-000000000013',1,'application/pdf',1024,repeat('a',64)));
insert into file_results values('finalize-replay',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reserve_id','73000000-0000-0000-0000-000000000013',1,'application/pdf',1024,repeat('a',64)));
insert into file_results values('finalize-reuse',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reserve_id','73000000-0000-0000-0000-000000000013',1,'application/pdf',1024,repeat('f',64)));
insert into file_results values('double-finalize',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reserve_id','73000000-0000-0000-0000-000000000014',2,'application/pdf',1024,repeat('a',64)));
reset role;
select is((select result->>'code' from file_results where label='actor-mismatch'),'NOT_FOUND_OR_NOT_AUTHORIZED','service actor must match locked reservation actor');
select is((select result->>'ok' from file_results where label='finalize-one'),'true','service finalization succeeds');
select is((select result->>'replayed' from file_results where label='finalize-replay'),'true','service finalization replays exactly');
select is((select result->>'code' from file_results where label='finalize-reuse'),'IDEMPOTENCY_KEY_REUSED','service finalization rejects request id payload reuse');
select is((select result->>'code' from file_results where label='double-finalize'),'UPLOAD_NOT_READY','double finalization is rejected');
select is((select state from public.file_upload_reservations where id=:'reserve_id'),'finalized','reservation is finalized');
select is((select version from public.file_upload_reservations where id=:'reserve_id'),2,'finalization increments reservation version');
select is((select count(*)::integer from public.task_file_versions where reservation_id=:'reserve_id'),1,'finalization creates exactly one immutable version');
select is((select count(*)::integer from public.business_events where request_id='73000000-0000-0000-0000-000000000013'),1,'finalization emits one event set');
select is((select count(*)::integer from public.command_requests where request_id='73000000-0000-0000-0000-000000000013' and state='completed'),1,'finalization completes one ledger row');

select id as file_id,current_version_id as first_version_id from public.task_files where task_id='72000000-0000-0000-0000-000000000001' \gset
select throws_ok(format('update public.task_file_versions set original_name=%L where id=%L','tampered.pdf',:'first_version_id'),'55000','Task file versions are immutable','version rows cannot be updated');
select throws_ok(format('delete from public.task_file_versions where id=%L',:'first_version_id'),'55000','Task file versions are immutable','version rows cannot be deleted');

-- Finalized objects are readable only to active project members and cannot be mutated by clients.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is((select count(*)::integer from storage.objects where bucket_id='teamup-files' and name=:'reserve_path'),1,'active member can read finalized object metadata');
update storage.objects set metadata='{"x":1}'::jsonb where bucket_id='teamup-files' and name=:'reserve_path';
select is((select metadata from storage.objects where bucket_id='teamup-files' and name=:'reserve_path'),'{"size":1024,"mimetype":"application/pdf"}'::jsonb,'authenticated client cannot update finalized object');
select throws_ok(format('delete from storage.objects where bucket_id=%L and name=%L','teamup-files',:'reserve_path'),'42501','Direct deletion from storage tables is not allowed. Use the Storage API instead.','authenticated client cannot directly delete finalized object metadata');
reset role;
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000005',true);
set local role authenticated;
select is((select count(*)::integer from storage.objects where bucket_id='teamup-files' and name=:'reserve_path'),0,'outsider cannot read finalized object');
reset role;

-- New-version reservation uses file OCC and appends without rewriting history.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into file_results values('new-version-stale',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000015',99,'new_version',:'file_id','revision.pdf','application/pdf',2048));
insert into file_results values('new-version-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000016',1,'new_version',:'file_id','revision.pdf','application/pdf',2048));
reset role;
select is((select result->>'code' from file_results where label='new-version-stale'),'STALE_VERSION','new version checks logical file version');
select is((select result->>'ok' from file_results where label='new-version-reserve'),'true','creator can reserve a new version');
select result->'data'->>'reservationId' as new_reserve_id from file_results where label='new-version-reserve' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.id=:'new_reserve_id'::uuid;
set local role service_role;
insert into file_results values('new-version-finalize',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'new_reserve_id','73000000-0000-0000-0000-000000000017',1,'application/pdf',2048,repeat('b',64)));
reset role;
select is((select result->>'ok' from file_results where label='new-version-finalize'),'true','new version finalization succeeds');
select is((select version from public.task_files where id=:'file_id'),2,'logical file aggregate version advances');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'),2,'old version is preserved');
select ok((select current_version_id<>:'first_version_id'::uuid from public.task_files where id=:'file_id'),'current pointer advances to newly appended version');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id' and restored_from_version_id is not null),0,'normal Day 4 uploads do not set restore provenance');

-- Actual metadata and SHA checks leave reservations pending.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('reserve-size-check',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000018',1,'new_file',null,'size.txt','text/plain',20));
insert into file_results values('reserve-type-check',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000019',1,'new_file',null,'type.txt','text/plain',20));
insert into file_results values('reserve-hash-check',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000020',1,'new_file',null,'hash.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as size_reserve_id from file_results where label='reserve-size-check' \gset
select result->'data'->>'reservationId' as type_reserve_id from file_results where label='reserve-type-check' \gset
select result->'data'->>'reservationId' as hash_reserve_id from file_results where label='reserve-hash-check' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.id in (:'size_reserve_id'::uuid,:'type_reserve_id'::uuid,:'hash_reserve_id'::uuid);
set local role service_role;
insert into file_results values('stale-finalize',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'size_reserve_id','73000000-0000-0000-0000-000000000027',99,'text/plain',20,repeat('c',64)));
reset role;
select is((select result->>'code' from file_results where label='stale-finalize'),'STALE_VERSION','service finalization checks reservation version');
select is((select state from public.file_upload_reservations where id=:'size_reserve_id'),'reserved','stale service call does not mutate reservation');
set local role service_role;
insert into file_results values('size-mismatch',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'size_reserve_id','73000000-0000-0000-0000-000000000021',1,'text/plain',19,repeat('c',64)));
insert into file_results values('type-mismatch',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'type_reserve_id','73000000-0000-0000-0000-000000000022',1,'application/pdf',20,repeat('d',64)));
insert into file_results values('bad-hash',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'hash_reserve_id','73000000-0000-0000-0000-000000000023',1,'text/plain',20,upper(repeat('e',64))));
reset role;
select is((select result->>'code' from file_results where label='size-mismatch'),'FILE_VALIDATION_FAILED','actual size must match declared size');
select is((select result->>'code' from file_results where label='type-mismatch'),'FILE_VALIDATION_FAILED','actual MIME must match declared MIME');
select is((select result->>'code' from file_results where label='bad-hash'),'FILE_VALIDATION_FAILED','SHA-256 must be lowercase hexadecimal');
select is((select count(*)::integer from public.file_upload_reservations where id in (:'size_reserve_id',:'type_reserve_id',:'hash_reserve_id') and state='reserved'),3,'validation failures leave reservations pending');

-- Service finalization rechecks current membership and quota under the project lock.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('reserve-membership-check',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000028',1,'new_file',null,'membership.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as membership_reserve_id from file_results where label='reserve-membership-check' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.id=:'membership_reserve_id'::uuid;
update public.project_members set member_state='left',departed_at=now() where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';
set local role service_role;
insert into file_results values('membership-recheck',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'membership_reserve_id','73000000-0000-0000-0000-000000000029',1,'text/plain',20,repeat('f',64)));
reset role;
select is((select result->>'code' from file_results where label='membership-recheck'),'NOT_FOUND_OR_NOT_AUTHORIZED','service finalization rechecks current membership');
select is((select state from public.file_upload_reservations where id=:'membership_reserve_id'),'reserved','failed membership recheck leaves reservation pending');
update public.project_members set member_state='active',departed_at=null where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';

insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select '71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/71000000-0000-0000-0000-000000000001/'||gen_random_uuid()||'/finalize-quota-'||i||'.pdf',
       'finalize-quota-'||i||'.pdf','application/pdf',50*1024*1024,'reserved',now()+interval '10 minutes',1
from generate_series(1,10) s(i);
insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/71000000-0000-0000-0000-000000000001/79000000-0000-0000-0000-000000000001/finalize-quota-extra.pdf',
       'finalize-quota-extra.pdf','application/pdf',13*1024*1024,'reserved',now()+interval '10 minutes',1);
set local role service_role;
insert into file_results values('finalize-quota',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'membership_reserve_id','73000000-0000-0000-0000-000000000030',1,'text/plain',20,repeat('f',64)));
reset role;
select is((select result->>'code' from file_results where label='finalize-quota'),'STORAGE_QUOTA_EXCEEDED','service finalization rechecks project quota including live reservations');
select is((select state from public.file_upload_reservations where id=:'membership_reserve_id'),'reserved','quota recheck failure leaves reservation pending');
delete from public.file_upload_reservations where original_name like 'finalize-quota-%';

-- Rejection is service-only, versioned, evented, replayable, and creates no file version.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('reserve-reject',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000024',1,'new_file',null,'reject.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as reject_reserve_id from file_results where label='reserve-reject' \gset
set local role service_role;
insert into file_results values('reject-one',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reject_reserve_id','73000000-0000-0000-0000-000000000025',1,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-replay',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'reject_reserve_id','73000000-0000-0000-0000-000000000025',1,'FILE_VALIDATION_FAILED'));
reset role;
select is((select state from public.file_upload_reservations where id=:'reject_reserve_id'),'rejected','rejection changes reservation state');
select is((select rejection_code from public.file_upload_reservations where id=:'reject_reserve_id'),'FILE_VALIDATION_FAILED','rejection stores stable code');
select is((select version from public.file_upload_reservations where id=:'reject_reserve_id'),2,'rejection advances reservation version');
select is((select result->>'replayed' from file_results where label='reject-replay'),'true','rejection replay is exact');
select is((select count(*)::integer from public.task_file_versions where reservation_id=:'reject_reserve_id'),0,'rejection creates no version');
select is((select count(*)::integer from public.business_events where request_id='73000000-0000-0000-0000-000000000025'),1,'rejection replay emits one event set');

-- Read API is task-scoped and active-member-only.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is((public.get_task_files('72000000-0000-0000-0000-000000000001')->>'ok'),'true','active member can read task file metadata');
reset role;
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000005',true);
set local role authenticated;
select is((public.get_task_files('72000000-0000-0000-0000-000000000001')->>'code'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot read task file metadata');
reset role;

-- Inject an event failure and prove ledger + reservation roll back together.
create function pg_temp.reject_day4_event() returns trigger language plpgsql as $$
begin
  if new.request_id='73000000-0000-0000-0000-000000000026'::uuid then
    raise exception using errcode='P0001',message='injected day4 event failure';
  end if;
  return new;
end;
$$;
create trigger day4_event_failure before insert on public.business_events for each row execute function pg_temp.reject_day4_event();
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok($$select public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000026',1,'new_file',null,'rollback.txt','text/plain',20)$$,'P0001','injected day4 event failure','event failure aborts reserve command');
reset role;
drop trigger day4_event_failure on public.business_events;
select is((select count(*)::integer from public.file_upload_reservations where original_name='rollback.txt'),0,'failed event rolls reservation back');
select is((select count(*)::integer from public.command_requests where request_id='73000000-0000-0000-0000-000000000026'),0,'failed event rolls ledger claim back');
select is((select count(*)::integer from public.business_events where request_id='73000000-0000-0000-0000-000000000026'),0,'failed event leaves no event');

-- Inject a finalization event failure and prove file/version/reservation/ledger changes roll back together.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('reserve-finalize-rollback',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000031',1,'new_file',null,'finalize-rollback.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as finalize_rollback_reserve_id from file_results where label='reserve-finalize-rollback' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.id=:'finalize_rollback_reserve_id'::uuid;

create or replace function pg_temp.reject_day4_event() returns trigger language plpgsql as $$
begin
  if new.request_id='73000000-0000-0000-0000-000000000032'::uuid then
    raise exception using errcode='P0001',message='injected finalize event failure';
  end if;
  return new;
end;
$$;
create trigger day4_finalize_event_failure before insert on public.business_events for each row execute function pg_temp.reject_day4_event();
set local role service_role;
select throws_ok(format(
  'select public.cmd_finalize_task_file_upload_service(%L,%L,%L,1,%L,20,%L)',
  '70000000-0000-0000-0000-000000000002', :'finalize_rollback_reserve_id',
  '73000000-0000-0000-0000-000000000032', 'text/plain', repeat('a',64)
),'P0001','injected finalize event failure','event failure aborts finalization atomically');
reset role;
drop trigger day4_finalize_event_failure on public.business_events;
select is((select state from public.file_upload_reservations where id=:'finalize_rollback_reserve_id'),'reserved','failed finalize keeps reservation reserved');
select is((select count(*)::integer from public.task_file_versions where reservation_id=:'finalize_rollback_reserve_id'),0,'failed finalize rolls version insertion back');
select is((select count(*)::integer from public.task_files where logical_name='finalize-rollback.txt'),0,'failed finalize rolls logical file insertion back');
select is((select count(*)::integer from public.command_requests where request_id='73000000-0000-0000-0000-000000000032'),0,'failed finalize rolls ledger claim back');
select is((select count(*)::integer from public.business_events where request_id='73000000-0000-0000-0000-000000000032'),0,'failed finalize leaves no event');


-- Attempt-2 regression coverage: exact grants, behavioral RLS, Storage upload-time authority,
-- physical quota accounting, reject-service failure matrix, replay/event exactness, and stale races.

-- Exact public function EXECUTE matrix.
with roles(role_name) as (
  values ('public'), ('anon'), ('authenticated'), ('service_role')
),
functions(signature, allowed_role) as (
  values
    ('public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)','authenticated'),
    ('public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)','service_role'),
    ('public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)','service_role'),
    ('public.get_task_files(uuid)','authenticated')
)
select is(
  has_function_privilege(roles.role_name, functions.signature, 'EXECUTE'),
  roles.role_name = functions.allowed_role,
  format('%s EXECUTE on %s is exact', roles.role_name, functions.signature)
)
from roles cross join functions;

-- Exact table privilege matrix: clients are read-only, service_role has only the DML needed by invoker RPCs.
with matrix(role_name, table_name, can_select, can_insert, can_update, can_delete) as (
  values
    ('public','public.file_upload_reservations',false,false,false,false),
    ('anon','public.file_upload_reservations',false,false,false,false),
    ('authenticated','public.file_upload_reservations',false,false,false,false),
    ('service_role','public.file_upload_reservations',false,false,false,false),
    ('public','public.task_files',false,false,false,false),
    ('anon','public.task_files',false,false,false,false),
    ('authenticated','public.task_files',false,false,false,false),
    ('service_role','public.task_files',false,false,false,false),
    ('public','public.task_file_versions',false,false,false,false),
    ('anon','public.task_file_versions',false,false,false,false),
    ('authenticated','public.task_file_versions',false,false,false,false),
    ('service_role','public.task_file_versions',false,false,false,false)
),
privs(privilege, ordinal) as (
  values ('SELECT',1),('INSERT',2),('UPDATE',3),('DELETE',4)
)
select is(
  has_table_privilege(matrix.role_name, matrix.table_name, privs.privilege),
  case privs.ordinal
    when 1 then matrix.can_select
    when 2 then matrix.can_insert
    when 3 then matrix.can_update
    else matrix.can_delete
  end,
  format('%s %s on %s is exact', matrix.role_name, privs.privilege, matrix.table_name)
)
from matrix cross join privs;

-- Public RPCs retain a fenced empty search_path.
select ok(
  coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""',
  p.proname || ' has empty search_path'
)
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'cmd_reserve_task_file_upload',
    'cmd_finalize_task_file_upload_service',
    'cmd_reject_task_file_upload_service',
    'get_task_files'
  );

-- Exact structural constraints required by the Day 4 model.
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.contype='p'
    and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='id')]::smallint[]
), 'reservations primary key is exactly id');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_target'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%mode%new_file%target_file_id%target_file_version%new_version%'
), 'reservation mode/target pairing check exists');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_rejection'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%state%rejected%rejection_code%'
), 'reservation state/rejection pairing check exists');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_size'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%declared_size_bytes > 0%'
    and pg_get_constraintdef(c.oid) ilike '%52428800%'
), 'reservation size is positive and capped at exactly 50 MiB');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_version'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%version > 0%'
), 'reservation version is positive');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_target_file_fkey'
    and c.contype='f'
    and c.confrelid='public.task_files'::regclass
    and array_length(c.conkey,1)=3
    and array_length(c.confkey,1)=3
), 'new-version target FK binds project, task, and file');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_files'::regclass
    and c.conname='task_files_current_version_same_file_fkey'
    and c.contype='f'
    and c.confrelid='public.task_file_versions'::regclass
    and c.condeferrable and c.condeferred
), 'current_version_id is a deferred same-file FK');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_restored_same_file_fkey'
    and c.contype='f'
    and c.confrelid='public.task_file_versions'::regclass
    and c.condeferrable and c.condeferred
), 'restored_from_version_id is a deferred same-file FK');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_file_version_unique'
    and c.contype='u'
), 'file/version pair is unique');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_size'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%size_bytes > 0%'
    and pg_get_constraintdef(c.oid) ilike '%52428800%'
), 'finalized version size is positive and capped at exactly 50 MiB');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_files'::regclass
    and c.conname='task_files_version'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%version > 0%'
), 'logical file version is positive');
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_version_number'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%version_number > 0%'
), 'file history version number is positive');

select is((
  select array(
    select a.attname
    from unnest(c.conkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_target_file_fkey'
), array['project_id','task_id','target_file_id']::name[], 'target FK source columns are exact');
select is((
  select array(
    select a.attname
    from unnest(c.confkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_target_file_fkey'
), array['project_id','task_id','id']::name[], 'target FK referenced columns are exact');
select is((
  select array(
    select a.attname
    from unnest(c.conkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.task_files'::regclass
    and c.conname='task_files_current_version_same_file_fkey'
), array['id','current_version_id']::name[], 'current-version FK source columns are exact');
select is((
  select array(
    select a.attname
    from unnest(c.confkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.task_files'::regclass
    and c.conname='task_files_current_version_same_file_fkey'
), array['file_id','id']::name[], 'current-version FK referenced columns enforce same file');
select is((
  select array(
    select a.attname
    from unnest(c.conkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_restored_same_file_fkey'
), array['file_id','restored_from_version_id']::name[], 'restore FK source columns are exact');
select is((
  select array(
    select a.attname
    from unnest(c.confkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum
    order by k.ord
  )
  from pg_constraint c
  where c.conrelid='public.task_file_versions'::regclass
    and c.conname='task_file_versions_restored_same_file_fkey'
), array['file_id','id']::name[], 'restore FK referenced columns enforce same file');
select ok(not exists(
  select 1
  from pg_policies p
  where p.schemaname='storage'
    and p.tablename='objects'
    and p.cmd in ('UPDATE','DELETE','ALL')
    and p.roles && array['public'::name,'anon'::name,'authenticated'::name]
), 'Storage exposes no client UPDATE/DELETE/ALL policy, including broad PUBLIC policies');


-- Behavioral RLS SELECT matrix for owner, leader/member, outsider, and anon.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::integer from public.file_upload_reservations where id=:'size_reserve_id'::uuid),1,'reservation owner can read own reservation');
select is((select count(*)::integer from public.task_files where id=:'file_id'::uuid),1,'active owner/member can read task file');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'::uuid),2,'active owner/member can read file versions');
reset role;

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is((select count(*)::integer from public.file_upload_reservations where id=:'size_reserve_id'::uuid),1,'active leader can read reservation');
select is((select count(*)::integer from public.task_files where id=:'file_id'::uuid),1,'active leader can read task file');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'::uuid),2,'active leader can read file versions');
reset role;

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is((select count(*)::integer from public.file_upload_reservations where id=:'size_reserve_id'::uuid),0,'ordinary active member cannot read another actor reservation');
select is((select count(*)::integer from public.task_files where id=:'file_id'::uuid),1,'ordinary active member can read task file');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'::uuid),2,'ordinary active member can read file versions');
reset role;

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000005',true);
set local role authenticated;
select is((select count(*)::integer from public.file_upload_reservations where id=:'size_reserve_id'::uuid),0,'outsider cannot read reservation');
select is((select count(*)::integer from public.task_files where id=:'file_id'::uuid),0,'outsider cannot read task file');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'::uuid),0,'outsider cannot read file versions');
reset role;

set local role anon;
select throws_ok($$select count(*) from public.file_upload_reservations$$,'42501',null,'anon cannot read reservations');
select throws_ok($$select count(*) from public.task_files$$,'42501',null,'anon cannot read task files');
select throws_ok($$select count(*) from public.task_file_versions$$,'42501',null,'anon cannot read task file versions');
reset role;

-- Direct client writes remain denied for all three business tables.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(format('update public.file_upload_reservations set updated_at=updated_at where id=%L',:'size_reserve_id'),'42501',null,'owner cannot directly update reservation');
select throws_ok(format('delete from public.file_upload_reservations where id=%L',:'size_reserve_id'),'42501',null,'owner cannot directly delete reservation');
select throws_ok(format('update public.task_files set updated_at=updated_at where id=%L',:'file_id'),'42501',null,'member cannot directly update task file');
select throws_ok(format('delete from public.task_files where id=%L',:'file_id'),'42501',null,'member cannot directly delete task file');
select throws_ok(format('update public.task_file_versions set original_name=original_name where id=%L',:'first_version_id'),'42501',null,'member cannot directly update file version');
select throws_ok(format('delete from public.task_file_versions where id=%L',:'first_version_id'),'42501',null,'member cannot directly delete file version');
reset role;

-- Storage INSERT rechecks current membership and current task role at upload time.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('storage-membership-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000040',1,'new_file',null,'storage-membership.txt','text/plain',20));
insert into file_results values('storage-role-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000041',1,'new_file',null,'storage-role.txt','text/plain',20));
insert into file_results values('storage-metadata-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000042',1,'new_file',null,'storage-metadata.txt','text/plain',20));
insert into file_results values('storage-size-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000043',1,'new_file',null,'storage-size.txt','text/plain',20));
insert into file_results values('storage-mime-reserve',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000044',1,'new_file',null,'storage-mime.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as storage_membership_reserve_id, result->'data'->>'objectPath' as storage_membership_path from file_results where label='storage-membership-reserve' \gset
select result->'data'->>'reservationId' as storage_role_reserve_id, result->'data'->>'objectPath' as storage_role_path from file_results where label='storage-role-reserve' \gset
select result->'data'->>'reservationId' as storage_metadata_reserve_id, result->'data'->>'objectPath' as storage_metadata_path from file_results where label='storage-metadata-reserve' \gset
select result->'data'->>'reservationId' as storage_size_reserve_id, result->'data'->>'objectPath' as storage_size_path from file_results where label='storage-size-reserve' \gset
select result->'data'->>'reservationId' as storage_mime_reserve_id, result->'data'->>'objectPath' as storage_mime_path from file_results where label='storage-mime-reserve' \gset

update public.project_members set member_state='left',departed_at=now() where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id,metadata) values(%L,%L,%L,%L::jsonb)',
  'teamup-files', :'storage_membership_path', '70000000-0000-0000-0000-000000000002', '{"size":20,"mimetype":"text/plain"}'
),'42501',null,'removed member cannot upload with a still-live reservation');
reset role;
update public.project_members set member_state='active',departed_at=null where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';


update public.tasks set assignee_id='70000000-0000-0000-0000-000000000004' where id='72000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id,metadata) values(%L,%L,%L,%L::jsonb)',
  'teamup-files', :'storage_role_path', '70000000-0000-0000-0000-000000000002', '{"size":20,"mimetype":"text/plain"}'
),'42501',null,'reassigned actor cannot upload with a still-live reservation');
reset role;
update public.tasks set assignee_id='70000000-0000-0000-0000-000000000002' where id='72000000-0000-0000-0000-000000000001';


-- The real Storage API materializes object metadata after the INSERT RLS check, so RLS
-- authorizes the exact reservation/path/current actor while trusted finalization validates
-- the persisted Storage metadata before any business file version is created.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('teamup-files',:'storage_size_path','70000000-0000-0000-0000-000000000002','{"size":19,"mimetype":"text/plain"}'::jsonb);
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('teamup-files',:'storage_mime_path','70000000-0000-0000-0000-000000000002','{"size":20,"mimetype":"application/pdf"}'::jsonb);
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('teamup-files',:'storage_metadata_path','70000000-0000-0000-0000-000000000002','{"size":20,"mimetype":"text/plain"}'::jsonb);
reset role;
set local role service_role;
insert into file_results values('storage-size-metadata-finalize',public.cmd_finalize_task_file_upload_service(
  '70000000-0000-0000-0000-000000000002',:'storage_size_reserve_id','73000000-0000-0000-0000-000000000045',1,'text/plain',20,repeat('a',64)));
insert into file_results values('storage-mime-metadata-finalize',public.cmd_finalize_task_file_upload_service(
  '70000000-0000-0000-0000-000000000002',:'storage_mime_reserve_id','73000000-0000-0000-0000-000000000046',1,'text/plain',20,repeat('b',64)));
reset role;
select is((select result->>'code' from file_results where label='storage-size-metadata-finalize'),'FILE_VALIDATION_FAILED','trusted finalization rejects persisted Storage size that differs from reservation');
select is((select result->>'field' from file_results where label='storage-size-metadata-finalize'),'actualSizeBytes','Storage size mismatch uses the stable size validation field');
select is((select result->>'code' from file_results where label='storage-mime-metadata-finalize'),'FILE_VALIDATION_FAILED','trusted finalization rejects persisted Storage MIME that differs from reservation');
select is((select result->>'field' from file_results where label='storage-mime-metadata-finalize'),'actualMimeType','Storage MIME mismatch uses the stable MIME validation field');
select is((select count(*)::integer from public.file_upload_reservations where id in (:'storage_size_reserve_id'::uuid,:'storage_mime_reserve_id'::uuid) and state='reserved'),2,'Storage metadata mismatch never finalizes the reservations');
select is((select count(*)::integer from public.task_file_versions where reservation_id in (:'storage_size_reserve_id'::uuid,:'storage_mime_reserve_id'::uuid)),0,'Storage metadata mismatch creates no immutable file version');
select is((select count(*)::integer from storage.objects where bucket_id='teamup-files' and name=:'storage_metadata_path'),1,'matching Storage metadata remains available for trusted finalization');

-- Quota fixture: 12 MiB finalized history + 9x50 MiB live reservations + one expired reservation.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('81000000-0000-0000-0000-000000000001','Quota project',now()+interval '10 days','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('81000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','leader','active'),
('81000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('82000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','Quota task','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002',now()+interval '3 days','in_progress',1,'assigned',now(),1);

-- Exact single-object binary boundary.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('file-boundary',public.cmd_reserve_task_file_upload('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000001',1,'new_file',null,'fifty-mib.bin','application/pdf',52428800));
reset role;
select is((select result->>'ok' from file_results where label='file-boundary'),'true','exactly 50 MiB is accepted');
delete from public.file_upload_reservations where id=((select result->'data'->>'reservationId' from file_results where label='file-boundary')::uuid);

insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values('83100000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file','pending/81000000-0000-0000-0000-000000000001/83100000-0000-0000-0000-000000000001/history.pdf','history.pdf','application/pdf',12582912,'finalized',now()-interval '1 hour',2);
insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values('84000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','history.pdf','70000000-0000-0000-0000-000000000002',1);
insert into public.task_file_versions(id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by)
values('85000000-0000-0000-0000-000000000001','84000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83100000-0000-0000-0000-000000000001',1,'pending/81000000-0000-0000-0000-000000000001/83100000-0000-0000-0000-000000000001/history.pdf','history.pdf','application/pdf',12582912,repeat('a',64),'70000000-0000-0000-0000-000000000002');
update public.task_files set current_version_id='85000000-0000-0000-0000-000000000001' where id='84000000-0000-0000-0000-000000000001';

insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/81000000-0000-0000-0000-000000000001/'||gen_random_uuid()||'/live-'||i||'.pdf',
       'live-'||i||'.pdf','application/pdf',52428800,'reserved',now()+interval '10 minutes',1
from generate_series(1,9) s(i);
insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file','pending/81000000-0000-0000-0000-000000000001/83100000-0000-0000-0000-000000000099/expired.pdf','expired.pdf','application/pdf',52428800,'reserved',now()-interval '1 minute',1);

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('project-boundary',public.cmd_reserve_task_file_upload('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000002',1,'new_file',null,'boundary.pdf','application/pdf',12582912));
insert into file_results values('project-one-over',public.cmd_reserve_task_file_upload('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000003',1,'new_file',null,'one-over.pdf','application/pdf',1));
reset role;
select is((select result->>'ok' from file_results where label='project-boundary'),'true','exactly 0.5 GiB project usage is accepted with finalized plus live bytes and expired reservation excluded');
select is((select result->>'code' from file_results where label='project-one-over'),'STORAGE_QUOTA_EXCEEDED','one byte over 0.5 GiB is rejected');

-- Unuploaded reservations must reserve the full per-object Storage envelope because INSERT RLS cannot trust final size metadata.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('81100000-0000-0000-0000-000000000001','Reservation envelope project',now()+interval '10 days','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('81100000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','leader','active'),
('81100000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('82100000-0000-0000-0000-000000000001','81100000-0000-0000-0000-000000000001','Reservation envelope task','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002',now()+interval '3 days','in_progress',1,'assigned',now(),1);
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.cmd_reserve_task_file_upload(
  '81100000-0000-0000-0000-000000000001',
  '82100000-0000-0000-0000-000000000001',
  ('83100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
  1,'new_file',null,'tiny-'||i||'.pdf','application/pdf',1
)
from generate_series(1,10) s(i);
insert into file_results values('reservation-envelope-eleventh',public.cmd_reserve_task_file_upload(
  '81100000-0000-0000-0000-000000000001',
  '82100000-0000-0000-0000-000000000001',
  '83100000-0000-0000-0000-000000000011',
  1,'new_file',null,'tiny-11.pdf','application/pdf',1
));
reset role;
select is((select count(*)::integer from public.file_upload_reservations where project_id='81100000-0000-0000-0000-000000000001' and state='reserved'),10,'ten live unuploaded reservations consume ten 50 MiB upload envelopes');
select is((select result->>'code' from file_results where label='reservation-envelope-eleventh'),'STORAGE_QUOTA_EXCEEDED','an eleventh live reservation is rejected before physical uploads can exceed the 0.5 GiB project cap');

-- Physical pending objects continue to count after their reservations expire.
delete from public.file_upload_reservations
where project_id='81000000-0000-0000-0000-000000000001' and state='reserved';
insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/81000000-0000-0000-0000-000000000001/86000000-0000-0000-0000-'||lpad(i::text,12,'0')||'/orphan-'||i||'.pdf',
       'orphan-'||i||'.pdf','application/pdf',52428800,'reserved',now()-interval '1 minute',1
from generate_series(1,9) s(i);
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,'70000000-0000-0000-0000-000000000002',jsonb_build_object('size',52428800,'mimetype','application/pdf')
from public.file_upload_reservations r
where r.project_id='81000000-0000-0000-0000-000000000001' and r.original_name like 'orphan-%';

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('orphan-boundary',public.cmd_reserve_task_file_upload('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000004',1,'new_file',null,'orphan-boundary.pdf','application/pdf',12582912));
insert into file_results values('orphan-one-over',public.cmd_reserve_task_file_upload('81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000005',1,'new_file',null,'orphan-one-over.pdf','application/pdf',1));
reset role;
select is((select result->>'ok' from file_results where label='orphan-boundary'),'true','historical plus expired physical pending objects can fill exactly 0.5 GiB');
select is((select result->>'code' from file_results where label='orphan-one-over'),'STORAGE_QUOTA_EXCEEDED','expired physical pending objects remain enforceable quota until removed or finalized');

-- Unknown persisted Storage size is quota-accounted conservatively at the bucket's 50 MiB ceiling.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('81200000-0000-0000-0000-000000000001','Unknown metadata quota project',now()+interval '10 days','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state)
values('81200000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','leader','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('82200000-0000-0000-0000-000000000001','81200000-0000-0000-0000-000000000001','Unknown metadata quota task','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',now()+interval '3 days','in_progress',1,'assigned',now(),1);
insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select ('83200000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       '81200000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','new_file',
       'pending/81200000-0000-0000-0000-000000000001/83200000-0000-0000-0000-'||lpad(i::text,12,'0')||'/unknown-'||i||'.pdf',
       'unknown-'||i||'.pdf','application/pdf',1,'reserved',now()-interval '1 minute',1
from generate_series(1,10) s(i);
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,'70000000-0000-0000-0000-000000000001','{}'::jsonb
from public.file_upload_reservations r
where r.project_id='81200000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into file_results values('unknown-metadata-quota',public.cmd_reserve_task_file_upload(
  '81200000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001',
  '83200000-0000-0000-0000-000000000011',1,'new_file',null,'next.pdf','application/pdf',1
));
reset role;
select is((select result->>'code' from file_results where label='unknown-metadata-quota'),'STORAGE_QUOTA_EXCEEDED','unknown physical object size reserves the full 50 MiB envelope instead of trusting client-declared bytes');

-- Complete reject-service failure, replay, ledger/event, and rollback matrix.
insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select ('87000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       '71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file',
       'pending/71000000-0000-0000-0000-000000000001/87000000-0000-0000-0000-'||lpad(i::text,12,'0')||'/reject-'||i||'.txt',
       'reject-'||i||'.txt','text/plain',20,'reserved',now()+interval '15 minutes',1
from generate_series(1,7) s(i);

set local role service_role;
insert into file_results values('reject-actor-mismatch-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000003','87000000-0000-0000-0000-000000000001','88000000-0000-0000-0000-000000000001',1,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-stale-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000002','88000000-0000-0000-0000-000000000002',99,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-stale-replay-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000002','88000000-0000-0000-0000-000000000002',99,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-stale-reuse-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000002','88000000-0000-0000-0000-000000000002',1,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-invalid-code-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000003','88000000-0000-0000-0000-000000000003',1,'NOT_A_CODE'));
reset role;
select is((select result->>'code' from file_results where label='reject-actor-mismatch-v2'),'NOT_FOUND_OR_NOT_AUTHORIZED','reject enforces actor match');
select is((select result->>'code' from file_results where label='reject-stale-v2'),'STALE_VERSION','reject enforces expected reservation version');
select is((select result->>'replayed' from file_results where label='reject-stale-replay-v2'),'true','stable reject failure replays from the command ledger');
select is((select result->>'code' from file_results where label='reject-stale-reuse-v2'),'IDEMPOTENCY_KEY_REUSED','stable reject failure reserves request id against changed payload');
select is((select result->>'code' from file_results where label='reject-invalid-code-v2'),'VALIDATION_FAILED','reject validates rejection code');
select is((select count(*)::integer from public.file_upload_reservations where id in ('87000000-0000-0000-0000-000000000001','87000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000003') and state='reserved'),3,'reject failures do not mutate reservations');

update public.project_members set member_state='left',departed_at=now() where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';
set local role service_role;
insert into file_results values('reject-membership-revoked-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000004','88000000-0000-0000-0000-000000000004',1,'FILE_VALIDATION_FAILED'));
reset role;
select is((select result->>'code' from file_results where label='reject-membership-revoked-v2'),'NOT_FOUND_OR_NOT_AUTHORIZED','reject rechecks current membership');
update public.project_members set member_state='active',departed_at=null where project_id='71000000-0000-0000-0000-000000000001' and user_id='70000000-0000-0000-0000-000000000002';

update public.tasks set assignee_id='70000000-0000-0000-0000-000000000004' where id='72000000-0000-0000-0000-000000000001';
set local role service_role;
insert into file_results values('reject-task-role-revoked-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000005','88000000-0000-0000-0000-000000000005',1,'FILE_VALIDATION_FAILED'));
reset role;
select is((select result->>'code' from file_results where label='reject-task-role-revoked-v2'),'NOT_FOUND_OR_NOT_AUTHORIZED','reject rechecks current task role');
update public.tasks set assignee_id='70000000-0000-0000-0000-000000000002' where id='72000000-0000-0000-0000-000000000001';

set local role service_role;
insert into file_results values('reject-success-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000006','88000000-0000-0000-0000-000000000006',1,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-replay-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000006','88000000-0000-0000-0000-000000000006',1,'FILE_VALIDATION_FAILED'));
insert into file_results values('reject-reuse-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000006','88000000-0000-0000-0000-000000000006',1,'STORAGE_QUOTA_EXCEEDED'));
insert into file_results values('reject-double-v2',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000006','88000000-0000-0000-0000-000000000007',2,'FILE_VALIDATION_FAILED'));
reset role;
select is((select result->>'ok' from file_results where label='reject-success-v2'),'true','reject success returns ok');
select is((select result->'data' from file_results where label='reject-replay-v2')::text,(select result->'data' from file_results where label='reject-success-v2')::text,'reject replay returns identical data');
select is((select result->>'aggregateId' from file_results where label='reject-replay-v2'),(select result->>'aggregateId' from file_results where label='reject-success-v2'),'reject replay preserves aggregate id');
select is((select result->>'aggregateVersion' from file_results where label='reject-replay-v2'),'2','reject replay preserves aggregate version');
select is((select result->>'replayed' from file_results where label='reject-replay-v2'),'true','reject replay is marked');
select is((select result->>'code' from file_results where label='reject-reuse-v2'),'IDEMPOTENCY_KEY_REUSED','reject detects request id payload reuse');
select is((select result->>'code' from file_results where label='reject-double-v2'),'UPLOAD_NOT_READY','double rejection is rejected');
select is((select count(*)::integer from public.command_requests where request_id='88000000-0000-0000-0000-000000000006' and result->'data'->>'reservationId'='87000000-0000-0000-0000-000000000006'),1,'reject stores one exact ledger result');
select is((select count(*)::integer from public.business_events where request_id='88000000-0000-0000-0000-000000000006' and project_id='71000000-0000-0000-0000-000000000001' and actor_id='70000000-0000-0000-0000-000000000002' and event_type='task_file_upload_rejected' and entity_type='file_upload_reservation' and entity_id='87000000-0000-0000-0000-000000000006' and event_data=jsonb_build_object('rejectionCode','FILE_VALIDATION_FAILED')),1,'reject emits exact event payload once');

create or replace function pg_temp.reject_day4_event() returns trigger language plpgsql as $$
begin
  if new.request_id='88000000-0000-0000-0000-000000000008'::uuid then
    raise exception using errcode='P0001',message='injected reject event failure';
  end if;
  return new;
end;
$$;
create trigger day4_reject_event_failure before insert on public.business_events for each row execute function pg_temp.reject_day4_event();
set local role service_role;
select throws_ok($$select public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','87000000-0000-0000-0000-000000000007','88000000-0000-0000-0000-000000000008',1,'FILE_VALIDATION_FAILED')$$,'P0001','injected reject event failure','reject event failure rolls the command back atomically');
reset role;
drop trigger day4_reject_event_failure on public.business_events;
select is((select state from public.file_upload_reservations where id='87000000-0000-0000-0000-000000000007'),'reserved','reject event failure leaves reservation reserved');
select is((select count(*)::integer from public.command_requests where request_id='88000000-0000-0000-0000-000000000008'),0,'reject event failure rolls ledger back');
select is((select count(*)::integer from public.business_events where request_id='88000000-0000-0000-0000-000000000008'),0,'reject event failure leaves no event');

-- Phase 2 reserves the full file-size envelope for each still-live reservation.
-- Earlier independent reject/validation fixtures are intentionally left in
-- the reserved state to test replay; expire only those fixtures before the
-- unrelated new-version race so they do not exhaust its project quota.
-- Preserve the rows and Storage objects for subsequent RLS/history assertions.
update public.file_upload_reservations
set expires_at = transaction_timestamp() - interval '1 minute'
where project_id = '71000000-0000-0000-0000-000000000001'
  and state = 'reserved';

-- New-version stale race: reserve twice at N, advance with one finalization, then finalize stale reservation.
select version as race_base_version from public.task_files where id=:'file_id'::uuid \gset
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into file_results values('race-reserve-a',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','89000000-0000-0000-0000-000000000001',:race_base_version,'new_version',:'file_id','race-a.pdf','application/pdf',30));
insert into file_results values('race-reserve-b',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','89000000-0000-0000-0000-000000000002',:race_base_version,'new_version',:'file_id','race-b.pdf','application/pdf',30));
reset role;
select result->'data'->>'reservationId' as race_a_id from file_results where label='race-reserve-a' \gset
select result->'data'->>'reservationId' as race_b_id from file_results where label='race-reserve-b' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.id in (:'race_a_id'::uuid,:'race_b_id'::uuid);
set local role service_role;
insert into file_results values('race-finalize-b',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'race_b_id','89000000-0000-0000-0000-000000000003',1,'application/pdf',30,repeat('b',64)));
reset role;
select count(*)::integer as race_versions_before_stale from public.task_file_versions where file_id=:'file_id'::uuid \gset
select version as race_file_version_after_b from public.task_files where id=:'file_id'::uuid \gset
create temporary table race_file_snapshot_v3 as select * from public.task_files where id=:'file_id'::uuid;
select current_version_id as race_current_version_before_stale from public.task_files where id=:'file_id'::uuid \gset
set local role service_role;
insert into file_results values('race-finalize-a-stale',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'race_a_id','89000000-0000-0000-0000-000000000004',1,'application/pdf',30,repeat('a',64)));
insert into file_results values('race-finalize-a-stale-replay',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'race_a_id','89000000-0000-0000-0000-000000000004',1,'application/pdf',30,repeat('a',64)));
insert into file_results values('race-finalize-a-stale-reuse',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000003',:'race_a_id','89000000-0000-0000-0000-000000000004',1,'application/pdf',30,repeat('c',64)));
reset role;
select is((select result->>'code' from file_results where label='race-finalize-a-stale'),'STALE_VERSION','stale new-version finalization is rejected after another finalization advances the file');
select is((select state from public.file_upload_reservations where id=:'race_a_id'::uuid),'reserved','stale new-version reservation remains reserved');
select is((select count(*)::integer from public.task_file_versions where file_id=:'file_id'::uuid),:race_versions_before_stale::integer,'stale new-version finalization creates no version');
select is((select version from public.task_files where id=:'file_id'::uuid),:race_file_version_after_b::integer,'stale new-version finalization does not advance aggregate version');
select is((select count(*)::integer from public.business_events where request_id='89000000-0000-0000-0000-000000000004'),0,'stale new-version finalization emits no business event');
select is((select current_version_id from public.task_files where id=:'file_id'::uuid),:'race_current_version_before_stale'::uuid,'stale finalization preserves current_version_id');
select is((select to_jsonb(f) from public.task_files f where f.id=:'file_id'::uuid),(select to_jsonb(s) from race_file_snapshot_v3 s),'stale finalization preserves the complete logical-file row');
select is((select result->>'replayed' from file_results where label='race-finalize-a-stale-replay'),'true','stable finalize failure replays from the command ledger');
select is((select result->>'code' from file_results where label='race-finalize-a-stale-reuse'),'IDEMPOTENCY_KEY_REUSED','stable finalize failure reserves request id against changed payload');
select is((select count(*)::integer from public.command_requests where request_id='89000000-0000-0000-0000-000000000004' and state='completed'),1,'stable stale finalization completes exactly one command ledger row');

-- Deep replay invariants for the original reserve/finalize paths.
select is((select result->'data' from file_results where label='reserve-replay')::text,(select result->'data' from file_results where label='reserve-one')::text,'reserve replay preserves reservation id, path, and expiresAt');
select is((select result->>'aggregateId' from file_results where label='reserve-replay'),(select result->>'aggregateId' from file_results where label='reserve-one'),'reserve replay preserves aggregate id');
select is((select result->>'aggregateVersion' from file_results where label='reserve-replay'),(select result->>'aggregateVersion' from file_results where label='reserve-one'),'reserve replay preserves aggregate version');
select is((select result->'data' from file_results where label='finalize-replay')::text,(select result->'data' from file_results where label='finalize-one')::text,'finalize replay preserves exact identifiers and version data');
select is((select result->>'aggregateId' from file_results where label='finalize-replay'),(select result->>'aggregateId' from file_results where label='finalize-one'),'finalize replay preserves aggregate id');
select is((select result->>'aggregateVersion' from file_results where label='finalize-replay'),(select result->>'aggregateVersion' from file_results where label='finalize-one'),'finalize replay preserves aggregate version');
-- Attempt-3 RED regressions: physical-object proof, definer boundary, orphan quota, and NULL domain failures.
select ok((select p.prosecdef from pg_proc p where p.oid='public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)'::regprocedure),'service finalize is SECURITY DEFINER');
select ok((select p.prosecdef from pg_proc p where p.oid='public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)'::regprocedure),'service reject is SECURITY DEFINER');
select ok(not has_table_privilege('service_role','public.file_upload_reservations','UPDATE'),'service role cannot bypass reject/finalize via reservation UPDATE');
select ok(not has_table_privilege('service_role','public.task_files','INSERT'),'service role cannot bypass finalize via task_files INSERT');
select ok(not has_table_privilege('service_role','public.task_file_versions','INSERT'),'service role cannot bypass finalize via task_file_versions INSERT');
select ok(not has_function_privilege('service_role','private.claim_command(uuid,text,uuid,bytea,uuid,uuid)','EXECUTE'),'service role cannot execute private command helpers directly');

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into file_results values('v3-reserve-missing-object',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000001',1,'new_file',null,'missing-object.txt','text/plain',20));
insert into file_results values('v3-reserve-storage-mismatch',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000002',1,'new_file',null,'mismatched-object.txt','text/plain',20));
reset role;
select result->'data'->>'reservationId' as v3_missing_reservation_id from file_results where label='v3-reserve-missing-object' \gset
select result->'data'->>'reservationId' as v3_mismatch_reservation_id from file_results where label='v3-reserve-storage-mismatch' \gset
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,r.actor_id,jsonb_build_object('size',19,'mimetype','application/pdf')
from public.file_upload_reservations r where r.id=:'v3_mismatch_reservation_id'::uuid;
set local role service_role;
insert into file_results values('v3-finalize-missing-object',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'v3_missing_reservation_id','9a000000-0000-0000-0000-000000000003',1,'text/plain',20,repeat('a',64)));
insert into file_results values('v3-finalize-storage-mismatch',public.cmd_finalize_task_file_upload_service('70000000-0000-0000-0000-000000000002',:'v3_mismatch_reservation_id','9a000000-0000-0000-0000-000000000004',1,'text/plain',20,repeat('b',64)));
reset role;
select is((select result->>'code' from file_results where label='v3-finalize-missing-object'),'UPLOAD_NOT_READY','finalize requires the physical Storage object');
select is((select result->>'code' from file_results where label='v3-finalize-storage-mismatch'),'FILE_VALIDATION_FAILED','finalize trusts stored Storage metadata rather than caller metadata');
select is((select count(*)::integer from public.task_file_versions where reservation_id in (:'v3_missing_reservation_id'::uuid,:'v3_mismatch_reservation_id'::uuid)),0,'physical Storage failures create no file versions');
select is((select count(*)::integer from public.business_events where request_id in ('9a000000-0000-0000-0000-000000000003','9a000000-0000-0000-0000-000000000004')),0,'physical Storage failures emit no events');
select is((select count(*)::integer from public.command_requests where request_id in ('9a000000-0000-0000-0000-000000000003','9a000000-0000-0000-0000-000000000004') and state='completed'),0,'physical Storage failures complete no ledger rows');

select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select lives_ok($$insert into file_results values('v3-null-mode',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000005',1,null,null,'null-mode.txt','text/plain',20))$$,'NULL mode returns a domain result instead of a constraint exception');
select lives_ok($$insert into file_results values('v3-null-mime',public.cmd_reserve_task_file_upload('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000006',1,'new_file',null,'null-mime.txt',null,20))$$,'NULL declared MIME returns a domain result instead of a constraint exception');
reset role;
select is((select result->>'code' from file_results where label='v3-null-mode'),'VALIDATION_FAILED','NULL mode is a stable validation failure');
select is((select result->>'code' from file_results where label='v3-null-mime'),'FILE_TYPE_NOT_ALLOWED','NULL declared MIME is a stable file-type failure');
select is((select count(*)::integer from public.file_upload_reservations where original_name in ('null-mode.txt','null-mime.txt')),0,'NULL reserve inputs create no reservations');
select is((select count(*)::integer from public.business_events where request_id in ('9a000000-0000-0000-0000-000000000005','9a000000-0000-0000-0000-000000000006')),0,'NULL reserve inputs emit no events');

insert into public.file_upload_reservations(id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
values('9a100000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000002','new_file','pending/71000000-0000-0000-0000-000000000001/9a100000-0000-0000-0000-000000000001/null-reject.txt','null-reject.txt','text/plain',20,'reserved',now()+interval '15 minutes',1);
set local role service_role;
select lives_ok($$insert into file_results values('v3-null-rejection-code',public.cmd_reject_task_file_upload_service('70000000-0000-0000-0000-000000000002','9a100000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000007',1,null))$$,'NULL rejection code returns a domain result instead of a constraint exception');
reset role;
select is((select result->>'code' from file_results where label='v3-null-rejection-code'),'VALIDATION_FAILED','NULL rejection code is a stable validation failure');
select is((select state from public.file_upload_reservations where id='9a100000-0000-0000-0000-000000000001'),'reserved','NULL rejection code leaves reservation untouched');
select is((select count(*)::integer from public.business_events where request_id='9a000000-0000-0000-0000-000000000007'),0,'NULL rejection code emits no event');

insert into auth.users(id,email) values('9b000000-0000-0000-0000-000000000001','orphan-uploader@example.test');
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('9b100000-0000-0000-0000-000000000001','Orphan quota project',now()+interval '10 days','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('9b100000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','leader','active'),
('9b100000-0000-0000-0000-000000000001','9b000000-0000-0000-0000-000000000001','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values('9b200000-0000-0000-0000-000000000001','9b100000-0000-0000-0000-000000000001','Orphan quota task','70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',now()+interval '3 days','in_progress',1,'assigned',now(),1);
insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version)
select '9b100000-0000-0000-0000-000000000001','9b200000-0000-0000-0000-000000000001','9b000000-0000-0000-0000-000000000001','new_file',
       'pending/9b100000-0000-0000-0000-000000000001/9b300000-0000-0000-0000-'||lpad(i::text,12,'0')||'/orphan-'||i||'.pdf',
       'orphan-'||i||'.pdf','application/pdf',52428800,'reserved',now()-interval '1 minute',1
from generate_series(1,10) s(i);
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'teamup-files',r.object_path,'9b000000-0000-0000-0000-000000000001',jsonb_build_object('size',r.declared_size_bytes,'mimetype',r.declared_mime_type)
from public.file_upload_reservations r where r.project_id='9b100000-0000-0000-0000-000000000001';
delete from auth.users where id='9b000000-0000-0000-0000-000000000001';
select is((select count(*)::integer from public.file_upload_reservations where project_id='9b100000-0000-0000-0000-000000000001' and actor_id is null),10,'actor deletion anonymizes reservations while retaining project attribution');
select is((select count(*)::integer from storage.objects where bucket_id='teamup-files' and name like 'pending/9b100000-0000-0000-0000-000000000001/%'),10,'actor deletion leaves physical pending objects');
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into file_results values('v3-orphan-after-user-delete',public.cmd_reserve_task_file_upload('9b100000-0000-0000-0000-000000000001','9b200000-0000-0000-0000-000000000001','9b000000-0000-0000-0000-000000000002',1,'new_file',null,'over-orphan-quota.pdf','application/pdf',13*1024*1024));
reset role;
select is((select result->>'code' from file_results where label='v3-orphan-after-user-delete'),'STORAGE_QUOTA_EXCEEDED','pending Storage bytes remain quota-accounted after uploader deletion');


-- Attempt-3 exact catalog coverage: complete FK source/ref/action semantics, unique keys, and normalized CHECKs.
with expected(table_name,constraint_name,ref_table,src,dst,delete_action,update_action,is_deferrable,is_deferred) as (
  values
    ('public.file_upload_reservations','file_upload_reservations_project_id_fkey','public.projects',array['project_id']::text[],array['id']::text[],'c','a',false,false),
    ('public.file_upload_reservations','file_upload_reservations_actor_id_fkey','auth.users',array['actor_id']::text[],array['id']::text[],'n','a',false,false),
    ('public.file_upload_reservations','file_upload_reservations_project_id_task_id_fkey','public.tasks',array['project_id','task_id']::text[],array['project_id','id']::text[],'c','a',false,false),
    ('public.file_upload_reservations','file_upload_reservations_target_file_fkey','public.task_files',array['project_id','task_id','target_file_id']::text[],array['project_id','task_id','id']::text[],'a','a',false,false),
    ('public.task_files','task_files_project_id_fkey','public.projects',array['project_id']::text[],array['id']::text[],'c','a',false,false),
    ('public.task_files','task_files_created_by_fkey','auth.users',array['created_by']::text[],array['id']::text[],'n','a',false,false),
    ('public.task_files','task_files_project_id_task_id_fkey','public.tasks',array['project_id','task_id']::text[],array['project_id','id']::text[],'c','a',false,false),
    ('public.task_files','task_files_current_version_same_file_fkey','public.task_file_versions',array['id','current_version_id']::text[],array['file_id','id']::text[],'a','a',true,true),
    ('public.task_file_versions','task_file_versions_reservation_id_fkey','public.file_upload_reservations',array['project_id','task_id','reservation_id','object_path']::text[],array['project_id','task_id','id','object_path']::text[],'a','a',false,false),
    ('public.task_file_versions','task_file_versions_uploaded_by_fkey','auth.users',array['uploaded_by']::text[],array['id']::text[],'n','a',false,false),
    ('public.task_file_versions','task_file_versions_project_id_task_id_file_id_fkey','public.task_files',array['project_id','task_id','file_id']::text[],array['project_id','task_id','id']::text[],'c','a',false,false),
    ('public.task_file_versions','task_file_versions_restored_same_file_fkey','public.task_file_versions',array['file_id','restored_from_version_id']::text[],array['file_id','id']::text[],'a','a',true,true)
),
actual as (
  select c.conrelid,c.conname,c.confrelid,c.confdeltype::text as delete_action,c.confupdtype::text as update_action,c.condeferrable,c.condeferred,
         array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord) as src,
         array(select a.attname::text from unnest(c.confkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum order by k.ord) as dst
  from pg_constraint c
  where c.contype='f' and c.conrelid in ('public.file_upload_reservations'::regclass,'public.task_files'::regclass,'public.task_file_versions'::regclass)
)
select ok(
  a.conrelid=e.table_name::regclass and a.confrelid=e.ref_table::regclass and a.src=e.src and a.dst=e.dst
  and a.delete_action=e.delete_action and a.update_action=e.update_action
  and a.condeferrable=e.is_deferrable and a.condeferred=e.is_deferred,
  format('%s has exact FK %s columns/actions',e.table_name,e.constraint_name)
)
from expected e left join actual a on a.conname=e.constraint_name and a.conrelid=e.table_name::regclass;

-- Legacy full-path UNIQUE constraints were replaced by partial UNIQUE indexes:
-- live upload reservations remain collision-protected, while finalized
-- reservations and copy-forward restored versions may reuse immutable paths.
with expected(table_name,constraint_name,cols) as (
  values
    ('public.file_upload_reservations','file_upload_reservations_scope_path_unique',array['project_id','task_id','id','object_path']::text[]),
    ('public.task_files','task_files_project_task_id_unique',array['project_id','task_id','id']::text[]),
    ('public.task_file_versions','task_file_versions_file_version_unique',array['file_id','version_number']::text[]),
    ('public.task_file_versions','task_file_versions_reservation_unique',array['reservation_id']::text[]),
    ('public.task_file_versions','task_file_versions_file_id_id_unique',array['file_id','id']::text[])
)
select is(
  (select array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord)
   from pg_constraint c where c.conrelid=e.table_name::regclass and c.conname=e.constraint_name and c.contype='u'),
  e.cols,
  format('%s unique key %s has exact columns',e.table_name,e.constraint_name)
)
from expected e;

with expected(table_name,index_name,index_predicate) as (
  values
    ('public.file_upload_reservations','file_upload_reservations_live_object_path_unique','(state = ''reserved''::text)'),
    ('public.task_file_versions','task_file_versions_uploaded_object_path_unique_idx','(restored_from_version_id IS NULL)')
)
select ok(
  coalesce(
    i.indisunique
    and i.indisvalid
    and i.indisready
    and i.indnkeyatts = 1
    and pg_get_indexdef(i.indexrelid,1,true) = 'object_path'
    and pg_get_expr(i.indpred,i.indrelid) = e.index_predicate,
    false
  ),
  format('%s partial UNIQUE index %s protects only %s',e.table_name,e.index_name,e.index_predicate)
)
from expected e
left join pg_class c on c.relname=e.index_name and c.relnamespace='public'::regnamespace
left join pg_index i on i.indexrelid=c.oid and i.indrelid=e.table_name::regclass;

with expected(table_name,cols) as (
  values
    ('public.file_upload_reservations',array['id']::text[]),
    ('public.task_files',array['id']::text[]),
    ('public.task_file_versions',array['id']::text[])
)
select is(
  (select array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord)
   from pg_constraint c where c.conrelid=e.table_name::regclass and c.contype='p'),
  e.cols,
  format('%s primary key columns are exact',e.table_name)
)
from expected e;

with expected(table_name,constraint_name,normalized) as (
  values
    ('public.file_upload_reservations','file_upload_reservations_mode','check((mode=any(array[''new_file'',''new_version''])))'),
    ('public.file_upload_reservations','file_upload_reservations_target','check((((mode=''new_file'')and(target_file_idisnull)and(target_file_versionisnull))or((mode=''new_version'')and(target_file_idisnotnull)and(target_file_versionisnotnull)and(target_file_version>0))))'),
    ('public.file_upload_reservations','file_upload_reservations_state','check((state=any(array[''reserved'',''finalized'',''rejected''])))'),
    ('public.file_upload_reservations','file_upload_reservations_rejection','check((((state=''rejected'')and(rejection_codeisnotnull))or((state<>''rejected'')and(rejection_codeisnull))))'),
    ('public.file_upload_reservations','file_upload_reservations_name_length','check(((char_length(original_name)>=1)and(char_length(original_name)<=255)))'),
    ('public.file_upload_reservations','file_upload_reservations_mime_length','check(((char_length(declared_mime_type)>=1)and(char_length(declared_mime_type)<=160)))'),
    ('public.file_upload_reservations','file_upload_reservations_size','check(((declared_size_bytes>0)and(declared_size_bytes<=209715200)and((state<>''reserved'')or(declared_size_bytes<=coalesce(reserved_envelope_bytes,(52428800)::bigint)))))'),
    ('public.file_upload_reservations','file_upload_reservations_version','check((version>0))'),
    ('public.task_files','task_files_logical_name_length','check(((char_length(logical_name)>=1)and(char_length(logical_name)<=255)))'),
    ('public.task_files','task_files_version','check((version>0))'),
    ('public.task_file_versions','task_file_versions_version_number','check((version_number>0))'),
    ('public.task_file_versions','task_file_versions_name_length','check(((char_length(original_name)>=1)and(char_length(original_name)<=255)))'),
    ('public.task_file_versions','task_file_versions_mime_length','check(((char_length(mime_type)>=1)and(char_length(mime_type)<=160)))'),
    ('public.task_file_versions','task_file_versions_size','check(((size_bytes>0)and((size_bytes<=52428800)or((size_bytes>52428800)and(size_bytes<=209715200)))))'),
    ('public.task_file_versions','task_file_versions_sha256','check((sha256_hex~''^[0-9a-f]{64}$''))')
)
select is(
  (select regexp_replace(regexp_replace(lower(pg_get_constraintdef(c.oid)),'::text','','g'),'[[:space:]]+','','g')
   from pg_constraint c where c.conrelid=e.table_name::regclass and c.conname=e.constraint_name and c.contype='c'),
  e.normalized,
  format('%s check %s has exact normalized expression',e.table_name,e.constraint_name)
)
from expected e;

-- The service role gets no direct private-schema capability after write RPCs became definers.
select ok(not has_schema_privilege('service_role','private','USAGE'),'service role has no private schema USAGE');
with helpers(signature) as (
  values
    ('private.failure(uuid,text,text,integer,jsonb)'),
    ('private.payload_hash(jsonb)'),
    ('private.claim_command(uuid,text,uuid,bytea,uuid,uuid)'),
    ('private.complete_command(uuid,jsonb,text,uuid,integer)'),
    ('private.replay_or_reuse(uuid,jsonb,boolean)'),
    ('private.reject_unless_authorized(boolean,uuid,uuid,jsonb,boolean)'),
    ('private.is_current_task_file_actor(uuid,uuid,uuid)'),
    ('private.task_file_project_usage_bytes(uuid,uuid)'),
    ('private.is_allowed_task_file_mime(text)'),
    ('private.emit_event(uuid,integer,uuid,uuid,text,text,uuid,uuid,jsonb)')
)
select ok(not has_function_privilege('service_role',signature,'EXECUTE'),format('service role cannot execute %s directly',signature))
from helpers;

-- Full command-ledger and event identity checks for reserve/finalize/reject.
select is((select cr.result from public.command_requests cr where cr.request_id='88000000-0000-0000-0000-000000000006'),(select result from file_results where label='reject-success-v2'),'reject ledger stores the exact returned result');
select is((select cr.state from public.command_requests cr where cr.request_id='88000000-0000-0000-0000-000000000006'),'completed','reject ledger is completed');
select is((select cr.resulting_entity_type from public.command_requests cr where cr.request_id='88000000-0000-0000-0000-000000000006'),'file_upload_reservation','reject ledger entity type is exact');
select is((select cr.resulting_entity_id from public.command_requests cr where cr.request_id='88000000-0000-0000-0000-000000000006'),'87000000-0000-0000-0000-000000000006'::uuid,'reject ledger entity id is exact');
select is((select cr.resulting_entity_version from public.command_requests cr where cr.request_id='88000000-0000-0000-0000-000000000006'),2,'reject ledger entity version is exact');

select is((select count(*)::integer from public.business_events e join public.command_requests cr on cr.id=e.command_request_id
  where e.request_id='73000000-0000-0000-0000-000000000010' and cr.request_id=e.request_id and e.event_seq=1
    and e.project_id='71000000-0000-0000-0000-000000000001' and e.actor_id='70000000-0000-0000-0000-000000000002'
    and e.event_type='task_file_upload_reserved' and e.entity_type='file_upload_reservation' and e.entity_id=:'reserve_id'::uuid
    and e.event_data=jsonb_build_object('taskId','72000000-0000-0000-0000-000000000001'::uuid,'mode','new_file')),1,'reserve event row has exact command binding, sequence, entity, and payload');
select is((select count(*)::integer from public.business_events e join public.command_requests cr on cr.id=e.command_request_id
  where e.request_id='73000000-0000-0000-0000-000000000013' and cr.request_id=e.request_id and e.event_seq=1
    and e.project_id='71000000-0000-0000-0000-000000000001' and e.actor_id='70000000-0000-0000-0000-000000000002'
    and e.event_type='task_file_upload_finalized' and e.entity_type='task_file' and e.entity_id=(select (result->'data'->>'fileId')::uuid from file_results where label='finalize-one')
    and e.event_data=jsonb_build_object('reservationId',:'reserve_id'::uuid,'fileVersionId',(select (result->'data'->>'fileVersionId')::uuid from file_results where label='finalize-one'),'versionNumber',1)),1,'finalize event row has exact command binding, sequence, entity, and payload');
select is((select count(*)::integer from public.business_events e join public.command_requests cr on cr.id=e.command_request_id
  where e.request_id='88000000-0000-0000-0000-000000000006' and cr.request_id=e.request_id and e.event_seq=1
    and e.project_id='71000000-0000-0000-0000-000000000001' and e.actor_id='70000000-0000-0000-0000-000000000002'
    and e.event_type='task_file_upload_rejected' and e.entity_type='file_upload_reservation' and e.entity_id='87000000-0000-0000-0000-000000000006'
    and e.event_data=jsonb_build_object('rejectionCode','FILE_VALIDATION_FAILED')),1,'reject event row has exact command binding, sequence, entity, and payload');
select is((select count(*)::integer from public.command_requests where request_id='89000000-0000-0000-0000-000000000004' and state='completed'),1,'stable stale finalization keeps one completed ledger row');

-- Behavioral RLS CRUD matrix. Temporarily expose table privileges so these probes exercise RLS itself.
create role day4_public_probe nologin;
grant select, insert, update, delete on public.file_upload_reservations, public.task_files, public.task_file_versions to public;
create or replace function pg_temp.day4_rls_probe(
  p_role text,
  p_uid uuid,
  p_operation text,
  p_table text,
  p_file_id uuid,
  p_file_version_id uuid,
  p_reservation_id uuid
) returns boolean
language plpgsql
as $$
declare
  v_allowed boolean := false;
  v_rows integer := 0;
begin
  begin
    perform set_config('request.jwt.claim.sub',coalesce(p_uid::text,''),true);
    execute format('set local role %I',p_role);
    if p_operation='SELECT' then
      if p_table='reservations' then
        execute 'select exists(select 1 from public.file_upload_reservations where id=$1)' into v_allowed using p_reservation_id;
      elsif p_table='files' then
        execute 'select exists(select 1 from public.task_files where id=$1)' into v_allowed using p_file_id;
      else
        execute 'select exists(select 1 from public.task_file_versions where id=$1)' into v_allowed using p_file_version_id;
      end if;
    elsif p_operation='INSERT' then
      if p_table='reservations' then
        execute 'insert into public.file_upload_reservations(project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version) values($1,$2,$3,''new_file'',''rls-probe/''||gen_random_uuid(),''rls.txt'',''text/plain'',1,''reserved'',now()+interval ''1 minute'',1)'
          using '71000000-0000-0000-0000-000000000001'::uuid,'72000000-0000-0000-0000-000000000001'::uuid,coalesce(p_uid,'70000000-0000-0000-0000-000000000002'::uuid);
      elsif p_table='files' then
        execute 'insert into public.task_files(project_id,task_id,logical_name,created_by,version) values($1,$2,''rls.txt'',$3,1)'
          using '71000000-0000-0000-0000-000000000001'::uuid,'72000000-0000-0000-0000-000000000001'::uuid,coalesce(p_uid,'70000000-0000-0000-0000-000000000002'::uuid);
      else
        execute 'insert into public.task_file_versions(id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by) values(gen_random_uuid(),$1,$2,$3,$4,999,''rls-probe/''||gen_random_uuid(),''rls.txt'',''text/plain'',1,repeat(''a'',64),$5)'
          using p_file_id,'71000000-0000-0000-0000-000000000001'::uuid,'72000000-0000-0000-0000-000000000001'::uuid,p_reservation_id,coalesce(p_uid,'70000000-0000-0000-0000-000000000002'::uuid);
      end if;
      v_allowed := true;
    elsif p_operation='UPDATE' then
      if p_table='reservations' then
        execute 'update public.file_upload_reservations set updated_at=updated_at where id=$1' using p_reservation_id;
      elsif p_table='files' then
        execute 'update public.task_files set updated_at=updated_at where id=$1' using p_file_id;
      else
        execute 'update public.task_file_versions set original_name=original_name where id=$1' using p_file_version_id;
      end if;
      get diagnostics v_rows = row_count;
      v_allowed := v_rows > 0;
    else
      if p_table='reservations' then
        execute 'delete from public.file_upload_reservations where id=$1' using p_reservation_id;
      elsif p_table='files' then
        execute 'delete from public.task_files where id=$1' using p_file_id;
      else
        execute 'delete from public.task_file_versions where id=$1' using p_file_version_id;
      end if;
      get diagnostics v_rows = row_count;
      v_allowed := v_rows > 0;
    end if;
    raise exception using errcode='P0001',message='day4_rls_probe_rollback';
  exception
    when insufficient_privilege then
      return false;
    when others then
      if sqlstate='P0001' and sqlerrm='day4_rls_probe_rollback' then
        return v_allowed;
      end if;
      return true;
  end;
end;
$$;

with identities(label,db_role,uid) as (
  values
    ('owner','authenticated','70000000-0000-0000-0000-000000000002'::uuid),
    ('leader','authenticated','70000000-0000-0000-0000-000000000001'::uuid),
    ('member','authenticated','70000000-0000-0000-0000-000000000004'::uuid),
    ('outsider','authenticated','70000000-0000-0000-0000-000000000005'::uuid),
    ('anon','anon',null::uuid),
    ('public','day4_public_probe',null::uuid)
),
tables(table_name) as (values ('reservations'),('files'),('versions'))
select is(
  pg_temp.day4_rls_probe(i.db_role,i.uid,'SELECT',t.table_name,:'file_id'::uuid,:'first_version_id'::uuid,:'size_reserve_id'::uuid),
  case when t.table_name='reservations' then i.label in ('owner','leader') else i.label in ('owner','leader','member') end,
  format('RLS SELECT %s on %s has exact behavior',i.label,t.table_name)
)
from identities i cross join tables t;

with identities(label,db_role,uid) as (
  values
    ('owner','authenticated','70000000-0000-0000-0000-000000000002'::uuid),
    ('leader','authenticated','70000000-0000-0000-0000-000000000001'::uuid),
    ('member','authenticated','70000000-0000-0000-0000-000000000004'::uuid),
    ('outsider','authenticated','70000000-0000-0000-0000-000000000005'::uuid),
    ('anon','anon',null::uuid),
    ('public','day4_public_probe',null::uuid)
),
tables(table_name) as (values ('reservations'),('files'),('versions')),
operations(operation) as (values ('INSERT'),('UPDATE'),('DELETE'))
select ok(
  not pg_temp.day4_rls_probe(i.db_role,i.uid,o.operation,t.table_name,:'file_id'::uuid,:'first_version_id'::uuid,:'size_reserve_id'::uuid),
  format('RLS %s denies %s on %s',i.label,o.operation,t.table_name)
)
from identities i cross join operations o cross join tables t;

revoke select, insert, update, delete on public.file_upload_reservations, public.task_files, public.task_file_versions from public;
drop role day4_public_probe;

-- NULL request ids are explicit domain failures, never raw SQLSTATE 22004.
select set_config('request.jwt.claim.sub','70000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select lives_ok(
  $$insert into file_results values('null-request-reserve',public.cmd_reserve_task_file_upload(
    '71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001',null,1,
    'new_file',null,'null-request.txt','text/plain',20))$$,
  'reserve NULL request id returns a domain result'
);
reset role;
select lives_ok(
  $$insert into file_results values('null-request-finalize',public.cmd_finalize_task_file_upload_service(
    '70000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000',null,1,
    'text/plain',20,repeat('a',64)))$$,
  'finalize NULL request id returns a domain result'
);
select lives_ok(
  $$insert into file_results values('null-request-reject',public.cmd_reject_task_file_upload_service(
    '70000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000',null,1,
    'FILE_VALIDATION_FAILED'))$$,
  'reject NULL request id returns a domain result'
);
select is((select result->>'code' from file_results where label='null-request-reserve'),'VALIDATION_FAILED','reserve NULL request id is a validation failure');
select is((select result->>'code' from file_results where label='null-request-finalize'),'VALIDATION_FAILED','finalize NULL request id is a validation failure');
select is((select result->>'code' from file_results where label='null-request-reject'),'VALIDATION_FAILED','reject NULL request id is a validation failure');

select * from finish();
rollback;
