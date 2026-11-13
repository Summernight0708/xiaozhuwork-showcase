begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('e1000000-0000-0000-0000-000000000001','dependency-guard-leader@example.test'),
 ('e1000000-0000-0000-0000-000000000002','dependency-guard-member@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values(
 'e2000000-0000-0000-0000-000000000001','Dependency review guard',now()+interval '30 days',
 'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',1
);

insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','leader','active','Guard Leader'),
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','member','active','Guard Member');

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,is_direct_assignment,
 accepted_at,assignment_state,version
) values
 (
  'e3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','Upstream',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  now()+interval '10 days','in_progress',false,now(),'assigned',1
 ),
 (
  'e3000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','Downstream',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002',
  now()+interval '20 days','in_progress',false,now(),'assigned',1
 );

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
values(
 'e2000000-0000-0000-0000-000000000001',
 'e3000000-0000-0000-0000-000000000001',
 'e3000000-0000-0000-0000-000000000002',
 'e1000000-0000-0000-0000-000000000001'
);

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,
 declared_size_bytes,state,expires_at,version
) values(
 'e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
 'e3000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002',
 'new_file','pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000001/work.pdf',
 'work.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2
);

insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values(
 'e5000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
 'e3000000-0000-0000-0000-000000000002','work.pdf','e1000000-0000-0000-0000-000000000002',1
);

insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,
 mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'e6000000-0000-0000-0000-000000000001','e5000000-0000-0000-0000-000000000001',
 'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',
 'e4000000-0000-0000-0000-000000000001',1,
 'pending/e2000000-0000-0000-0000-000000000001/e4000000-0000-0000-0000-000000000001/work.pdf',
 'work.pdf','application/pdf',100,repeat('e',64),'e1000000-0000-0000-0000-000000000002'
);
update public.task_files
set current_version_id='e6000000-0000-0000-0000-000000000001'
where id='e5000000-0000-0000-0000-000000000001';

create temporary table dependency_guard_results(label text primary key,result jsonb);
grant all on dependency_guard_results to authenticated;

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dependency_guard_results values(
 'blocked-submit',
 public.cmd_submit_task_for_review(
  'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000002',
  null,
  array['e6000000-0000-0000-0000-000000000001']::uuid[],
  'e7000000-0000-0000-0000-000000000001',
  1
 )
);
reset role;

select is(
 (select result->>'ok' from dependency_guard_results where label='blocked-submit'),
 'true',
 'unfinished upstream no longer blocks downstream submission'
);
select is(
 (select status from public.tasks where id='e3000000-0000-0000-0000-000000000002'),
 'awaiting_review',
 'downstream enters awaiting_review while upstream is still incomplete'
);
select is(
 (select count(*)::integer from public.task_review_rounds
  where task_id='e3000000-0000-0000-0000-000000000002' and state='pending'),
 1,
 'downstream creates one pending manual review round'
);
select is(
 (select status from public.tasks where id='e3000000-0000-0000-0000-000000000001'),
 'in_progress',
 'upstream remains unfinished during downstream submission'
);

select id::text as dependency_guard_round_id
from public.task_review_rounds
where task_id='e3000000-0000-0000-0000-000000000002'
  and state='pending' \gset

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into dependency_guard_results values(
 'early-approve',
 public.cmd_review_task_submission(
  'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000002',
  :'dependency_guard_round_id'::uuid,
  'approve',
  null,
  'e7000000-0000-0000-0000-000000000003',
  1
 )
);
reset role;

select is(
 (select result->>'ok' from dependency_guard_results where label='early-approve'),
 'true',
 'manual review approval is allowed before upstream completion'
);
select is(
 (select status from public.tasks where id='e3000000-0000-0000-0000-000000000002'),
 'completed',
 'manual approval completes downstream with incomplete upstream'
);
select is(
 (select state from public.task_review_rounds where id=:'dependency_guard_round_id'::uuid),
 'approved',
 'manual approval is auditable as approved, not auto-completed'
);
select is(
 (select status from public.tasks where id='e3000000-0000-0000-0000-000000000001'),
 'in_progress',
 'upstream is not implicitly changed by downstream approval'
);

-- A separately configured no-review task uses the SAME evidence-preserving
-- submission RPC but never invents an approver, decision, or pending review.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into dependency_guard_results values(
 'created-no-review',
 public.cmd_create_task(
  p_project_id=>'e2000000-0000-0000-0000-000000000001'::uuid,
  p_request_id=>'e7000000-0000-0000-0000-000000000011'::uuid,
  p_expected_version=>1,
  p_title=>'No review task',
  p_description=>'Lightweight downstream task',
  p_deadline_at=>now()+interval '15 days',
  p_weight=>3::smallint,
  p_assignment_mode=>'direct',
  p_assignee_id=>'e1000000-0000-0000-0000-000000000002'::uuid,
  p_required_submission_file_type=>null,
  p_requires_review=>false
 )
);
reset role;

select is(
 (select result->>'ok' from dependency_guard_results where label='created-no-review'),
 'true',
 'task creation RPC accepts requiresReview=false'
);

select (result->'data'->>'taskId') as no_review_task_id
from dependency_guard_results where label='created-no-review' \gset

select is(
 (select requires_review from public.tasks where id=:'no_review_task_id'::uuid),
 false,
 'new no-review flag is stored in the authoritative task record'
);
select is(
 (select requires_review from public.tasks where id='e3000000-0000-0000-0000-000000000002'),
 true,
 'existing tasks default to manual review'
);

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
values(
 'e2000000-0000-0000-0000-000000000001',
 'e3000000-0000-0000-0000-000000000001',
 :'no_review_task_id'::uuid,
 'e1000000-0000-0000-0000-000000000001'
);
update public.tasks
set assignee_id='e1000000-0000-0000-0000-000000000002',
    assignment_state='assigned',status='in_progress',accepted_at=now()
where id=:'no_review_task_id'::uuid;

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dependency_guard_results values(
 'submit-no-review',
 public.cmd_submit_task_for_review(
  'e2000000-0000-0000-0000-000000000001',
  :'no_review_task_id'::uuid,
  'Completed with a text-only evidence snapshot',
  array[]::uuid[],
  'e7000000-0000-0000-0000-000000000012',
  1
 )
);
reset role;

select is(
 (select result->>'ok' from dependency_guard_results where label='submit-no-review'),
 'true',
 'no-review text-only submission succeeds with unfinished upstream'
);
select is(
 (select result->'data'->>'autoCompleted' from dependency_guard_results where label='submit-no-review'),
 'true',
 'submission result identifies auto completion'
);
select is(
 (select status from public.tasks where id=:'no_review_task_id'::uuid),
 'completed',
 'no-review submission transitions directly to completed'
);
select ok(
 (select completed_at is not null and first_submitted_at is not null
  from public.tasks where id=:'no_review_task_id'::uuid),
 'auto-completed tasks retain completion and first submission timestamps'
);
select is(
 (select state from public.task_review_rounds where task_id=:'no_review_task_id'::uuid),
 'completed_without_review',
 'immutable evidence round records no-review completion distinctly'
);
select ok(
 (select reviewed_by is null and reviewed_at is null and decision is null
     and submission_text_snapshot='Completed with a text-only evidence snapshot'
  from public.task_review_rounds where task_id=:'no_review_task_id'::uuid),
 'auto-completion retains evidence without forging a reviewer or decision'
);
select is(
 (select count(*)::integer from public.task_review_rounds
  where task_id=:'no_review_task_id'::uuid and state='pending'),
 0,
 'no manual review is queued for no-review submissions'
);
select is(
 (select count(*)::integer from public.task_first_submission_facts
  where task_id=:'no_review_task_id'::uuid),
 1,
 'G lifecycle first-submission provenance remains authoritative'
);
select ok(
 exists(select 1 from public.business_events where entity_type='task_review_round'
  and event_type='task_submitted_without_review'
  and (event_data->>'taskId')=:'no_review_task_id'::text),
 'audit identifies automatic completion separately from approval'
);

select * from finish();
rollback;
