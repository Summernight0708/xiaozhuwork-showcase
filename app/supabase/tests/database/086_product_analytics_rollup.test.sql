begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'private','analytics_daily_metrics',
  'versioned analytics daily rollup table exists'
);
select has_function(
  'public','run_analytics_daily_rollup_service',
  array['date','date','integer'],
  'service-only daily rollup RPC exists'
);

select ok(
  not has_table_privilege('anon','private.analytics_daily_metrics','SELECT'),
  'anon cannot read rollups directly'
);
select ok(
  not has_table_privilege('authenticated','private.analytics_daily_metrics','SELECT'),
  'authenticated cannot read rollups directly'
);
select function_privs_are(
  'public','run_analytics_daily_rollup_service',
  array['date','date','integer'],
  'authenticated',array[]::text[],
  'authenticated cannot run rollups'
);
select function_privs_are(
  'public','run_analytics_daily_rollup_service',
  array['date','date','integer'],
  'service_role',array['EXECUTE'],
  'service role can run rollups'
);

select throws_ok(
  $$insert into private.analytics_daily_metrics(
      metric_date,metric_key,dimension_key,definition_version,
      numeric_value,sample_size,calculated_at
    ) values('2026-10-10','wacp',null,1,1,1,now())$$,
  '23502',null,
  'dimension_key is never null'
);
select throws_ok(
  $$insert into private.analytics_daily_metrics(
      metric_date,metric_key,dimension_key,definition_version,
      numeric_value,sample_size,calculated_at
    ) values('2026-10-10','unknown_metric','',1,1,1,now())$$,
  '23514',null,
  'unknown metric keys are rejected'
);
select throws_ok(
  $$insert into private.analytics_daily_metrics(
      metric_date,metric_key,dimension_key,definition_version,
      numeric_value,sample_size,calculated_at
    ) values('2026-10-10','wacp','all',1,1,1,now())$$,
  '23514',null,
  'non-dimensional metrics reject alternate aliases'
);
select throws_ok(
  $$insert into private.analytics_daily_metrics(
      metric_date,metric_key,dimension_key,definition_version,
      numeric_value,sample_size,calculated_at
    ) values('2026-10-10','lifecycle_project_count','unknown',1,1,1,now())$$,
  '23514',null,
  'lifecycle dimension is constrained to the frozen six values'
);

insert into auth.users(id,email,created_at) values
 ('a8600000-0000-0000-0000-000000000001','rollup-a@example.test','2026-10-01 00:00:00+00'),
 ('a8600000-0000-0000-0000-000000000002','rollup-b@example.test','2026-10-01 00:00:00+00');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by,created_at
) values
 ('a8610000-0000-0000-0000-000000000004','Late fact Oct4','2027-01-01','a8600000-0000-0000-0000-000000000001','a8600000-0000-0000-0000-000000000001','2026-10-04 00:00:00+00'),
 ('a8610000-0000-0000-0000-000000000010','Rerun Oct10','2027-01-01','a8600000-0000-0000-0000-000000000001','a8600000-0000-0000-0000-000000000001','2026-10-10 00:00:00+00');

insert into public.project_members(
 project_id,user_id,role,member_state,is_observer
) values
 ('a8610000-0000-0000-0000-000000000004','a8600000-0000-0000-0000-000000000001','leader','active',false),
 ('a8610000-0000-0000-0000-000000000004','a8600000-0000-0000-0000-000000000002','member','active',false),
 ('a8610000-0000-0000-0000-000000000010','a8600000-0000-0000-0000-000000000001','leader','active',false),
 ('a8610000-0000-0000-0000-000000000010','a8600000-0000-0000-0000-000000000002','member','active',false);

insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data,created_at
) values
 ('a8610000-0000-0000-0000-000000000004','a8600000-0000-0000-0000-000000000001','task_created','analytics_rollup','{}','2026-10-04 01:00:00+00'),
 ('a8610000-0000-0000-0000-000000000010','a8600000-0000-0000-0000-000000000001','task_created','analytics_rollup','{}','2026-10-10 01:00:00+00');

create temp table rollup_results(label text primary key,result jsonb);
grant all on rollup_results to service_role;

set local role service_role;
insert into rollup_results values(
 'first-seven',
 public.run_analytics_daily_rollup_service('2026-10-04','2026-10-10',1)
);
reset role;

select is(
 (select count(*)::integer
  from private.analytics_daily_metrics
  where metric_date between '2026-10-04' and '2026-10-10'
    and definition_version=1),
 112,
 'seven dates produce exactly sixteen frozen metric rows each'
);
select is(
 (select numeric_value
  from private.analytics_daily_metrics
  where metric_date='2026-10-10'
    and metric_key='project_activation_numerator'
    and dimension_key=''
    and definition_version=1),
 0::numeric,
 'first rollup sees only one actor and no activation'
);
select is(
 (select numeric_value
  from private.analytics_daily_metrics
  where metric_date='2026-10-04'
    and metric_key='project_activation_numerator'
    and dimension_key=''
    and definition_version=1),
 0::numeric,
 'historical date initially has no activation'
);

insert into private.analytics_daily_metrics(
 metric_date,metric_key,dimension_key,definition_version,
 numeric_value,sample_size,calculated_at
) values(
 '2026-10-10','wacp','',2,999,999,'2026-10-20 00:00:00+00'
);

insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data,created_at
) values
 ('a8610000-0000-0000-0000-000000000004','a8600000-0000-0000-0000-000000000002','task_claimed','analytics_rollup','{}','2026-10-04 02:00:00+00'),
 ('a8610000-0000-0000-0000-000000000010','a8600000-0000-0000-0000-000000000002','task_claimed','analytics_rollup','{}','2026-10-10 02:00:00+00');

set local role service_role;
insert into rollup_results values(
 'rerun-seven',
 public.run_analytics_daily_rollup_service('2026-10-04','2026-10-10',1)
);
insert into rollup_results values(
 'bad-version',
 public.run_analytics_daily_rollup_service('2026-10-04','2026-10-10',2)
);
insert into rollup_results values(
 'bad-range',
 public.run_analytics_daily_rollup_service('2026-10-10','2026-10-04',1)
);
insert into rollup_results values(
 'series',
 public.ops_get_product_timeseries_service('2026-10-04','2026-10-10',1)
);
reset role;

select is(
 (select count(*)::integer
  from private.analytics_daily_metrics
  where metric_date between '2026-10-04' and '2026-10-10'
    and definition_version=1),
 112,
 'same-version rerun updates rows without duplicates'
);
select is(
 (select numeric_value
  from private.analytics_daily_metrics
  where metric_date='2026-10-10'
    and metric_key='project_activation_numerator'
    and dimension_key=''
    and definition_version=1),
 1::numeric,
 'same-day rerun updates a late activation fact'
);
select is(
 (select numeric_value
  from private.analytics_daily_metrics
  where metric_date='2026-10-04'
    and metric_key='project_activation_numerator'
    and dimension_key=''
    and definition_version=1),
 1::numeric,
 'seven-day recompute absorbs a late historical fact'
);
select is(
 (select numeric_value
  from private.analytics_daily_metrics
  where metric_date='2026-10-10'
    and metric_key='wacp'
    and dimension_key=''
    and definition_version=2),
 999::numeric,
 'v1 rerun leaves coexisting newer definition rows intact'
);
select is(
 (select result->>'code' from rollup_results where label='bad-version'),
 'VALIDATION_FAILED',
 'rollup service does not silently compute unsupported definition versions'
);
select is(
 (select result->>'code' from rollup_results where label='bad-range'),
 'VALIDATION_FAILED',
 'rollup service rejects reversed ranges'
);
select ok(
 not exists(
   select 1 from private.analytics_daily_metrics
   where definition_version=1
     and metric_key<>'lifecycle_project_count'
     and dimension_key<>''
 ),
 'all non-dimensional v1 rows use the empty-string dimension exactly'
);
select is(
 (select jsonb_array_length(result->'data')
  from rollup_results where label='series'),
 112,
 'timeseries reads all frozen v1 rows for the requested seven dates'
);
select is(
 (
   select array_agg(key order by key)
   from jsonb_object_keys(
     (select result->'data'->0 from rollup_results where label='series')
   ) key
 ),
 array['date','dimensionKey','metricKey','sampleSize','value']::text[],
 'timeseries points exactly match ProductAnalyticsSeriesPointV1'
);
select ok(
 not ((select result->'data' from rollup_results where label='series')::text
   ~ '"definitionVersion"'),
 'timeseries point DTO does not leak storage-version internals'
);

select * from finish();
rollback;
