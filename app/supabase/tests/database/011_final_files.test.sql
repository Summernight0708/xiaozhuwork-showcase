begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_file_final_designations','version-level final-file designation table exists');
select has_function(
  'public','cmd_set_task_file_version_final',
  array['uuid','uuid','uuid','integer','boolean'],
  'controlled final-file RPC exists'
);
select ok(not has_table_privilege('authenticated','public.task_file_final_designations','INSERT'),'browser cannot directly mark final files');
select ok(has_table_privilege('authenticated','public.task_file_final_designations','SELECT'),'authorized users can read final-file facts');

insert into auth.users(id,email) values
 ('c1100000-0000-0000-0000-000000000001','final-leader@example.test'),
 ('c1100000-0000-0000-0000-000000000002','final-member@example.test'),
 ('c1100000-0000-0000-0000-000000000003','final-admin@example.test'),
 ('c1100000-0000-0000-0000-000000000004','final-observer@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values(
 'c2100000-0000-0000-0000-000000000001','Final files',now()+interval '20 days',
 'c1100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('c3100000-0000-0000-0000-000000000001','c2100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001','leader','active',false,1),
 ('c3100000-0000-0000-0000-000000000002','c2100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000002','member','active',false,1),
 ('c3100000-0000-0000-0000-000000000003','c2100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000003','admin','active',false,1),
 ('c3100000-0000-0000-0000-000000000004','c2100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000004','observer','active',true,1);

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,completed_at,version) values
 ('c4100000-0000-0000-0000-000000000001','c2100000-0000-0000-0000-000000000001','Completed','c1100000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000002',now()+interval '5 days','completed',3,'assigned',now()-interval '2 days',now()-interval '1 day',1),
 ('c4100000-0000-0000-0000-000000000002','c2100000-0000-0000-0000-000000000001','Working','c1100000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',3,'assigned',now()-interval '1 day',null,1);

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values
 ('c5100000-0000-0000-0000-000000000001','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000002','new_file','pending/c210/final-v1.txt','final-v1.txt','text/plain',10,'finalized',now()+interval '1 day',2),
 ('c5100000-0000-0000-0000-000000000002','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000002','new_file','pending/c210/other-v1.txt','other-v1.txt','text/plain',10,'finalized',now()+interval '1 day',2),
 ('c5100000-0000-0000-0000-000000000003','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000002','new_file','pending/c210/work-v1.txt','work-v1.txt','text/plain',10,'finalized',now()+interval '1 day',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version) values
 ('c6100000-0000-0000-0000-000000000001','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','final.txt','c1100000-0000-0000-0000-000000000002',1),
 ('c6100000-0000-0000-0000-000000000002','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','other.txt','c1100000-0000-0000-0000-000000000002',1),
 ('c6100000-0000-0000-0000-000000000003','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000002','work.txt','c1100000-0000-0000-0000-000000000002',1);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values
 ('c7100000-0000-0000-0000-000000000001','c6100000-0000-0000-0000-000000000001','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','c5100000-0000-0000-0000-000000000001',1,'pending/c210/final-v1.txt','final-v1.txt','text/plain',10,repeat('a',64),'c1100000-0000-0000-0000-000000000002'),
 ('c7100000-0000-0000-0000-000000000002','c6100000-0000-0000-0000-000000000002','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000001','c5100000-0000-0000-0000-000000000002',1,'pending/c210/other-v1.txt','other-v1.txt','text/plain',10,repeat('b',64),'c1100000-0000-0000-0000-000000000002'),
 ('c7100000-0000-0000-0000-000000000003','c6100000-0000-0000-0000-000000000003','c2100000-0000-0000-0000-000000000001','c4100000-0000-0000-0000-000000000002','c5100000-0000-0000-0000-000000000003',1,'pending/c210/work-v1.txt','work-v1.txt','text/plain',10,repeat('c',64),'c1100000-0000-0000-0000-000000000002');

update public.task_files set current_version_id='c7100000-0000-0000-0000-000000000001' where id='c6100000-0000-0000-0000-000000000001';
update public.task_files set current_version_id='c7100000-0000-0000-0000-000000000002' where id='c6100000-0000-0000-0000-000000000002';
update public.task_files set current_version_id='c7100000-0000-0000-0000-000000000003' where id='c6100000-0000-0000-0000-000000000003';

create temporary table final_rpc_results(label text primary key,result jsonb);
grant all on final_rpc_results to authenticated;

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into final_rpc_results values('mark-one',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'c9100000-0000-0000-0000-000000000001',0,true
));
insert into final_rpc_results values('mark-one-replay',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'c9100000-0000-0000-0000-000000000001',0,true
));
insert into final_rpc_results values('mark-one-reuse',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'c9100000-0000-0000-0000-000000000001',0,false
));
insert into final_rpc_results values('mark-two',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000002',0,true
));
reset role;

select is((select result->>'ok' from final_rpc_results where label='mark-one'),'true','leader marks a specific immutable version final');
select is((select result->>'replayed' from final_rpc_results where label='mark-one-replay'),'true','final command replays');
select is((select result->>'code' from final_rpc_results where label='mark-one-reuse'),'IDEMPOTENCY_KEY_REUSED','final command rejects request id reuse');
select is((select count(*)::integer from public.task_file_final_designations where project_id='c2100000-0000-0000-0000-000000000001' and is_final),2,'project may have multiple final versions');
select is((select count(*)::integer from public.task_file_final_designations where task_id='c4100000-0000-0000-0000-000000000001' and is_final),2,'task may have multiple final versions');

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into final_rpc_results values('member-denied',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000003',1,false
));
reset role;
select is((select result->>'code' from final_rpc_results where label='member-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','member cannot publish final status');

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into final_rpc_results values('admin-denied',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000004',1,false
));
reset role;
select is((select result->>'code' from final_rpc_results where label='admin-denied'),'NOT_FOUND_OR_NOT_AUTHORIZED','admin is not implicitly a final-deliverable curator');

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into final_rpc_results values('observer-denied',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000005',1,false
));
reset role;
select is((select result->>'code' from final_rpc_results where label='observer-denied'),'NOT_AUTHORIZED','observer cannot mutate final status');

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into final_rpc_results values('stale',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000006',0,false
));
insert into final_rpc_results values('unmark-one',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000001',
 'c9100000-0000-0000-0000-000000000007',1,false
));
insert into final_rpc_results values('working-denied',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000003',
 'c9100000-0000-0000-0000-000000000008',0,true
));
reset role;
select is((select result->>'code' from final_rpc_results where label='stale'),'STALE_VERSION','final designation uses optimistic concurrency');
select is((select result->>'currentVersion' from final_rpc_results where label='stale'),'1','stale final response returns designation version');
select is((select is_final from public.task_file_final_designations where file_version_id='c7100000-0000-0000-0000-000000000001'),false,'unmark preserves designation history row');
select is((select version from public.task_file_final_designations where file_version_id='c7100000-0000-0000-0000-000000000001'),2,'unmark advances designation version');
select is((select result->>'code' from final_rpc_results where label='working-denied'),'INVALID_TRANSITION','only completed task versions can become final');

update public.projects
set lifecycle_state='completed',completed_at=now(),version=version+1
where id='c2100000-0000-0000-0000-000000000001';

set local role authenticated;
insert into final_rpc_results values('formal-lock',public.cmd_set_task_file_version_final(
 'c2100000-0000-0000-0000-000000000001','c7100000-0000-0000-0000-000000000002',
 'c9100000-0000-0000-0000-000000000009',1,false
));
reset role;
select is((select result->>'code' from final_rpc_results where label='formal-lock'),'INVALID_TRANSITION','formalized/completed project freezes final-file status');

select set_config('request.jwt.claim.sub','c1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::integer from public.task_file_final_designations where project_id='c2100000-0000-0000-0000-000000000001'),2,'active member can read final-file facts through RLS');
reset role;

select is((select count(*)::integer from public.business_events where project_id='c2100000-0000-0000-0000-000000000001' and event_type in ('task_file_version_final_marked','task_file_version_final_unmarked')),3,'final status changes are audited');

select * from finish();
rollback;
