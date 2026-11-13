begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_help_requests','help request truth exists');
select has_table('public','upstream_rework_requests','upstream rework truth exists');
select ok(
  coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.task_help_requests')),false),
  'help request truth enables RLS'
);
select ok(
  coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.upstream_rework_requests')),false),
  'upstream rework truth enables RLS'
);
select ok(
  case when to_regclass('public.task_help_requests') is null then false
       else has_table_privilege('authenticated','public.task_help_requests','SELECT') end,
  'authenticated may read help truth'
);
select ok(
  case when to_regclass('public.task_help_requests') is null then false
       else not has_table_privilege('authenticated','public.task_help_requests','INSERT') end,
  'authenticated cannot insert help truth'
);
select ok(
  case when to_regclass('public.upstream_rework_requests') is null then false
       else has_table_privilege('authenticated','public.upstream_rework_requests','SELECT') end,
  'authenticated may read rework truth'
);
select ok(
  case when to_regclass('public.upstream_rework_requests') is null then false
       else not has_table_privilege('authenticated','public.upstream_rework_requests','INSERT') end,
  'authenticated cannot insert rework truth'
);
-- Task Help commands: authorization, idempotency, optimistic versioning, and safe unblock ownership.
select has_function(
  'public','cmd_create_task_help_request',
  array['uuid','uuid','uuid','integer','text','uuid','boolean'],
  'create help command exists'
);
select has_function(
  'public','cmd_resolve_task_help_request',
  array['uuid','uuid','uuid','integer'],
  'resolve help command exists'
);
select ok(
  coalesce((
    select prosecdef and proconfig @> array['search_path=""']
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='cmd_create_task_help_request'
  ),false),
  'create help RPC is SECURITY DEFINER with empty search_path'
);
select ok(
  coalesce((
    select prosecdef and proconfig @> array['search_path=""']
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='cmd_resolve_task_help_request'
  ),false),
  'resolve help RPC is SECURITY DEFINER with empty search_path'
);

insert into auth.users(id,email) values
 ('a1000000-0000-0000-0000-000000000001','help-leader@example.test'),
 ('a1000000-0000-0000-0000-000000000002','help-assignee@example.test'),
 ('a1000000-0000-0000-0000-000000000003','help-target@example.test'),
 ('a1000000-0000-0000-0000-000000000004','help-other@example.test'),
 ('a1000000-0000-0000-0000-000000000005','help-observer@example.test'),
 ('a1000000-0000-0000-0000-000000000006','help-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state)
values(
 'a2000000-0000-0000-0000-000000000001','Help project',now()+interval '20 days',
 'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1,'weighted','active'
);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version,departed_at) values
 ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','leader','active',false,1,null),
 ('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','member','active',false,1,null),
 ('a3000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003','member','active',false,1,null),
 ('a3000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000004','admin','active',false,1,null),
 ('a3000000-0000-0000-0000-000000000005','a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000005','observer','active',true,1,null);

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,blocked_reason,version
) values
 ('a4000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Help owned block','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',2,now()-interval '1 day','assigned',null,1),
 ('a4000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','Existing block','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '6 days','blocked',2,now()-interval '1 day','assigned','existing blocker',1),
 ('a4000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','Resolve role task','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '7 days','in_progress',2,now()-interval '1 day','assigned',null,1),
 ('a4000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000001','Stale block ownership','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '8 days','in_progress',2,now()-interval '1 day','assigned',null,1);

create temporary table help_results(label text primary key,result jsonb);
grant all on help_results to authenticated;

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into help_results values('create-block',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',
 'a9000000-0000-0000-0000-000000000001',1,'Need leader help',null,true
));
insert into help_results values('create-block-replay',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',
 'a9000000-0000-0000-0000-000000000001',1,'Need leader help',null,true
));
insert into help_results values('create-block-reuse',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',
 'a9000000-0000-0000-0000-000000000001',1,'Changed payload',null,true
));
insert into help_results values('existing-block',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002',
 'a9000000-0000-0000-0000-000000000002',1,'Do not overwrite',null,true
));
insert into help_results values('observer-target',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000003',
 'a9000000-0000-0000-0000-000000000003',1,'Observer invalid','a1000000-0000-0000-0000-000000000005',false
));
insert into help_results values('create-target',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000003',
 'a9000000-0000-0000-0000-000000000004',1,'Please assist','a1000000-0000-0000-0000-000000000003',false
));
insert into help_results values('stale-task',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000004',
 'a9000000-0000-0000-0000-000000000005',0,'Stale version','a1000000-0000-0000-0000-000000000003',false
));
reset role;

select is((select result->>'ok' from help_results where label='create-block'),'true','assignee creates blocking help');
select is((select result->>'replayed' from help_results where label='create-block-replay'),'true','identical help create replays');
select is((select result->>'code' from help_results where label='create-block-reuse'),'IDEMPOTENCY_KEY_REUSED','help request id reuse with new payload rejected');
select is((select result->>'code' from help_results where label='existing-block'),'INVALID_TRANSITION','new help cannot replace an existing manual block');
select is((select blocked_reason from public.tasks where id='a4000000-0000-0000-0000-000000000002'),'existing blocker','existing block reason preserved');
select is((select result->>'code' from help_results where label='observer-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','observer cannot be selected as helper');
select is((select result->>'ok' from help_results where label='create-target'),'true','assignee may choose an active non-observer member');
select is((select result->>'code' from help_results where label='stale-task'),'STALE_VERSION','create rejects stale task version');
select is((select target_user_id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),'a1000000-0000-0000-0000-000000000001'::uuid,'default helper is active leader');
select is((select status from public.tasks where id='a4000000-0000-0000-0000-000000000001'),'blocked','blocking help marks task blocked');
select is((select version from public.tasks where id='a4000000-0000-0000-0000-000000000001'),2,'blocking help increments task version once');
select is((select blocked_task_version from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),2,'help stores exact blocked task version');
select is((select count(*)::integer from public.business_events where event_type='task_help_requested'),2,'only successful new help requests emit events');
select ok(
  not exists(
    select 1 from public.business_events
    where event_type='task_help_requested' and event_data::text like '%Need leader help%'
  ),
  'help message is excluded from business event payload'
);

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into help_results values('unrelated-resolve',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000003'),
 'a9000000-0000-0000-0000-000000000006',1
));
reset role;
select is((select result->>'code' from help_results where label='unrelated-resolve'),'NOT_FOUND_OR_NOT_AUTHORIZED','unrelated member cannot resolve help');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into help_results values('target-resolve',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000003'),
 'a9000000-0000-0000-0000-000000000007',1
));
reset role;
select is((select result->>'ok' from help_results where label='target-resolve'),'true','target helper may resolve');
select is((select result #>> '{data,taskResumed}' from help_results where label='target-resolve'),'false','non-blocking help never resumes task');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into help_results values('requester-resolve',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),
 'a9000000-0000-0000-0000-000000000008',1
));
insert into help_results values('requester-resolve-replay',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),
 'a9000000-0000-0000-0000-000000000008',1
));
insert into help_results values('requester-resolve-again',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),
 'a9000000-0000-0000-0000-000000000009',2
));
reset role;

select is((select result->>'ok' from help_results where label='requester-resolve'),'true','requester may resolve blocking help');
select is((select result #>> '{data,taskResumed}' from help_results where label='requester-resolve'),'true','owned manual block safely resumes');
select is((select result->>'replayed' from help_results where label='requester-resolve-replay'),'true','resolve replay is idempotent');
select is((select result->>'code' from help_results where label='requester-resolve-again'),'INVALID_TRANSITION','new request cannot resolve already resolved help');
select is((select status from public.tasks where id='a4000000-0000-0000-0000-000000000001'),'in_progress','owned block resumes to in progress');
select is((select version from public.tasks where id='a4000000-0000-0000-0000-000000000001'),3,'safe resume increments task once');
select is((select version from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000001'),2,'resolve increments help row version once');

-- A later task update owns the current blocked state; resolving an old help must not erase it.
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into help_results values('old-block-create',public.cmd_create_task_help_request(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000004',
 'a9000000-0000-0000-0000-000000000010',1,'Old help blocker','a1000000-0000-0000-0000-000000000003',true
));
insert into help_results values('later-progress',public.cmd_update_task_progress(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000004',
 'a9000000-0000-0000-0000-000000000011',2,'in_progress','worked around it',null
));
insert into help_results values('later-block',public.cmd_update_task_progress(
 'a2000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000004',
 'a9000000-0000-0000-0000-000000000012',3,'blocked','new blocker','New blocker reason'
));
insert into help_results values('old-block-resolve',public.cmd_resolve_task_help_request(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.task_help_requests where task_id='a4000000-0000-0000-0000-000000000004'),
 'a9000000-0000-0000-0000-000000000013',1
));
reset role;

select is((select result->>'ok' from help_results where label='old-block-resolve'),'true','old help may still be resolved');
select is((select result #>> '{data,taskResumed}' from help_results where label='old-block-resolve'),'false','old help does not own later blocked state');
select is((select status from public.tasks where id='a4000000-0000-0000-0000-000000000004'),'blocked','later block remains blocked');
select is((select blocked_reason from public.tasks where id='a4000000-0000-0000-0000-000000000004'),'New blocker reason','later block reason is preserved');

select is((select count(*)::integer from public.business_events where event_type='task_help_resolved'),3,'successful resolves emit exactly one event each');
-- Upstream Rework commands: direct-dependency authorization, leader decision, durable history.
select has_function(
  'public','cmd_request_upstream_rework',
  array['uuid','uuid','uuid','uuid','integer','integer','text'],
  'request upstream rework command exists'
);
select has_function(
  'public','cmd_review_upstream_rework',
  array['uuid','uuid','uuid','integer','text'],
  'review upstream rework command exists'
);
select ok(
  coalesce((
    select prosecdef and proconfig @> array['search_path=""']
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='cmd_request_upstream_rework'
  ),false),
  'request rework RPC is SECURITY DEFINER with empty search_path'
);
select ok(
  coalesce((
    select prosecdef and proconfig @> array['search_path=""']
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='cmd_review_upstream_rework'
  ),false),
  'review rework RPC is SECURITY DEFINER with empty search_path'
);

insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,
 assignment_state,first_submitted_at,completed_at,version
) values
 ('b4000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Upstream approve','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000003',now()+interval '4 days','completed',3,now()-interval '3 days','assigned',now()-interval '2 days',now()-interval '1 day',5),
 ('b4000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','Downstream active','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '6 days','in_progress',2,now()-interval '2 days','assigned',null,null,4),
 ('b4000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','Downstream historical complete','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '6 days','completed',2,now()-interval '2 days','assigned',now()-interval '1 day',now()-interval '1 hour',7),
 ('b4000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000001','Upstream reject','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000003',now()+interval '4 days','completed',2,now()-interval '2 days','assigned',now()-interval '1 day',now()-interval '1 hour',2),
 ('b4000000-0000-0000-0000-000000000005','a2000000-0000-0000-0000-000000000001','Downstream reject','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '7 days','in_progress',2,now()-interval '2 days','assigned',null,null,3),
 ('b4000000-0000-0000-0000-000000000006','a2000000-0000-0000-0000-000000000001','Upstream direct leader','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000003',now()+interval '4 days','completed',2,now()-interval '2 days','assigned',now()-interval '1 day',now()-interval '1 hour',8),
 ('b4000000-0000-0000-0000-000000000007','a2000000-0000-0000-0000-000000000001','Downstream direct leader','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000002',now()+interval '7 days','in_progress',2,now()-interval '2 days','assigned',null,null,2),
 ('b4000000-0000-0000-0000-000000000008','a2000000-0000-0000-0000-000000000001','Completed non-direct','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000003',now()+interval '4 days','completed',2,now()-interval '2 days','assigned',now()-interval '1 day',now()-interval '1 hour',1);

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by) values
 ('a2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001'),
 ('a2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000001'),
 ('a2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','b4000000-0000-0000-0000-000000000005','a1000000-0000-0000-0000-000000000001'),
 ('a2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000006','b4000000-0000-0000-0000-000000000007','a1000000-0000-0000-0000-000000000001');

create temporary table rework_results(label text primary key,result jsonb);
grant all on rework_results to authenticated;

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into rework_results values('request',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',4,5,'Please revise the upstream output'
));
insert into rework_results values('request-replay',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',4,5,'Please revise the upstream output'
));
insert into rework_results values('request-reuse',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',4,5,'Different requirement'
));
insert into rework_results values('second-pending',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000003','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000002',7,5,'Another pending request'
));
insert into rework_results values('non-direct',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000008',
 'b9000000-0000-0000-0000-000000000003',4,1,'Not a direct dependency'
));
reset role;

select is((select result->>'ok' from rework_results where label='request'),'true','downstream assignee requests direct upstream rework');
select is((select result->>'replayed' from rework_results where label='request-replay'),'true','rework request replay is idempotent');
select is((select result->>'code' from rework_results where label='request-reuse'),'IDEMPOTENCY_KEY_REUSED','rework request payload mismatch rejected');
select is((select result->>'code' from rework_results where label='second-pending'),'INVALID_TRANSITION','only one pending request allowed per upstream');
select is((select result->>'code' from rework_results where label='non-direct'),'INVALID_TRANSITION','non-direct upstream cannot be requested');
select is((select state from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),'pending','member request stays pending');
select is((select upstream_completed_version from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),5,'request snapshots completed upstream version');
select ok(
  not exists(
    select 1 from public.business_events
    where event_type='upstream_rework_requested' and event_data::text like '%Please revise%'
  ),
  'rework requirement is excluded from event payload'
);

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into rework_results values('nonleader-review',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),
 'b9000000-0000-0000-0000-000000000004',1,'approve'
));
reset role;
select is((select result->>'code' from rework_results where label='nonleader-review'),'NOT_FOUND_OR_NOT_AUTHORIZED','nonleader cannot decide rework');

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rework_results values('approve-stale-request',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),
 'b9000000-0000-0000-0000-000000000005',0,'approve'
));
insert into rework_results values('approve',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),
 'b9000000-0000-0000-0000-000000000006',1,'approve'
));
insert into rework_results values('approve-replay',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),
 'b9000000-0000-0000-0000-000000000006',1,'approve'
));
insert into rework_results values('approve-again',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),
 'b9000000-0000-0000-0000-000000000007',2,'approve'
));
reset role;

select is((select result->>'code' from rework_results where label='approve-stale-request'),'STALE_VERSION','review checks request row version');
select is((select result->>'ok' from rework_results where label='approve'),'true','leader approves pending rework');
select is((select result->>'replayed' from rework_results where label='approve-replay'),'true','rework decision replay is idempotent');
select is((select result->>'code' from rework_results where label='approve-again'),'INVALID_TRANSITION','approved request cannot be decided again');
select is((select state from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),'approved','request history records approval');
select is((select version from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000001'),2,'approval increments request version');
select is((select status from public.tasks where id='b4000000-0000-0000-0000-000000000001'),'in_progress','approved rework reopens upstream');
select is((select completed_at from public.tasks where id='b4000000-0000-0000-0000-000000000001'),null::timestamptz,'approved rework clears upstream completed_at');
select is((select version from public.tasks where id='b4000000-0000-0000-0000-000000000001'),6,'approved rework increments upstream version once');
select ok((select first_submitted_at is not null from public.tasks where id='b4000000-0000-0000-0000-000000000001'),'rework preserves first submission history');
select is((select status from public.tasks where id='b4000000-0000-0000-0000-000000000003'),'completed','completed downstream history is not rolled back');

-- Reject path keeps the upstream completed.
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into rework_results values('reject-request',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000005','b4000000-0000-0000-0000-000000000004',
 'b9000000-0000-0000-0000-000000000008',3,2,'Reject this request'
));
reset role;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rework_results values('reject',public.cmd_review_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 (select id from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000004'),
 'b9000000-0000-0000-0000-000000000009',1,'reject'
));
reset role;
select is((select result->>'ok' from rework_results where label='reject'),'true','leader rejects pending rework');
select is((select state from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000004'),'rejected','rejection remains durable history');
select is((select status from public.tasks where id='b4000000-0000-0000-0000-000000000004'),'completed','rejection leaves upstream completed');
select is((select version from public.tasks where id='b4000000-0000-0000-0000-000000000004'),2,'rejection does not change upstream version');

-- Leader direct rework creates approved history and reopens without a pending phase.
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into rework_results values('leader-direct',public.cmd_request_upstream_rework(
 'a2000000-0000-0000-0000-000000000001',
 'b4000000-0000-0000-0000-000000000007','b4000000-0000-0000-0000-000000000006',
 'b9000000-0000-0000-0000-000000000010',2,8,'Leader direct rework'
));
reset role;
select is((select result->>'ok' from rework_results where label='leader-direct'),'true','leader may directly rework a completed direct upstream');
select is((select state from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000006'),'approved','leader direct path writes approved audit fact');
select is((select version from public.upstream_rework_requests where upstream_task_id='b4000000-0000-0000-0000-000000000006'),1,'direct approval starts as one immutable decision fact');
select is((select status from public.tasks where id='b4000000-0000-0000-0000-000000000006'),'in_progress','leader direct rework reopens upstream');
select is((select version from public.tasks where id='b4000000-0000-0000-0000-000000000006'),9,'leader direct rework increments upstream once');

select is((select count(*)::integer from public.business_events where event_type='upstream_rework_requested'),2,'member rework requests each emit one request event');
select is((select count(*)::integer from public.business_events where event_type='upstream_rework_approved'),2,'review approval and direct leader approval each emit one approval event');
select is((select count(*)::integer from public.business_events where event_type='upstream_rework_rejected'),1,'rejection emits one audit event');
-- Event-derived notifications use trusted facts, dedupe recipients, skip actors, and navigate to tasks.
select is(
  (select count(*)::integer from public.notifications where notification_type='task_help_requested' and recipient_id='a1000000-0000-0000-0000-000000000001'),
  1,'default leader receives the blocking help request'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='task_help_requested' and recipient_id='a1000000-0000-0000-0000-000000000003'),
  2,'chosen helper receives each help request exactly once'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='task_help_resolved' and recipient_id='a1000000-0000-0000-0000-000000000001'),
  1,'requester resolution notifies the leader target'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='task_help_resolved' and recipient_id='a1000000-0000-0000-0000-000000000002'),
  1,'target resolution notifies the requester'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='task_help_resolved' and recipient_id='a1000000-0000-0000-0000-000000000003'),
  1,'requester resolution notifies chosen target'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='upstream_rework_requested' and recipient_id='a1000000-0000-0000-0000-000000000001'),
  2,'leader receives each member rework request'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='upstream_rework_approved' and recipient_id='a1000000-0000-0000-0000-000000000002'),
  2,'requester or incomplete downstream assignee receives each approval once'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='upstream_rework_approved' and recipient_id='a1000000-0000-0000-0000-000000000003'),
  2,'upstream assignee receives each approval once'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='upstream_rework_rejected' and recipient_id='a1000000-0000-0000-0000-000000000002'),
  1,'rework requester receives rejection'
);
select is(
  (select count(*)::integer from public.notifications where notification_type='upstream_rework_approved' and recipient_id='a1000000-0000-0000-0000-000000000001'),
  0,'actor does not receive own direct approval notification'
);
select is(
  (select count(*)::integer from public.notifications
   where notification_type in (
     'task_help_requested','task_help_resolved','upstream_rework_requested',
     'upstream_rework_approved','upstream_rework_rejected'
   ) and entity_type is distinct from 'task'),
  0,'workflow notifications always target task entities'
);

select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is(
  (public.resolve_notification_target((
    select id from public.notifications
    where recipient_id='a1000000-0000-0000-0000-000000000003'
      and notification_type='upstream_rework_approved'
    order by created_at,id limit 1
  ))->>'routeName'),
  'task-detail','workflow notification resolves to Task Detail'
);
reset role;

select * from finish();
rollback;
