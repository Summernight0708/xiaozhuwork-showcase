-- TeamUp Beta product analytics daily rollups v1.

create table private.analytics_daily_metrics (
  metric_date date not null,
  metric_key text not null,
  dimension_key text not null,
  definition_version integer not null check (definition_version > 0),
  numeric_value numeric not null,
  sample_size integer not null check (sample_size >= 0),
  calculated_at timestamptz not null,
  primary key(metric_date,metric_key,dimension_key,definition_version),
  constraint analytics_daily_metric_key_v1 check (
    definition_version <> 1
    or metric_key in (
      'wacp',
      'project_activation_numerator',
      'project_activation_denominator',
      'user_activation_numerator',
      'user_activation_denominator',
      'first_value_numerator',
      'first_value_denominator',
      'core_loop_completed',
      'project_completion_numerator',
      'project_completion_denominator',
      'lifecycle_project_count'
    )
  ),
  constraint analytics_daily_dimension_v1 check (
    definition_version <> 1
    or (
      metric_key = 'lifecycle_project_count'
      and dimension_key in (
        'setup','collaborating','quiet','stalled','completed','archived'
      )
    )
    or (
      metric_key <> 'lifecycle_project_count'
      and dimension_key = ''
    )
  )
);

alter table private.analytics_daily_metrics enable row level security;
revoke all on private.analytics_daily_metrics
  from public,anon,authenticated,service_role;

insert into private.lifecycle_pii_classifications(
  schema_name,table_name,column_name,data_type,classification
)
select
  n.nspname,
  c.relname,
  a.attname,
  format_type(a.atttypid,a.atttypmod),
  case
    when format_type(a.atttypid,a.atttypmod)='uuid'
      then 'identity_reference'
    when format_type(a.atttypid,a.atttypmod) in ('json','jsonb')
      then 'unstructured_json'
    when format_type(a.atttypid,a.atttypmod) ~ '^(text|character|citext)'
      then 'free_text'
    else 'structured'
  end
from pg_attribute a
join pg_class c on c.oid=a.attrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='private'
  and c.relname='analytics_daily_metrics'
  and c.relkind in ('r','p')
  and a.attnum>0
  and not a.attisdropped
on conflict(schema_name,table_name,column_name) do update
set data_type=excluded.data_type,
    classification=excluded.classification,
    disposition='manual_review_required';

create function private.analytics_rollup_points_v1(p_metric_date date)
returns table(
  metric_key text,
  dimension_key text,
  numeric_value numeric,
  sample_size integer
)
language plpgsql
stable
set search_path=''
as $$
declare
  v_from timestamptz;
  v_to timestamptz;
  v_overview jsonb;
  v_lifecycle_total integer;
  v_week_start date;
  v_wacp integer;
begin
  if p_metric_date is null then
    raise exception using errcode='22004',message='METRIC_DATE_REQUIRED';
  end if;

  v_from := p_metric_date::timestamp at time zone 'Asia/Shanghai';
  v_to := (p_metric_date+1)::timestamp at time zone 'Asia/Shanghai';
  v_overview := private.analytics_overview_v1(v_from,v_to,v_to);

  if coalesce(v_overview->>'ok','true') <> 'true' then
    raise exception using
      errcode='P0001',
      message=coalesce(v_overview->>'code','ANALYTICS_OVERVIEW_FAILED');
  end if;

  v_week_start := date_trunc('week',p_metric_date::timestamp)::date;
  v_wacp := private.analytics_wacp_v1(v_week_start);
  v_lifecycle_total :=
    coalesce((v_overview->'lifecycle'->>'setup')::integer,0)
    + coalesce((v_overview->'lifecycle'->>'collaborating')::integer,0)
    + coalesce((v_overview->'lifecycle'->>'quiet')::integer,0)
    + coalesce((v_overview->'lifecycle'->>'stalled')::integer,0)
    + coalesce((v_overview->'lifecycle'->>'completed')::integer,0)
    + coalesce((v_overview->'lifecycle'->>'archived')::integer,0);

  return query
  select * from (
    values
      ('wacp','',v_wacp::numeric,greatest(v_wacp,0)),
      (
        'project_activation_numerator','',
        coalesce((v_overview->'projectActivation'->>'numerator')::numeric,0),
        coalesce((v_overview->'projectActivation'->>'denominator')::integer,0)
      ),
      (
        'project_activation_denominator','',
        coalesce((v_overview->'projectActivation'->>'denominator')::numeric,0),
        coalesce((v_overview->'projectActivation'->>'denominator')::integer,0)
      ),
      (
        'user_activation_numerator','',
        coalesce((v_overview->'userActivation'->>'numerator')::numeric,0),
        coalesce((v_overview->'userActivation'->>'denominator')::integer,0)
      ),
      (
        'user_activation_denominator','',
        coalesce((v_overview->'userActivation'->>'denominator')::numeric,0),
        coalesce((v_overview->'userActivation'->>'denominator')::integer,0)
      ),
      (
        'first_value_numerator','',
        coalesce((v_overview->'firstValueRate'->>'numerator')::numeric,0),
        coalesce((v_overview->'firstValueRate'->>'denominator')::integer,0)
      ),
      (
        'first_value_denominator','',
        coalesce((v_overview->'firstValueRate'->>'denominator')::numeric,0),
        coalesce((v_overview->'firstValueRate'->>'denominator')::integer,0)
      ),
      (
        'core_loop_completed','',
        coalesce((v_overview->>'coreLoopCompleted')::numeric,0),
        greatest(coalesce((v_overview->>'coreLoopCompleted')::integer,0),0)
      ),
      (
        'project_completion_numerator','',
        coalesce((v_overview->'projectCompletion'->>'numerator')::numeric,0),
        coalesce((v_overview->'projectCompletion'->>'denominator')::integer,0)
      ),
      (
        'project_completion_denominator','',
        coalesce((v_overview->'projectCompletion'->>'denominator')::numeric,0),
        coalesce((v_overview->'projectCompletion'->>'denominator')::integer,0)
      ),
      (
        'lifecycle_project_count','setup',
        coalesce((v_overview->'lifecycle'->>'setup')::numeric,0),
        v_lifecycle_total
      ),
      (
        'lifecycle_project_count','collaborating',
        coalesce((v_overview->'lifecycle'->>'collaborating')::numeric,0),
        v_lifecycle_total
      ),
      (
        'lifecycle_project_count','quiet',
        coalesce((v_overview->'lifecycle'->>'quiet')::numeric,0),
        v_lifecycle_total
      ),
      (
        'lifecycle_project_count','stalled',
        coalesce((v_overview->'lifecycle'->>'stalled')::numeric,0),
        v_lifecycle_total
      ),
      (
        'lifecycle_project_count','completed',
        coalesce((v_overview->'lifecycle'->>'completed')::numeric,0),
        v_lifecycle_total
      ),
      (
        'lifecycle_project_count','archived',
        coalesce((v_overview->'lifecycle'->>'archived')::numeric,0),
        v_lifecycle_total
      )
  ) as points(metric_key,dimension_key,numeric_value,sample_size);
end;
$$;

create function private.analytics_rollup_day_v1(p_metric_date date)
returns integer
language plpgsql
volatile
security definer
set search_path=''
as $$
declare
  v_rows integer;
begin
  insert into private.analytics_daily_metrics(
    metric_date,metric_key,dimension_key,definition_version,
    numeric_value,sample_size,calculated_at
  )
  select
    p_metric_date,
    p.metric_key,
    p.dimension_key,
    1,
    p.numeric_value,
    p.sample_size,
    clock_timestamp()
  from private.analytics_rollup_points_v1(p_metric_date) p
  on conflict(metric_date,metric_key,dimension_key,definition_version)
  do update set
    numeric_value=excluded.numeric_value,
    sample_size=excluded.sample_size,
    calculated_at=excluded.calculated_at;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

create function public.run_analytics_daily_rollup_service(
  p_from_date date,
  p_to_date date,
  p_definition_version integer
) returns jsonb
language plpgsql
volatile
security definer
set search_path=''
as $$
declare
  v_date date;
  v_dates integer := 0;
  v_rows integer := 0;
begin
  if p_definition_version is distinct from 1
     or p_from_date is null
     or p_to_date is null
     or p_from_date > p_to_date then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  v_date := p_from_date;
  while v_date <= p_to_date loop
    v_rows := v_rows + private.analytics_rollup_day_v1(v_date);
    v_dates := v_dates + 1;
    v_date := v_date + 1;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'fromDate',p_from_date,
      'toDate',p_to_date,
      'definitionVersion',1,
      'datesProcessed',v_dates,
      'rowsUpserted',v_rows
    )
  );
end;
$$;

revoke all on function private.analytics_rollup_points_v1(date)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_rollup_day_v1(date)
  from public,anon,authenticated,service_role;
revoke all on function public.run_analytics_daily_rollup_service(date,date,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.run_analytics_daily_rollup_service(date,date,integer)
  to service_role;

create or replace function public.ops_get_product_timeseries_service(
  p_from_date date,
  p_to_date date,
  p_definition_version integer
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_data jsonb;
begin
  if p_definition_version is distinct from 1
     or p_from_date is null
     or p_to_date is null
     or p_from_date > p_to_date then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date',m.metric_date,
        'metricKey',m.metric_key,
        'dimensionKey',m.dimension_key,
        'value',m.numeric_value,
        'sampleSize',m.sample_size
      )
      order by m.metric_date,m.metric_key,m.dimension_key
    ),
    '[]'::jsonb
  )
  into v_data
  from private.analytics_daily_metrics m
  where m.metric_date between p_from_date and p_to_date
    and m.definition_version=p_definition_version;

  return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

revoke all on function public.ops_get_product_timeseries_service(date,date,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.ops_get_product_timeseries_service(date,date,integer)
  to service_role;
