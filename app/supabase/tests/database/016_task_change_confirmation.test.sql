begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_change_proposals','task change proposal truth exists');
select has_function(
  'public','cmd_propose_task_change',
  array['uuid','uuid','timestamp with time zone','smallint','uuid','integer','text'],
  'proposal command exists'
);
select has_function(
  'public','cmd_respond_to_task_change',
  array['uuid','uuid','uuid','text','text','uuid','integer'],
  'response command exists'
);
select ok((select relrowsecurity from pg_class where oid='public.task_change_proposals'::regclass),'proposal truth enables RLS');
select ok(has_table_privilege('authenticated','public.task_change_proposals_visible','SELECT'),'members may read privacy-safe proposal truth through authorized view');
select ok(not has_table_privilege('authenticated','public.task_change_proposals','INSERT'),'browser cannot insert proposal truth');
select ok(not has_table_privilege('authenticated','public.task_change_proposals','UPDATE'),'browser cannot update proposal truth');
select ok(not has_table_privilege('authenticated','public.task_change_proposals','DELETE'),'browser cannot delete proposal truth');
select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='cmd_propose_task_change'),
  'propose RPC is SECURITY DEFINER with empty search_path'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='cmd_respond_to_task_change'),
  'respond RPC is SECURITY DEFINER with empty search_path'
);

insert into auth.users(id,email) values
 ('c1000000-0000-0000-0000-000000000001','change-leader@example.test'),
 ('c1000000-0000-0000-0000-000000000002','change-creator@example.test'),
 ('c1000000-0000-0000-0000-000000000003','change-assignee@example.test'),
 ('c1000000-0000-0000-0000-000000000004','change-other@example.test'),
 ('c1000000-0000-0000-0000-000000000005','change-observer@example.test'),
 ('c1000000-0000-0000-0000-000000000006','change-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state)
values(
 'c2000000-0000-0000-0000-000000000001','Change confirmation',now()+interval '20 days',
 'c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',1,'weighted','active'
);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version,departed_at) values
 ('c3000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','leader','active',false,1,null),
 ('c3000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','member','active',false,1,null),
 ('c3000000-0000-0000-0000-000000000003','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','member','active',false,1,null),
 ('c3000000-0000-0000-0000-000000000004','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000004','admin','active',false,1,null),
 ('c3000000-0000-0000-0000-000000000005','c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000005','observer','active',true,1,null);

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version
) values
 ('c4000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','Accepted task','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '5 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001','Reject task','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '6 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000003','c2000000-0000-0000-0000-000000000001','Responsibility changes','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '7 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000004','c2000000-0000-0000-0000-000000000001','Review locked','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '8 days','awaiting_review',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000005','c2000000-0000-0000-0000-000000000001','No-op task','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '9 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000006','c2000000-0000-0000-0000-000000000001','Activity-only weight','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '9 days','not_started',2,null,'assigned',1),
 ('c4000000-0000-0000-0000-000000000007','c2000000-0000-0000-0000-000000000001','Removed confirmer','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '9 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('c4000000-0000-0000-0000-000000000008','c2000000-0000-0000-0000-000000000001','Inactive project','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003',now()+interval '9 days','in_progress',2,now()-interval '1 day','assigned',1);

update public.tasks set progress_text='work already started' where id='c4000000-0000-0000-0000-000000000006';

create temporary table change_results(label text primary key,result jsonb);
grant all on change_results to authenticated;

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into change_results values('create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000001',1
));
insert into change_results values('create-replay',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000001',1
));
insert into change_results values('create-reuse',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 now()+interval '10 days',4::smallint,'c9000000-0000-0000-0000-000000000001',1
));
insert into change_results values('second-pending',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 now()+interval '11 days',4::smallint,'c9000000-0000-0000-0000-000000000002',1
));
insert into change_results values('noop',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000005',
 (select deadline_at from public.tasks where id='c4000000-0000-0000-0000-000000000005'),2::smallint,
 'c9000000-0000-0000-0000-000000000003',1
));
insert into change_results values('past-deadline',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()-interval '1 minute',3::smallint,'c9000000-0000-0000-0000-000000000004',1
));
insert into change_results values('project-deadline',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()+interval '30 days',3::smallint,'c9000000-0000-0000-0000-000000000005',1
));
insert into change_results values('stale-task',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000006',0
));
insert into change_results values('locked',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000004',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000007',1
));
reset role;

select is((select result->>'ok' from change_results where label='create'),'true','creator creates proposal');
select is((select result->>'replayed' from change_results where label='create-replay'),'true','identical create replays');
select is((select result->>'code' from change_results where label='create-reuse'),'IDEMPOTENCY_KEY_REUSED','request id mismatch rejected');
select is((select result->>'code' from change_results where label='second-pending'),'INVALID_TRANSITION','second pending proposal rejected');
select is((select result->>'code' from change_results where label='noop'),'VALIDATION_FAILED','no-op proposal rejected');
select is((select result->>'code' from change_results where label='past-deadline'),'DDL_NOT_IN_FUTURE','past deadline rejected');
select is((select result->>'code' from change_results where label='project-deadline'),'DDL_NOT_IN_FUTURE','deadline beyond project rejected');
select is((select result->>'code' from change_results where label='stale-task'),'STALE_VERSION','stale task version rejected');
select is((select result->>'code' from change_results where label='locked'),'INVALID_TRANSITION','review task definition locked');
select is((select deadline_at from public.tasks where id='c4000000-0000-0000-0000-000000000001'),now()+interval '5 days','proposal does not immediately change deadline');
select is((select weight from public.tasks where id='c4000000-0000-0000-0000-000000000001'),2::smallint,'proposal does not immediately change weight');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),'pending','proposal is pending');
select is((select required_confirmer_id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),'c1000000-0000-0000-0000-000000000003'::uuid,'assignee snapshot is durable');
select is((select base_task_version from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),1,'base task version stored');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into change_results values('observer',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000008',1
));
reset role;
select is((select result->>'code' from change_results where label='observer'),'NOT_AUTHORIZED','observer is read only');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000006',true);
set local role authenticated;
insert into change_results values('outsider',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()+interval '10 days',3::smallint,'c9000000-0000-0000-0000-000000000009',1
));
reset role;
select is((select result->>'code' from change_results where label='outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot propose');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into change_results values('unrelated-approve',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),
 'approve',null,'c9000000-0000-0000-0000-000000000010',1
));
reset role;
select is((select result->>'code' from change_results where label='unrelated-approve'),'NOT_FOUND_OR_NOT_AUTHORIZED','only required assignee can decide');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into change_results values('approve',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),
 'approve',null,'c9000000-0000-0000-0000-000000000011',1
));
insert into change_results values('approve-replay',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),
 'approve',null,'c9000000-0000-0000-0000-000000000011',1
));
insert into change_results values('approve-reuse',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),
 'reject','changed','c9000000-0000-0000-0000-000000000011',1
));
reset role;

select is((select result->>'ok' from change_results where label='approve'),'true','assignee approves');
select is((select result->>'replayed' from change_results where label='approve-replay'),'true','decision replay is idempotent');
select is((select result->>'code' from change_results where label='approve-reuse'),'IDEMPOTENCY_KEY_REUSED','decision payload mismatch rejected');
select is((select weight from public.tasks where id='c4000000-0000-0000-0000-000000000001'),3::smallint,'approval atomically applies weight');
select is((select deadline_at from public.tasks where id='c4000000-0000-0000-0000-000000000001'),now()+interval '10 days','approval atomically applies deadline');
select is((select version from public.tasks where id='c4000000-0000-0000-0000-000000000001'),2,'approval increments task version exactly once');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),'approved','proposal approved');
select is((select version from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000001'),2,'proposal version increments once');
select ok((select accepted_at > now()-interval '1 minute' from public.tasks where id='c4000000-0000-0000-0000-000000000001'),'confirmation resets effective start');
select is((select count(*)::integer from public.notifications where notification_type='task_change_confirmation' and recipient_id='c1000000-0000-0000-0000-000000000003'),1,'proposal notifies assignee exactly once');
select is((select count(*)::integer from public.notifications where notification_type='task_change_approved' and recipient_id='c1000000-0000-0000-0000-000000000002'),1,'approval notifies proposer exactly once');

-- Reject path leaves task definition untouched.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into change_results values('leader-create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 now()+interval '12 days',4::smallint,'c9000000-0000-0000-0000-000000000012',1
));
reset role;
select is((select result->>'ok' from change_results where label='leader-create'),'true','leader can propose');

select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into change_results values('reject',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000002'),
 'reject','暂不同意','c9000000-0000-0000-0000-000000000013',1
));
reset role;
select is((select result->>'ok' from change_results where label='reject'),'true','assignee can reject');
select is((select deadline_at from public.tasks where id='c4000000-0000-0000-0000-000000000002'),now()+interval '6 days','reject keeps deadline');
select is((select weight from public.tasks where id='c4000000-0000-0000-0000-000000000002'),2::smallint,'reject keeps weight');
select is((select version from public.tasks where id='c4000000-0000-0000-0000-000000000002'),1,'reject keeps task version');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000002'),'rejected','proposal rejected');
select is((select count(*)::integer from public.notifications where notification_type='task_change_rejected' and recipient_id='c1000000-0000-0000-0000-000000000001'),1,'rejection notifies proposer');

-- Responsibility change while pending fails closed.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into change_results values('responsibility-create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000003',
 now()+interval '13 days',3::smallint,'c9000000-0000-0000-0000-000000000014',1
));
reset role;
update public.tasks set assignee_id='c1000000-0000-0000-0000-000000000004',version=version+1 where id='c4000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into change_results values('responsibility-old-assignee',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000003',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000003'),
 'approve',null,'c9000000-0000-0000-0000-000000000015',1
));
reset role;
select is((select result->>'code' from change_results where label='responsibility-old-assignee'),'INVALID_TRANSITION','responsibility change fails closed');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000003'),'pending','responsibility change never auto approves');

-- Activity alone is enough to require weight confirmation even before accepted_at exists.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into change_results values('activity-weight-create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000006',
 (select deadline_at from public.tasks where id='c4000000-0000-0000-0000-000000000006'),3::smallint,
 'c9000000-0000-0000-0000-000000000016',1
));
insert into change_results values('removed-create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000007',
 now()+interval '14 days',3::smallint,'c9000000-0000-0000-0000-000000000017',1
));
insert into change_results values('inactive-project-create',public.cmd_propose_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000008',
 now()+interval '15 days',3::smallint,'c9000000-0000-0000-0000-000000000018',1
));
reset role;
select is((select result->>'ok' from change_results where label='activity-weight-create'),'true','activity-only weight change enters confirmation workflow');
select is((select accepted_at from public.tasks where id='c4000000-0000-0000-0000-000000000006'),null::timestamptz,'activity-only proposal does not fake acceptance before decision');

-- Removing the snapshotted confirmer while pending must fail closed.
update public.project_members set member_state='removed',departed_at=now(),version=version+1 where id='c3000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into change_results values('removed-confirmer-decision',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000007',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000007'),
 'approve',null,'c9000000-0000-0000-0000-000000000019',1
));
reset role;
select is((select result->>'ok' from change_results where label='removed-confirmer-decision'),'false','removed confirmer cannot approve');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000007'),'pending','removed confirmer leaves proposal pending');
update public.project_members set member_state='active',departed_at=null,version=version+1 where id='c3000000-0000-0000-0000-000000000003';

-- Project transition out of active while pending also fails closed.
update public.projects set lifecycle_state='contribution_review',version=version+1 where id='c2000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into change_results values('inactive-project-decision',public.cmd_respond_to_task_change(
 'c2000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000008',
 (select id from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000008'),
 'approve',null,'c9000000-0000-0000-0000-000000000020',1
));
reset role;
select is((select result->>'code' from change_results where label='inactive-project-decision'),'PROJECT_NOT_ACTIVE','inactive project blocks decision');
select is((select state from public.task_change_proposals where task_id='c4000000-0000-0000-0000-000000000008'),'pending','inactive project leaves proposal pending');
update public.projects set lifecycle_state='active',version=version+1 where id='c2000000-0000-0000-0000-000000000001';

-- Recipient-only notification target resolution remains fail closed.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is(
 (public.resolve_notification_target((select id from public.notifications where notification_type='task_change_confirmation' limit 1))->>'routeName'),
 'task-detail','assignee resolves safe task target'
);
reset role;
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is(
 public.resolve_notification_target((select id from public.notifications where notification_type='task_change_confirmation' limit 1)),
 null::jsonb,'other member cannot resolve another recipients notification'
);
reset role;

select is((select count(*)::integer from public.business_events where event_type='task_change_proposed'),6,'successful proposals emit one audit event each');
select is((select count(*)::integer from public.business_events where event_type='task_change_approved'),1,'approval audited');
select is((select count(*)::integer from public.business_events where event_type='task_change_rejected'),1,'rejection audited');

select * from finish();
rollback;
