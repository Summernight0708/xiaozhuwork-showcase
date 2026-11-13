begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
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

insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,grant_source)
 values('f7c00000-0000-0000-0000-000000000001','pro','active',now()-interval '1 day',now()+interval '30 days','test');
create temp table f2_compare_seen(label text,result jsonb);
grant all on f2_compare_seen to authenticated;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f2_compare_seen values('masked',public.cmd_compare_task_file_versions(
 'f7d00000-0000-0000-0000-000000000001','f7f20000-0000-0000-0000-000000000001',
 'f7f20000-0000-0000-0000-000000000001','f7f30000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'ok' from f2_compare_seen where label='masked'),'true','authorized Pro comparison still works');
select ok((select result::text not like '%Real Person Report.pdf%' from f2_compare_seen where label='masked'),'comparison including nested diff hides original name');
select is((select result#>'{data,metadataComparison,diff,uploadedBy,base}' from f2_compare_seen where label='masked'),'null'::jsonb,'comparison diff masks retired uploader');
select is((select result#>>'{data,base,sha256Hex}' from f2_compare_seen where label='masked'),repeat('a',64),'comparison hash preserved');

create temp table f2_provenance_seen(
  creator uuid, uploader uuid, reserver uuid,
  file_name text, version_name text, reserve_name text
);
grant insert,select on f2_provenance_seen to authenticated;
select ok(not has_column_privilege('authenticated','public.task_files','created_by','SELECT'),
 'raw file-creator UUID not directly readable');
select ok(not has_column_privilege('authenticated','public.task_file_versions','uploaded_by','SELECT'),
 'raw file-uploader UUID not directly readable');
select ok(not has_column_privilege('authenticated','public.file_upload_reservations','actor_id','SELECT'),
 'raw upload-reserver UUID not directly readable');
select ok(not has_column_privilege('authenticated','public.project_recovery_point_file_items','captured_uploaded_by','SELECT'),
 'recovery-point raw uploader UUID not directly readable');
select ok(has_column_privilege('authenticated','public.task_file_versions','sha256_hex','SELECT'),
 'file checksum remains available');
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f2_provenance_seen select
 (select created_by from public.task_files_visible where id='f7f10000-0000-0000-0000-000000000001'),
 (select uploaded_by from public.task_file_versions_visible where id='f7f20000-0000-0000-0000-000000000001'),
 (select actor_id from public.file_upload_reservations_visible where id='f7f00000-0000-0000-0000-000000000001'),
 (select logical_name from public.task_files_visible where id='f7f10000-0000-0000-0000-000000000001'),
 (select original_name from public.task_file_versions_visible where id='f7f20000-0000-0000-0000-000000000001'),
 (select original_name from public.file_upload_reservations_visible where id='f7f00000-0000-0000-0000-000000000001');
reset role;
select is((select creator from f2_provenance_seen),null::uuid,'masked file creator UUID');
select is((select uploader from f2_provenance_seen),null::uuid,'masked version uploader UUID');
select is((select reserver from f2_provenance_seen),null::uuid,'masked reserved uploader UUID');
select is((select file_name from f2_provenance_seen),'已注销成员文件','masked file logical name');
select is((select version_name from f2_provenance_seen),'已注销成员文件','masked version name');
select is((select reserve_name from f2_provenance_seen),'已注销成员文件','masked reservation name');

-- A canceled request must immediately regain normal file metadata.
update public.account_lifecycle_requests set state='canceled',
 canceled_at=now(),version=version+1
 where user_id='f7c00000-0000-0000-0000-000000000002';
truncate f2_provenance_seen;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f2_provenance_seen select
 (select created_by from public.task_files_visible where id='f7f10000-0000-0000-0000-000000000001'),
 (select uploaded_by from public.task_file_versions_visible where id='f7f20000-0000-0000-0000-000000000001'),
 (select actor_id from public.file_upload_reservations_visible where id='f7f00000-0000-0000-0000-000000000001'),
 (select logical_name from public.task_files_visible where id='f7f10000-0000-0000-0000-000000000001'),
 (select original_name from public.task_file_versions_visible where id='f7f20000-0000-0000-0000-000000000001'),
 (select original_name from public.file_upload_reservations_visible where id='f7f00000-0000-0000-0000-000000000001');
reset role;
select is((select creator from f2_provenance_seen),
 'f7c00000-0000-0000-0000-000000000002'::uuid,'canceled creator ID visible');
select is((select uploader from f2_provenance_seen),
 'f7c00000-0000-0000-0000-000000000002'::uuid,'canceled uploader ID visible');
select is((select reserver from f2_provenance_seen),
 'f7c00000-0000-0000-0000-000000000002'::uuid,'canceled reservation ID visible');
select is((select file_name from f2_provenance_seen),
 'Real Person Report.pdf','canceled file name restored');
select is((select version_name from f2_provenance_seen),
 'Real Person Report.pdf','canceled version name restored');
select is((select reserve_name from f2_provenance_seen),
 'Real Person Report.pdf','canceled reservation name restored');

-- Existing active uploader can still fetch all exact Edge finalize fields.
set local role authenticated;
insert into f2_compare_seen values('canceled-replay',public.cmd_compare_task_file_versions(
 'f7d00000-0000-0000-0000-000000000001','f7f20000-0000-0000-0000-000000000001',
 'f7f20000-0000-0000-0000-000000000001','f7f30000-0000-0000-0000-000000000001'));
reset role;
select is((select result#>>'{data,base,originalName}' from f2_compare_seen where label='canceled-replay'),'Real Person Report.pdf','cancellation restores metadata even on same-key replay');
update public.account_lifecycle_requests set state='pending',canceled_at=null where user_id='f7c00000-0000-0000-0000-000000000002';
set local role authenticated;
insert into f2_compare_seen values('pending-replay',public.cmd_compare_task_file_versions(
 'f7d00000-0000-0000-0000-000000000001','f7f20000-0000-0000-0000-000000000001',
 'f7f20000-0000-0000-0000-000000000001','f7f30000-0000-0000-0000-000000000001'));
reset role;
select is((select result->>'replayed' from f2_compare_seen where label='pending-replay'),'true','comparison replay contract preserved');
select ok((select result::text not like '%Real Person Report.pdf%' from f2_compare_seen where label='pending-replay'),'preexisting cached response cannot bypass current privacy state');

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,expires_at
) values('f7f00000-0000-0000-0000-000000000004',
 'f7d00000-0000-0000-0000-000000000001',
 'f7e00000-0000-0000-0000-000000000001',
 'f7c00000-0000-0000-0000-000000000004',
 'new_file','projects/privacy/active.txt','active.txt','text/plain',42,
 now()+interval '1 hour');
create temp table f2_active_uploader(actor uuid,filename text,bytes bigint);
grant insert,select on f2_active_uploader to authenticated;
select set_config('request.jwt.claim.sub','f7c00000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into f2_active_uploader
 select actor_id,original_name,declared_size_bytes
 from public.file_upload_reservations_visible
 where id='f7f00000-0000-0000-0000-000000000004';
reset role;
select is((select actor from f2_active_uploader),
 'f7c00000-0000-0000-0000-000000000004'::uuid,
 'ordinary uploader actor identity preserved for Edge finalize');
select is((select filename from f2_active_uploader),
 'active.txt','ordinary uploader original filename preserved');
select is((select bytes from f2_active_uploader),42::bigint,
 'ordinary uploader expected bytes preserved');
select * from finish();
rollback;
