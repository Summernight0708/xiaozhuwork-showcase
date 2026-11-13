begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('f1000000-0000-0000-0000-000000000001','five-leader@example.test'),
 ('f1000000-0000-0000-0000-000000000002','five-primary@example.test'),
 ('f1000000-0000-0000-0000-000000000003','five-collaborator@example.test'),
 ('f1000000-0000-0000-0000-000000000004','five-observer@example.test'),
 ('f1000000-0000-0000-0000-000000000005','five-upstream@example.test');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values(
 'f2000000-0000-0000-0000-000000000001','Five feature integration',now()+interval '30 days',
 'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',
 1,'weighted','active'
);

insert into public.project_members(
 id,project_id,user_id,role,member_state,is_observer,version,departed_at,display_name_snapshot
) values
 ('f3000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','leader','active',false,1,null,'Leader'),
 ('f3000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','member','active',false,1,null,'Primary'),
 ('f3000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000003','member','active',false,1,null,'Collaborator'),
 ('f3000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000004','observer','active',true,1,null,'Observer'),
 ('f3000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','member','active',false,1,null,'Upstream');

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,
 assignment_state,first_submitted_at,completed_at,version,required_submission_file_type
) values
 ('f4000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','Formal upstream',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005',
  now()+interval '5 days','completed',3,now()-interval '3 days','assigned',now()-interval '2 days',now()-interval '1 day',1,'xlsx'),
 ('f4000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','Binding downstream',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002',
  now()+interval '8 days','in_progress',2,now()-interval '2 days','assigned',null,null,1,null),
 ('f4000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','Help task',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002',
  now()+interval '9 days','in_progress',2,now()-interval '2 days','assigned',null,null,1,null),
 ('f4000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','Rework upstream',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005',
  now()+interval '6 days','completed',2,now()-interval '3 days','assigned',now()-interval '2 days',now()-interval '1 day',1,null),
 ('f4000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','Rework downstream',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002',
  now()+interval '10 days','in_progress',2,now()-interval '2 days','assigned',null,null,1,null),
 ('f4000000-0000-0000-0000-000000000006','f2000000-0000-0000-0000-000000000001','Primary-only authority',
  'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002',
  now()+interval '11 days','in_progress',2,now()-interval '2 days','assigned',null,null,1,null);

insert into public.task_collaborators(
 id,project_id,task_id,user_id,user_name_snapshot,state,invited_by,
 invited_by_name_snapshot,responded_at,version
) values
 ('f3500000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003','Collaborator','accepted','f1000000-0000-0000-0000-000000000001','Leader',now(),1),
 ('f3500000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000003','f1000000-0000-0000-0000-000000000003','Collaborator','accepted','f1000000-0000-0000-0000-000000000001','Leader',now(),1),
 ('f3500000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000003','Collaborator','accepted','f1000000-0000-0000-0000-000000000001','Leader',now(),1),
 ('f3500000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000006','f1000000-0000-0000-0000-000000000003','Collaborator','accepted','f1000000-0000-0000-0000-000000000001','Leader',now(),1);

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by) values
 ('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000001'),
 ('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000004','f4000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000001');

-- Finalized upstream versions: data v1/v2, approved companion, rejected, changes-requested, legacy-approved.
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,object_path,
 original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('f5000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/data-v1.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2),
 ('f5000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/data-v2.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,'finalized',now()+interval '1 hour',2),
 ('f5000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/notes.pdf','notes.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('f5000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/rejected.pdf','rejected.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('f5000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/changes.pdf','changes.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2),
 ('f5000000-0000-0000-0000-000000000006','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','new_file',null,null,'five/legacy.pdf','legacy.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version) values
 ('f6000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','data.xlsx','f1000000-0000-0000-0000-000000000005',1),
 ('f6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','notes.pdf','f1000000-0000-0000-0000-000000000005',1),
 ('f6000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','rejected.pdf','f1000000-0000-0000-0000-000000000005',1),
 ('f6000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','changes.pdf','f1000000-0000-0000-0000-000000000005',1),
 ('f6000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','legacy.pdf','f1000000-0000-0000-0000-000000000005',1);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values
 ('f7000000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000001',1,'five/data-v1.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('a',64),'f1000000-0000-0000-0000-000000000005'),
 ('f7000000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000002',2,'five/data-v2.xlsx','data.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',100,repeat('b',64),'f1000000-0000-0000-0000-000000000005'),
 ('f7000000-0000-0000-0000-000000000003','f6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000003',1,'five/notes.pdf','notes.pdf','application/pdf',100,repeat('c',64),'f1000000-0000-0000-0000-000000000005'),
 ('f7000000-0000-0000-0000-000000000004','f6000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000004',1,'five/rejected.pdf','rejected.pdf','application/pdf',100,repeat('d',64),'f1000000-0000-0000-0000-000000000005'),
 ('f7000000-0000-0000-0000-000000000005','f6000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000005',1,'five/changes.pdf','changes.pdf','application/pdf',100,repeat('e',64),'f1000000-0000-0000-0000-000000000005'),
 ('f7000000-0000-0000-0000-000000000006','f6000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000006',1,'five/legacy.pdf','legacy.pdf','application/pdf',100,repeat('f',64),'f1000000-0000-0000-0000-000000000005');

update public.task_files set current_version_id='f7000000-0000-0000-0000-000000000002' where id='f6000000-0000-0000-0000-000000000001';
update public.task_files set current_version_id='f7000000-0000-0000-0000-000000000003' where id='f6000000-0000-0000-0000-000000000002';
update public.task_files set current_version_id='f7000000-0000-0000-0000-000000000004' where id='f6000000-0000-0000-0000-000000000003';
update public.task_files set current_version_id='f7000000-0000-0000-0000-000000000005' where id='f6000000-0000-0000-0000-000000000004';
update public.task_files set current_version_id='f7000000-0000-0000-0000-000000000006' where id='f6000000-0000-0000-0000-000000000005';

-- First approved multi-file round makes every selected attachment formal, not only position 1.
insert into public.task_review_rounds(
 id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,state,decision,
 reviewed_by,reviewed_at,rejection_reason,version,submission_text_snapshot,required_submission_file_type_snapshot
) values
 ('f8000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001',1,
  'f7000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','approved','approve',
  'f1000000-0000-0000-0000-000000000001',now()-interval '1 day',null,1,'approved bundle','xlsx'),
 ('f8000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001',2,
  'f7000000-0000-0000-0000-000000000004','f1000000-0000-0000-0000-000000000005','rejected','reject',
  'f1000000-0000-0000-0000-000000000001',now()-interval '1 day','rejected',1,'rejected bundle','xlsx'),
 ('f8000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001',3,
  'f7000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000005','rejected','request_changes',
  'f1000000-0000-0000-0000-000000000001',now()-interval '1 day','needs changes',1,'changes requested','xlsx'),
 ('f8000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001',4,
  'f7000000-0000-0000-0000-000000000006','f1000000-0000-0000-0000-000000000005','approved','approve',
  'f1000000-0000-0000-0000-000000000001',now()-interval '1 day',null,1,'legacy compatible','xlsx');

insert into public.task_review_round_files(review_round_id,project_id,task_id,file_version_id,position) values
 ('f8000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000001',1),
 ('f8000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000003',2),
 ('f8000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000004',1),
 ('f8000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000005',1),
 ('f8000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000006',1);

select ok(private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000001'),'approved position-1 file is formal');
select ok(private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000003'),'approved second attachment is also formal');
select ok(not private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000004'),'rejected round file is not formal');
select ok(not private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000005'),'request-changes round file is not formal');
select ok(private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000006'),'legacy-compatible approved position-1 binding remains formal');

-- Later required type changes never rewrite the historical requirement snapshot.
update public.tasks set required_submission_file_type='pdf' where id='f4000000-0000-0000-0000-000000000001';
select is(
 (select required_submission_file_type_snapshot from public.task_review_rounds where id='f8000000-0000-0000-0000-000000000001'),
 'xlsx','approved review retains its original required-file-type snapshot'
);

create temporary table five_results(label text primary key,result jsonb);
grant all on five_results to authenticated;

-- Accepted collaborator can request Task Help.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into five_results values('collaborator-help',public.cmd_create_task_help_request(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000003',
 'f9000000-0000-0000-0000-000000000001',1,'Collaborator needs help',null,false
));
insert into five_results values('collaborator-rework',public.cmd_request_upstream_rework(
 'f2000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000005','f4000000-0000-0000-0000-000000000004',
 'f9000000-0000-0000-0000-000000000002',1,1,'Collaborator asks for upstream revision'
));
insert into five_results values('collaborator-submit',public.cmd_submit_task_for_review(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000006',
 'collaborator must not be final submitter',array[]::uuid[],
 'f9000000-0000-0000-0000-000000000003',1
));
reset role;

select is((select result->>'ok' from five_results where label='collaborator-help'),'true','accepted collaborator can request Task Help');
select is((select result->>'ok' from five_results where label='collaborator-rework'),'true','accepted collaborator can request direct upstream rework');
select is((select result->>'code' from five_results where label='collaborator-submit'),'NOT_FOUND_OR_NOT_AUTHORIZED','accepted collaborator cannot final-submit');

-- Collaborator may not approve/reject the rework they requested.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into five_results values('collaborator-rework-review',public.cmd_review_upstream_rework(
 'f2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where downstream_task_id='f4000000-0000-0000-0000-000000000005'),
 'f9000000-0000-0000-0000-000000000004',1,'approve'
));
reset role;
select is((select result->>'code' from five_results where label='collaborator-rework-review'),'NOT_FOUND_OR_NOT_AUTHORIZED','accepted collaborator cannot decide upstream rework');

-- Existing Task Change Confirmation seat remains the primary, never an accepted collaborator.
insert into public.task_change_proposals(
 id,project_id,task_id,proposed_by,proposer_name_snapshot,state,
 old_deadline_at,new_deadline_at,old_weight,new_weight,base_task_version,
 required_confirmer_id,required_confirmer_name_snapshot,version
) select
 'f8500000-0000-0000-0000-000000000001',project_id,id,'f1000000-0000-0000-0000-000000000001','Leader','pending',
 deadline_at,deadline_at+interval '1 day',weight,weight,version,
 'f1000000-0000-0000-0000-000000000002','Primary',1
from public.tasks where id='f4000000-0000-0000-0000-000000000006';

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into five_results values('collaborator-change-confirm',public.cmd_respond_to_task_change(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000006',
 'f8500000-0000-0000-0000-000000000001','approve',null,
 'f9000000-0000-0000-0000-000000000005',1
));
reset role;
select is((select result->>'code' from five_results where label='collaborator-change-confirm'),'NOT_FOUND_OR_NOT_AUTHORIZED','accepted collaborator cannot occupy primary task-change confirmation seat');

-- Successful preview context may record light use; participant may strengthen it. Recording a newer formal version alone never switches.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into five_results values('collaborator-light-bind',public.cmd_record_task_artifact_use(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000006'
));
insert into five_results values('collaborator-strong-bind',public.cmd_set_task_artifact_binding_strength(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000001','strong',
 'f9000000-0000-0000-0000-000000000007',1
));
reset role;
select is((select result->>'ok' from five_results where label='collaborator-light-bind'),'true','accepted collaborator can create light binding');
select is((select result->>'ok' from five_results where label='collaborator-strong-bind'),'true','accepted collaborator can strengthen binding');

-- Leader is not implicitly a binding mutator when not a downstream participant.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into five_results values('leader-bind-rejected',public.cmd_record_task_artifact_use(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000008'
));
reset role;
select is((select result->>'code' from five_results where label='leader-bind-rejected'),'NOT_FOUND_OR_NOT_AUTHORIZED','leader without task participation cannot mutate artifact binding');

-- Observer mutations remain denied.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into five_results values('observer-bind-rejected',public.cmd_record_task_artifact_use(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000009'
));
reset role;
select is((select result->>'code' from five_results where label='observer-bind-rejected'),'NOT_AUTHORIZED','observer cannot mutate artifact binding');

-- A later approved multi-file round makes data v2 formal in second position and emits the normal approval event.
insert into public.task_review_rounds(
 id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,state,decision,
 reviewed_by,reviewed_at,rejection_reason,version,submission_text_snapshot,required_submission_file_type_snapshot
) values(
 'f8000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001',5,
 'f7000000-0000-0000-0000-000000000003','f1000000-0000-0000-0000-000000000005','approved','approve',
 'f1000000-0000-0000-0000-000000000001',now(),null,1,'new approved bundle','pdf'
);
insert into public.task_review_round_files(review_round_id,project_id,task_id,file_version_id,position) values
 ('f8000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000003',1),
 ('f8000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000002',2);

insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,event_data)
values(
 'f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',
 'task_submission_approved','task','f4000000-0000-0000-0000-000000000001',
 jsonb_build_object('taskId','f4000000-0000-0000-0000-000000000001')
);

select ok(private.is_formal_task_artifact_version('f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f7000000-0000-0000-0000-000000000002'),'second attachment in later approved review becomes formal');
select is(
 (select file_version_id::text from public.task_artifact_bindings where downstream_task_id='f4000000-0000-0000-0000-000000000002'),
 'f7000000-0000-0000-0000-000000000001','strong binding remains on v1 after newer formal v2 appears'
);
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000002'
    and notification_type='artifact_binding_update'
    and entity_type='task'
    and entity_id='f4000000-0000-0000-0000-000000000002'),
 1,'new approved second attachment emits one task-scoped strong-binding notification'
);

-- Re-emitting the same approval event cannot duplicate the notification.
insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,event_data)
values(
 'f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',
 'task_submission_approved','task','f4000000-0000-0000-0000-000000000001',
 jsonb_build_object('taskId','f4000000-0000-0000-0000-000000000001')
);
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000002'
    and notification_type='artifact_binding_update'
    and entity_id='f4000000-0000-0000-0000-000000000002'),
 1,'duplicate approval trigger path remains notification-idempotent'
);

-- Successful use of v2 still does not switch; explicit version switch does.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into five_results values('preview-newer-no-switch',public.cmd_record_task_artifact_use(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000002','f9000000-0000-0000-0000-000000000010'
));
insert into five_results values('explicit-switch',public.cmd_switch_task_artifact_binding_version(
 'f2000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000002',
 'f7000000-0000-0000-0000-000000000002','f9000000-0000-0000-0000-000000000011',2
));
reset role;
select is((select result #>> '{data,changed}' from five_results where label='preview-newer-no-switch'),'false','preview-success use of newer version never auto-switches existing binding');
select is((select result->>'ok' from five_results where label='explicit-switch'),'true','accepted collaborator can explicitly switch binding version');
select is(
 (select file_version_id::text from public.task_artifact_bindings where downstream_task_id='f4000000-0000-0000-0000-000000000002'),
 'f7000000-0000-0000-0000-000000000002','explicit switch is the only operation that changes bound version'
);

-- Three independent notification producers coexist and target task detail entities.
select ok(
 exists(select 1 from pg_trigger where tgname='business_event_creates_task_collaborator_notification' and not tgisinternal)
 and exists(select 1 from pg_trigger where tgname='business_event_notifies_task_help_rework' and not tgisinternal)
 and exists(select 1 from pg_trigger where tgname='artifact_binding_event_creates_notification' and not tgisinternal),
 'collaborator, help/rework, and artifact-binding notification triggers coexist'
);

select * from finish();
rollback;
