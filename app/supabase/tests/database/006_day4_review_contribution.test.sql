begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_review_rounds','review rounds table exists');
select has_table('public','contribution_reports','contribution reports table exists');
select has_table('public','contribution_items','contribution items table exists');
select has_table('public','contribution_confirmations','contribution confirmations table exists');
select has_column('public','projects','lifecycle_state','projects have lifecycle state');
select has_column('public','projects','completed_at','projects have completed timestamp');
select has_column('public','contribution_reports','eligible_member_count','reports snapshot eligible member count');
select has_column('public','contribution_reports','required_confirmation_count','reports snapshot majority threshold');
select has_column('public','contribution_items','member_display_name_snapshot','contribution facts snapshot member display name');

select has_function('public','cmd_submit_task_for_review',array['uuid','uuid','text','uuid[]','uuid','integer'],'submit review RPC exists');
select has_function('public','cmd_review_task_submission',array['uuid','uuid','uuid','text','text','uuid','integer'],'review submission RPC exists');
select has_function('public','cmd_create_contribution_report',array['uuid','uuid','integer'],'create contribution report RPC exists');
select has_function('public','cmd_confirm_contribution_report',array['uuid','uuid','uuid','integer'],'confirm contribution report RPC exists');
select has_function('public','get_project_contribution_report',array['uuid'],'contribution report read RPC exists');
select has_function('public','get_project_report_export',array['uuid'],'contribution report export snapshot RPC exists');
select ok(not has_function_privilege('public','public.get_project_report_export(uuid)','EXECUTE'),'PUBLIC cannot read export snapshot');
select ok(not has_function_privilege('anon','public.get_project_report_export(uuid)','EXECUTE'),'anon cannot read export snapshot');
select ok(has_function_privilege('authenticated','public.get_project_report_export(uuid)','EXECUTE'),'authenticated can read authorized export snapshot');
select ok(not has_function_privilege('service_role','public.get_project_report_export(uuid)','EXECUTE'),'service role cannot bypass user-scoped export authorization');

select ok(
  (select count(*)=4 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname in ('cmd_submit_task_for_review','cmd_review_task_submission','cmd_create_contribution_report','cmd_confirm_contribution_report')
     and p.prosecdef
     and p.proconfig @> array['search_path=""']),
  'all Day 4 write RPCs are SECURITY DEFINER with empty search_path'
);
select ok(not has_function_privilege('public','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),'PUBLIC cannot submit review');
select ok(not has_function_privilege('anon','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),'anon cannot submit review');
select ok(has_function_privilege('authenticated','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),'authenticated can submit review');
select ok(not has_function_privilege('service_role','public.cmd_submit_task_for_review(uuid,uuid,text,uuid[],uuid,integer)','EXECUTE'),'service role cannot impersonate client submit command');
select ok(not has_table_privilege('authenticated','public.task_review_rounds','INSERT'),'authenticated cannot directly insert review rounds');
select ok(not has_table_privilege('authenticated','public.contribution_reports','UPDATE'),'authenticated cannot directly mutate reports');
select ok(not has_table_privilege('service_role','public.task_review_rounds','UPDATE'),'service role cannot bypass review RPC');
select ok(not has_table_privilege('service_role','public.contribution_items','INSERT'),'service role cannot forge contribution facts');

insert into auth.users(id,email) values
 ('a1000000-0000-0000-0000-000000000001','day4-leader@example.test'),
 ('a1000000-0000-0000-0000-000000000002','day4-member@example.test'),
 ('a1000000-0000-0000-0000-000000000003','day4-outsider@example.test');

insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('a2000000-0000-0000-0000-000000000001','Review project',now()+interval '10 days','weighted',
       'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','leader','active','Day4 Leader'),
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','member','active','Day4 Member');

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,is_direct_assignment,accepted_at,assignment_state,version)
values('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Deliverable',
       'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002',
       now()+interval '5 days','in_progress',3,false,now(), 'assigned',1);

insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,declared_mime_type,declared_size_bytes,state,expires_at,version
) values(
 'a4000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
 'a3000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002',
 'new_file','pending/a2000000-0000-0000-0000-000000000001/a4000000-0000-0000-0000-000000000001/report.pdf',
 'report.pdf','application/pdf',100,'finalized',now()+interval '1 hour',2
);
insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values('a5000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
       'a3000000-0000-0000-0000-000000000001','report.pdf','a1000000-0000-0000-0000-000000000002',1);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'a6000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001',
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 'a4000000-0000-0000-0000-000000000001',1,
 'pending/a2000000-0000-0000-0000-000000000001/a4000000-0000-0000-0000-000000000001/report.pdf',
 'report.pdf','application/pdf',100,repeat('a',64),'a1000000-0000-0000-0000-000000000002'
);
update public.task_files set current_version_id='a6000000-0000-0000-0000-000000000001' where id='a5000000-0000-0000-0000-000000000001';

create temporary table day4_results(label text primary key,result jsonb);
grant all on day4_results to authenticated;

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into day4_results values('submit-outsider',public.cmd_submit_task_for_review(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 null,array['a6000000-0000-0000-0000-000000000001']::uuid[],'a7000000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'code' from day4_results where label='submit-outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot submit another member task');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into day4_results values('submit-one',public.cmd_submit_task_for_review(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 null,array['a6000000-0000-0000-0000-000000000001']::uuid[],'a7000000-0000-0000-0000-000000000002',1));
insert into day4_results values('submit-one-replay',public.cmd_submit_task_for_review(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 null,array['a6000000-0000-0000-0000-000000000001']::uuid[],'a7000000-0000-0000-0000-000000000002',1));
insert into day4_results values('submit-one-reuse',public.cmd_submit_task_for_review(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 null,array['a6000000-0000-0000-0000-000000000001']::uuid[],'a7000000-0000-0000-0000-000000000002',99));
reset role;

select is((select result->>'ok' from day4_results where label='submit-one'),'true','assignee submits finalized file version');
select is((select result->>'replayed' from day4_results where label='submit-one-replay'),'true','identical submit replays');
select is((select result->>'code' from day4_results where label='submit-one-reuse'),'IDEMPOTENCY_KEY_REUSED','submit key reuse with changed payload fails');
select is((select status from public.tasks where id='a3000000-0000-0000-0000-000000000001'),'awaiting_review','submission moves task to awaiting review');
select ok((select first_submitted_at is not null from public.tasks where id='a3000000-0000-0000-0000-000000000001'),'first submission timestamp is frozen');
select is((select count(*)::integer from public.task_review_rounds where task_id='a3000000-0000-0000-0000-000000000001'),1,'submit replay creates one review round');
select is((select count(*)::integer from public.business_events where request_id='a7000000-0000-0000-0000-000000000002'),1,'submit emits one event exactly once');

select id::text as round_one_id from public.task_review_rounds where task_id='a3000000-0000-0000-0000-000000000001' and round_number=1 \gset
select first_submitted_at::text as first_submit_at from public.tasks where id='a3000000-0000-0000-0000-000000000001' \gset

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into day4_results values('self-review',public.cmd_review_task_submission(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',:'round_one_id',
 'approve',null,'a7000000-0000-0000-0000-000000000003',1));
reset role;
select is((select result->>'code' from day4_results where label='self-review'),'NOT_FOUND_OR_NOT_AUTHORIZED','assignee cannot approve own submission');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('reject-null-reason',public.cmd_review_task_submission(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',:'round_one_id',
 'reject',null,'a7000000-0000-0000-0000-000000000004',1));
insert into day4_results values('reject-one',public.cmd_review_task_submission(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',:'round_one_id',
 'reject','Needs revision','a7000000-0000-0000-0000-000000000005',1));
reset role;
select is((select result->>'code' from day4_results where label='reject-null-reason'),'VALIDATION_FAILED','reject requires explicit reason');
select is((select state from public.task_review_rounds where id=:'round_one_id'::uuid),'rejected','rejection seals review round');
select is((select rejection_reason from public.task_review_rounds where id=:'round_one_id'::uuid),'Needs revision','rejection reason retained');
select is((select status from public.tasks where id='a3000000-0000-0000-0000-000000000001'),'in_progress','rejection returns task to in progress');

select version::text as task_version_after_reject from public.tasks where id='a3000000-0000-0000-0000-000000000001' \gset
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into day4_results values('resubmit',public.cmd_submit_task_for_review(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',
 null,array['a6000000-0000-0000-0000-000000000001']::uuid[],'a7000000-0000-0000-0000-000000000006',:task_version_after_reject::integer));
reset role;
select is((select max(round_number) from public.task_review_rounds where task_id='a3000000-0000-0000-0000-000000000001'),2,'resubmission creates a new immutable round');
select is((select first_submitted_at::text from public.tasks where id='a3000000-0000-0000-0000-000000000001'),:'first_submit_at','resubmission preserves first_submitted_at');
select id::text as round_two_id from public.task_review_rounds where task_id='a3000000-0000-0000-0000-000000000001' and round_number=2 \gset

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('approve-two',public.cmd_review_task_submission(
 'a2000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',:'round_two_id',
 'approve',null,'a7000000-0000-0000-0000-000000000007',1));
reset role;
select is((select state from public.task_review_rounds where id=:'round_two_id'::uuid),'approved','authorized reviewer approves current round');
select is((select status from public.tasks where id='a3000000-0000-0000-0000-000000000001'),'completed','approval completes task');
select ok((select completed_at is not null from public.tasks where id='a3000000-0000-0000-0000-000000000001'),'approval records completion time');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into day4_results values('report-not-leader',public.cmd_create_contribution_report(
 'a2000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000008',1));
reset role;
select is((select result->>'code' from day4_results where label='report-not-leader'),'NOT_FOUND_OR_NOT_AUTHORIZED','only leader creates contribution report');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('report-create',public.cmd_create_contribution_report(
 'a2000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000009',1));
insert into day4_results values('report-replay',public.cmd_create_contribution_report(
 'a2000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000009',1));
reset role;
select is((select result->>'ok' from day4_results where label='report-create'),'true','leader creates contribution snapshot');
select is((select result->>'replayed' from day4_results where label='report-replay'),'true','report creation replays exactly');
select is((select lifecycle_state from public.projects where id='a2000000-0000-0000-0000-000000000001'),'contribution_review','report creation freezes project into contribution review');
select is((select count(*)::integer from public.contribution_reports where project_id='a2000000-0000-0000-0000-000000000001'),1,'one report per project');
select is((select count(*)::integer from public.contribution_items where project_id='a2000000-0000-0000-0000-000000000001'),1,'single completed task creates one contribution fact');
select is((select task_weight::text from public.contribution_items where project_id='a2000000-0000-0000-0000-000000000001'),'3.0000','task weight uses four-decimal authority');
select is((select share::text from public.contribution_items where project_id='a2000000-0000-0000-0000-000000000001'),'1.0000','single-assignee share is exactly one');
select is((select contribution_value::text from public.contribution_items where project_id='a2000000-0000-0000-0000-000000000001'),'3.0000','weighted contribution uses four-decimal authority');
select report_id::text as report_id from public.contribution_items where project_id='a2000000-0000-0000-0000-000000000001' limit 1 \gset
select is((select member_display_name_snapshot from public.contribution_items where report_id=:'report_id'::uuid),'Day4 Member','report creation freezes member display name');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.get_project_report_export(:'report_id'::uuid) as draft_export \gset
reset role;
select is((:'draft_export'::jsonb->>'statusLabel'),'DRAFT','draft export is visibly marked DRAFT');
select is((:'draft_export'::jsonb->>'disclaimer'),'仅供参考，不代表教师评分或成员能力评价','draft export carries the required disclaimer');
select is((:'draft_export'::jsonb->'items'->0->>'memberDisplayName'),'Day4 Member','draft export uses frozen member display name');
select is((:'draft_export'::jsonb->'items'->0->>'contributionValueAuthority'),'3.0000','draft export preserves four-decimal authority value');
select is((:'draft_export'::jsonb->'items'->0->>'contributionValueDisplay'),'3.00','draft export includes two-decimal display value');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('confirm-leader',public.cmd_confirm_contribution_report(
 'a2000000-0000-0000-0000-000000000001',:'report_id','a7000000-0000-0000-0000-000000000010',1));
reset role;
select is((select state from public.contribution_reports where id=:'report_id'::uuid),'draft','one of two eligible confirmations remains draft');
select is((select count(*)::integer from public.contribution_confirmations where report_id=:'report_id'::uuid),1,'first confirmation recorded once');

select version::text as report_version from public.contribution_reports where id=:'report_id'::uuid \gset
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into day4_results values('confirm-member',public.cmd_confirm_contribution_report(
 'a2000000-0000-0000-0000-000000000001',:'report_id','a7000000-0000-0000-0000-000000000011',:report_version::integer));
reset role;
select is((select state from public.contribution_reports where id=:'report_id'::uuid),'formal','strict majority formalizes contribution report');
select ok((select formalized_at is not null from public.contribution_reports where id=:'report_id'::uuid),'formalization timestamp recorded');
select is((select lifecycle_state from public.projects where id='a2000000-0000-0000-0000-000000000001'),'completed','formalization completes project');
select ok((select completed_at is not null from public.projects where id='a2000000-0000-0000-0000-000000000001'),'project completion timestamp recorded');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.get_project_report_export(:'report_id'::uuid) as formal_export \gset
reset role;
select is((:'formal_export'::jsonb->>'statusLabel'),'FORMAL','formal export is visibly marked FORMAL');
select ok((:'formal_export'::jsonb->>'formalizedAt') is not null,'formal export includes formalization timestamp');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select public.get_project_report_export(:'report_id'::uuid) as outsider_export \gset
reset role;
select is((:'outsider_export'::jsonb->>'code'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot read report export snapshot');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select lives_ok($$select public.get_project_contribution_report('a2000000-0000-0000-0000-000000000001')$$,'active member can read contribution report snapshot');
reset role;

select ok((select relrowsecurity from pg_class where oid='public.task_review_rounds'::regclass),'review rounds enable RLS');
select ok((select relrowsecurity from pg_class where oid='public.contribution_reports'::regclass),'reports enable RLS');
select ok((select relrowsecurity from pg_class where oid='public.contribution_items'::regclass),'items enable RLS');
select ok((select relrowsecurity from pg_class where oid='public.contribution_confirmations'::regclass),'confirmations enable RLS');

-- Terminal review rows must never rely on SQL CHECK's NULL-is-not-false behavior.
select throws_ok(
  $$insert into public.task_review_rounds(
      id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,
      state,decision,reviewed_at,version
    ) values(
      'af000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
      'a3000000-0000-0000-0000-000000000001',98,'a6000000-0000-0000-0000-000000000001',
      'a1000000-0000-0000-0000-000000000002','approved',null,now(),2
    )$$,
  '23514',
  null,
  'approved review requires an explicit approve decision'
);
select throws_ok(
  $$insert into public.task_review_rounds(
      id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,
      state,decision,rejection_reason,reviewed_at,version
    ) values(
      'af000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001',
      'a3000000-0000-0000-0000-000000000001',99,'a6000000-0000-0000-0000-000000000001',
      'a1000000-0000-0000-0000-000000000002','rejected',null,'reason',now(),2
    )$$,
  '23514',
  null,
  'rejected review requires an explicit reject or request_changes decision'
);
select throws_ok(
  $$insert into public.task_review_rounds(
      id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,
      state,decision,rejection_reason,reviewed_at,version
    ) values(
      'af000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001',
      'a3000000-0000-0000-0000-000000000001',100,'a6000000-0000-0000-0000-000000000001',
      'a1000000-0000-0000-0000-000000000002','rejected','reject','   ',now(),2
    )$$,
  '23514',
  null,
  'rejected review reason must contain non-whitespace text'
);

-- Contribution majority is frozen when the report snapshot is created.
insert into auth.users(id,email) values
 ('a1000000-0000-0000-0000-000000000004','day4-snapshot-member@example.test');
insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values('a2000000-0000-0000-0000-000000000002','Snapshot majority project',now()+interval '10 days','weighted',
       'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1);
insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values
 ('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','leader','active','Snapshot Leader'),
 ('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000004','member','active','Snapshot Member');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,assignment_state,accepted_at,first_submitted_at,completed_at,version)
values('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','Snapshot completed task',
       'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000004',
       now()+interval '5 days','completed',2,'assigned',now()-interval '3 hours',now()-interval '2 hours',now()-interval '1 hour',3);
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('snapshot-report-create',public.cmd_create_contribution_report(
 'a2000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000012',1));
reset role;
select result->'data'->>'reportId' as snapshot_report_id from day4_results where label='snapshot-report-create' \gset
select lives_ok(
 $$delete from auth.users where id='a1000000-0000-0000-0000-000000000004'$$,
 'member account deletion after report creation preserves the frozen report snapshot'
);
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into day4_results values('snapshot-confirm-leader',public.cmd_confirm_contribution_report(
 'a2000000-0000-0000-0000-000000000002',:'snapshot_report_id','a7000000-0000-0000-0000-000000000013',1));
reset role;
select is((select result->'data'->>'eligibleCount' from day4_results where label='snapshot-confirm-leader'),'2','confirmation keeps the report-creation eligible member count');
select is((select result->'data'->>'requiredCount' from day4_results where label='snapshot-confirm-leader'),'2','confirmation keeps the report-creation majority threshold');
select is((select result->'data'->>'formalized' from day4_results where label='snapshot-confirm-leader'),'false','one confirmation cannot formalize after a snapshotted member later deletes their account');
select is((select state from public.contribution_reports where id=:'snapshot_report_id'::uuid),'draft','member deletion does not lower an existing report majority threshold');
select is((select member_user_id from public.contribution_items where report_id=:'snapshot_report_id'::uuid),null::uuid,'deleted member id is anonymized in contribution history');
select is((select member_display_name_snapshot from public.contribution_items where report_id=:'snapshot_report_id'::uuid),'Snapshot Member','deleted member keeps frozen report display-name snapshot');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.get_project_report_export(:'snapshot_report_id'::uuid) as deleted_member_export \gset
reset role;
select is((:'deleted_member_export'::jsonb->'items'->0->>'memberDisplayName'),'Snapshot Member','export remains readable after member account deletion');
select ok((:'deleted_member_export'::jsonb->'items'->0->'memberUserId') = 'null'::jsonb,'export represents deleted member id as JSON null');

select * from finish();
rollback;
