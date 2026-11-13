begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_review_round_files','review round file bindings exist');
select has_column('public','tasks','required_submission_file_type','task has optional required file type');
select has_column('public','tasks','required_submission_file_types','task stores the authoritative required type array');
select has_column('public','task_change_proposals','new_required_submission_file_types','proposal stores the new required type array');
select has_column('public','task_review_rounds','submission_text_snapshot','round stores text snapshot');
select has_column('public','task_review_rounds','required_submission_file_type_snapshot','round stores requirement snapshot');
select has_column('public','task_review_rounds','required_submission_file_types_snapshot','round snapshots the complete requirement array');
select ok(
  (select relrowsecurity from pg_class where oid='public.task_review_round_files'::regclass),
  'review round files enable RLS'
);
select ok(has_table_privilege('authenticated','public.task_review_round_files','SELECT'),'members can read round files through RLS');
select ok(not has_table_privilege('authenticated','public.task_review_round_files','INSERT'),'browser cannot bind review files');
select ok(not has_table_privilege('authenticated','public.task_review_round_files','UPDATE'),'browser cannot rewrite review files');
select ok(not has_table_privilege('authenticated','public.task_review_round_files','DELETE'),'browser cannot remove review files');
select has_function(
  'public','cmd_submit_task_for_review',
  array['uuid','uuid','text','uuid[]','uuid','integer'],
  'unified submit RPC exists'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='cmd_submit_task_for_review'
     and pg_get_function_identity_arguments(p.oid)='p_project_id uuid, p_task_id uuid, p_submission_text text, p_file_version_ids uuid[], p_request_id uuid, p_expected_version integer'),
  'submit RPC is SECURITY DEFINER with empty search_path'
);
select ok(
  not has_function_privilege('public','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),
  'PUBLIC cannot submit review'
);
select ok(
  not has_function_privilege('anon','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),
  'anon cannot submit review'
);
select ok(
  has_function_privilege('authenticated','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),
  'authenticated can submit review'
);
select ok(
  not has_function_privilege('service_role','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),
  'service role cannot impersonate submit RPC'
);

insert into auth.users(id,email) values
 ('d1000000-0000-0000-0000-000000000001','unified-leader@example.test'),
 ('d1000000-0000-0000-0000-000000000002','unified-creator@example.test'),
 ('d1000000-0000-0000-0000-000000000003','unified-assignee@example.test'),
 ('d1000000-0000-0000-0000-000000000004','unified-outsider@example.test'),
 ('d1000000-0000-0000-0000-000000000005','unified-collaborator@example.test');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values(
 'd2000000-0000-0000-0000-000000000001','Unified submissions',now()+interval '30 days',
 'd1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',
 1,'weighted','active'
);

insert into public.project_members(
 id,project_id,user_id,role,member_state,is_observer,version,departed_at,display_name_snapshot
) values
 ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','leader','active',false,1,null,'Leader'),
 ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002','member','active',false,1,null,'Creator'),
 ('d3000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000003','member','active',false,1,null,'Assignee'),
 ('d3000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000005','member','active',false,1,null,'Collaborator');

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
 accepted_at,assignment_state,version,required_submission_file_type
) values
 ('d4000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','Text only','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,null),
 ('d4000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','Multi file','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,null),
 ('d4000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','Needs PPTX','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,'pptx'),
 ('d4000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','Empty rejected','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,null),
 ('d4000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','Injection target','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,null),
 ('d4000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000001','Unfinalized target','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now(),'assigned',1,null);

insert into public.task_collaborators(
 id,project_id,task_id,user_id,user_name_snapshot,state,invited_by,
 invited_by_name_snapshot,responded_at,version
) values(
 'd3500000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001',
 'd4000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000005',
 'Collaborator','accepted','d1000000-0000-0000-0000-000000000002','Creator',now(),1
);

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('d5000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000005','new_file','pending/d2/d5/one.xlsx','one.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2),
 ('d5000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/two.pdf','two.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('d5000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/slides.pptx','slides.pptx','application/vnd.openxmlformats-officedocument.presentationml.presentation',100,'finalized',now()+interval '1 hour',2),
 ('d5000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/data.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2),
 ('d5000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/other.pdf','other.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('d5000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000006','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/draft.pdf','draft.pdf','application/pdf',100,'reserved',now()+interval '1 hour',1),
 ('d5000000-0000-0000-0000-000000000007','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','d1000000-0000-0000-0000-000000000003','new_file','pending/d2/d5/other.xlsx','other.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version) values
 ('d6000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','one.xlsx','d1000000-0000-0000-0000-000000000005',1),
 ('d6000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','two.pdf','d1000000-0000-0000-0000-000000000003',1),
 ('d6000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','slides.pptx','d1000000-0000-0000-0000-000000000003',1),
 ('d6000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','data.xlsx','d1000000-0000-0000-0000-000000000003',1),
 ('d6000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','other.pdf','d1000000-0000-0000-0000-000000000003',1),
 ('d6000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000006','draft.pdf','d1000000-0000-0000-0000-000000000003',1),
 ('d6000000-0000-0000-0000-000000000007','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','other.xlsx','d1000000-0000-0000-0000-000000000003',1);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,
 original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values
 ('d7000000-0000-0000-0000-000000000001','d6000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','d5000000-0000-0000-0000-000000000001',1,'pending/d2/d5/one.xlsx','one.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('a',64),'d1000000-0000-0000-0000-000000000005'),
 ('d7000000-0000-0000-0000-000000000002','d6000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002','d5000000-0000-0000-0000-000000000002',1,'pending/d2/d5/two.pdf','two.pdf','application/pdf',100,repeat('b',64),'d1000000-0000-0000-0000-000000000003'),
 ('d7000000-0000-0000-0000-000000000003','d6000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','d5000000-0000-0000-0000-000000000003',1,'pending/d2/d5/slides.pptx','slides.pptx','application/vnd.openxmlformats-officedocument.presentationml.presentation',100,repeat('c',64),'d1000000-0000-0000-0000-000000000003'),
 ('d7000000-0000-0000-0000-000000000004','d6000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003','d5000000-0000-0000-0000-000000000004',1,'pending/d2/d5/data.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('d',64),'d1000000-0000-0000-0000-000000000003'),
 ('d7000000-0000-0000-0000-000000000005','d6000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','d5000000-0000-0000-0000-000000000005',1,'pending/d2/d5/other.pdf','other.pdf','application/pdf',100,repeat('e',64),'d1000000-0000-0000-0000-000000000003'),
 ('d7000000-0000-0000-0000-000000000006','d6000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000006','d5000000-0000-0000-0000-000000000006',1,'pending/d2/d5/draft.pdf','draft.pdf','application/pdf',100,repeat('f',64),'d1000000-0000-0000-0000-000000000003'),
 ('d7000000-0000-0000-0000-000000000007','d6000000-0000-0000-0000-000000000007','d2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005','d5000000-0000-0000-0000-000000000007',1,'pending/d2/d5/other.xlsx','other.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('7',64),'d1000000-0000-0000-0000-000000000003');

update public.task_files f
set current_version_id=v.id
from public.task_file_versions v
where v.file_id=f.id;

create temporary table unified_results(label text primary key,result jsonb);
grant all on unified_results to authenticated;

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);
set local role authenticated;

insert into unified_results values('text-only',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 '  Finished in text only.  ',array[]::uuid[],
 'd8000000-0000-0000-0000-000000000001',1
));

insert into unified_results values('multi-file',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 'Combined deliverables',
 array['d7000000-0000-0000-0000-000000000001','d7000000-0000-0000-0000-000000000002']::uuid[],
 'd8000000-0000-0000-0000-000000000002',1
));
insert into unified_results values('multi-file-replay',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 'Combined deliverables',
 array['d7000000-0000-0000-0000-000000000001','d7000000-0000-0000-0000-000000000002']::uuid[],
 'd8000000-0000-0000-0000-000000000002',1
));
insert into unified_results values('multi-file-reuse',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 'Changed text',
 array['d7000000-0000-0000-0000-000000000001','d7000000-0000-0000-0000-000000000002']::uuid[],
 'd8000000-0000-0000-0000-000000000002',1
));

insert into unified_results values('required-missing',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 null,array['d7000000-0000-0000-0000-000000000004']::uuid[],
 'd8000000-0000-0000-0000-000000000003',1
));
insert into unified_results values('required-success',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 'Slides plus workbook',
 array['d7000000-0000-0000-0000-000000000003','d7000000-0000-0000-0000-000000000004']::uuid[],
 'd8000000-0000-0000-0000-000000000004',1
));

insert into unified_results values('empty',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000004',
 '   ',array[]::uuid[],
 'd8000000-0000-0000-0000-000000000005',1
));

insert into unified_results values('cross-task',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005',
 null,array['d7000000-0000-0000-0000-000000000001']::uuid[],
 'd8000000-0000-0000-0000-000000000006',1
));
insert into unified_results values('unfinalized',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000006',
 null,array['d7000000-0000-0000-0000-000000000006']::uuid[],
 'd8000000-0000-0000-0000-000000000007',1
));
insert into unified_results values('duplicate',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005',
 null,array['d7000000-0000-0000-0000-000000000005','d7000000-0000-0000-0000-000000000005']::uuid[],
 'd8000000-0000-0000-0000-000000000008',1
));
reset role;

-- Multi-format OR semantics: XLSX alone is rejected, while one matching PDF is sufficient.
update public.tasks
set required_submission_file_types=array['pdf','pptx']::text[]
where id='d4000000-0000-0000-0000-000000000005';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into unified_results values('required-array-nonmatching',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005',
 null,array['d7000000-0000-0000-0000-000000000007']::uuid[],
 'd8000000-0000-0000-0000-000000000013',1
));
insert into unified_results values('required-array-success',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000005',
 null,array['d7000000-0000-0000-0000-000000000005']::uuid[],
 'd8000000-0000-0000-0000-000000000014',1
));
reset role;

-- Exercise the actual v2 create/edit RPCs in a fresh project below the active-task quota.
insert into public.projects(
 id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values(
 'd2000000-0000-0000-0000-000000000002','Array RPC contract',
 now()+interval '30 days','d1000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000001',1,'weighted','active'
);
insert into public.project_members(
 id,project_id,user_id,role,member_state,is_observer,version,departed_at,display_name_snapshot
) values(
 'd3000000-0000-0000-0000-000000000005',
 'd2000000-0000-0000-0000-000000000002',
 'd1000000-0000-0000-0000-000000000001',
 'leader','active',false,1,null,'Leader'
);

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into unified_results values('create-array-task',public.cmd_create_task_v2(
 'd2000000-0000-0000-0000-000000000002','d8000000-0000-0000-0000-000000000015',
 (select version from public.projects where id='d2000000-0000-0000-0000-000000000002'),
 'Array contract task',null,now()+interval '5 days',2::smallint,'claimable',null,
 array['pdf','doc']::text[],true
));
select is((select required_submission_file_types from public.tasks where id=((select result->'data'->>'taskId' from unified_results where label='create-array-task'))::uuid),array['pdf','doc']::text[],'v2 task creation stores the canonical required type array');
insert into unified_results values('edit-array-task',public.cmd_edit_task_v2(
 'd2000000-0000-0000-0000-000000000002',
 ((select result->'data'->>'taskId' from unified_results where label='create-array-task'))::uuid,
 'd8000000-0000-0000-0000-000000000016',1,
 'Array contract task',null,
 (select deadline_at from public.tasks where id=((select result->'data'->>'taskId' from unified_results where label='create-array-task'))::uuid),
 2::smallint,array['doc','docx']::text[]
));
reset role;

select is((select result->>'code' from unified_results where label='required-array-nonmatching'),'VALIDATION_FAILED','multi-format requirements reject files matching none of the allowed types');
select is((select result->'details'->>'reason' from unified_results where label='required-array-nonmatching'),'required_file_type_missing','non-matching multi-format failure is structured');
select is((select result->>'ok' from unified_results where label='required-array-success'),'true','one matching file satisfies a multi-format requirement');
select is((select required_submission_file_types from public.tasks where id='d4000000-0000-0000-0000-000000000005'),array['pdf','pptx']::text[],'task keeps its canonical required type array');
select is((select required_submission_file_types_snapshot from public.task_review_rounds where task_id='d4000000-0000-0000-0000-000000000005'),array['pdf','pptx']::text[],'review round snapshots every allowed type');
select is((select result->>'ok' from unified_results where label='create-array-task'),'true','v2 task creation accepts the required type array');
select is((select required_submission_file_types from public.tasks where id=((select result->'data'->>'taskId' from unified_results where label='create-array-task'))::uuid),array['doc','docx']::text[],'v2 task edit updates array even when scalar projection changes');
select is((select result->>'ok' from unified_results where label='edit-array-task'),'true','v2 task edit accepts the required type array');
select is((select required_submission_file_types from public.tasks where id=((select result->'data'->>'taskId' from unified_results where label='create-array-task'))::uuid),array['doc','docx']::text[],'v2 task edit updates array even when scalar projection changes');

select is((select result->>'ok' from unified_results where label='text-only'),'true','text-only submission succeeds');
select is((select submission_text_snapshot from public.task_review_rounds where task_id='d4000000-0000-0000-0000-000000000001'),'Finished in text only.','text is normalized and snapshotted');
select is((select submitted_file_version_id from public.task_review_rounds where task_id='d4000000-0000-0000-0000-000000000001'),null::uuid,'text-only round has no legacy file');
select is((select count(*)::integer from public.task_review_round_files where task_id='d4000000-0000-0000-0000-000000000001'),0,'text-only round has zero files');

select is((select result->>'ok' from unified_results where label='multi-file'),'true','text plus multi-file submission succeeds');
select is((select result->>'replayed' from unified_results where label='multi-file-replay'),'true','identical submission replays');
select is((select result->>'code' from unified_results where label='multi-file-reuse'),'IDEMPOTENCY_KEY_REUSED','changed payload cannot reuse request id');
select is((select count(*)::integer from public.task_review_round_files where task_id='d4000000-0000-0000-0000-000000000002'),2,'one round binds both selected file versions');
select is((select count(*)::integer from public.business_events where request_id='d8000000-0000-0000-0000-000000000002'),1,'replay emits one submit event');
select is((select submitted_file_version_id from public.task_review_rounds where task_id='d4000000-0000-0000-0000-000000000002'),'d7000000-0000-0000-0000-000000000001'::uuid,'legacy mirror points at first selected file');
select is((select uploaded_by from public.task_file_versions where id='d7000000-0000-0000-0000-000000000001'),'d1000000-0000-0000-0000-000000000005'::uuid,'selected finalized file was uploaded by accepted collaborator');
select ok(
  exists(
    select 1 from public.task_review_round_files rf
    where rf.task_id='d4000000-0000-0000-0000-000000000002'
      and rf.file_version_id='d7000000-0000-0000-0000-000000000001'
  ),
  'primary unified submission accepts collaborator-uploaded finalized file'
);

select is((select result->>'code' from unified_results where label='required-missing'),'VALIDATION_FAILED','required type rejects submission without matching file');
select is((select result->'details'->>'reason' from unified_results where label='required-missing'),'required_file_type_missing','required-type failure is structured');
select is((select result->>'ok' from unified_results where label='required-success'),'true','required type accepts matching PPTX plus other files');
select is((select required_submission_file_type_snapshot from public.task_review_rounds where task_id='d4000000-0000-0000-0000-000000000003'),'pptx','round snapshots required type');

select is((select result->>'code' from unified_results where label='empty'),'VALIDATION_FAILED','empty submission rejected');
select is((select result->'details'->>'reason' from unified_results where label='empty'),'empty_submission','empty submission has stable reason');
select is((select result->>'code' from unified_results where label='cross-task'),'NOT_FOUND_OR_NOT_AUTHORIZED','cross-task file injection rejected');
select is((select result->>'code' from unified_results where label='unfinalized'),'NOT_FOUND_OR_NOT_AUTHORIZED','unfinalized file version rejected');
select is((select result->'details'->>'reason' from unified_results where label='duplicate'),'duplicate_file_version','duplicate file id rejected');

select throws_ok(
  $$update public.task_review_rounds
    set submission_text_snapshot='mutated'
    where task_id='d4000000-0000-0000-0000-000000000002'$$,
  '55000',null,'submission text snapshot is immutable'
);
select throws_ok(
  $$delete from public.task_review_round_files
    where task_id='d4000000-0000-0000-0000-000000000002'
    and position=1$$,
  '55000',null,'round-file binding is immutable'
);

-- Return the required-PPTX task to in-progress, then prove requirement changes need confirmation.
select id::text as required_round_id
from public.task_review_rounds
where task_id='d4000000-0000-0000-0000-000000000003' \gset

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into unified_results values('reject-required',public.cmd_review_task_submission(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 :'required_round_id','request_changes','Use PDF instead',
 'd8000000-0000-0000-0000-000000000009',1
));
insert into unified_results values('silent-requirement-change',public.cmd_edit_task(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 'd8000000-0000-0000-0000-000000000010',
 (select version from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 'Needs PPTX',null,
 (select deadline_at from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 2::smallint,'pdf'
));
insert into unified_results values('propose-requirement-change',public.cmd_propose_task_change_v2(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 (select deadline_at from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 2::smallint,'d8000000-0000-0000-0000-000000000011',
 (select version from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 array['pdf','docx']::text[]
));
reset role;

select is((select result->>'code' from unified_results where label='silent-requirement-change'),'CONFIRMATION_REQUIRED','post-submission required type cannot change silently');
select is((select result->>'ok' from unified_results where label='propose-requirement-change'),'true','required type change enters existing confirmation flow');
select is((select old_required_submission_file_type from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003'),'pptx','proposal scalar snapshots old required type');
select is((select new_required_submission_file_type from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003'),'pdf','proposal scalar projects the first new required type');
select is((select old_required_submission_file_types from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003'),array['pptx']::text[],'proposal snapshots old required type array');
select is((select new_required_submission_file_types from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003'),array['pdf','docx']::text[],'proposal snapshots every new required type');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into unified_results values('approve-requirement-change',public.cmd_respond_to_task_change(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 (select id from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003'),
 'approve',null,'d8000000-0000-0000-0000-000000000012',1
));
reset role;

select is((select result->>'ok' from unified_results where label='approve-requirement-change'),'true','assignee approves required type change');
select is((select required_submission_file_type from public.tasks where id='d4000000-0000-0000-0000-000000000003'),'pdf','approved proposal keeps scalar compatibility projection');
select is((select required_submission_file_types from public.tasks where id='d4000000-0000-0000-0000-000000000003'),array['pdf','docx']::text[],'approved proposal applies the complete required type array');
select is((select required_submission_file_type_snapshot from public.task_review_rounds where id=:'required_round_id'::uuid),'pptx','historical round keeps old scalar snapshot');
select is((select required_submission_file_types_snapshot from public.task_review_rounds where id=:'required_round_id'::uuid),array['pptx']::text[],'historical round keeps old required type array snapshot');

-- A multi-format change that preserves the first/scalar type still requires confirmation.
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into unified_results values('same-first-direct-edit',public.cmd_edit_task_v2(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 'd8000000-0000-0000-0000-000000000017',
 (select version from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select title from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select description from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select deadline_at from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select weight from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 array['pdf','docx','xlsx']::text[]
));
insert into unified_results values('same-first-proposal',public.cmd_propose_task_change_v2(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 (select deadline_at from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select weight from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 'd8000000-0000-0000-0000-000000000018',
 (select version from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 array['pdf','docx','xlsx']::text[]
));
reset role;

select is((select result->>'code' from unified_results where label='same-first-direct-edit'),'CONFIRMATION_REQUIRED','direct edit cannot bypass confirmation when the scalar projection is unchanged');
select is((select result->>'ok' from unified_results where label='same-first-proposal'),'true','array-only requirement change enters the confirmation flow');
select is((select new_required_submission_file_types from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003' and state='pending'),array['pdf','docx','xlsx']::text[],'proposal preserves an array-only change with the same scalar projection');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into unified_results values('approve-same-first-proposal',public.cmd_respond_to_task_change(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 (select id from public.task_change_proposals where task_id='d4000000-0000-0000-0000-000000000003' and state='pending'),
 'approve',null,'d8000000-0000-0000-0000-000000000019',1
));
reset role;
select is((select result->>'ok' from unified_results where label='approve-same-first-proposal'),'true','approval applies an array-only requirement change');
select is((select required_submission_file_type from public.tasks where id='d4000000-0000-0000-0000-000000000003'),'pdf','array-only approval keeps scalar compatibility projection');
select is((select required_submission_file_types from public.tasks where id='d4000000-0000-0000-0000-000000000003'),array['pdf','docx','xlsx']::text[],'array-only approval updates the authoritative array');

-- Retrying an identical array request after the task state changes must replay
-- the original result rather than changing the legacy scalar payload hash.
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into unified_results values('same-first-proposal-replay',public.cmd_propose_task_change_v2(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 (select deadline_at from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 (select weight from public.tasks where id='d4000000-0000-0000-0000-000000000003'),
 'd8000000-0000-0000-0000-000000000018',
 (select base_task_version from public.task_change_proposals
  where id=((select result->'data'->>'proposalId' from unified_results where label='same-first-proposal'))::uuid),
 array['pdf','docx','xlsx']::text[]
));
reset role;
select is((select result->>'ok' from unified_results where label='same-first-proposal-replay'),'true','same-array retry returns the original proposal result');
select is((select result->>'replayed' from unified_results where label='same-first-proposal-replay'),'true','same-array retry remains idempotent after approval changes task state');

select * from finish();
rollback;
