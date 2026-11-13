begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public',
  'cmd_compare_task_file_versions',
  array['uuid','uuid','uuid','uuid'],
  'version compare RPC exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ),
  'anon cannot compare file versions'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated users can call version compare RPC'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ),
  'service role has no client compare grant'
);

insert into auth.users(id,email) values
('21000000-0000-0000-0000-000000000001','compare-leader@example.test'),
('21000000-0000-0000-0000-000000000002','compare-member@example.test'),
('21000000-0000-0000-0000-000000000003','compare-outsider@example.test'),
('21000000-0000-0000-0000-000000000004','compare-other-project@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
('21100000-0000-0000-0000-000000000001','Compare project',now()+interval '7 days','21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001',1),
('21100000-0000-0000-0000-000000000002','Other compare project',now()+interval '7 days','21000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004',1);

insert into public.project_members(project_id,user_id,role,member_state) values
('21100000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001','leader','active'),
('21100000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','member','active'),
('21100000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000004','leader','active');

insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  '21000000-0000-0000-0000-000000000001','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  '21000000-0000-0000-0000-000000000001','test',1
);

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version) values
('21200000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','Compare task','21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002',now()+interval '3 days','completed',1,'assigned',now(),1),
('21200000-0000-0000-0000-000000000002','21100000-0000-0000-0000-000000000001','Second compare task','21000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002',now()+interval '3 days','completed',1,'assigned',now(),1),
('21200000-0000-0000-0000-000000000003','21100000-0000-0000-0000-000000000002','Other project task','21000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004',now()+interval '3 days','completed',1,'assigned',now(),1);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version) values
('21400000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','notes.md','21000000-0000-0000-0000-000000000002',3),
('21400000-0000-0000-0000-000000000002','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000002','other.md','21000000-0000-0000-0000-000000000002',1),
('21400000-0000-0000-0000-000000000003','21100000-0000-0000-0000-000000000002','21200000-0000-0000-0000-000000000003','notes.md','21000000-0000-0000-0000-000000000004',1);

insert into public.file_upload_reservations(
  id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
  object_path,original_name,declared_mime_type,declared_size_bytes,state,
  expires_at,version
) values
('21300000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','new_file',null,null,'pending/compare/v1/notes.md','notes.md','text/markdown',10,'finalized',now()+interval '1 hour',2),
('21300000-0000-0000-0000-000000000002','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','new_version','21400000-0000-0000-0000-000000000001',1,'pending/compare/v2/notes.md','notes.md','text/markdown',14,'finalized',now()+interval '1 hour',2),
('21300000-0000-0000-0000-000000000003','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','new_version','21400000-0000-0000-0000-000000000001',2,'pending/compare/v3/image.png','image.png','image/png',99,'finalized',now()+interval '1 hour',2),
('21300000-0000-0000-0000-000000000004','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000002','new_file',null,null,'pending/compare/other/other.md','other.md','text/markdown',8,'finalized',now()+interval '1 hour',2),
('21300000-0000-0000-0000-000000000005','21100000-0000-0000-0000-000000000002','21200000-0000-0000-0000-000000000003','21000000-0000-0000-0000-000000000004','new_file',null,null,'pending/compare/cross/notes.md','notes.md','text/markdown',8,'finalized',now()+interval '1 hour',2);

insert into public.task_file_versions(
  id,file_id,project_id,task_id,reservation_id,version_number,object_path,
  original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values
('21500000-0000-0000-0000-000000000001','21400000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21300000-0000-0000-0000-000000000001',1,'pending/compare/v1/notes.md','notes.md','text/markdown',10,repeat('1',64),'21000000-0000-0000-0000-000000000002'),
('21500000-0000-0000-0000-000000000002','21400000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21300000-0000-0000-0000-000000000002',2,'pending/compare/v2/notes.md','notes.md','text/markdown',14,repeat('2',64),'21000000-0000-0000-0000-000000000002'),
('21500000-0000-0000-0000-000000000003','21400000-0000-0000-0000-000000000001','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000001','21300000-0000-0000-0000-000000000003',3,'pending/compare/v3/image.png','image.png','image/png',99,repeat('3',64),'21000000-0000-0000-0000-000000000002'),
('21500000-0000-0000-0000-000000000004','21400000-0000-0000-0000-000000000002','21100000-0000-0000-0000-000000000001','21200000-0000-0000-0000-000000000002','21300000-0000-0000-0000-000000000004',1,'pending/compare/other/other.md','other.md','text/markdown',8,repeat('4',64),'21000000-0000-0000-0000-000000000002'),
('21500000-0000-0000-0000-000000000005','21400000-0000-0000-0000-000000000003','21100000-0000-0000-0000-000000000002','21200000-0000-0000-0000-000000000003','21300000-0000-0000-0000-000000000005',1,'pending/compare/cross/notes.md','notes.md','text/markdown',8,repeat('5',64),'21000000-0000-0000-0000-000000000004');

update public.task_files set current_version_id='21500000-0000-0000-0000-000000000003' where id='21400000-0000-0000-0000-000000000001';
update public.task_files set current_version_id='21500000-0000-0000-0000-000000000004' where id='21400000-0000-0000-0000-000000000002';
update public.task_files set current_version_id='21500000-0000-0000-0000-000000000005' where id='21400000-0000-0000-0000-000000000003';

create temporary table compare_results(label text primary key,result jsonb);
grant all on compare_results to authenticated;

select set_config('request.jwt.claim.sub','21000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into compare_results values('text-degraded',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000002',
  '21600000-0000-0000-0000-000000000001'
));
insert into compare_results values('text-replay',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000002',
  '21600000-0000-0000-0000-000000000001'
));
insert into compare_results values('text-reuse',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000002',
  '21500000-0000-0000-0000-000000000001',
  '21600000-0000-0000-0000-000000000001'
));
insert into compare_results values('binary-unsupported',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000002',
  '21500000-0000-0000-0000-000000000003',
  '21600000-0000-0000-0000-000000000002'
));
insert into compare_results values('different-file',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000004',
  '21600000-0000-0000-0000-000000000003'
));
insert into compare_results values('cross-project-probe',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000005',
  '21600000-0000-0000-0000-000000000004'
));
reset role;

select is((select result->>'ok' from compare_results where label='text-degraded'),'true','member can compare two versions from the same logical file');
select is((select result #>> '{data,metadataComparison,status}' from compare_results where label='text-degraded'),'supported','metadata diff is supported');
select is((select result #>> '{data,metadataComparison,diff,sizeBytes,delta}' from compare_results where label='text-degraded'),'4','metadata diff includes size delta');
select is((select result #>> '{data,contentComparison,status}' from compare_results where label='text-degraded'),'degraded','text-like content diff is degraded without Storage orchestration');
select is((select result #>> '{data,contentComparison,requires}' from compare_results where label='text-degraded'),'edge_orchestration','degraded text diff declares Edge orchestration requirement');
select ok(not ((select result from compare_results where label='text-degraded')::text like '%pending/compare%'),'compare result does not expose storage object paths');
select is((select result->>'replayed' from compare_results where label='text-replay'),'true','compare replay is idempotent');
select is((select result->>'code' from compare_results where label='text-reuse'),'IDEMPOTENCY_KEY_REUSED','compare request id cannot be reused for a different payload');
select is((select result #>> '{data,contentComparison,status}' from compare_results where label='binary-unsupported'),'unsupported','binary content comparison is explicitly unsupported');
select is((select result->>'code' from compare_results where label='different-file'),'VALIDATION_FAILED','different logical files are rejected');
select is((select result #>> '{details,reason}' from compare_results where label='different-file'),'different_logical_file','different logical file failure is structured');
select is((select result->>'code' from compare_results where label='cross-project-probe'),'NOT_FOUND_OR_NOT_AUTHORIZED','cross-project version probing is hidden');
select is(
  (select count(*)::integer from public.business_events where event_type='task_file_versions_compared' and project_id='21100000-0000-0000-0000-000000000001'),
  2,
  'successful fresh comparisons emit audit events'
);
select is(
  (select count(*)::integer from public.command_requests where command_name='cmd_compare_task_file_versions' and project_id='21100000-0000-0000-0000-000000000001'),
  4,
  'fresh compare request keys are command-recorded for idempotency'
);

select set_config('request.jwt.claim.sub','21000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into compare_results values('outsider',public.cmd_compare_task_file_versions(
  '21100000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000001',
  '21500000-0000-0000-0000-000000000002',
  '21600000-0000-0000-0000-000000000005'
));
reset role;
select is((select result->>'code' from compare_results where label='outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot compare private project files');

select finish();
rollback;
