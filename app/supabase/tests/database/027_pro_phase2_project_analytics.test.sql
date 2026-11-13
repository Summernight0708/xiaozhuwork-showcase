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


select has_function(
  'public','get_project_analytics',array['uuid','timestamp with time zone','timestamp with time zone'],
  'project analytics RPC has the frozen signature'
);
select has_function(
  'private','phase2_project_analytics_payload',
  array['uuid','timestamp with time zone','timestamp with time zone','timestamp with time zone'],
  'analytics uses one private authoritative payload query'
);
select function_privs_are(
  'public','get_project_analytics',array['uuid','timestamp with time zone','timestamp with time zone'],
  'authenticated',array['EXECUTE'],
  'only authenticated clients can execute project analytics'
);
select function_privs_are(
  'private','phase2_project_analytics_payload',
  array['uuid','timestamp with time zone','timestamp with time zone','timestamp with time zone'],
  'authenticated',array[]::text[],
  'browser clients cannot execute the private aggregate directly'
);

insert into auth.users(id,email) values
  ('c1000000-0000-4000-8000-000000000001','analytics-pro@example.test'),
  ('c1000000-0000-4000-8000-000000000002','analytics-observer@example.test'),
  ('c1000000-0000-4000-8000-000000000003','analytics-former@example.test'),
  ('c1000000-0000-4000-8000-000000000004','analytics-free@example.test'),
  ('c1000000-0000-4000-8000-000000000005','analytics-grace@example.test'),
  ('c1000000-0000-4000-8000-000000000006','analytics-revoked@example.test'),
  ('c1000000-0000-4000-8000-000000000007','analytics-outsider@example.test');

insert into public.projects(
  id,name,timezone,start_at,deadline_at,leader_id,created_by,lifecycle_state,completed_at,version,created_at
) values
  (
    'c2000000-0000-4000-8000-000000000001','Analytics Pro','America/New_York',
    now()-interval '20 days',now()+interval '20 days',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    'active',null,1,now()-interval '30 days'
  ),
  (
    'c2000000-0000-4000-8000-000000000002','Analytics Free','Asia/Shanghai',
    null,now()+interval '20 days',
    'c1000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000004',
    'active',null,1,now()-interval '10 days'
  ),
  (
    'c2000000-0000-4000-8000-000000000003','Analytics Grace','Europe/Paris',
    null,now()+interval '20 days',
    'c1000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000005',
    'active',null,1,now()-interval '10 days'
  ),
  (
    'c2000000-0000-4000-8000-000000000004','Analytics Empty Completed','UTC',
    now()-interval '12 days',now()+interval '20 days',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    'completed',now()-interval '2 days',1,now()-interval '15 days'
  );

insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
  ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','leader','active',false),
  ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002','observer','active',true),
  ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003','member','removed',false),
  ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000006','member','removed',false),
  ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000004','leader','active',false),
  ('c2000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000005','leader','active',false),
  ('c2000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000001','leader','active',false);

insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'c1000000-0000-4000-8000-000000000001','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'c1000000-0000-4000-8000-000000000001','test',1
);

insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values(
  'c2000000-0000-4000-8000-000000000003',
  now()-interval '1 hour',now()+interval '2 days','account_expired',1
);

insert into public.tasks(
  id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
  assignment_state,accepted_at,completed_at,canceled_at,cancel_reason,blocked_reason,
  version,created_at,updated_at
) values
  (
    'c3000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Overdue',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()-interval '1 hour','not_started',1,'assigned',now()-interval '6 days',null,null,null,null,
    1,now()-interval '6 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001','Dependency blocked',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003',
    now()+interval '2 days','in_progress',2,'assigned',now()-interval '5 days',null,null,null,null,
    1,now()-interval '5 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000001','Explicit blocked',
    'c1000000-0000-4000-8000-000000000001',null,
    now()+interval '3 days','blocked',null,'claimable',null,null,null,null,'Waiting for access',
    1,now()-interval '4 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000001','Review',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()+interval '4 days','awaiting_review',4,'assigned',now()-interval '3 days',null,null,null,null,
    1,now()-interval '3 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000005','c2000000-0000-4000-8000-000000000001','Completed valid',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()+interval '5 days','completed',5,'assigned',now()-interval '2 days',now()-interval '1 day',null,null,null,
    1,now()-interval '1 day 2 hours',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000006','c2000000-0000-4000-8000-000000000001','Canceled upstream',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()+interval '6 days','canceled',3,'assigned',now()-interval '3 days',null,now()-interval '1 day','Canceled',null,
    1,now()-interval '3 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000007','c2000000-0000-4000-8000-000000000001','Reopened',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002',
    now()+interval '7 days','in_progress',3,'assigned',now()-interval '2 days',now()-interval '12 hours',null,null,null,
    1,now()-interval '2 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000008','c2000000-0000-4000-8000-000000000001','Completed missing time',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()+interval '8 days','completed',1,'assigned',now()-interval '2 days',null,null,null,null,
    1,now()-interval '2 days',now()
  ),
  (
    'c3000000-0000-4000-8000-000000000009','c2000000-0000-4000-8000-000000000001','Completed invalid timing',
    'c1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',
    now()+interval '9 days','completed',2,'assigned',now()-interval '2 days',now()-interval '6 hours',null,null,null,
    1,now()-interval '5 hours',now()
  );

insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
values(
  'c2000000-0000-4000-8000-000000000001',
  'c3000000-0000-4000-8000-000000000006',
  'c3000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000001'
);

create temporary table analytics_results(label text primary key,result jsonb);
grant all on analytics_results to authenticated;

-- Authorization and validation are evaluated before the release/plan gates.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
insert into analytics_results values(
  'unauthenticated',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'code' from analytics_results where label='unauthenticated'),'UNAUTHENTICATED','anonymous JWT receives a safe authentication failure');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000007',true);
set local role authenticated;
insert into analytics_results values(
  'outsider',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'code' from analytics_results where label='outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider is denied before plan state is revealed');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000006',true);
set local role authenticated;
insert into analytics_results values(
  'revoked',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'code' from analytics_results where label='revoked'),'NOT_FOUND_OR_NOT_AUTHORIZED','removed member loses analytics immediately');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into analytics_results values(
  'invalid-order',
  public.get_project_analytics('c2000000-0000-4000-8000-000000000001',now(),now())
),(
  'invalid-181',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '181 days',now()
  )
),(
  'invalid-future',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '1 day',now()+interval '6 minutes'
  )
),(
  'unreleased-pro',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'code' from analytics_results where label='invalid-order'),'VALIDATION_FAILED','from must be before to');
select is((select result->>'code' from analytics_results where label='invalid-181'),'VALIDATION_FAILED','181-day window is rejected');
select is((select result->>'code' from analytics_results where label='invalid-future'),'VALIDATION_FAILED','to beyond clock tolerance is rejected');
select is((select result->>'code' from analytics_results where label='unreleased-pro'),'CAPABILITY_NOT_AVAILABLE','planned analytics is closed for Pro before G release');

-- Test-only simulated G release. The surrounding transaction rolls this back.
create or replace function private.capability_is_released(p_capability text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    p_capability = any(array[
      'file_full_history','file_batch_rollback','file_version_compare',
      'project_recovery_point','project_analytics'
    ]::text[]),
    false
  );
$$;
revoke all on function private.capability_is_released(text)
  from public,anon,authenticated,service_role;

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000004',true);
set local role authenticated;
insert into analytics_results values(
  'released-free',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000002',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'code' from analytics_results where label='released-free'),'CAPABILITY_REQUIRES_PRO','released analytics on Free uses the paid capability failure');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into analytics_results values(
  'pro-main',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
),(
  'pro-180',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '180 days',now()
  )
),(
  'empty-completed',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000004',now()-interval '2 days',now()
  )
);
reset role;

select is((select result->>'ok' from analytics_results where label='pro-main'),'true','active Pro member receives analytics');
select is((select result->>'ok' from analytics_results where label='pro-180'),'true','exactly 180 days is accepted');
select is((select result->>'projectTimezone' from analytics_results where label='pro-main'),'America/New_York','project timezone is metadata and does not change UTC buckets');
select is((select result->>'provenance' from analytics_results where label='pro-main'),'current_rows','response declares current-row provenance');
select is((select result->>'historyComplete' from analytics_results where label='pro-main'),'false','response does not claim complete history');

select is(
  (select array_agg(key order by key) from jsonb_object_keys((select result from analytics_results where label='pro-main')) key),
  array[
    'asOf','completionTiming','dataIssues','difficultyDistribution','historyComplete',
    'memberTaskDistribution','ok','projectCycle','projectId','projectTimezone',
    'provenance','schemaVersion','totals','trends','window'
  ]::text[],
  'success response has exactly the frozen top-level fields'
);
select is(
  (select array_agg(key order by key) from jsonb_object_keys((select result->'totals' from analytics_results where label='pro-main')) key),
  array['awaitingReviewTasks','blockedTasks','completedInWindow','completedTasks','overdueTasks','taskTotal']::text[],
  'totals have exactly six frozen fields'
);

select is((select (result#>>'{totals,taskTotal}')::integer from analytics_results where label='pro-main'),8,'canceled task is excluded from task total');
select is((select (result#>>'{totals,completedTasks}')::integer from analytics_results where label='pro-main'),3,'completed total uses current status');
select is((select (result#>>'{totals,overdueTasks}')::integer from analytics_results where label='pro-main'),1,'overdue uses current incomplete status and deadline before asOf');
select is((select (result#>>'{totals,awaitingReviewTasks}')::integer from analytics_results where label='pro-main'),1,'awaiting review is counted');
select is((select (result#>>'{totals,blockedTasks}')::integer from analytics_results where label='pro-main'),2,'explicit block and canceled direct upstream are both blocked once');
select is((select (result#>>'{totals,completedInWindow}')::integer from analytics_results where label='pro-main'),2,'window completion uses current completed status with a timestamp');
select is((select (result#>>'{dataIssues,completedMissingTime}')::integer from analytics_results where label='pro-main'),1,'completed row missing its timestamp is disclosed');
select is((select (result#>>'{completionTiming,count}')::integer from analytics_results where label='pro-main'),1,'only valid completed durations enter timing');
select is((select (result#>>'{completionTiming,averageSeconds}')::integer from analytics_results where label='pro-main'),7200,'average completion duration is rounded seconds');
select is((select (result#>>'{completionTiming,medianSeconds}')::integer from analytics_results where label='pro-main'),7200,'median completion duration is rounded seconds');
select is((select (result#>>'{completionTiming,invalidTimeRows}')::integer from analytics_results where label='pro-main'),1,'negative timing row is disclosed');

select is(
  (select sum((item->>'count')::integer) from analytics_results r cross join lateral jsonb_array_elements(r.result->'memberTaskDistribution') item where r.label='pro-main'),
  8::bigint,
  'member task distribution sums to task total'
);
select is(
  (select string_agg(item->>'kind',',' order by ordinal) from analytics_results r cross join lateral jsonb_array_elements(r.result->'memberTaskDistribution') with ordinality x(item,ordinal) where r.label='pro-main'),
  'active_member,former_member,unassigned',
  'active assignees sort before former and unassigned sentinel buckets'
);
select is(
  (select sum((item->>'count')::integer) from analytics_results r cross join lateral jsonb_array_elements(r.result->'difficultyDistribution') item where r.label='pro-main'),
  8::bigint,
  'difficulty distribution sums to task total'
);
select is(
  (select jsonb_agg(item->'stars' order by ordinal) from analytics_results r cross join lateral jsonb_array_elements(r.result->'difficultyDistribution') with ordinality x(item,ordinal) where r.label='pro-main'),
  '[1,2,3,4,5,null]'::jsonb,
  'difficulty returns six fixed ordered buckets including unrated'
);
select is(
  (select jsonb_array_length(result->'trends') from analytics_results where label='pro-main'),
  (
    ((now()-interval '1 microsecond') at time zone 'UTC')::date
    - ((now()-interval '7 days') at time zone 'UTC')::date
    + 1
  ),
  'UTC trend series is zero-filled across every touched calendar day'
);
select ok(
  (select bool_and((item->>'created')::numeric >= 0 and (item->>'completed')::numeric >= 0) from analytics_results r cross join lateral jsonb_array_elements(r.result->'trends') item where r.label='pro-main'),
  'trend counts are safe nonnegative JSON numbers'
);
select is((select jsonb_array_length(result->'memberTaskDistribution') from analytics_results where label='empty-completed'),0,'zero-task project has an empty member distribution');
select is((select sum((item->>'count')::integer) from analytics_results r cross join lateral jsonb_array_elements(r.result->'difficultyDistribution') item where r.label='empty-completed'),0::bigint,'zero-task project still has six zero difficulty buckets');
select isnt((select result#>>'{projectCycle,completedAt}' from analytics_results where label='empty-completed'),null::text,'completed project returns its real completed timestamp');
select is((select result#>>'{projectCycle,startSource}' from analytics_results where label='empty-completed'),'start_at','project cycle prefers explicit start_at');
select ok((select (result#>>'{projectCycle,completedCycleSeconds}')::numeric > 0 from analytics_results where label='empty-completed'),'completed project returns a positive completed cycle duration');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000002',true);
set local role authenticated;
insert into analytics_results values(
  'observer',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000001',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'ok' from analytics_results where label='observer'),'true','active observer may read aggregates');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000005',true);
set local role authenticated;
insert into analytics_results values(
  'grace',
  public.get_project_analytics(
    'c2000000-0000-4000-8000-000000000003',now()-interval '7 days',now()
  )
);
reset role;
select is((select result->>'ok' from analytics_results where label='grace'),'true','Grace project may read released analytics');

select has_index('public','tasks','tasks_project_completed_at_idx','analytics completion lookup index exists');
select has_index('public','tasks','tasks_project_created_at_idx','analytics creation lookup index exists');

select * from finish();
rollback;
