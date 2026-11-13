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


select has_function('private','project_has_capability',array['uuid','text'],'central project capability helper exists');
select has_function('private','project_capability_failure',array['uuid','text','uuid'],'central capability failure helper exists');

insert into auth.users(id,email) values
('f1100000-0000-0000-0000-000000000001','p3-free-leader@example.test'),
('f1100000-0000-0000-0000-000000000002','p3-pro-leader@example.test'),
('f1100000-0000-0000-0000-000000000003','p3-grace-leader@example.test'),
('f1100000-0000-0000-0000-000000000004','p3-pro-member@example.test'),
('f1100000-0000-0000-0000-000000000005','p3-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
('f2100000-0000-0000-0000-000000000001','P3 Free history',now()+interval '20 days','f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',1),
('f2100000-0000-0000-0000-000000000002','P3 Pro',now()+interval '20 days','f1100000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000002',1),
('f2100000-0000-0000-0000-000000000003','P3 Grace',now()+interval '20 days','f1100000-0000-0000-0000-000000000003','f1100000-0000-0000-0000-000000000003',1),
('f2100000-0000-0000-0000-000000000004','P3 Free batch',now()+interval '20 days','f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',1),
('f2100000-0000-0000-0000-000000000005','P3 Free recovery',now()+interval '20 days','f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',1);

insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
('f2100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001','leader','active',false),
('f2100000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000002','leader','active',false),
('f2100000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000004','member','active',false),
('f2100000-0000-0000-0000-000000000003','f1100000-0000-0000-0000-000000000003','leader','active',false),
('f2100000-0000-0000-0000-000000000004','f1100000-0000-0000-0000-000000000001','leader','active',false),
('f2100000-0000-0000-0000-000000000005','f1100000-0000-0000-0000-000000000001','leader','active',false);

insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'f1100000-0000-0000-0000-000000000002','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'f1100000-0000-0000-0000-000000000002','test',1
);

insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values('f2100000-0000-0000-0000-000000000003',now()-interval '1 hour',now()+interval '2 days','account_expired',1);

insert into public.tasks(
  id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
  is_direct_assignment,accepted_at,assignment_state,version
) values
('f3100000-0000-0000-0000-000000000001','f2100000-0000-0000-0000-000000000001','P3 Free history task','f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',now()+interval '10 days','in_progress',1,false,now(),'assigned',1),
('f3100000-0000-0000-0000-000000000002','f2100000-0000-0000-0000-000000000002','P3 Pro task','f1100000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000002',now()+interval '10 days','in_progress',1,false,now(),'assigned',1),
('f3100000-0000-0000-0000-000000000003','f2100000-0000-0000-0000-000000000003','P3 Grace task','f1100000-0000-0000-0000-000000000003','f1100000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',1,false,now(),'assigned',1),
('f3100000-0000-0000-0000-000000000004','f2100000-0000-0000-0000-000000000004','P3 Free batch task','f1100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',now()+interval '10 days','in_progress',1,false,now(),'assigned',1);

create temporary table p3_file_fixture(
  project_id uuid primary key,
  task_id uuid not null,
  file_id uuid not null,
  actor_id uuid not null,
  max_version integer not null
);
insert into p3_file_fixture values
('f2100000-0000-0000-0000-000000000001','f3100000-0000-0000-0000-000000000001','f5100000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001',12),
('f2100000-0000-0000-0000-000000000002','f3100000-0000-0000-0000-000000000002','f5100000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000002',12),
('f2100000-0000-0000-0000-000000000003','f3100000-0000-0000-0000-000000000003','f5100000-0000-0000-0000-000000000003','f1100000-0000-0000-0000-000000000003',12),
('f2100000-0000-0000-0000-000000000004','f3100000-0000-0000-0000-000000000004','f5100000-0000-0000-0000-000000000004','f1100000-0000-0000-0000-000000000001',2);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
select file_id,project_id,task_id,'p3-history.txt',actor_id,max_version
from p3_file_fixture;

create temporary table p3_history_fixture as
select
  f.project_id,
  f.task_id,
  f.file_id,
  f.actor_id,
  f.max_version,
  s.version_number,
  extensions.gen_random_uuid() as reservation_id,
  extensions.gen_random_uuid() as version_id
from p3_file_fixture f
cross join lateral generate_series(1,f.max_version) as s(version_number);
grant select on p3_history_fixture to authenticated;

insert into public.file_upload_reservations(
  id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
  object_path,original_name,declared_mime_type,declared_size_bytes,
  state,expires_at,version
)
select
  h.reservation_id,h.project_id,h.task_id,h.actor_id,
  case when h.version_number=1 then 'new_file' else 'new_version' end,
  case when h.version_number=1 then null else h.file_id end,
  case when h.version_number=1 then null else h.version_number-1 end,
  format('pending/%s/%s/v%s.txt',h.project_id,h.reservation_id,h.version_number),
  format('history-v%s.txt',h.version_number),
  'text/plain',100+h.version_number,'finalized',now(),2
from p3_history_fixture h;

insert into public.task_file_versions(
  id,file_id,project_id,task_id,reservation_id,version_number,
  object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by
)
select
  h.version_id,h.file_id,h.project_id,h.task_id,h.reservation_id,h.version_number,
  format('pending/%s/%s/v%s.txt',h.project_id,h.reservation_id,h.version_number),
  format('history-v%s.txt',h.version_number),
  'text/plain',100+h.version_number,repeat(substr(md5(h.version_number::text),1,1),64),h.actor_id
from p3_history_fixture h;

update public.task_files f
set current_version_id=h.version_id
from p3_history_fixture h
where h.file_id=f.id
  and h.version_number=h.max_version;

insert into public.project_recovery_points(
  id,project_id,created_by,label,project_version,version,item_count
) values (
  'f7100000-0000-0000-0000-000000000001',
  'f2100000-0000-0000-0000-000000000005',
  'f1100000-0000-0000-0000-000000000001',
  'Free restore fixture',1,1,0
);

create temporary table p3_results(label text primary key,result jsonb);
grant all on p3_results to authenticated;

-- Capability registry/effective entitlement semantics.
select ok(
  (select bool_and(private.project_has_capability('f2100000-0000-0000-0000-000000000002',c.capability))
   from (values
     ('file_full_history'::text),
     ('file_batch_rollback'),
     ('file_version_compare'),
     ('project_recovery_point')
   ) c(capability)),
  'active Pro project receives every released file capability'
);
select ok(
  (select bool_and(private.project_has_capability('f2100000-0000-0000-0000-000000000003',c.capability))
   from (values
     ('file_full_history'::text),
     ('file_batch_rollback'),
     ('file_version_compare'),
     ('project_recovery_point')
   ) c(capability)),
  'Grace project receives every released file capability'
);
select ok(
  not private.project_has_capability('f2100000-0000-0000-0000-000000000001','file_full_history'),
  'Free project does not receive released Pro capability'
);
select ok(
  not private.project_has_capability('f2100000-0000-0000-0000-000000000002','enhanced_report'),
  'planned capability stays unavailable even on Pro'
);
select ok(
  not private.project_has_capability('f2100000-0000-0000-0000-000000000002','totally_unknown_capability'),
  'unknown capability stays unavailable'
);
select is(
  private.project_capability_failure('f2100000-0000-0000-0000-000000000002','enhanced_report',null)->>'code',
  'CAPABILITY_NOT_AVAILABLE',
  'planned capability uses CAPABILITY_NOT_AVAILABLE'
);
select is(
  private.project_capability_failure('f2100000-0000-0000-0000-000000000001','file_batch_rollback',null)->>'code',
  'CAPABILITY_REQUIRES_PRO',
  'released capability on Free uses CAPABILITY_REQUIRES_PRO'
);
select ok(
  private.project_capability_failure('f2100000-0000-0000-0000-000000000002','file_batch_rollback',null) is null,
  'released capability on Pro has no capability failure'
);

-- Full history: Free is capped to the newest ten across pagination; Pro/Grace are full.
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p3_results values(
  'history-free',
  public.get_task_file_history('f5100000-0000-0000-0000-000000000001',100,null)
);
insert into p3_results values(
  'history-free-bypass',
  public.get_task_file_history('f5100000-0000-0000-0000-000000000001',100,3)
);
reset role;
select is(jsonb_array_length((select result#>'{data,versions}' from p3_results where label='history-free')),10,'Free history returns at most ten versions');
select is((select result#>>'{data,versions,0,versionNumber}' from p3_results where label='history-free'),'12','Free history starts at newest version');
select is((select result#>>'{data,versions,9,versionNumber}' from p3_results where label='history-free'),'3','Free history stops at the tenth newest version');
select is(jsonb_array_length((select result#>'{data,versions}' from p3_results where label='history-free-bypass')),0,'Free pagination cannot cross the ten-version boundary');
select ok(
  not exists(
    select 1
    from p3_results r
    cross join lateral jsonb_array_elements(r.result#>'{data,versions}') v
    where r.label='history-free' and v ? 'objectPath'
  ),
  'history response never leaks Storage object paths'
);

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p3_results values(
  'history-pro',
  public.get_task_file_history('f5100000-0000-0000-0000-000000000002',100,null)
);
reset role;
select is(jsonb_array_length((select result#>'{data,versions}' from p3_results where label='history-pro')),12,'active Pro reads more than ten versions');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p3_results values(
  'history-grace',
  public.get_task_file_history('f5100000-0000-0000-0000-000000000003',100,null)
);
reset role;
select is(jsonb_array_length((select result#>'{data,versions}' from p3_results where label='history-grace')),12,'Grace reads more than ten versions');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into p3_results values(
  'history-outsider',
  public.get_task_file_history('f5100000-0000-0000-0000-000000000002',100,null)
);
reset role;
select is((select result->>'code' from p3_results where label='history-outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider is denied before history entitlement is considered');

-- Version compare capability gate.
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p3_results values(
  'compare-free',
  public.cmd_compare_task_file_versions(
    'f2100000-0000-0000-0000-000000000001',
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000001' and version_number=11),
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000001' and version_number=12),
    'f9000000-0000-0000-0000-000000000001'
  )
);
reset role;
select is((select result->>'code' from p3_results where label='compare-free'),'CAPABILITY_REQUIRES_PRO','Free authorized compare returns capability error');
select is((select count(*)::integer from public.business_events where request_id='f9000000-0000-0000-0000-000000000001'),0,'Free compare emits no business event');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p3_results values(
  'compare-pro',
  public.cmd_compare_task_file_versions(
    'f2100000-0000-0000-0000-000000000002',
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=11),
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=12),
    'f9000000-0000-0000-0000-000000000002'
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='compare-pro'),'true','active Pro compare succeeds');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p3_results values(
  'compare-grace',
  public.cmd_compare_task_file_versions(
    'f2100000-0000-0000-0000-000000000003',
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000003' and version_number=11),
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000003' and version_number=12),
    'f9000000-0000-0000-0000-000000000003'
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='compare-grace'),'true','Grace compare succeeds');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into p3_results values(
  'compare-outsider',
  public.cmd_compare_task_file_versions(
    'f2100000-0000-0000-0000-000000000002',
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=11),
    (select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=12),
    'f9000000-0000-0000-0000-000000000004'
  )
);
reset role;
select is((select result->>'code' from p3_results where label='compare-outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','compare outsider receives business authorization error');

-- Recovery point create/restore: leader AND capability.
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p3_results values(
  'recovery-free-create',
  public.cmd_create_project_recovery_point(
    'f2100000-0000-0000-0000-000000000005',
    'f9000000-0000-0000-0000-000000000010',1,'free-should-not-exist'
  )
);
insert into p3_results values(
  'recovery-free-restore',
  public.cmd_restore_project_recovery_point(
    'f2100000-0000-0000-0000-000000000005',
    'f7100000-0000-0000-0000-000000000001',
    'f9000000-0000-0000-0000-000000000011',1
  )
);
reset role;
select is((select result->>'code' from p3_results where label='recovery-free-create'),'CAPABILITY_REQUIRES_PRO','Free leader cannot create recovery point');
select is((select result->>'code' from p3_results where label='recovery-free-restore'),'CAPABILITY_REQUIRES_PRO','Free leader cannot restore recovery point');
select is((select count(*)::integer from public.project_recovery_points where project_id='f2100000-0000-0000-0000-000000000005' and label='free-should-not-exist'),0,'Free recovery rejection creates no recovery point');
select is((select version from public.projects where id='f2100000-0000-0000-0000-000000000005'),1,'Free recovery rejection does not mutate project version');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p3_results values(
  'recovery-pro-create',
  public.cmd_create_project_recovery_point(
    'f2100000-0000-0000-0000-000000000002',
    'f9000000-0000-0000-0000-000000000012',1,'pro-point'
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='recovery-pro-create'),'true','active Pro leader creates recovery point');
select (result#>>'{data,recoveryPointId}')::uuid as p3_pro_recovery_point
from p3_results where label='recovery-pro-create' \gset

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into p3_results values(
  'recovery-pro-member-create',
  public.cmd_create_project_recovery_point(
    'f2100000-0000-0000-0000-000000000002',
    'f9000000-0000-0000-0000-000000000013',1,'member-denied'
  )
);
insert into p3_results values(
  'recovery-pro-member-restore',
  public.cmd_restore_project_recovery_point(
    'f2100000-0000-0000-0000-000000000002',
    :'p3_pro_recovery_point',
    'f9000000-0000-0000-0000-000000000014',1
  )
);
reset role;
select is((select result->>'code' from p3_results where label='recovery-pro-member-create'),'NOT_FOUND_OR_NOT_AUTHORIZED','Pro project non-leader cannot create recovery point');
select is((select result->>'code' from p3_results where label='recovery-pro-member-restore'),'NOT_FOUND_OR_NOT_AUTHORIZED','Pro project non-leader cannot restore recovery point');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p3_results values(
  'recovery-pro-restore',
  public.cmd_restore_project_recovery_point(
    'f2100000-0000-0000-0000-000000000002',
    :'p3_pro_recovery_point',
    'f9000000-0000-0000-0000-000000000015',1
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='recovery-pro-restore'),'true','active Pro leader restores recovery point');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p3_results values(
  'recovery-grace-create',
  public.cmd_create_project_recovery_point(
    'f2100000-0000-0000-0000-000000000003',
    'f9000000-0000-0000-0000-000000000016',1,'grace-point'
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='recovery-grace-create'),'true','Grace leader creates recovery point');
select (result#>>'{data,recoveryPointId}')::uuid as p3_grace_recovery_point
from p3_results where label='recovery-grace-create' \gset
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p3_results values(
  'recovery-grace-restore',
  public.cmd_restore_project_recovery_point(
    'f2100000-0000-0000-0000-000000000003',
    :'p3_grace_recovery_point',
    'f9000000-0000-0000-0000-000000000017',1
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='recovery-grace-restore'),'true','Grace leader restores recovery point');

-- Batch rollback: file authority AND capability, no partial write on Free rejection.
select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p3_results values(
  'rollback-free',
  public.cmd_batch_rollback_task_files(
    'f2100000-0000-0000-0000-000000000004',
    'f9000000-0000-0000-0000-000000000020',1,
    jsonb_build_array(jsonb_build_object(
      'fileId','f5100000-0000-0000-0000-000000000004',
      'restoreVersionId',(select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000004' and version_number=1),
      'expectedVersion',2
    ))
  )
);
reset role;
select is((select result->>'code' from p3_results where label='rollback-free'),'CAPABILITY_REQUIRES_PRO','Free authorized file actor cannot batch rollback');
select is((select version from public.task_files where id='f5100000-0000-0000-0000-000000000004'),2,'Free rollback rejection leaves file version unchanged');
select is((select version from public.projects where id='f2100000-0000-0000-0000-000000000004'),1,'Free rollback rejection leaves project version unchanged');
select is((select count(*)::integer from public.business_events where request_id='f9000000-0000-0000-0000-000000000020'),0,'Free rollback rejection emits no audit event');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into p3_results values(
  'rollback-pro-member',
  public.cmd_batch_rollback_task_files(
    'f2100000-0000-0000-0000-000000000002',
    'f9000000-0000-0000-0000-000000000021',2,
    jsonb_build_array(jsonb_build_object(
      'fileId','f5100000-0000-0000-0000-000000000002',
      'restoreVersionId',(select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=11),
      'expectedVersion',12
    ))
  )
);
reset role;
select is((select result->>'code' from p3_results where label='rollback-pro-member'),'NOT_FOUND_OR_NOT_AUTHORIZED','Pro ordinary member cannot bypass task/file authority');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p3_results values(
  'rollback-pro',
  public.cmd_batch_rollback_task_files(
    'f2100000-0000-0000-0000-000000000002',
    'f9000000-0000-0000-0000-000000000022',2,
    jsonb_build_array(jsonb_build_object(
      'fileId','f5100000-0000-0000-0000-000000000002',
      'restoreVersionId',(select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=11),
      'expectedVersion',12
    ))
  )
);
insert into p3_results values(
  'rollback-pro-replay',
  public.cmd_batch_rollback_task_files(
    'f2100000-0000-0000-0000-000000000002',
    'f9000000-0000-0000-0000-000000000022',2,
    jsonb_build_array(jsonb_build_object(
      'fileId','f5100000-0000-0000-0000-000000000002',
      'restoreVersionId',(select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000002' and version_number=11),
      'expectedVersion',12
    ))
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='rollback-pro'),'true','active Pro file actor batch rollback succeeds');
select is((select result->>'replayed' from p3_results where label='rollback-pro-replay'),'true','capability gate preserves request-id replay');
select is((select version from public.task_files where id='f5100000-0000-0000-0000-000000000002'),13,'Pro rollback appends exactly one version despite replay');

select set_config('request.jwt.claim.sub','f1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into p3_results values(
  'rollback-grace',
  public.cmd_batch_rollback_task_files(
    'f2100000-0000-0000-0000-000000000003',
    'f9000000-0000-0000-0000-000000000023',2,
    jsonb_build_array(jsonb_build_object(
      'fileId','f5100000-0000-0000-0000-000000000003',
      'restoreVersionId',(select version_id from p3_history_fixture where project_id='f2100000-0000-0000-0000-000000000003' and version_number=11),
      'expectedVersion',12
    ))
  )
);
reset role;
select is((select result->>'ok' from p3_results where label='rollback-grace'),'true','Grace file actor batch rollback succeeds');

select * from finish();
rollback;
