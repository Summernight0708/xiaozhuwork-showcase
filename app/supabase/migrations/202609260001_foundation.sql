create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  real_name text,
  student_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (display_name is null or char_length(display_name) between 1 and 80),
  constraint profiles_real_name_length check (real_name is null or char_length(real_name) between 1 and 120)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  course_name text,
  description text,
  timezone text not null default 'Asia/Shanghai',
  deadline_at timestamptz not null,
  contribution_mode text not null default 'weighted',
  auto_penalty_enabled boolean not null default false,
  require_real_name boolean not null default false,
  require_student_number boolean not null default false,
  leader_id uuid references auth.users (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  archived_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_name_length check (char_length(name) between 1 and 120),
  constraint projects_course_name_length check (course_name is null or char_length(course_name) <= 120),
  constraint projects_description_length check (description is null or char_length(description) <= 2000),
  constraint projects_contribution_mode check (contribution_mode in ('weighted', 'facts_only')),
  constraint projects_version_positive check (version > 0)
);

create table public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  role text not null default 'member',
  member_state text not null default 'active',
  is_observer boolean not null default false,
  joined_at timestamptz not null default now(),
  departed_at timestamptz,
  display_name_snapshot text,
  created_at timestamptz not null default now(),
  constraint project_members_role check (role in ('leader', 'member')),
  constraint project_members_state check (member_state in ('invited', 'active', 'left', 'removed', 'deleted')),
  constraint project_members_user_project_unique unique (project_id, user_id),
  constraint project_members_departure_state check ((member_state = 'active' and departed_at is null) or member_state <> 'active')
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  title text not null,
  description text,
  created_by uuid references auth.users (id) on delete set null,
  assignee_id uuid references auth.users (id) on delete set null,
  deadline_at timestamptz not null,
  status text not null default 'not_started',
  weight smallint,
  is_direct_assignment boolean not null default false,
  accepted_at timestamptz,
  first_submitted_at timestamptz,
  completed_at timestamptz,
  blocked_reason text,
  version integer not null default 1,
  canceled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_title_length check (char_length(title) between 1 and 240),
  constraint tasks_description_length check (description is null or char_length(description) <= 4000),
  constraint tasks_status check (status in ('not_started', 'in_progress', 'blocked', 'awaiting_review', 'completed', 'canceled')),
  constraint tasks_weight_range check (weight is null or weight between 1 and 5),
  constraint tasks_blocked_reason check ((status = 'blocked' and blocked_reason is not null and char_length(blocked_reason) > 0) or status <> 'blocked'),
  constraint tasks_canceled_reason check ((status = 'canceled' and canceled_at is not null and cancel_reason is not null) or status <> 'canceled'),
  constraint tasks_version_positive check (version > 0),
  constraint tasks_project_id_unique unique (project_id, id)
);

create table public.task_dependencies (
  project_id uuid not null references public.projects (id) on delete cascade,
  upstream_task_id uuid not null,
  downstream_task_id uuid not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (upstream_task_id, downstream_task_id),
  foreign key (project_id, upstream_task_id) references public.tasks (project_id, id) on delete cascade,
  foreign key (project_id, downstream_task_id) references public.tasks (project_id, id) on delete cascade,
  constraint task_dependencies_no_self_reference check (upstream_task_id <> downstream_task_id)
);

create table public.business_events (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.projects (id),
  actor_id uuid references auth.users (id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  request_id uuid,
  event_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint business_events_type_not_empty check (length(event_type) > 0),
  constraint business_events_entity_not_empty check (length(entity_type) > 0)
);

create table public.command_requests (
  project_id uuid not null references public.projects (id) on delete cascade,
  actor_id uuid not null references auth.users (id) on delete cascade,
  command_name text not null,
  request_id uuid not null,
  result jsonb,
  resulting_version integer,
  created_at timestamptz not null default now(),
  primary key (project_id, actor_id, command_name, request_id),
  constraint command_requests_name_not_empty check (length(command_name) > 0)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  notification_type text not null,
  entity_type text,
  entity_id uuid,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_message_length check (char_length(message) between 1 and 1000)
);

create function public.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.create_profile_for_auth_user() from public, anon, authenticated;
create trigger auth_user_creates_profile
after insert on auth.users
for each row execute function public.create_profile_for_auth_user();

create index project_members_user_state_idx on public.project_members (user_id, member_state);
create index tasks_project_status_deadline_idx on public.tasks (project_id, status, deadline_at);
create index task_dependencies_downstream_idx on public.task_dependencies (downstream_task_id);
create index business_events_project_created_idx on public.business_events (project_id, created_at desc);
create unique index business_events_request_unique_idx on public.business_events (project_id, actor_id, event_type, request_id) where request_id is not null;
create index notifications_recipient_unread_idx on public.notifications (recipient_id, created_at desc) where read_at is null;

create function public.is_active_project_member(target_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.project_members pm
    where pm.project_id = target_project_id
      and pm.user_id = (select auth.uid())
      and pm.member_state = 'active'
  );
$$;
revoke all on function public.is_active_project_member(uuid) from public, anon;
grant execute on function public.is_active_project_member(uuid) to authenticated;

create function public.enforce_task_project_deadline()
returns trigger
language plpgsql
set search_path = ''
as $$
declare project_deadline timestamptz;
begin
  select p.deadline_at into project_deadline from public.projects p where p.id = new.project_id;
  if project_deadline is null or new.deadline_at > project_deadline then
    raise exception using errcode = '23514', constraint = 'tasks_within_project_deadline',
      message = 'Task deadline must not exceed the project deadline';
  end if;
  return new;
end;
$$;
create trigger tasks_enforce_project_deadline
before insert or update of project_id, deadline_at on public.tasks
for each row execute function public.enforce_task_project_deadline();

create function public.enforce_project_deadline_against_tasks()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deadline_at is distinct from old.deadline_at and exists (
    select 1 from public.tasks t where t.project_id = new.id and t.deadline_at > new.deadline_at
  ) then
    raise exception using errcode = '23514', constraint = 'project_deadline_covers_tasks',
      message = 'Project deadline cannot precede an existing task deadline';
  end if;
  return new;
end;
$$;
create trigger projects_enforce_task_deadlines
before update of deadline_at on public.projects
for each row execute function public.enforce_project_deadline_against_tasks();

create function public.reject_business_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and old.actor_id is not null
    and new.actor_id is null
    and (to_jsonb(new) - 'actor_id') = (to_jsonb(old) - 'actor_id') then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Business events are immutable';
end;
$$;
create trigger business_events_immutable
before update or delete on public.business_events
for each row execute function public.reject_business_event_mutation();

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.tasks enable row level security;
alter table public.task_dependencies enable row level security;
alter table public.business_events enable row level security;
alter table public.command_requests enable row level security;
alter table public.notifications enable row level security;

create policy profiles_select_self on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_self on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy projects_select_active_member on public.projects for select to authenticated using (public.is_active_project_member(id));
create policy project_members_select_same_project on public.project_members for select to authenticated using (public.is_active_project_member(project_id));
create policy tasks_select_active_member on public.tasks for select to authenticated using (public.is_active_project_member(project_id));
create policy task_dependencies_select_active_member on public.task_dependencies for select to authenticated using (public.is_active_project_member(project_id));
create policy business_events_select_active_member on public.business_events for select to authenticated using (public.is_active_project_member(project_id));
create policy notifications_select_recipient on public.notifications for select to authenticated using (recipient_id = (select auth.uid()));
create policy notifications_mark_read on public.notifications for update to authenticated using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));

revoke all on public.profiles, public.projects, public.project_members, public.tasks,
  public.task_dependencies, public.business_events, public.command_requests, public.notifications
  from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, real_name, student_number) on public.profiles to authenticated;
grant select on public.projects, public.project_members, public.tasks, public.task_dependencies, public.business_events to authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

comment on table public.business_events is 'Append-only project audit facts; only the actor reference may be nulled for account deletion. Restrictive project FK deliberately prevents hard delete until the approved retention purge is implemented.';
comment on table public.command_requests is 'Idempotency ledger; populated transactionally by command RPCs.';
comment on table public.project_members is 'Membership truth; client writes are withheld until transactional command RPCs exist.';
