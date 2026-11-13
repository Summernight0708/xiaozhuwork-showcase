begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_primary_handoffs','primary handoff table exists');
select has_function(
  'public','cmd_request_task_primary_handoff',
  array['uuid','uuid','uuid','uuid','integer'],
  'request primary handoff command exists'
);
select has_function(
  'public','cmd_respond_task_primary_handoff',
  array['uuid','uuid','uuid','text','uuid','integer','integer'],
  'respond primary handoff command exists'
);
select has_function(
  'public','cmd_cancel_task_primary_handoff',
  array['uuid','uuid','uuid','uuid','integer','integer'],
  'cancel primary handoff command exists'
);
select has_function(
  'public','cmd_unassign_task_primary',
  array['uuid','uuid','uuid','integer'],
  'unassign primary command exists'
);
select has_function(
  'public','cmd_correct_task_review_request_changes',
  array['uuid','uuid','uuid','uuid','integer','integer'],
  'review correction command exists'
);
select has_column(
  'public','task_review_rounds','correction_of_review_round_id',
  'review rounds record correction provenance'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.task_primary_handoffs'::regclass),
  'primary handoffs enable RLS'
);
select ok(
  has_table_privilege('authenticated','public.task_primary_handoffs_visible','SELECT'),
  'authenticated members can read privacy-safe handoffs through scoped view'
);
select ok(
  not has_table_privilege('authenticated','public.task_primary_handoffs','INSERT')
  and not has_table_privilege('authenticated','public.task_primary_handoffs','UPDATE')
  and not has_table_privilege('authenticated','public.task_primary_handoffs','DELETE'),
  'browser cannot directly mutate primary handoffs'
);

insert into auth.users(id,email) values
 ('e1000000-0000-0000-0000-000000000001','authority-leader@example.test'),
 ('e1000000-0000-0000-0000-000000000002','authority-creator@example.test'),
 ('e1000000-0000-0000-0000-000000000003','authority-primary@example.test'),
 ('e1000000-0000-0000-0000-000000000004','authority-target@example.test'),
 ('e1000000-0000-0000-0000-000000000005','authority-observer@example.test'),
 ('e1000000-0000-0000-0000-000000000006','authority-removed@example.test'),
 ('e1000000-0000-0000-0000-000000000007','authority-outsider@example.test'),
 ('e1000000-0000-0000-0000-000000000008','authority-other-member@example.test');

update public.profiles set display_name='组长' where id='e1000000-0000-0000-0000-000000000001';
update public.profiles set display_name='创建者' where id='e1000000-0000-0000-0000-000000000002';
update public.profiles set display_name='原主负责人' where id='e1000000-0000-0000-0000-000000000003';
update public.profiles set display_name='新主负责人' where id='e1000000-0000-0000-0000-000000000004';

insert into public.projects(
  id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values
 (
  'e2000000-0000-0000-0000-000000000001','Authority project',now()+interval '30 days',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  1,'weighted','active'
 ),
 (
  'e2000000-0000-0000-0000-000000000002','Other authority project',now()+interval '30 days',
  'e1000000-0000-0000-0000-000000000008','e1000000-0000-0000-0000-000000000008',
  1,'weighted','active'
 ),
 (
  'e2000000-0000-0000-0000-000000000003','Create authority project',now()+interval '30 days',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
  1,'weighted','active'
 );

insert into public.project_members(
  id,project_id,user_id,role,member_state,is_observer,version,departed_at,display_name_snapshot
) values
 ('e3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','leader','active',false,1,null,'组长'),
 ('e3000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','member','active',false,1,null,'创建者'),
 ('e3000000-0000-0000-0000-000000000003','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003','member','active',false,1,null,'原主负责人'),
 ('e3000000-0000-0000-0000-000000000004','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000004','member','active',false,1,null,'新主负责人'),
 ('e3000000-0000-0000-0000-000000000005','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000005','observer','active',true,1,null,'观察者'),
 ('e3000000-0000-0000-0000-000000000006','e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000006','member','removed',false,2,now()-interval '1 day','已移除'),
 ('e3000000-0000-0000-0000-000000000008','e2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000008','leader','active',false,1,null,'其他组长'),
 ('e3000000-0000-0000-0000-000000000011','e2000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000001','leader','active',false,1,null,'组长'),
 ('e3000000-0000-0000-0000-000000000012','e2000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000002','member','active',false,1,null,'创建者'),
 ('e3000000-0000-0000-0000-000000000013','e2000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000005','observer','active',true,1,null,'观察者'),
 ('e3000000-0000-0000-0000-000000000014','e2000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000006','member','removed',false,2,now()-interval '1 day','已移除');

insert into public.tasks(
  id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
  accepted_at,assignment_state,progress_text,version
) values
 ('e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','Transfer task','e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',3,now()-interval '1 day','assigned','已有进度',1),
 ('e4000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','Unassign task','e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now()-interval '1 day','assigned','旧负责人进度',1),
 ('e4000000-0000-0000-0000-000000000003','e2000000-0000-0000-0000-000000000001','Review correction task','e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now()-interval '2 days','assigned',null,4),
 ('e4000000-0000-0000-0000-000000000004','e2000000-0000-0000-0000-000000000001','Change pending task','e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now()-interval '1 day','assigned',null,1),
 ('e4000000-0000-0000-0000-000000000005','e2000000-0000-0000-0000-000000000001','History locked task','e1000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now()-interval '1 day','assigned',null,1);

insert into public.task_collaborators(
  id,project_id,task_id,user_id,user_name_snapshot,state,invited_by,
  invited_by_name_snapshot,responded_at,version
) values(
  'e5000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000004',
  '新主负责人','accepted','e1000000-0000-0000-0000-000000000002','创建者',
  now()-interval '1 hour',2
);

insert into public.task_change_proposals(
  id,project_id,task_id,proposed_by,proposer_name_snapshot,state,
  old_deadline_at,new_deadline_at,old_weight,new_weight,base_task_version,
  required_confirmer_id,required_confirmer_name_snapshot,version
) select
  'e6000000-0000-0000-0000-000000000001',
  project_id,id,created_by,'创建者','pending',
  deadline_at,deadline_at+interval '1 day',weight,weight,version,
  assignee_id,'原主负责人',1
from public.tasks where id='e4000000-0000-0000-0000-000000000004';

insert into public.task_review_rounds(
  id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,
  submitted_at,state,decision,reviewed_by,reviewed_at,rejection_reason,version,
  submission_text_snapshot,required_submission_file_type_snapshot
) values
 (
  'e7000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000003',
  1,null,'e1000000-0000-0000-0000-000000000003',
  now()-interval '2 hours','rejected','request_changes',
  'e1000000-0000-0000-0000-000000000002',now()-interval '1 hour',
  '误点了要求修改',2,'原始提交说明',null
 ),
 (
  'e7000000-0000-0000-0000-000000000002',
  'e2000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000005',
  1,null,'e1000000-0000-0000-0000-000000000003',
  now()-interval '2 hours','rejected','request_changes',
  'e1000000-0000-0000-0000-000000000002',now()-interval '1 hour',
  '历史验收',2,'历史提交',null
 );

update public.tasks
set first_submitted_at=now()-interval '2 hours'
where id in ('e4000000-0000-0000-0000-000000000003','e4000000-0000-0000-0000-000000000005');

insert into public.business_events(
  project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data
) values(
  'e2000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000002',
  'task_submission_changes_requested','task_review_round',
  'e7000000-0000-0000-0000-000000000001',
  'e9000000-0000-0000-0000-000000000001',
  jsonb_build_object(
    'taskId','e4000000-0000-0000-0000-000000000003',
    'action','request_changes','reason','误点了要求修改','taskVersion',4
  )
);

create temporary table authority_results(label text primary key,result jsonb);
grant all on authority_results to authenticated;

-- Bug #10: server authority aligns with active non-observer membership.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into authority_results values('create-ok',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000010',1,
  'Authorized create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
insert into authority_results values('create-replay',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000010',1,
  'Authorized create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
insert into authority_results values('create-stale',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000011',1,
  'Stale create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
reset role;

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into authority_results values('create-observer',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000012',2,
  'Observer create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
reset role;

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000006',true);
set local role authenticated;
insert into authority_results values('create-removed',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000013',2,
  'Removed create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
reset role;

select is((select result->>'ok' from authority_results where label='create-ok'),'true','active member creates task');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000007',true);
set local role authenticated;
insert into authority_results values('create-outsider',public.cmd_create_task(
  'e2000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000014',2,
  'Outsider create',null,now()+interval '5 days',2::smallint,'claimable',null,null
));
reset role;

select is((select result->>'replayed' from authority_results where label='create-replay'),'true','create request id replay is idempotent');
select is((select result->>'code' from authority_results where label='create-stale'),'STALE_VERSION','stale project version is explicit');
select is((select result->>'code' from authority_results where label='create-observer'),'NOT_AUTHORIZED','observer is read only');
select is((select result->>'code' from authority_results where label='create-removed'),'NOT_FOUND_OR_NOT_AUTHORIZED','removed member cannot create');
select is((select result->>'code' from authority_results where label='create-outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','wrong-project outsider cannot create');

-- Bug #17: request/accept promotes a collaborator to primary atomically.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into authority_results values('handoff-request',public.cmd_request_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000004','e9000000-0000-0000-0000-000000000020',1
));
insert into authority_results values('handoff-request-replay',public.cmd_request_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000004','e9000000-0000-0000-0000-000000000020',1
));
reset role;

select is((select result->>'ok' from authority_results where label='handoff-request'),'true','current primary requests handoff');
select is((select result->>'replayed' from authority_results where label='handoff-request-replay'),'true','handoff request replay is idempotent');
select is((select state from public.task_primary_handoffs where task_id='e4000000-0000-0000-0000-000000000001'),'pending','handoff starts pending');
select is((select assignee_id from public.tasks where id='e4000000-0000-0000-0000-000000000001'),'e1000000-0000-0000-0000-000000000003'::uuid,'source remains primary until accept');

select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into authority_results values('handoff-accept',public.cmd_respond_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001',
  (select id from public.task_primary_handoffs where task_id='e4000000-0000-0000-0000-000000000001'),
  'accept','e9000000-0000-0000-0000-000000000021',1,1
));
reset role;

select is((select result->>'ok' from authority_results where label='handoff-accept'),'true','target accepts primary handoff');
select is((select assignee_id from public.tasks where id='e4000000-0000-0000-0000-000000000001'),'e1000000-0000-0000-0000-000000000004'::uuid,'target becomes primary');
select is((select version from public.tasks where id='e4000000-0000-0000-0000-000000000001'),2,'accepted handoff increments task version once');
select is((select state from public.task_collaborators where id='e5000000-0000-0000-0000-000000000001'),'removed','promoted collaborator exits active collaborator role');
select ok(
  exists(
    select 1 from public.notifications
    where notification_type='task_primary_handoff_requested'
      and recipient_id='e1000000-0000-0000-0000-000000000004'
  ),
  'handoff target receives request notification'
);

-- Unsafe target identities fail closed.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into authority_results values('handoff-observer-target',public.cmd_request_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
  'e1000000-0000-0000-0000-000000000005','e9000000-0000-0000-0000-000000000022',1
));
insert into authority_results values('handoff-removed-target',public.cmd_request_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
  'e1000000-0000-0000-0000-000000000006','e9000000-0000-0000-0000-000000000023',1
));
insert into authority_results values('handoff-outsider-target',public.cmd_request_task_primary_handoff(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
  'e1000000-0000-0000-0000-000000000007','e9000000-0000-0000-0000-000000000024',1
));
reset role;
select is((select result->>'code' from authority_results where label='handoff-observer-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','observer cannot become primary');
select is((select result->>'code' from authority_results where label='handoff-removed-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','removed member cannot become primary');
select is((select result->>'code' from authority_results where label='handoff-outsider-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot become primary');

-- Voluntary unassign returns task to claimable without rewriting dependency/history facts.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into authority_results values('unassign',public.cmd_unassign_task_primary(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
  'e9000000-0000-0000-0000-000000000030',1
));
insert into authority_results values('unassign-replay',public.cmd_unassign_task_primary(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000002',
  'e9000000-0000-0000-0000-000000000030',1
));
insert into authority_results values('unassign-pending-change',public.cmd_unassign_task_primary(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004',
  'e9000000-0000-0000-0000-000000000031',1
));
insert into authority_results values('unassign-review-history',public.cmd_unassign_task_primary(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000005',
  'e9000000-0000-0000-0000-000000000032',1
));
reset role;

select is((select result->>'ok' from authority_results where label='unassign'),'true','primary can voluntarily unassign safe task');
select is((select result->>'replayed' from authority_results where label='unassign-replay'),'true','unassign replay is idempotent');
select is((select assignment_state from public.tasks where id='e4000000-0000-0000-0000-000000000002'),'claimable','unassigned task becomes claimable');
select is((select assignee_id from public.tasks where id='e4000000-0000-0000-0000-000000000002'),null::uuid,'unassigned task has no primary');
select is((select status from public.tasks where id='e4000000-0000-0000-0000-000000000002'),'not_started','unassigned task resets stored status');
select is((select progress_text from public.tasks where id='e4000000-0000-0000-0000-000000000002'),null::text,'unassigned task clears old primary progress');
select is((select result->'details'->>'reason' from authority_results where label='unassign-pending-change'),'task_change_pending','pending task change blocks unassign');
select is((select result->>'code' from authority_results where label='unassign-review-history'),'INVALID_TRANSITION','review history permanently blocks unassign');

-- Bug #13: correction is append-only and keeps the mistaken round immutable.
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into authority_results values('review-correction',public.cmd_correct_task_review_request_changes(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000003',
  'e7000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000040',4,2
));
insert into authority_results values('review-correction-replay',public.cmd_correct_task_review_request_changes(
  'e2000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000003',
  'e7000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000040',4,2
));
reset role;

select is((select result->>'ok' from authority_results where label='review-correction'),'true','original reviewer opens correction review');
select is((select result->>'replayed' from authority_results where label='review-correction-replay'),'true','review correction replay is idempotent');
select is((select state from public.task_review_rounds where id='e7000000-0000-0000-0000-000000000001'),'rejected','mistaken source round stays terminal');
select is((select decision from public.task_review_rounds where id='e7000000-0000-0000-0000-000000000001'),'request_changes','mistaken decision is not rewritten');
select is((select version from public.task_review_rounds where id='e7000000-0000-0000-0000-000000000001'),2,'source review version stays unchanged');
select is(
  (select count(*)::integer from public.task_review_rounds
   where task_id='e4000000-0000-0000-0000-000000000003'
     and state='pending'
     and correction_of_review_round_id='e7000000-0000-0000-0000-000000000001'),
  1,
  'correction appends one new pending review round'
);
select is((select status from public.tasks where id='e4000000-0000-0000-0000-000000000003'),'awaiting_review','correction puts same submission back under review');
select is((select version from public.tasks where id='e4000000-0000-0000-0000-000000000003'),5,'correction increments task version exactly once');

select throws_ok(
  $$update public.task_review_rounds set rejection_reason='篡改' where id='e7000000-0000-0000-0000-000000000001'$$,
  '55000','Terminal task review rounds are immutable',
  'terminal mistaken review remains immutable'
);

select * from finish();
rollback;
