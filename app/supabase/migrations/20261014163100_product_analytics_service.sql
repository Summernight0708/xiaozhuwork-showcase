-- TeamUp Beta product analytics service boundary v1.

create function public.ops_get_product_analytics_service(
  p_from timestamptz,
  p_to timestamptz,
  p_definition_version integer
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_overview jsonb;
  v_complete_since timestamptz;
  v_coverage_version integer;
  v_partial boolean;
  v_data jsonb;
begin
  if p_definition_version is distinct from 1
     or p_from is null
     or p_to is null
     or p_from >= p_to then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  v_overview := private.analytics_overview_v1(p_from,p_to,p_to);
  if coalesce(v_overview->>'ok','true') <> 'true' then
    return v_overview;
  end if;

  select c.complete_since,c.definition_version
    into v_complete_since,v_coverage_version
  from private.analytics_coverage c
  where c.source='business_analytics';

  v_partial :=
    v_complete_since is null
    or v_coverage_version is distinct from 1
    or v_complete_since > p_from;

  v_data :=
    jsonb_build_object(
      'schemaVersion',1,
      'definitionVersion',1,
      'coverage',jsonb_build_object(
        'businessAnalyticsCompleteSince',v_complete_since,
        'partial',v_partial
      )
    )
    || (v_overview - 'definitionVersion');

  return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

revoke all on function public.ops_get_product_analytics_service(
  timestamptz,timestamptz,integer
) from public,anon,authenticated,service_role;
grant execute on function public.ops_get_product_analytics_service(
  timestamptz,timestamptz,integer
) to service_role;

create function public.ops_get_product_timeseries_service(
  p_from_date date,
  p_to_date date,
  p_definition_version integer
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_definition_version is distinct from 1
     or p_from_date is null
     or p_to_date is null
     or p_from_date > p_to_date then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  return jsonb_build_object('ok',true,'data','[]'::jsonb);
end;
$$;

revoke all on function public.ops_get_product_timeseries_service(
  date,date,integer
) from public,anon,authenticated,service_role;
grant execute on function public.ops_get_product_timeseries_service(
  date,date,integer
) to service_role;
