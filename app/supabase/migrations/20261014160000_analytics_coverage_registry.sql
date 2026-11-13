create schema if not exists private;

create table private.analytics_coverage (
  source text primary key
    check (source in ('auth','umami','sentry','business_analytics')),
  complete_since timestamptz not null,
  definition_version integer not null
    check (definition_version > 0),
  verified_at timestamptz not null,
  note text
);

insert into private.lifecycle_pii_classifications(
  schema_name,
  table_name,
  column_name,
  data_type,
  classification
)
values
  ('private','analytics_coverage','source','text','free_text'),
  ('private','analytics_coverage','complete_since','timestamp with time zone','structured'),
  ('private','analytics_coverage','definition_version','integer','structured'),
  ('private','analytics_coverage','verified_at','timestamp with time zone','structured'),
  ('private','analytics_coverage','note','text','free_text');

comment on table private.analytics_coverage is
  'Verified per-source analytics completeness boundaries. Dates are set explicitly only after deployed verification.';

revoke all on table private.analytics_coverage
  from PUBLIC, anon, authenticated, service_role;

create function public.cmd_set_analytics_coverage_service(
  p_source text,
  p_complete_since timestamptz,
  p_definition_version integer,
  p_verified_at timestamptz,
  p_note text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_row private.analytics_coverage%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
  end if;

  insert into private.analytics_coverage as coverage (
    source,
    complete_since,
    definition_version,
    verified_at,
    note
  )
  values (
    p_source,
    p_complete_since,
    p_definition_version,
    p_verified_at,
    p_note
  )
  on conflict (source) do update
  set complete_since = excluded.complete_since,
      definition_version = excluded.definition_version,
      verified_at = excluded.verified_at,
      note = excluded.note
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'source', v_row.source,
    'completeSince', v_row.complete_since,
    'definitionVersion', v_row.definition_version,
    'verifiedAt', v_row.verified_at,
    'note', v_row.note
  );
end;
$$;

comment on function public.cmd_set_analytics_coverage_service(
  text,timestamptz,integer,timestamptz,text
) is
  'Service-only explicit upsert of a verified analytics source coverage boundary.';

revoke all on function public.cmd_set_analytics_coverage_service(
  text,timestamptz,integer,timestamptz,text
) from PUBLIC, anon, authenticated, service_role;
grant execute on function public.cmd_set_analytics_coverage_service(
  text,timestamptz,integer,timestamptz,text
) to service_role;

create function public.get_analytics_coverage_service()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_data jsonb;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source', coverage.source,
        'completeSince', coverage.complete_since,
        'definitionVersion', coverage.definition_version,
        'verifiedAt', coverage.verified_at,
        'note', coverage.note
      )
      order by coverage.source
    ),
    '[]'::jsonb
  )
  into v_data
  from private.analytics_coverage coverage;

  return jsonb_build_object('ok', true, 'data', v_data);
end;
$$;

comment on function public.get_analytics_coverage_service() is
  'Service-only read of verified per-source analytics coverage boundaries.';

revoke all on function public.get_analytics_coverage_service()
  from PUBLIC, anon, authenticated, service_role;
grant execute on function public.get_analytics_coverage_service()
  to service_role;
