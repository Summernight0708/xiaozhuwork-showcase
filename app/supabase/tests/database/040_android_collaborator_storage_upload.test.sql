begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Mirrors the reserve service's authorization while exercising the Storage
-- INSERT policy as authenticated (rather than checking SQL text alone).
select is((select count(*)::integer from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'teamup_files_insert_reserved'
    and cmd = 'INSERT' and roles @> array['authenticated'::name]),
  1, 'exactly one authenticated Storage INSERT policy for reserved uploads');
select ok(
  (select with_check ilike '%teamup_storage_reserved_upload_allowed%'
   from pg_policies where schemaname='storage' and tablename='objects'
    and policyname='teamup_files_insert_reserved')
  and pg_get_functiondef('public.teamup_storage_reserved_upload_allowed(text)'::regprocedure)
    ilike '%task_collaborators%'
  and pg_get_functiondef('public.teamup_storage_reserved_upload_allowed(text)'::regprocedure)
    ilike '%accepted%',
  'Storage policy and its definer helper explicitly require accepted collaborators');
select ok(not exists(select 1 from pg_policies
  where schemaname='storage' and tablename='objects'
    and cmd in ('UPDATE','DELETE') and roles @> array['authenticated'::name]
    and coalesce(qual,'') ilike '%teamup-files%'),
  'no teamup-files UPDATE/DELETE permission added');

-- A schema-only isolated clone has no seed bucket. Production already has it.
-- This fixture is rollback-scoped and never changes an existing bucket.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('teamup-files','teamup-files',false,52428800,array['image/png'])
on conflict (id) do nothing;

insert into auth.users(id,email) values
('e1100000-0000-0000-0000-000000000001','storage-rls-role-1@example.test'),
('e1100000-0000-0000-0000-000000000002','storage-rls-role-2@example.test'),
('e1100000-0000-0000-0000-000000000003','storage-rls-role-3@example.test'),
('e1100000-0000-0000-0000-000000000004','storage-rls-role-4@example.test'),
('e1100000-0000-0000-0000-000000000005','storage-rls-role-5@example.test'),
('e1100000-0000-0000-0000-000000000006','storage-rls-role-6@example.test'),
('e1100000-0000-0000-0000-000000000007','storage-rls-role-7@example.test'),
('e1100000-0000-0000-0000-000000000008','storage-rls-role-8@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state)
values ('e2100000-0000-0000-0000-000000000001','Android collaborator Storage policy QA',now()+interval '30 days','e1100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001',1,'weighted','active');
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','leader','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000002','member','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000003','member','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','member','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000005','member','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000006','member','active',false),
('e2100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000007','observer','active',true);
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,version)
values ('e3100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','Collaborator Storage upload', 'e1100000-0000-0000-0000-000000000003','e1100000-0000-0000-0000-000000000002',now()+interval '10 days','in_progress',1,'assigned',now(),1);

insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at,invited_by) values
('e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','accepted',now(),'e1100000-0000-0000-0000-000000000003'),
('e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000005','pending',null,'e1100000-0000-0000-0000-000000000003');
-- The DB's integrity trigger already forbids observer/outsider accepted rows.
-- Storage must still reject their forged reservations independently.

insert into public.file_upload_reservations(
  id,project_id,task_id,actor_id,mode,object_path,
  original_name,declared_mime_type,declared_size_bytes,
  state,expires_at,version,reserved_envelope_bytes
) values
('e4100000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000001/case-1.png','case-1.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000002','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000002/case-2.png','case-2.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000003','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000003','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000003/case-3.png','case-3.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000004','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000004/case-4.png','case-4.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000005','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000005','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000005/case-5.png','case-5.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000006','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000006','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000006/case-6.png','case-6.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000007','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000007','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000007/case-7.png','case-7.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000008','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000008','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000008/case-8.png','case-8.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000009','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000009/case-9.png','case-9.png','image/png',1024,'reserved',now()+interval '-1 minutes',1,52428800),
('e4100000-0000-0000-0000-000000000010','e2100000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000004','new_file','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000010/case-10.png','case-10.png','image/png',1024,'reserved',now()+interval '10 minutes',1,52428800);

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
select lives_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000001/case-1.png','e1100000-0000-0000-0000-000000000001','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, 'project leader may insert');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
select lives_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000002/case-2.png','e1100000-0000-0000-0000-000000000002','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, 'primary assignee may insert');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
select lives_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000003/case-3.png','e1100000-0000-0000-0000-000000000003','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, 'task creator may insert');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
select lives_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000004/case-4.png','e1100000-0000-0000-0000-000000000004','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, 'accepted collaborator may insert');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000005/case-5.png','e1100000-0000-0000-0000-000000000005','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, '42501', null, 'pending collaborator is denied');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000006',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000006/case-6.png','e1100000-0000-0000-0000-000000000006','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, '42501', null, 'unassigned member is denied');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000007',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000007/case-7.png','e1100000-0000-0000-0000-000000000007','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, '42501', null, 'observer with a forged reservation is denied');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000008',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000008/case-8.png','e1100000-0000-0000-0000-000000000008','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, '42501', null, 'outsider with a forged reservation is denied');
reset role;

select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000009/case-9.png','e1100000-0000-0000-0000-000000000004','{"size":1024,"mimetype":"image/png"}'::jsonb)$$, '42501', null, 'expired accepted-collaborator reservation is denied');
reset role;

-- Revoked collaboration must immediately lose Storage write authority.
update public.task_collaborators
set state='removed',removed_at=now()
where project_id='e2100000-0000-0000-0000-000000000001' and task_id='e3100000-0000-0000-0000-000000000001' and user_id='e1100000-0000-0000-0000-000000000004';
select set_config('request.jwt.claim.sub','e1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000010/case-10.png','e1100000-0000-0000-0000-000000000004')$$,
  '42501',null,'removed collaborator cannot insert even with live reservation');
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id)
  values ('teamup-files','pending/e2100000-0000-0000-0000-000000000001/e4100000-0000-0000-0000-000000000004/unreserved.png','e1100000-0000-0000-0000-000000000004')$$,
  '42501',null,'unreserved pending path is always denied');
reset role;

select * from finish();
rollback;
