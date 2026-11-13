-- F: Account-scoped Pro project discovery and C analytics authorization.
-- Neither this migration nor the RPCs enable unreleased capabilities.

create index if not exists project_members_cross_project_active_idx
  on public.project_members (user_id, project_id)
  where member_state = 'active';

create or replace function private.phase2_account_capability_failure(
  p_actor uuid,
  p_capability text
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;
  if p_capability is null
    or p_capability not in ('cross_project_overview','cross_project_analytics')
    or not private.capability_is_released(p_capability)
  then
    return private.failure(null, 'CAPABILITY_NOT_AVAILABLE');
  end if;
  if not private.is_account_pro(p_actor, transaction_timestamp()) then
    return private.failure(null, 'CAPABILITY_REQUIRES_PRO');
  end if;
  return null;
end;
$$;

revoke all on function private.phase2_account_capability_failure(uuid,text)
  from public, anon, authenticated, service_role;

create or replace function public.get_my_cross_project_projects(
  p_search text default null,
  p_limit integer default 50,
  p_after_project_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_failure jsonb;
  v_search text := nullif(btrim(p_search), '');
  v_pattern text;
  v_limit integer;
  v_projects jsonb;
  v_last_id uuid;
  v_count integer;
begin
  v_failure := private.phase2_account_capability_failure(
    v_actor, 'cross_project_overview'
  );
  if v_failure is not null then return v_failure; end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    return private.failure(null, 'VALIDATION_FAILED', 'limit');
  end if;
  if p_search is not null and char_length(v_search) > 100 then
    return private.failure(null, 'VALIDATION_FAILED', 'search');
  end if;
  v_limit := p_limit;

  -- LIKE metacharacters are literal input, not client-controlled patterns.
  if v_search is not null then
    v_pattern := '%' ||
      replace(replace(replace(v_search, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
  end if;

  with page as (
    select p.id, p.name, p.course_name, p.timezone,
           p.deadline_at, p.lifecycle_state
    from public.project_members pm
    join public.projects p on p.id = pm.project_id
    where pm.user_id = v_actor
      and pm.member_state = 'active'
      and (p_after_project_id is null or p.id > p_after_project_id)
      and (
        v_pattern is null
        or p.name ilike v_pattern escape E'\\'
        or p.course_name ilike v_pattern escape E'\\'
      )
    order by p.id asc
    limit v_limit + 1
  ), numbered as (
    select page.*, row_number() over (order by id asc) as rn
    from page
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'projectId', id, 'name', name, 'courseName', course_name,
          'timezone', timezone, 'deadlineAt', deadline_at,
          'lifecycleState', lifecycle_state
        ) order by id
      ) filter (where rn <= v_limit),
      '[]'::jsonb
    ),
    (max(id::text) filter (where rn <= v_limit))::uuid,
    count(*)::integer
  into v_projects, v_last_id, v_count
  from numbered;

  return jsonb_build_object(
    'ok', true,
    'schemaVersion', 1,
    'projects', v_projects,
    'nextCursor', case when v_count > v_limit then v_last_id else null end
  );
end;
$$;

-- Edge-only discovery. An optional explicit set is validated atomically:
-- one inaccessible ID invalidates the entire request, never filters it.
-- Passing NULL means all projects (max 100); '{}' means none.
create or replace function public.get_my_cross_project_access(
  p_project_ids uuid[] default null
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_failure jsonb;
  v_ids uuid[];
  v_count integer;
begin
  v_failure := private.phase2_account_capability_failure(
    v_actor, 'cross_project_analytics'
  );
  if v_failure is not null then return v_failure; end if;

  if p_project_ids is null then
    select array_agg(project_id order by project_id)
    into v_ids
    from (
      select pm.project_id
      from public.project_members pm
      where pm.user_id = v_actor and pm.member_state = 'active'
      order by pm.project_id
      limit 101
    ) visible;
    v_count := coalesce(cardinality(v_ids), 0);
    if v_count > 100 then
      return private.failure(null, 'QUERY_LIMIT_EXCEEDED');
    end if;
  else
    if cardinality(p_project_ids) > 500 or array_position(p_project_ids, null) is not null then
      return private.failure(null, 'VALIDATION_FAILED', 'projectIds');
    end if;
    select array_agg(id order by id)
    into v_ids
    from (select distinct unnest(p_project_ids) as id) distinct_ids;
    v_count := coalesce(cardinality(v_ids), 0);
    if v_count > 100 then
      return private.failure(null, 'QUERY_LIMIT_EXCEEDED');
    end if;
    if exists (
      select 1
      from unnest(coalesce(v_ids,'{}'::uuid[])) as requested(id)
      where not exists (
        select 1 from public.project_members pm
        where pm.project_id = requested.id
          and pm.user_id = v_actor
          and pm.member_state = 'active'
      )
    ) then
      return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'schemaVersion', 1,
    'projectIds', to_jsonb(coalesce(v_ids,'{}'::uuid[]))
  );
end;
$$;

comment on function public.get_my_cross_project_access(uuid[]) is
  'F-only Edge preflight and postflight: account capability + active memberships, no task data.';

revoke all on function public.get_my_cross_project_projects(text,integer,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_cross_project_access(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_cross_project_projects(text,integer,uuid)
  to authenticated;
grant execute on function public.get_my_cross_project_access(uuid[])
  to authenticated;
