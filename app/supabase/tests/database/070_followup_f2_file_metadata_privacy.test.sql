begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_view('public','task_files_visible','logical-file privacy view exists');
select has_view('public','task_file_versions_visible','file-version privacy view exists');
select has_view('public','file_upload_reservations_visible','upload reservation privacy view exists');
select ok(not has_column_privilege('authenticated','public.task_files','logical_name','SELECT'),'raw logical filename private');
select ok(not has_column_privilege('authenticated','public.task_file_versions','original_name','SELECT'),'raw uploaded filename private');
select ok(not has_column_privilege('authenticated','public.file_upload_reservations','original_name','SELECT'),'raw reserved filename private');
select ok(not has_column_privilege('authenticated','public.project_recovery_point_file_items','captured_original_name','SELECT'),'raw recovery filename private');
select ok(has_column_privilege('authenticated','public.task_file_versions','sha256_hex','SELECT'),'file hash remains readable for authorized member');
insert into auth.users(id,email) values
 ('f7c00000-0000-0000-0000-000000000001','f2-file-leader@example.test'),
 ('f7c00000-0000-0000-0000-000000000002','f2-file-subject@example.test'),
 ('f7c00000-0000-0000-0000-000000000003','f2-file-outsider@example.test'),
 ('f7c00000-0000-0000-0000-000000000004','f2-file-ordinary-member@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
 values('f7d00000-0000-0000-0000-000000000001','Privacy file project',
 now()+interval '7 days','f7c00000-0000-0000-0000-000000000001',
 'f7c00000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values
 ('f7d00000-0000-0000-0000-000000000001','f7c00000-0000-0000-0000-000000000001','leader','active',false),
 ('f7d00000-0000-0000-0000-000000000001','f7c00000-0000-0000-0000-000000000002','member','active',false),
 ('f7d00000-0000-0000-0000-000000000001','f7c00000-0000-0000-0000-000000000004','member','active',false);
insert into public.tasks(id,project_id,title,created_by,deadline_at)
 values('f7e00000-0000-0000-0000-000000000001',
 'f7d00000-0000-0000-0000-000000000001',
 'Historical team attachment','f7c00000-0000-0000-0000-000000000001',
 now()+interval '3 days');
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,expires_at)
 values('f7f00000-0000-0000-0000-000000000001',
 'f7d00000-0000-0000-0000-000000000001',
 'f7e00000-0000-0000-0000-000000000001',
 'f7c00000-0000-0000-0000-000000000002','new_file',
 'projects/f7d00000/privacy/file-1.pdf','Real Person Report.pdf','application/pdf',
 1024,now()+interval '10 hours');
insert into public.task_files(
 id,project_id,task_id,logical_name,created_by)
 values('f7f10000-0000-0000-0000-000000000001',
 'f7d00000-0000-0000-0000-000000000001',
 'f7e00000-0000-0000-0000-000000000001',
 'Real Person Report.pdf','f7c00000-0000-0000-0000-000000000002');
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,
 original_name,mime_type,size_bytes,sha256_hex,uploaded_by)
 values('f7f20000-0000-0000-0000-000000000001',
 'f7f10000-0000-0000-0000-000000000001',
 'f7d00000-0000-0000-0000-000000000001',
 'f7e00000-0000-0000-0000-000000000001',
 'f7f00000-0000-0000-0000-000000000001',1,
 'projects/f7d00000/privacy/file-1.pdf','Real Person Report.pdf',
 'application/pdf',1024,repeat('a',64),
 'f7c00000-0000-0000-0000-000000000002');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until)
 values('f7c00000-0000-0000-0000-000000000002','pending',1,1,
 now()-interval '1 day',now()+interval '29 days');

create temp table f2_file_read(logical_name text,original_name text,reservation_name text);
grant all on f2_file_read to authenticated;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f2_file_read select
 (select logical_name from public.task_files_visible where id='f7f10000-0000-0000-0000-000000000001'),
 (select original_name from public.task_file_versions_visible where id='f7f20000-0000-0000-0000-000000000001'),
 (select original_name from public.file_upload_reservations_visible where id='f7f00000-0000-0000-0000-000000000001');
reset role;
select is((select logical_name from f2_file_read),'已注销成员文件','logical shared file masked for deleting member');
select is((select original_name from f2_file_read),'已注销成员文件','version filename masked');
select is((select reservation_name from f2_file_read),'已注销成员文件','reserved filename masked');
select is((select sha256_hex from public.task_file_versions where id='f7f20000-0000-0000-0000-000000000001'),repeat('a',64),'underlying file hash unchanged');
truncate f2_file_read;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f2_file_read select logical_name,null,null from public.task_files_visible
 where project_id='f7d00000-0000-0000-0000-000000000001';
reset role;
select is((select count(*)::integer from f2_file_read),0,'outsider cannot enumerate file metadata');

truncate f2_file_read;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into f2_file_read select null,null,original_name from public.file_upload_reservations_visible
 where project_id='f7d00000-0000-0000-0000-000000000001';
reset role;
select is((select count(*)::integer from f2_file_read),0,
 'non-owning ordinary member cannot see reservation metadata');

-- Regression: the real Edge upload finalizer selects reserved private metadata
-- through the SAME authorized view with the uploader JWT.
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,expires_at)
 values('f7f00000-0000-0000-0000-000000000002',
 'f7d00000-0000-0000-0000-000000000001',
 'f7e00000-0000-0000-0000-000000000001',
 'f7c00000-0000-0000-0000-000000000004',
 'new_file','projects/f7d00000/privacy/active-upload.txt',
 'active-upload.txt','text/plain',64,now()+interval '1 hour');
create temp table f2_finalizer_reservation(
 id uuid, actor_id uuid,original_name text,object_path text,
 declared_mime_type text,declared_size_bytes bigint);
grant all on f2_finalizer_reservation to authenticated;
select set_config('request.jwt.claim.sub',
 'f7c00000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into f2_finalizer_reservation
 select id,actor_id,original_name,object_path,
   declared_mime_type,declared_size_bytes
 from public.file_upload_reservations_visible
 where id='f7f00000-0000-0000-0000-000000000002';
reset role;
select is((select original_name from f2_finalizer_reservation),
 'active-upload.txt','active uploader can finalize from privacy view');
select is((select declared_size_bytes from f2_finalizer_reservation),
 64::bigint,'privacy view provides the exact reserved file size');
select is((select count(*)::integer from f2_finalizer_reservation),
 1,'authenticated finalizer reservation lookup returns exactly one row');

select * from finish();
rollback;
