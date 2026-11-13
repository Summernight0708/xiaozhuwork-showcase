-- TeamUp Beta product analytics definition v1:
-- capture actor eligibility at business-event insertion time.
--
-- Historical rows are intentionally not backfilled. Pre-coverage events whose
-- event-time role cannot be proven remain incomplete rather than being guessed
-- from current membership state.

create table private.analytics_event_actor_eligibility (
  business_event_id bigint primary key,
  project_id uuid not null,
  actor_user_id uuid,
  actor_was_eligible boolean not null,
  definition_version integer not null default 1
    check (definition_version = 1),
  captured_at timestamptz not null default transaction_timestamp()
);

create index analytics_event_actor_project_idx
  on private.analytics_event_actor_eligibility(project_id, business_event_id);

alter table private.analytics_event_actor_eligibility enable row level security;
revoke all on private.analytics_event_actor_eligibility
  from public, anon, authenticated, service_role;

create function private.analytics_is_effective_event_v1(p_event_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_event_type = any(array[
      'project_member_joined',
      'task_assignment_accepted',
      'task_claimed',
      'task_collaborator_accepted',
      'task_created',
      'task_file_version_final_marked',
      'task_submission_approved',
      'task_submission_changes_requested',
      'task_submission_rejected',
      'task_submitted_for_review',
      'task_submitted_without_review',
      'upstream_rework_approved',
      'upstream_rework_requested'
    ]::text[]),
    false
  );
$$;

revoke all on function private.analytics_is_effective_event_v1(text)
  from public, anon, authenticated, service_role;

create function private.capture_analytics_event_actor_eligibility_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eligible boolean := false;
begin
  if not private.analytics_is_effective_event_v1(new.event_type) then
    return new;
  end if;

  if new.actor_id is not null then
    select exists(
      select 1
      from public.project_members pm
      where pm.project_id = new.project_id
        and pm.user_id = new.actor_id
        and pm.member_state = 'active'
        and not pm.is_observer
    )
    into v_eligible;
  end if;

  insert into private.analytics_event_actor_eligibility(
    business_event_id,
    project_id,
    actor_user_id,
    actor_was_eligible,
    definition_version,
    captured_at
  ) values (
    new.id,
    new.project_id,
    new.actor_id,
    coalesce(v_eligible, false),
    1,
    transaction_timestamp()
  );

  return new;
end;
$$;

revoke all on function private.capture_analytics_event_actor_eligibility_v1()
  from public, anon, authenticated, service_role;

create trigger business_event_snapshots_analytics_actor_v1
after insert on public.business_events
for each row
execute function private.capture_analytics_event_actor_eligibility_v1();

-- Keep the F2 privacy inventory complete. This is a conservative review
-- classification only; it does not approve retention or cleanup behavior.
insert into private.lifecycle_pii_classifications(
  schema_name,
  table_name,
  column_name,
  data_type,
  classification
)
select
  n.nspname,
  c.relname,
  a.attname,
  format_type(a.atttypid, a.atttypmod),
  case
    when format_type(a.atttypid, a.atttypmod) = 'uuid'
      then 'identity_reference'
    when format_type(a.atttypid, a.atttypmod) in ('json', 'jsonb')
      then 'unstructured_json'
    when format_type(a.atttypid, a.atttypmod) ~ '^(text|character|citext)'
      then 'free_text'
    else 'structured'
  end
from pg_attribute a
join pg_class c on c.oid = a.attrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'private'
  and c.relname = 'analytics_event_actor_eligibility'
  and c.relkind in ('r', 'p')
  and a.attnum > 0
  and not a.attisdropped
on conflict (schema_name, table_name, column_name) do update
set data_type = excluded.data_type,
    classification = excluded.classification,
    disposition = 'manual_review_required';

-- Definition v1 semantic helpers. All actor-dependent facts consume the
-- event-time eligibility snapshot above; current membership is never used to
-- reinterpret historical collaboration events.
create function private.analytics_project_activation_at_v1(
  p_project_id uuid,
  p_at timestamptz
) returns timestamptz
language sql
stable
set search_path = ''
as $$
  with actor_first as (
    select
      a.actor_user_id,
      min(e.created_at) as first_at
    from private.analytics_event_actor_eligibility a
    join public.business_events e on e.id = a.business_event_id
    where a.project_id = p_project_id
      and a.definition_version = 1
      and a.actor_was_eligible
      and a.actor_user_id is not null
      and e.created_at <= p_at
    group by a.actor_user_id
  ),
  first_two as (
    select actor_user_id, first_at
    from actor_first
    order by first_at, actor_user_id
    limit 2
  )
  select case when count(*) = 2 then max(first_at) else null end
  from first_two;
$$;

create function private.analytics_project_last_collaboration_at_v1(
  p_project_id uuid,
  p_at timestamptz
) returns timestamptz
language sql
stable
set search_path = ''
as $$
  select max(e.created_at)
  from private.analytics_event_actor_eligibility a
  join public.business_events e on e.id = a.business_event_id
  where a.project_id = p_project_id
    and a.definition_version = 1
    and a.actor_was_eligible
    and a.actor_user_id is not null
    and e.created_at <= p_at;
$$;

create function private.analytics_project_first_value_at_v1(
  p_project_id uuid,
  p_at timestamptz
) returns timestamptz
language sql
stable
set search_path = ''
as $$
  select min(e.created_at)
  from private.analytics_event_actor_eligibility a
  join public.business_events e on e.id = a.business_event_id
  join public.tasks t
    on t.project_id = e.project_id
   and (e.event_data->>'taskId') ~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and t.id = (e.event_data->>'taskId')::uuid
  where a.project_id = p_project_id
    and a.definition_version = 1
    and a.actor_was_eligible
    and e.created_at <= p_at
    and t.status = 'completed'
    and t.completed_at is not null
    and t.completed_at <= p_at
    and (
      (e.event_type = 'task_submission_approved' and t.requires_review)
      or
      (e.event_type = 'task_submitted_without_review' and not t.requires_review)
    );
$$;

create function private.analytics_project_facts_v1(
  p_project_id uuid,
  p_at timestamptz
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_project public.projects%rowtype;
  v_activated_at timestamptz;
  v_first_value_at timestamptz;
  v_last_collaboration_at timestamptz;
  v_completed_at timestamptz;
  v_archived_at timestamptz;
  v_eligible_members integer;
  v_completed_tasks integer;
  v_lifecycle text;
begin
  if p_project_id is null or p_at is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  select * into v_project
  from public.projects p
  where p.id = p_project_id;

  if not found then
    return jsonb_build_object('ok',false,'code','NOT_FOUND');
  end if;

  v_activated_at :=
    private.analytics_project_activation_at_v1(p_project_id, p_at);
  v_last_collaboration_at :=
    private.analytics_project_last_collaboration_at_v1(p_project_id, p_at);
  v_first_value_at :=
    private.analytics_project_first_value_at_v1(p_project_id, p_at);

  if v_activated_at is not null and v_last_collaboration_at is null then
    return jsonb_build_object(
      'ok',false,
      'code','SERVICE_DATA_INCOMPLETE',
      'reason','activated_without_last_collaboration'
    );
  end if;

  v_completed_at := case
    when v_project.completed_at is not null and v_project.completed_at <= p_at
      then v_project.completed_at
    else null
  end;
  v_archived_at := case
    when v_project.archived_at is not null and v_project.archived_at <= p_at
      then v_project.archived_at
    else null
  end;

  select count(*)::integer
  into v_eligible_members
  from public.project_members pm
  where pm.project_id = p_project_id
    and pm.member_state = 'active'
    and not pm.is_observer
    and pm.user_id is not null;

  select count(*)::integer
  into v_completed_tasks
  from public.tasks t
  where t.project_id = p_project_id
    and t.status = 'completed'
    and t.completed_at is not null
    and t.completed_at <= p_at;

  v_lifecycle := case
    when v_archived_at is not null then 'archived'
    when v_completed_at is not null then 'completed'
    when v_activated_at is null then 'setup'
    when v_last_collaboration_at > p_at - interval '168 hours'
      then 'collaborating'
    when v_last_collaboration_at > p_at - interval '336 hours'
      then 'quiet'
    else 'stalled'
  end;

  return jsonb_build_object(
    'activatedAt',v_activated_at,
    'firstValueAt',v_first_value_at,
    'lastCollaborationAt',v_last_collaboration_at,
    'completedAt',v_completed_at,
    'archivedAt',v_archived_at,
    'eligibleMemberCount',v_eligible_members,
    'completedTaskCount',v_completed_tasks,
    'lifecycle',v_lifecycle
  );
end;
$$;

create function private.analytics_user_activation_at_v1(p_user_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with account as (
    select u.created_at
    from auth.users u
    where u.id = p_user_id
  ),
  actor_projects as (
    select distinct a.project_id
    from private.analytics_event_actor_eligibility a
    where a.definition_version = 1
      and a.actor_was_eligible
      and a.actor_user_id = p_user_id
  ),
  candidates as (
    select
      ap.project_id,
      private.analytics_project_activation_at_v1(
        ap.project_id,
        'infinity'::timestamptz
      ) as activated_at
    from actor_projects ap
  )
  select min(c.activated_at)
  from candidates c
  cross join account u
  where c.activated_at is not null
    and c.activated_at <= u.created_at + interval '168 hours'
    and exists (
      select 1
      from private.analytics_event_actor_eligibility a
      join public.business_events e on e.id = a.business_event_id
      where a.project_id = c.project_id
        and a.definition_version = 1
        and a.actor_was_eligible
        and a.actor_user_id = p_user_id
        and e.created_at <= c.activated_at
    );
$$;

create function private.analytics_user_activated_v1(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.analytics_user_activation_at_v1(p_user_id) is not null;
$$;

create function private.analytics_wacp_v1(p_week_start date)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_value integer;
begin
  if p_week_start is null
     or extract(isodow from p_week_start)::integer <> 1 then
    raise exception using
      errcode = '22023',
      message = 'WEEK_START_MUST_BE_SHANGHAI_MONDAY';
  end if;

  v_start := p_week_start::timestamp at time zone 'Asia/Shanghai';
  v_end := (p_week_start + 7)::timestamp at time zone 'Asia/Shanghai';

  select count(*)::integer
  into v_value
  from (
    select a.project_id
    from private.analytics_event_actor_eligibility a
    join public.business_events e on e.id = a.business_event_id
    where a.definition_version = 1
      and a.actor_was_eligible
      and a.actor_user_id is not null
      and e.created_at >= v_start
      and e.created_at < v_end
    group by a.project_id
    having count(distinct a.actor_user_id) >= 2
  ) q;

  return coalesce(v_value,0);
end;
$$;

create function private.analytics_rate_fact_v1(
  p_numerator bigint,
  p_denominator bigint
) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'numerator',coalesce(p_numerator,0),
    'denominator',coalesce(p_denominator,0),
    'rate',case
      when coalesce(p_denominator,0) = 0 then null
      else coalesce(p_numerator,0)::numeric / p_denominator::numeric
    end
  );
$$;

create function private.analytics_overview_v1(
  p_from timestamptz,
  p_to timestamptz,
  p_at timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project_den bigint := 0;
  v_project_activation_num bigint := 0;
  v_user_den bigint := 0;
  v_user_activation_num bigint := 0;
  v_first_value_den bigint := 0;
  v_first_value_num bigint := 0;
  v_core_loop_completed bigint := 0;
  v_project_completion_num bigint := 0;
  v_setup bigint := 0;
  v_collaborating bigint := 0;
  v_quiet bigint := 0;
  v_stalled bigint := 0;
  v_completed bigint := 0;
  v_archived bigint := 0;
  v_week_start date;
begin
  if p_from is null or p_to is null or p_at is null or p_from >= p_to then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  with cohort as (
    select
      p.id,
      p.completed_at,
      private.analytics_project_facts_v1(p.id,p_at) as facts
    from public.projects p
    where p.created_at >= p_from
      and p.created_at < p_to
      and p.created_at <= p_at
  )
  select
    count(*)::bigint,
    count(*) filter (
      where (facts->>'activatedAt') is not null
    )::bigint,
    count(*) filter (
      where (facts->>'activatedAt') is not null
    )::bigint,
    count(*) filter (
      where (facts->>'activatedAt') is not null
        and (facts->>'firstValueAt') is not null
    )::bigint,
    count(*) filter (
      where p.completed_at is not null and p.completed_at <= p_at
    )::bigint,
    count(*) filter (where facts->>'lifecycle'='setup')::bigint,
    count(*) filter (where facts->>'lifecycle'='collaborating')::bigint,
    count(*) filter (where facts->>'lifecycle'='quiet')::bigint,
    count(*) filter (where facts->>'lifecycle'='stalled')::bigint,
    count(*) filter (where facts->>'lifecycle'='completed')::bigint,
    count(*) filter (where facts->>'lifecycle'='archived')::bigint
  into
    v_project_den,
    v_project_activation_num,
    v_first_value_den,
    v_first_value_num,
    v_project_completion_num,
    v_setup,
    v_collaborating,
    v_quiet,
    v_stalled,
    v_completed,
    v_archived
  from cohort p;

  with user_cohort as (
    select
      u.id,
      private.analytics_user_activation_at_v1(u.id) as activated_at
    from auth.users u
    where u.created_at >= p_from
      and u.created_at < p_to
      and u.created_at <= p_at
  )
  select
    count(*)::bigint,
    count(*) filter (
      where activated_at is not null and activated_at <= p_at
    )::bigint
  into v_user_den,v_user_activation_num
  from user_cohort;

  select count(*)::bigint
  into v_core_loop_completed
  from private.analytics_event_actor_eligibility a
  join public.business_events e on e.id = a.business_event_id
  join public.tasks t
    on t.project_id = e.project_id
   and (e.event_data->>'taskId') ~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and t.id = (e.event_data->>'taskId')::uuid
  where a.definition_version = 1
    and a.actor_was_eligible
    and e.created_at >= p_from
    and e.created_at < p_to
    and e.created_at <= p_at
    and t.status = 'completed'
    and t.completed_at is not null
    and t.completed_at <= p_at
    and (
      (e.event_type='task_submission_approved' and t.requires_review)
      or
      (e.event_type='task_submitted_without_review' and not t.requires_review)
    );

  v_week_start :=
    date_trunc('week',p_at at time zone 'Asia/Shanghai')::date;

  return jsonb_build_object(
    'definitionVersion',1,
    'wacp',jsonb_build_object(
      'weekStart',v_week_start,
      'value',private.analytics_wacp_v1(v_week_start)
    ),
    'projectActivation',
      private.analytics_rate_fact_v1(v_project_activation_num,v_project_den),
    'userActivation',
      private.analytics_rate_fact_v1(v_user_activation_num,v_user_den),
    'firstValueRate',
      private.analytics_rate_fact_v1(v_first_value_num,v_first_value_den),
    'coreLoopCompleted',v_core_loop_completed,
    'lifecycle',jsonb_build_object(
      'setup',v_setup,
      'collaborating',v_collaborating,
      'quiet',v_quiet,
      'stalled',v_stalled,
      'completed',v_completed,
      'archived',v_archived
    ),
    'projectCompletion',
      private.analytics_rate_fact_v1(v_project_completion_num,v_project_den)
  );
end;
$$;

revoke all on function private.analytics_project_activation_at_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_project_last_collaboration_at_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_project_first_value_at_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_project_facts_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_user_activation_at_v1(uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_user_activated_v1(uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_wacp_v1(date)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_rate_fact_v1(bigint,bigint)
  from public,anon,authenticated,service_role;
revoke all on function private.analytics_overview_v1(timestamptz,timestamptz,timestamptz)
  from public,anon,authenticated,service_role;
