begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column('public','task_review_rounds','delegation_required','review round stores delegation requirement');
select has_column('public','task_review_rounds','delegated_reviewer_id','review round stores per-round delegate');
select has_table('private','task_review_delegation_events','immutable review delegation audit exists');
select ok(not has_schema_privilege('authenticated','private','USAGE'),'review delegation audit is in a private schema');
select ok(not has_table_privilege('authenticated','private.task_review_delegation_events','INSERT')
  and not has_table_privilege('authenticated','private.task_review_delegation_events','UPDATE'),
  'clients cannot forge delegation records');
select ok(not has_function_privilege('authenticated','private.refresh_independent_review_delegate(uuid,text)','EXECUTE'),
  'browser cannot manually appoint itself a reviewer');

insert into auth.users(id,email) values
 ('f1000000-0000-0000-0000-000000000001','delegate-leader@example.test'),
 ('f1000000-0000-0000-0000-000000000002','delegate-member@example.test'),
 ('f1000000-0000-0000-0000-000000000003','delegate-observer@example.test'),
 ('f1000000-0000-0000-0000-000000000004','delegate-outsider@example.test'),
 ('f1000000-0000-0000-0000-000000000005','delegate-backup@example.test');

insert into public.projects(
  id,name,deadline_at,leader_id,created_by,lifecycle_state,version
) values(
 'f2000000-0000-0000-0000-000000000001','Delegate QA',
 now()+interval '30 days',
 'f1000000-0000-0000-0000-000000000001',
 'f1000000-0000-0000-0000-000000000001','active',1
);
insert into public.project_members(
  project_id,user_id,role,member_state,is_observer,display_name_snapshot
) values
 ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','leader','active',false,'Leader'),
 ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','member','active',false,'Reviewer'),
 ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000003','observer','active',true,'Observer');

insert into public.tasks(
  id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
  accepted_at,assignment_state,version
) values
 ('f3000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001',
  'Self assigned leader task','f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',now()+interval '5 days',
  'awaiting_review',1,now(),'assigned',1),
 ('f3000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001',
  'Followup self assigned','f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',now()+interval '5 days',
  'awaiting_review',1,now(),'assigned',1);

insert into public.task_review_rounds(
 id,project_id,task_id,round_number,submitted_file_version_id,
 submitted_by,submission_text_snapshot
) values
 ('f4000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001',1,null,
  'f1000000-0000-0000-0000-000000000001','Done'),
 ('f4000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000002',1,null,
  'f1000000-0000-0000-0000-000000000001','Done');

select ok((select delegation_required from public.task_review_rounds
  where id='f4000000-0000-0000-0000-000000000001'),
  'leader self submission requires independent review');
select is((select delegated_reviewer_id::text from public.task_review_rounds
  where id='f4000000-0000-0000-0000-000000000001'),
  'f1000000-0000-0000-0000-000000000002','only eligible member delegated');
select is((select count(*)::integer from private.task_review_delegation_events
  where review_round_id='f4000000-0000-0000-0000-000000000001'),1,
  'assignment recorded in append-only audit');

create temporary table delegate_results(label text primary key,result jsonb);
grant all on delegate_results to authenticated;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into delegate_results values('self',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'code' from delegate_results where label='self'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','leader cannot self-review');

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into delegate_results values('observer',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000002',1));
reset role;
select is((select result->>'code' from delegate_results where label='observer'),
 'NOT_AUTHORIZED','observer cannot review');

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into delegate_results values('outsider',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000003',1));
reset role;
select is((select result->>'code' from delegate_results where label='outsider'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot review');

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into delegate_results values('delegated_approve',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000004',1));
reset role;
select is((select result->>'ok' from delegate_results where label='delegated_approve'),
 'true','delegated member can approve only assigned round');
select is((select status from public.tasks where id='f3000000-0000-0000-0000-000000000001'),
 'completed','delegated approval completes task normally');
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into delegate_results values('approve_replay',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000004',1));
insert into delegate_results values('already_processed',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001',
 'approve',null,'f5000000-0000-0000-0000-000000000006',2));
reset role;
select is((select result->>'replayed' from delegate_results where label='approve_replay'),
 'true','delegated approval supports idempotent replay');
select is((select result->>'code' from delegate_results where label='already_processed'),
 'REVIEW_NOT_PENDING','new command cannot review a terminal round');


update public.project_members set member_state='removed'
where project_id='f2000000-0000-0000-0000-000000000001'
 and user_id='f1000000-0000-0000-0000-000000000002';
select ok((select delegation_required and delegated_reviewer_id is null
  from public.task_review_rounds where id='f4000000-0000-0000-0000-000000000002'),
 'unavailable candidate fails closed; no auto-approval');
select is((select status from public.tasks where id='f3000000-0000-0000-0000-000000000002'),
 'awaiting_review','waiting task remains pending');

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into delegate_results values('removed_delegate',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000002',
 'f4000000-0000-0000-0000-000000000002',
 'approve',null,'f5000000-0000-0000-0000-000000000005',1));
reset role;
select ok((select result->>'code' from delegate_results where label='removed_delegate')
  in ('NOT_AUTHORIZED','NOT_FOUND_OR_NOT_AUTHORIZED'),
  'removed delegate no longer has review capability');

select throws_ok(
  $$update private.task_review_delegation_events
    set reason='forged' where review_round_id='f4000000-0000-0000-0000-000000000002'$$,
  '55000',null,'delegation audit is immutable');

insert into public.project_members(
 project_id,user_id,role,member_state,is_observer,display_name_snapshot
) values (
 'f2000000-0000-0000-0000-000000000001',
 'f1000000-0000-0000-0000-000000000005',
 'member','active',false,'Backup'
);
select is((select delegated_reviewer_id::text from public.task_review_rounds
  where id='f4000000-0000-0000-0000-000000000002'),
 'f1000000-0000-0000-0000-000000000005',
 'joining independent member rescues previously unreviewable pending round');

select * from finish();
rollback;
