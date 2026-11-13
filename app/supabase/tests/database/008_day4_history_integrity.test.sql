begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Historical user references must anonymize instead of deleting immutable business history.
insert into auth.users(id,email) values
 ('c1000000-0000-0000-0000-000000000001','history-leader@example.test'),
 ('c1000000-0000-0000-0000-000000000002','history-uploader@example.test'),
 ('c1000000-0000-0000-0000-000000000003','history-reviewer@example.test'),
 ('c1000000-0000-0000-0000-000000000004','history-account@example.test'),
 ('c1000000-0000-0000-0000-000000000005','history-capacity-1@example.test'),
 ('c1000000-0000-0000-0000-000000000006','history-capacity-2@example.test'),
 ('c1000000-0000-0000-0000-000000000007','history-capacity-3@example.test'),
 ('c1000000-0000-0000-0000-000000000008','history-capacity-4@example.test'),
 ('c1000000-0000-0000-0000-000000000009','history-capacity-5@example.test'),
 ('c1000000-0000-0000-0000-000000000010','history-capacity-joiner@example.test');

insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('c2000000-0000-0000-0000-000000000001','History project',now()+interval '10 days','weighted',
       'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
 ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','leader','active'),
 ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','member','active'),
 ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','member','active');

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,first_submitted_at,completed_at,version)
values('c3000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','Historical task',
       'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
       now()+interval '5 days','completed',4,'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3);

insert into public.project_invitations(
 id,project_id,created_by,token_hash,mode,expires_at,max_uses,uses_count,version
) values(
 'cd000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001',
 'c1000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('historical-approved-invite','utf8'),'sha256'),
 'approval',now()+interval '3 days',1,1,2
);
insert into public.project_join_requests(
 id,invitation_id,project_id,user_id,state,version,reviewed_by,reviewed_at
) values(
 'ce000000-0000-0000-0000-000000000001','cd000000-0000-0000-0000-000000000001',
 'c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
 'approved',2,'c1000000-0000-0000-0000-000000000001',now()-interval '1 day'
);
insert into public.task_assignment_offers(
 id,task_id,project_id,target_user_id,state,version,created_by,responded_at
) values(
 'cf000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
 'c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
 'accepted',2,'c1000000-0000-0000-0000-000000000001',now()-interval '3 hours'
);

-- Pending application retained across account deletion must never be approvable as a NULL user.
insert into public.project_invitations(
 id,project_id,created_by,token_hash,mode,expires_at,version
) values(
 'cd000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001',
 'c1000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('historical-pending-invite','utf8'),'sha256'),
 'approval',now()+interval '3 days',1
);
insert into public.project_join_requests(
 id,invitation_id,project_id,user_id,state,version
) values(
 'ce000000-0000-0000-0000-000000000002','cd000000-0000-0000-0000-000000000002',
 'c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
 'pending',1
);

-- A completed task must remain contribution-reportable after its assignee is anonymized.
insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('c2000000-0000-0000-0000-000000000002','Anonymous contribution project',now()+interval '10 days','weighted',
       'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
 ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001','leader','active'),
 ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000002','member','active');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,first_submitted_at,completed_at,version)
values('c3000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000002','Anonymous completed task',
       'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
       now()+interval '5 days','completed',3,'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3);

-- An anonymized membership is history, not a live capacity slot.
insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('c2000000-0000-0000-0000-000000000003','Capacity after deletion',now()+interval '10 days','weighted',
       'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state) values
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000001','leader','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000002','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000003','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000004','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000005','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000006','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000007','member','active'),
 ('c2000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000008','member','active');
insert into public.project_invitations(
 id,project_id,created_by,token_hash,mode,expires_at,version
) values(
 'cd000000-0000-0000-0000-000000000003','c2000000-0000-0000-0000-000000000003',
 'c1000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('capacity-after-deletion','utf8'),'sha256'),
 'direct',now()+interval '3 days',1
);

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values(
 'c4000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001',
 'c3000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002',
 'new_file','pending/c2000000-0000-0000-0000-000000000001/c4000000-0000-0000-0000-000000000001/history.pdf',
 'history.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2
);
insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values('c5000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001',
       'c3000000-0000-0000-0000-000000000001','history.pdf','c1000000-0000-0000-0000-000000000002',1);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'c6000000-0000-0000-0000-000000000001','c5000000-0000-0000-0000-000000000001',
 'c2000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
 'c4000000-0000-0000-0000-000000000001',1,
 'pending/c2000000-0000-0000-0000-000000000001/c4000000-0000-0000-0000-000000000001/history.pdf',
 'history.pdf','application/pdf',100,repeat('c',64),'c1000000-0000-0000-0000-000000000002'
);
update public.task_files set current_version_id='c6000000-0000-0000-0000-000000000001'
where id='c5000000-0000-0000-0000-000000000001';

insert into public.task_review_rounds(
 id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,submitted_at,
 state,decision,reviewed_by,reviewed_at,version
) values(
 'c7000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001',
 'c3000000-0000-0000-0000-000000000001',1,'c6000000-0000-0000-0000-000000000001',
 'c1000000-0000-0000-0000-000000000002',now()-interval '2 hours',
 'approved','approve','c1000000-0000-0000-0000-000000000003',now()-interval '1 hour',2
);

insert into public.contribution_reports(
 id,project_id,state,contribution_mode,source_project_version,eligible_member_count,required_confirmation_count,created_by,version
) values(
 'c8000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001',
 'draft','weighted',1,3,2,'c1000000-0000-0000-0000-000000000001',1
);
insert into public.contribution_items(
 id,report_id,project_id,task_id,member_user_id,member_display_name_snapshot,task_weight,share,contribution_value,task_title_snapshot,completed_at_snapshot
) values(
 'c9000000-0000-0000-0000-000000000001','c8000000-0000-0000-0000-000000000001',
 'c2000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
 'c1000000-0000-0000-0000-000000000002','Historical member',4.0000,1.0000,4.0000,'Historical task',now()-interval '1 hour'
);
insert into public.contribution_confirmations(id,report_id,project_id,user_id)
values('ca000000-0000-0000-0000-000000000001','c8000000-0000-0000-0000-000000000001',
       'c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002');

-- Exercise a real command so deletion must retain a linked ledger and business event.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.cmd_create_task(
  'c2000000-0000-0000-0000-000000000001',
  'cb000000-0000-0000-0000-000000000001',
  1,
  'Historical command task',
  null::text,
  now()+interval '1 day',
  1::smallint,
  'claimable',
  null::uuid
);
reset role;
select is(
  (select count(*)::integer from public.business_events where request_id='cb000000-0000-0000-0000-000000000001'),
  1,
  'history fixture includes a real command-linked business event'
);

select lives_ok(
  $$delete from auth.users where id='c1000000-0000-0000-0000-000000000002'$$,
  'deleting uploader/member anonymizes immutable file, review, and contribution history'
);
select is((select actor_id from public.file_upload_reservations where id='c4000000-0000-0000-0000-000000000001'),null::uuid,'finalized reservation actor is anonymized');
select is((select uploaded_by from public.task_file_versions where id='c6000000-0000-0000-0000-000000000001'),null::uuid,'file-version uploader is anonymized');
select is((select submitted_by from public.task_review_rounds where id='c7000000-0000-0000-0000-000000000001'),null::uuid,'review submitter is anonymized');
select is((select member_user_id from public.contribution_items where id='c9000000-0000-0000-0000-000000000001'),null::uuid,'contribution member is anonymized');
select is((select user_id from public.contribution_confirmations where id='ca000000-0000-0000-0000-000000000001'),null::uuid,'contribution confirmation user is anonymized');
select is(
  (select count(*)::integer from public.project_join_requests where id='ce000000-0000-0000-0000-000000000001'),
  1,
  'approved join-request history survives applicant deletion'
);
select is(
  (select user_id from public.project_join_requests where id='ce000000-0000-0000-0000-000000000001'),
  null::uuid,
  'approved join-request applicant is anonymized'
);
select is(
  (select count(*)::integer from public.task_assignment_offers where id='cf000000-0000-0000-0000-000000000001'),
  1,
  'accepted assignment-offer history survives target deletion'
);
select is(
  (select target_user_id from public.task_assignment_offers where id='cf000000-0000-0000-0000-000000000001'),
  null::uuid,
  'accepted assignment-offer target is anonymized'
);
select is((select contribution_value::text from public.contribution_items where id='c9000000-0000-0000-0000-000000000001'),'4.0000','anonymization preserves contribution value');
select is(
  (select count(*)::integer from public.business_events where request_id='cb000000-0000-0000-0000-000000000001'),
  1,
  'deleting command actor retains the immutable business event'
);
select is(
  (select actor_id from public.command_requests where request_id='cb000000-0000-0000-0000-000000000001'),
  null::uuid,
  'deleting command actor anonymizes the retained command ledger'
);

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(
  public.cmd_review_project_join_request(
    'c2000000-0000-0000-0000-000000000001',
    'ce000000-0000-0000-0000-000000000002',
    'approve',
    'cb000000-0000-0000-0000-000000000002',
    1
  )->>'code',
  'NOT_FOUND_OR_NOT_AUTHORIZED',
  'leader cannot approve an anonymized pending applicant into a NULL membership'
);
select ok(
  (public.cmd_create_contribution_report(
    'c2000000-0000-0000-0000-000000000002',
    'cb000000-0000-0000-0000-000000000003',
    1
  )->>'ok')::boolean,
  'completed work remains reportable after assignee anonymization'
);
reset role;
select is(
  (select member_user_id from public.contribution_items where project_id='c2000000-0000-0000-0000-000000000002'),
  null::uuid,
  'contribution snapshot preserves the deleted assignee anonymously'
);

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000010',true);
set local role authenticated;
select ok(
  (public.cmd_join_project_via_invite(
    'capacity-after-deletion',
    'cb000000-0000-0000-0000-000000000004',
    1
  )->>'ok')::boolean,
  'anonymized membership does not consume a live project capacity slot'
);
reset role;
select is(
  (select count(*)::integer from public.project_members
   where project_id='c2000000-0000-0000-0000-000000000003'
     and member_state='active' and user_id is not null),
  8,
  'capacity join fills the eighth live member slot exactly'
);

select lives_ok(
  $$delete from auth.users where id='c1000000-0000-0000-0000-000000000003'$$,
  'deleting reviewer anonymizes a terminal review without rewriting decision history'
);
select is((select reviewed_by from public.task_review_rounds where id='c7000000-0000-0000-0000-000000000001'),null::uuid,'terminal review reviewer is anonymized');
select is((select decision from public.task_review_rounds where id='c7000000-0000-0000-0000-000000000001'),'approve','review decision remains immutable after reviewer deletion');

-- Account-scoped command history must also survive auth-user deletion.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select public.cmd_create_project(
  'cc000000-0000-0000-0000-000000000001',0,'Historical account command',now()+interval '20 days',
  null,null,null,'weighted',false,false
);
reset role;
select is((select count(*)::integer from public.business_events where request_id='cc000000-0000-0000-0000-000000000001'),1,'account-scoped command creates linked business event');
select lives_ok(
  $$delete from auth.users where id='c1000000-0000-0000-0000-000000000004'$$,
  'deleting account-scoped command actor preserves command/event history'
);
select is((select count(*)::integer from public.command_requests where request_id='cc000000-0000-0000-0000-000000000001'),1,'account-scoped command ledger survives actor deletion');
select is((select actor_id from public.command_requests where request_id='cc000000-0000-0000-0000-000000000001'),null::uuid,'account-scoped command actor is anonymized');
select is((select account_id from public.command_requests where request_id='cc000000-0000-0000-0000-000000000001'),null::uuid,'account-scoped command account scope is anonymized');
select is((select count(*)::integer from public.business_events where request_id='cc000000-0000-0000-0000-000000000001'),1,'account-scoped business event survives actor deletion');

-- Composite foreign keys prevent cross-project report/task corruption even for privileged maintenance code.
select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.contribution_items'::regclass
    and c.conname='contribution_items_project_task_fkey'
    and c.confrelid='public.tasks'::regclass
    and array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','task_id']::text[]
    and array(select a.attname::text from unnest(c.confkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','id']::text[]
    and c.confdeltype='a' and c.confupdtype='a'
),'contribution item task FK binds exact project/task identity');

select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.contribution_items'::regclass
    and c.conname='contribution_items_project_report_fkey'
    and c.confrelid='public.contribution_reports'::regclass
    and array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','report_id']::text[]
    and array(select a.attname::text from unnest(c.confkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','id']::text[]
    and c.confdeltype='c' and c.confupdtype='a'
),'contribution item report FK binds exact project/report identity');

select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.contribution_confirmations'::regclass
    and c.conname='contribution_confirmations_project_report_fkey'
    and c.confrelid='public.contribution_reports'::regclass
    and array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','report_id']::text[]
    and array(select a.attname::text from unnest(c.confkey) with ordinality k(attnum,ord)
              join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum order by k.ord)
        = array['project_id','id']::text[]
    and c.confdeltype='c' and c.confupdtype='a'
),'confirmation FK binds exact project/report identity');

select ok(exists(
  select 1 from pg_constraint c
  where c.conrelid='public.file_upload_reservations'::regclass
    and c.conname='file_upload_reservations_actor_id_fkey'
    and c.confrelid='auth.users'::regclass
    and c.confdeltype='n' and c.confupdtype='a'
),'reservation uploader FK uses ON DELETE SET NULL for historical retention');

select * from finish();
rollback;
