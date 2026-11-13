begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public','ops_get_product_analytics_service',
  array['timestamp with time zone','timestamp with time zone','integer'],
  'service-only product analytics overview RPC exists'
);
select has_function(
  'public','ops_get_product_timeseries_service',
  array['date','date','integer'],
  'service-only product analytics timeseries RPC exists'
);

select function_privs_are(
  'public','ops_get_product_analytics_service',
  array['timestamp with time zone','timestamp with time zone','integer'],
  'anon',array[]::text[],
  'anon cannot execute product analytics overview'
);
select function_privs_are(
  'public','ops_get_product_analytics_service',
  array['timestamp with time zone','timestamp with time zone','integer'],
  'authenticated',array[]::text[],
  'authenticated cannot execute product analytics overview'
);
select function_privs_are(
  'public','ops_get_product_analytics_service',
  array['timestamp with time zone','timestamp with time zone','integer'],
  'service_role',array['EXECUTE'],
  'service role alone can execute product analytics overview'
);
select function_privs_are(
  'public','ops_get_product_timeseries_service',
  array['date','date','integer'],
  'anon',array[]::text[],
  'anon cannot execute product analytics timeseries'
);
select function_privs_are(
  'public','ops_get_product_timeseries_service',
  array['date','date','integer'],
  'authenticated',array[]::text[],
  'authenticated cannot execute product analytics timeseries'
);
select function_privs_are(
  'public','ops_get_product_timeseries_service',
  array['date','date','integer'],
  'service_role',array['EXECUTE'],
  'service role alone can execute product analytics timeseries'
);

select ok(
  not exists(
    select 1
    from information_schema.routine_privileges
    where routine_schema='public'
      and routine_name in (
        'ops_get_product_analytics_service',
        'ops_get_product_timeseries_service'
      )
      and grantee='PUBLIC'
      and privilege_type='EXECUTE'
  ),
  'analytics service RPCs have no PUBLIC execute grant'
);

insert into auth.users(id,email,created_at) values
 ('a8500000-0000-0000-0000-000000000001','analytics-service-a@example.test','2026-10-10 00:00:00+00'),
 ('a8500000-0000-0000-0000-000000000002','analytics-service-b@example.test','2026-10-10 00:00:00+00');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by,created_at
) values(
 'a8510000-0000-0000-0000-000000000001',
 'Analytics service contract fixture',
 '2027-01-01 00:00:00+00',
 'a8500000-0000-0000-0000-000000000001',
 'a8500000-0000-0000-0000-000000000001',
 '2026-10-10 00:00:00+00'
);

insert into public.project_members(
 project_id,user_id,role,member_state,is_observer
) values
 ('a8510000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000001','leader','active',false),
 ('a8510000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000002','member','active',false);

insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data,created_at
) values
 ('a8510000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-10-11 00:00:00+00'),
 ('a8510000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000002','task_claimed','analytics_test','{}','2026-10-12 00:00:00+00');

insert into public.tasks(
 id,project_id,title,deadline_at,status,requires_review,completed_at,created_by,assignee_id,created_at
) values(
 'a8520000-0000-0000-0000-000000000001',
 'a8510000-0000-0000-0000-000000000001',
 'Service first value task',
 '2026-12-01 00:00:00+00',
 'completed',
 false,
 '2026-10-13 00:00:00+00',
 'a8500000-0000-0000-0000-000000000001',
 'a8500000-0000-0000-0000-000000000002',
 '2026-10-10 12:00:00+00'
);

insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data,created_at
) values(
 'a8510000-0000-0000-0000-000000000001',
 'a8500000-0000-0000-0000-000000000002',
 'task_submitted_without_review',
 'task_review_round',
 '{"taskId":"a8520000-0000-0000-0000-000000000001"}',
 '2026-10-13 00:00:00+00'
);

insert into private.analytics_coverage(
 source,complete_since,definition_version,verified_at,note
) values(
 'business_analytics',
 '2026-10-01 00:00:00+00',
 1,
 '2026-10-14 00:00:00+00',
 '085 service contract fixture'
);

create temp table analytics_service_results(
 label text primary key,
 result jsonb
);
grant all on analytics_service_results to service_role;

-- Intentionally do not set request.jwt.claim.role. The current Supabase secret
-- key path is enforced by PostgreSQL EXECUTE grants, not a legacy JWT claim.
set local role service_role;

insert into analytics_service_results values(
 'overview',
 public.ops_get_product_analytics_service(
   '2026-10-10 00:00:00+00',
   '2026-10-20 00:00:00+00',
   1
 )
);
insert into analytics_service_results values(
 'overview-repeat',
 public.ops_get_product_analytics_service(
   '2026-10-10 00:00:00+00',
   '2026-10-20 00:00:00+00',
   1
 )
);
insert into analytics_service_results values(
 'overview-partial',
 public.ops_get_product_analytics_service(
   '2026-09-20 00:00:00+00',
   '2026-10-20 00:00:00+00',
   1
 )
);
insert into analytics_service_results values(
 'bad-version',
 public.ops_get_product_analytics_service(
   '2026-10-10 00:00:00+00',
   '2026-10-20 00:00:00+00',
   2
 )
);
insert into analytics_service_results values(
 'bad-range',
 public.ops_get_product_analytics_service(
   '2026-10-20 00:00:00+00',
   '2026-10-10 00:00:00+00',
   1
 )
);
insert into analytics_service_results values(
 'timeseries',
 public.ops_get_product_timeseries_service(
   '2026-10-10',
   '2026-10-20',
   1
 )
);
insert into analytics_service_results values(
 'timeseries-bad-version',
 public.ops_get_product_timeseries_service(
   '2026-10-10',
   '2026-10-20',
   2
 )
);
insert into analytics_service_results values(
 'timeseries-bad-range',
 public.ops_get_product_timeseries_service(
   '2026-10-20',
   '2026-10-10',
   1
 )
);

reset role;

select is(
 (select result->>'ok' from analytics_service_results where label='overview'),
 'true',
 'service overview succeeds without relying on a legacy JWT role claim'
);
select is(
 (select result from analytics_service_results where label='overview-repeat'),
 (select result from analytics_service_results where label='overview'),
 'same from/to/version returns a stable overview DTO'
);
select is(
 (select result->'data'->'coverage'->>'businessAnalyticsCompleteSince'
  from analytics_service_results where label='overview'),
 '2026-10-01T00:00:00+00:00',
 'overview exposes business analytics coverage boundary'
);
select is(
 (select result->'data'->'coverage'->>'partial'
  from analytics_service_results where label='overview'),
 'false',
 'window starting after verified coverage is complete'
);
select is(
 (select result->'data'->'coverage'->>'partial'
  from analytics_service_results where label='overview-partial'),
 'true',
 'window starting before verified coverage is marked partial'
);

select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data' from analytics_service_results where label='overview')
   ) key
 ),
 array[
   'coreLoopCompleted','coverage','definitionVersion','firstValueRate',
   'lifecycle','projectActivation','projectCompletion','schemaVersion',
   'userActivation','wacp'
 ]::text[],
 'overview DTO top-level keys exactly match contract v1'
);
select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data'->'coverage' from analytics_service_results where label='overview')
   ) key
 ),
 array['businessAnalyticsCompleteSince','partial']::text[],
 'coverage DTO keys exactly match contract v1'
);
select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data'->'wacp' from analytics_service_results where label='overview')
   ) key
 ),
 array['value','weekStart']::text[],
 'WACP DTO keys exactly match contract v1'
);
select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data'->'projectActivation' from analytics_service_results where label='overview')
   ) key
 ),
 array['denominator','numerator','rate']::text[],
 'RateFact keys exactly match contract v1'
);
select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data'->'lifecycle' from analytics_service_results where label='overview')
   ) key
 ),
 array['archived','collaborating','completed','quiet','setup','stalled']::text[],
 'lifecycle keys exactly match contract v1'
);
select is(
 (select result->'data'->>'schemaVersion'
  from analytics_service_results where label='overview'),
 '1',
 'overview schemaVersion is frozen to 1'
);
select is(
 (select result->'data'->>'definitionVersion'
  from analytics_service_results where label='overview'),
 '1',
 'overview definitionVersion is frozen to 1'
);
select is(
 (select result->'data'->'lifecycle'->>'quiet'
  from analytics_service_results where label='overview'),
 '1',
 'service evaluates lifecycle at p_to rather than query time'
);

select is(
 (select result->>'code' from analytics_service_results where label='bad-version'),
 'VALIDATION_FAILED',
 'overview rejects unsupported definition versions'
);
select is(
 (select result->>'code' from analytics_service_results where label='bad-range'),
 'VALIDATION_FAILED',
 'overview rejects reversed time ranges'
);
select is(
 (select result->>'ok' from analytics_service_results where label='timeseries'),
 'true',
 'timeseries stable interface succeeds before rollup implementation'
);
select is(
 (select result->'data' from analytics_service_results where label='timeseries'),
 '[]'::jsonb,
 'timeseries is empty until Task 4 daily rollups exist'
);
select is(
 (select result->>'code' from analytics_service_results where label='timeseries-bad-version'),
 'VALIDATION_FAILED',
 'timeseries rejects unsupported definition versions'
);
select is(
 (select result->>'code' from analytics_service_results where label='timeseries-bad-range'),
 'VALIDATION_FAILED',
 'timeseries rejects reversed date ranges'
);

select ok(
 (select result::text from analytics_service_results where label='overview')
   !~* '(projectId|project_id|userId|user_id|email|a85[0-9a-f-]{20,})',
 'aggregate overview leaks no project/user/email identifiers'
);

select * from finish();
rollback;
