-- Pro Phase 2 / Workstream C: authoritative project analytics.
-- The capability remains closed until G adds project_analytics to the release registry.

create index if not exists tasks_project_completed_at_idx
  on public.tasks(project_id,completed_at);

create index if not exists tasks_project_created_at_idx
  on public.tasks(project_id,created_at);

create function private.phase2_project_analytics_utc(p_value timestamptz)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select to_char(
    p_value at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
  );
$$;

create function private.phase2_project_analytics_payload(
  p_project_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_as_of timestamptz
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with
  project_row as materialized (
    select
      p.id,
      p.timezone,
      p.start_at,
      p.created_at,
      p.deadline_at,
      p.lifecycle_state,
      p.completed_at
    from public.projects p
    where p.id=p_project_id
  ),
  task_facts as materialized (
    select
      t.id,
      t.status,
      t.assignee_id,
      t.weight,
      t.deadline_at,
      t.created_at,
      t.completed_at,
      exists(
        select 1
        from public.task_dependencies d
        join public.tasks upstream
          on upstream.id=d.upstream_task_id
         and upstream.project_id=d.project_id
        where d.project_id=p_project_id
          and d.downstream_task_id=t.id
          and upstream.status<>'completed'
      ) as has_unfinished_direct_dependency
    from public.tasks t
    where t.project_id=p_project_id
      and t.status<>'canceled'
  ),
  totals as (
    select
      count(*)::bigint as task_total,
      count(*) filter(where status='completed')::bigint as completed_tasks,
      count(*) filter(
        where status not in ('completed','canceled')
          and deadline_at<p_as_of
      )::bigint as overdue_tasks,
      count(*) filter(where status='awaiting_review')::bigint as awaiting_review_tasks,
      count(*) filter(
        where status<>'completed'
          and (status='blocked' or has_unfinished_direct_dependency)
      )::bigint as blocked_tasks,
      count(*) filter(
        where status='completed'
          and completed_at>=p_from
          and completed_at<p_to
      )::bigint as completed_in_window,
      count(*) filter(
        where status='completed' and completed_at is null
      )::bigint as completed_missing_time
    from task_facts
  ),
  member_classified as (
    select
      case
        when tf.assignee_id is null then 'unassigned'
        when pm.user_id is not null then 'active_member'
        else 'former_member'
      end as kind,
      case
        when pm.user_id is not null then tf.assignee_id
        else null
      end as user_id
    from task_facts tf
    left join public.project_members pm
      on pm.project_id=p_project_id
     and pm.user_id=tf.assignee_id
     and pm.member_state='active'
     and pm.role<>'observer'
  ),
  member_counts as (
    select
      kind,
      user_id,
      count(*)::bigint as task_count,
      case kind
        when 'active_member' then 0
        when 'former_member' then 1
        else 2
      end as kind_order
    from member_classified
    group by kind,user_id
  ),
  member_distribution as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'kind',kind,
          'userId',user_id,
          'count',task_count
        )
        order by kind_order,user_id::text
      ),
      '[]'::jsonb
    ) as value
    from member_counts
  ),
  difficulty_buckets(stars,bucket_order) as (
    values
      (1::smallint,1),
      (2::smallint,2),
      (3::smallint,3),
      (4::smallint,4),
      (5::smallint,5),
      (null::smallint,6)
  ),
  difficulty_distribution as (
    select jsonb_agg(
      jsonb_build_object(
        'stars',b.stars,
        'count',coalesce(c.task_count,0::bigint)
      )
      order by b.bucket_order
    ) as value
    from difficulty_buckets b
    left join (
      select weight,count(*)::bigint as task_count
      from task_facts
      group by weight
    ) c on c.weight is not distinct from b.stars
  ),
  completion_timing as (
    select
      count(*) filter(
        where status='completed'
          and completed_at>=p_from
          and completed_at<p_to
          and completed_at>=created_at
      )::bigint as sample_count,
      round(avg(
        extract(epoch from (completed_at-created_at))::double precision
      ) filter(
        where status='completed'
          and completed_at>=p_from
          and completed_at<p_to
          and completed_at>=created_at
      ))::bigint as average_seconds,
      round((
        percentile_cont(0.5) within group(
          order by extract(epoch from (completed_at-created_at))::double precision
        ) filter(
          where status='completed'
            and completed_at>=p_from
            and completed_at<p_to
            and completed_at>=created_at
        )
      )::numeric)::bigint as median_seconds,
      count(*) filter(
        where status='completed'
          and completed_at>=p_from
          and completed_at<p_to
          and completed_at<created_at
      )::bigint as invalid_time_rows
    from task_facts
  ),
  trend_days as (
    select day_value::date as day
    from generate_series(
      ((p_from at time zone 'UTC')::date)::timestamp,
      (((p_to-interval '1 microsecond') at time zone 'UTC')::date)::timestamp,
      interval '1 day'
    ) day_value
  ),
  created_by_day as (
    select
      (created_at at time zone 'UTC')::date as day,
      count(*)::bigint as task_count
    from task_facts
    where created_at>=p_from and created_at<p_to
    group by (created_at at time zone 'UTC')::date
  ),
  completed_by_day as (
    select
      (completed_at at time zone 'UTC')::date as day,
      count(*)::bigint as task_count
    from task_facts
    where completed_at>=p_from and completed_at<p_to
    group by (completed_at at time zone 'UTC')::date
  ),
  trends as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day',to_char(d.day,'YYYY-MM-DD'),
          'created',coalesce(c.task_count,0::bigint),
          'completed',coalesce(f.task_count,0::bigint)
        )
        order by d.day
      ),
      '[]'::jsonb
    ) as value
    from trend_days d
    left join created_by_day c on c.day=d.day
    left join completed_by_day f on f.day=d.day
  )
  select jsonb_build_object(
    'ok',true,
    'schemaVersion',1,
    'projectId',p.id,
    'asOf',private.phase2_project_analytics_utc(p_as_of),
    'provenance','current_rows',
    'historyComplete',false,
    'projectTimezone',p.timezone,
    'window',jsonb_build_object(
      'from',private.phase2_project_analytics_utc(p_from),
      'to',private.phase2_project_analytics_utc(p_to),
      'bucket','day',
      'timezone','UTC'
    ),
    'totals',jsonb_build_object(
      'taskTotal',t.task_total,
      'completedTasks',t.completed_tasks,
      'overdueTasks',t.overdue_tasks,
      'awaitingReviewTasks',t.awaiting_review_tasks,
      'blockedTasks',t.blocked_tasks,
      'completedInWindow',t.completed_in_window
    ),
    'memberTaskDistribution',m.value,
    'difficultyDistribution',d.value,
    'completionTiming',jsonb_build_object(
      'count',ct.sample_count,
      'averageSeconds',ct.average_seconds,
      'medianSeconds',ct.median_seconds,
      'invalidTimeRows',ct.invalid_time_rows
    ),
    'projectCycle',jsonb_build_object(
      'startAt',private.phase2_project_analytics_utc(coalesce(p.start_at,p.created_at)),
      'startSource',case when p.start_at is null then 'created_at' else 'start_at' end,
      'deadlineAt',private.phase2_project_analytics_utc(p.deadline_at),
      'completedAt',case
        when p.lifecycle_state='completed'
        then private.phase2_project_analytics_utc(p.completed_at)
        else null
      end,
      'completedCycleSeconds',case
        when p.lifecycle_state='completed'
        then round(greatest(
          0::numeric,
          extract(epoch from (p.completed_at-coalesce(p.start_at,p.created_at)))
        ))::bigint
        else null
      end,
      'elapsedSeconds',round(greatest(
        0::numeric,
        extract(epoch from (
          case
            when p.lifecycle_state='completed' then p.completed_at
            else p_as_of
          end-coalesce(p.start_at,p.created_at)
        ))
      ))::bigint
    ),
    'trends',tr.value,
    'dataIssues',jsonb_build_object(
      'completedMissingTime',t.completed_missing_time,
      'historicalStatusReconstructionAvailable',false,
      'collaboratorCreditAvailable',false
    )
  )
  from project_row p
  cross join totals t
  cross join member_distribution m
  cross join difficulty_distribution d
  cross join completion_timing ct
  cross join trends tr;
$$;

create function public.get_project_analytics(
  p_project_id uuid,
  p_from timestamptz,
  p_to timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_as_of timestamptz:=transaction_timestamp();
begin
  if v_actor is null then
    return private.failure(null,'UNAUTHENTICATED');
  end if;

  if p_project_id is null
     or not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  if not private.is_active_member(p_project_id,v_actor) then
    return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  if p_from is null then
    return private.failure(null,'VALIDATION_FAILED','from');
  end if;
  if p_to is null then
    return private.failure(null,'VALIDATION_FAILED','to');
  end if;
  if p_from>=p_to then
    return private.failure(
      null,'VALIDATION_FAILED','from',null,
      jsonb_build_object('reason','from_must_precede_to')
    );
  end if;
  if p_to-p_from>interval '180 days' then
    return private.failure(
      null,'VALIDATION_FAILED','to',null,
      jsonb_build_object('reason','window_exceeds_180_days')
    );
  end if;
  -- A small tolerance absorbs browser/server clock skew without allowing a
  -- caller to request meaningful future facts.
  if p_to>v_as_of+interval '5 minutes' then
    return private.failure(
      null,'VALIDATION_FAILED','to',null,
      jsonb_build_object('reason','to_in_future')
    );
  end if;

  if not private.capability_is_released('project_analytics') then
    return private.failure(null,'CAPABILITY_NOT_AVAILABLE');
  end if;

  if not private.project_has_capability(p_project_id,'project_analytics') then
    return private.failure(null,'CAPABILITY_REQUIRES_PRO');
  end if;

  return private.phase2_project_analytics_payload(
    p_project_id,p_from,p_to,v_as_of
  );
end;
$$;

revoke all on function private.phase2_project_analytics_utc(timestamptz),
  private.phase2_project_analytics_payload(uuid,timestamptz,timestamptz,timestamptz)
from public,anon,authenticated,service_role;

revoke all on function public.get_project_analytics(uuid,timestamptz,timestamptz)
from public,anon,authenticated,service_role;
grant execute on function public.get_project_analytics(uuid,timestamptz,timestamptz)
to authenticated;

comment on function public.get_project_analytics(uuid,timestamptz,timestamptz)
is 'Schema v1 operational project analytics from current retained task rows; capability remains G-release gated.';
