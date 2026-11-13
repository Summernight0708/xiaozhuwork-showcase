begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_function('private','f2_mask_file_payload',array['jsonb'],'F2 guards server-serialized file history');
select ok(not has_function_privilege('authenticated','public.get_task_files_f2_unmasked(uuid)','EXECUTE'),'cannot bypass file list mask');
select ok(not has_function_privilege('authenticated','public.get_task_file_history_f2_unmasked(uuid,integer,integer)','EXECUTE'),'cannot bypass file history mask');
select ok(not has_function_privilege('authenticated','public.get_upstream_artifacts_f2_unmasked(uuid)','EXECUTE'),'cannot bypass upstream artifacts mask');
select ok(has_function_privilege('authenticated','public.get_task_files(uuid)','EXECUTE'),'authorized file list remains callable');
select ok(has_function_privilege('authenticated','public.get_task_file_history(uuid,integer,integer)','EXECUTE'),'authorized history remains callable');
select ok(has_function_privilege('authenticated','public.get_upstream_artifacts(uuid)','EXECUTE'),'authorized upstream list remains callable');
insert into auth.users(id,email) values
 ('f8100000-0000-0000-0000-000000000001','f2-legacy-file-uploader@example.test'),
 ('f8100000-0000-0000-0000-000000000002','f2-legacy-file-leader@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
 values('f8200000-0000-0000-0000-000000000001','F2 JSON file history',
 now()+interval '10 days','f8100000-0000-0000-0000-000000000002',
 'f8100000-0000-0000-0000-000000000002');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values
 ('f8200000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000002','leader','active',false),
 ('f8200000-0000-0000-0000-000000000001','f8100000-0000-0000-0000-000000000001','member','active',false);
insert into public.tasks(id,project_id,title,created_by,deadline_at)
 values('f8300000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
 'F2 JSON task','f8100000-0000-0000-0000-000000000002',now()+interval '7 days');
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,expires_at)
 values('f8400000-0000-0000-0000-000000000001',
 'f8200000-0000-0000-0000-000000000001','f8300000-0000-0000-0000-000000000001',
 'f8100000-0000-0000-0000-000000000001','new_file',
 'projects/f2/json-file.pdf','Sensitive Original.pdf','application/pdf',512,now()+interval '1 hour');
insert into public.task_files(id,project_id,task_id,logical_name,created_by)
 values('f8500000-0000-0000-0000-000000000001','f8200000-0000-0000-0000-000000000001',
 'f8300000-0000-0000-0000-000000000001','Sensitive Logical.pdf',
 'f8100000-0000-0000-0000-000000000001');
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,
 original_name,mime_type,size_bytes,sha256_hex,uploaded_by)
 values('f8600000-0000-0000-0000-000000000001',
 'f8500000-0000-0000-0000-000000000001',
 'f8200000-0000-0000-0000-000000000001',
 'f8300000-0000-0000-0000-000000000001',
 'f8400000-0000-0000-0000-000000000001',1,
 'projects/f2/json-file.pdf','Sensitive Original.pdf',
 'application/pdf',512,repeat('a',64),
 'f8100000-0000-0000-0000-000000000001');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until)
 values('f8100000-0000-0000-0000-000000000001','pending',1,1,
 now()-interval '1 day',now()+interval '29 days');

create temp table f2_json_result(payload jsonb);
grant all on f2_json_result to authenticated;
select set_config('request.jwt.claim.sub','f8100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into f2_json_result
  select public.get_task_files('f8300000-0000-0000-0000-000000000001');
reset role;
select is((select payload#>>'{data,files,0,logicalName}' from f2_json_result),
 '已注销成员文件','authorized file list masks logical name');
select is((select payload#>>'{data,files,0,versions,0,originalName}' from f2_json_result),
 '已注销成员文件','authorized file list masks version original name');
select is((select payload#>'{data,files,0,versions,0,uploadedBy}' from f2_json_result),
 'null'::jsonb,'authorized list removes deleted member uploader UUID');
select is((select payload#>>'{data,files,0,versions,0,sha256Hex}' from f2_json_result),
 repeat('a',64),'signed file content hash retained');
truncate f2_json_result;
select set_config('request.jwt.claim.sub','f8100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into f2_json_result
  select public.get_task_file_history('f8500000-0000-0000-0000-000000000001',10,null);
reset role;
select is((select payload#>>'{data,versions,0,originalName}' from f2_json_result),
 '已注销成员文件','authorized file history masks original filename');
select * from finish();
rollback;
