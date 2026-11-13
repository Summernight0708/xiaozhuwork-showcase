-- Task responsibility extension: one primary assignee plus opt-in collaborators.
-- tasks.assignee_id remains the only primary delivery responsibility.

create table public.task_collaborators (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  task_id uuid not null,
  user_id uuid references auth.users (id) on delete set null,
  user_name_snapshot text,
  state text not null default 'pending',
  invited_by uuid references auth.users (id) on delete set null,
  invited_by_name_snapshot text,
  responded_at timestamptz,
  removed_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id)
    references public.tasks (project_id, id) on delete cascade,
  constraint task_collaborators_state
    check (state in ('pending','accepted','rejected','removed')),
  constraint task_collaborators_version_positive check (version > 0),
  constraint task_collaborators_response_state check (
    (state = 'pending' and responded_at is null and removed_at is null)
    or (state in ('accepted','rejected') and responded_at is not null and removed_at is null)
    or (state = 'removed' and removed_at is not null)
  )
);

create unique index task_collaborators_active_task_user_unique
  on public.task_collaborators (task_id, user_id)
  where user_id is not null and state in ('pending','accepted');
create index task_collaborators_project_state_idx
  on public.task_collaborators (project_id, state, created_at);
create index task_collaborators_user_state_idx
  on public.task_collaborators (user_id, state, updated_at)
  where user_id is not null;

alter table public.task_collaborators enable row level security;

create policy task_collaborators_select_active_member
on public.task_collaborators for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_collaborators from public, anon, authenticated, service_role;
grant select on public.task_collaborators to authenticated;

create or replace function private.is_eligible_task_collaborator_member(
  p_project_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.project_members pm
    where pm.project_id = p_project_id
      and pm.user_id = p_user_id
      and pm.member_state = 'active'
      and pm.role <> 'observer'
      and pm.is_observer is false
  );
$$;

create or replace function private.has_accepted_task_collaboration(
  p_project_id uuid,
  p_task_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.task_collaborators c
    where c.project_id = p_project_id
      and c.task_id = p_task_id
      and c.user_id = p_user_id
      and c.state = 'accepted'
  );
$$;

create or replace function private.is_task_participant(
  p_project_id uuid,
  p_task_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_eligible_task_collaborator_member(p_project_id, p_user_id)
    and exists (
      select 1
      from public.tasks t
      where t.project_id = p_project_id
        and t.id = p_task_id
        and (
          t.assignee_id = p_user_id
          or private.has_accepted_task_collaboration(
            p_project_id,p_task_id,p_user_id
          )
        )
    );
$$;

create or replace function private.can_manage_task_collaborators(
  p_project_id uuid,
  p_task_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_eligible_task_collaborator_member(p_project_id,p_user_id)
    and exists (
      select 1
      from public.tasks t
      where t.project_id=p_project_id
        and t.id=p_task_id
        and (
          t.created_by=p_user_id
          or private.is_active_leader(p_project_id,p_user_id)
        )
    );
$$;

create or replace function private.assert_task_collaborator_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_assignee uuid;
begin
  if new.state in ('pending','accepted') then
    if new.user_id is null
       or not private.is_eligible_task_collaborator_member(new.project_id,new.user_id) then
      raise exception using
        errcode='23514',
        constraint='task_collaborator_requires_active_non_observer_member',
        message='Pending or accepted collaborator must be an active non-observer project member';
    end if;

    select t.assignee_id into v_assignee
    from public.tasks t
    where t.project_id=new.project_id and t.id=new.task_id;

    if v_assignee is not distinct from new.user_id then
      raise exception using
        errcode='23514',
        constraint='task_primary_assignee_not_collaborator',
        message='Primary assignee cannot also be a pending or accepted collaborator';
    end if;
  end if;
  return new;
end;
$$;

create trigger task_collaborators_integrity
before insert or update on public.task_collaborators
for each row execute function private.assert_task_collaborator_integrity();

create or replace function private.assert_task_primary_not_collaborator()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.assignee_id is not null and exists (
    select 1
    from public.task_collaborators c
    where c.project_id=new.project_id
      and c.task_id=new.id
      and c.user_id=new.assignee_id
      and c.state in ('pending','accepted')
  ) then
    raise exception using
      errcode='23514',
      constraint='task_primary_assignee_not_collaborator',
      message='Primary assignee cannot also be a pending or accepted collaborator';
  end if;
  return new;
end;
$$;

create trigger tasks_primary_collaborator_integrity
before update of assignee_id on public.tasks
for each row execute function private.assert_task_primary_not_collaborator();

create or replace function public.cmd_invite_task_collaborator(
  p_project_id uuid,
  p_task_id uuid,
  p_user_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_relation public.task_collaborators%rowtype;
  v_user_name text;
  v_actor_name text;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_task_id is null or p_user_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId'
           when p_task_id is null then 'taskId'
           else 'userId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'userId',p_user_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_invite_task_collaborator',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.can_manage_task_collaborators(p_project_id,p_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p
  where p.id=p_project_id for update;
  select * into v_task from public.tasks t
  where t.project_id=p_project_id and t.id=p_task_id for update;
  if not found then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_relation
  from public.task_collaborators c
  where c.task_id=p_task_id
    and c.user_id=p_user_id
    and c.state in ('pending','accepted')
  for update;

  if not private.can_manage_task_collaborators(p_project_id,p_task_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.assignment_state <> 'assigned' or v_task.assignee_id is null
        or v_task.status in ('completed','canceled') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_not_open_for_collaboration')
    );
  elsif not private.is_eligible_task_collaborator_member(p_project_id,p_user_id) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','userId');
  elsif v_task.assignee_id=p_user_id then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_assignee_cannot_collaborate')
    );
  elsif v_relation.id is null and coalesce(p_expected_version,-1) <> 0 then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,0);
  elsif v_relation.id is not null and p_expected_version is distinct from v_relation.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_relation.version);
  elsif v_relation.id is not null then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_relation.version,
      jsonb_build_object('reason','collaboration_already_active')
    );
  else
    select coalesce(p.display_name,pm.display_name_snapshot,'成员')
      into v_user_name
    from public.project_members pm
    left join public.profiles p on p.id=pm.user_id
    where pm.project_id=p_project_id and pm.user_id=p_user_id
    limit 1;

    select coalesce(p.display_name,pm.display_name_snapshot,'成员')
      into v_actor_name
    from public.project_members pm
    left join public.profiles p on p.id=pm.user_id
    where pm.project_id=p_project_id and pm.user_id=v_actor
    limit 1;

    insert into public.task_collaborators(
      project_id,task_id,user_id,user_name_snapshot,state,invited_by,
      invited_by_name_snapshot
    ) values(
      p_project_id,p_task_id,p_user_id,v_user_name,'pending',v_actor,v_actor_name
    ) returning * into v_relation;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_collaborator_invited','task_collaborator',v_relation.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'userId',p_user_id,'collaboratorVersion',v_relation.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'collaboratorId',v_relation.id,'userId',p_user_id,
        'state',v_relation.state,'collaboratorVersion',v_relation.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_collaborator','aggregateId',v_relation.id,
      'aggregateVersion',v_relation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_collaborator',v_relation.id,v_relation.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_respond_to_task_collaborator(
  p_project_id uuid,
  p_task_id uuid,
  p_collaborator_id uuid,
  p_action text,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_relation public.task_collaborators%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'collaboratorId',p_collaborator_id,
    'action',p_action,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_respond_to_task_collaborator',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    exists(
      select 1 from public.task_collaborators c
      where c.id=p_collaborator_id and c.project_id=p_project_id
        and c.task_id=p_task_id and c.user_id=v_actor
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p
  where p.id=p_project_id for update;
  select * into v_task from public.tasks t
  where t.project_id=p_project_id and t.id=p_task_id for update;
  select * into v_relation from public.task_collaborators c
  where c.id=p_collaborator_id and c.project_id=p_project_id
    and c.task_id=p_task_id for update;

  if v_relation.id is null or v_relation.user_id is distinct from v_actor then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_relation.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_relation.version);
  elsif v_relation.state <> 'pending' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_relation.version,
      jsonb_build_object('reason','invitation_not_pending')
    );
  elsif p_action is null or p_action not in ('accept','reject') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='accept' and v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_action='accept' and (
    v_task.id is null
    or v_task.assignment_state <> 'assigned'
    or v_task.assignee_id is null
    or v_task.status in ('completed','canceled')
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,coalesce(v_task.version,0),
      jsonb_build_object('reason','task_not_open_for_collaboration')
    );
  elsif p_action='accept'
        and not private.is_eligible_task_collaborator_member(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_action='accept' and v_task.assignee_id=v_actor then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_relation.version,
      jsonb_build_object('reason','primary_assignee_cannot_collaborate')
    );
  else
    update public.task_collaborators
    set state=case p_action when 'accept' then 'accepted' else 'rejected' end,
        responded_at=now(),
        removed_at=null,
        version=version+1,
        updated_at=now()
    where id=v_relation.id
    returning * into v_relation;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case p_action
        when 'accept' then 'task_collaborator_accepted'
        else 'task_collaborator_rejected'
      end,
      'task_collaborator',v_relation.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'userId',v_actor,'collaboratorVersion',v_relation.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'collaboratorId',v_relation.id,'userId',v_actor,
        'state',v_relation.state,'collaboratorVersion',v_relation.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_collaborator','aggregateId',v_relation.id,
      'aggregateVersion',v_relation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_collaborator',v_relation.id,v_relation.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_remove_task_collaborator(
  p_project_id uuid,
  p_task_id uuid,
  p_collaborator_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_relation public.task_collaborators%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,
    'collaboratorId',p_collaborator_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_remove_task_collaborator',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.can_manage_task_collaborators(p_project_id,p_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.projects p
  where p.id=p_project_id for update;
  perform 1 from public.tasks t
  where t.project_id=p_project_id and t.id=p_task_id for update;
  select * into v_relation from public.task_collaborators c
  where c.id=p_collaborator_id and c.project_id=p_project_id
    and c.task_id=p_task_id for update;

  if not private.can_manage_task_collaborators(p_project_id,p_task_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_relation.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_relation.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_relation.version);
  elsif v_relation.state not in ('pending','accepted') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_relation.version,
      jsonb_build_object('reason','collaboration_not_active')
    );
  else
    update public.task_collaborators
    set state='removed',removed_at=now(),version=version+1,updated_at=now()
    where id=v_relation.id
    returning * into v_relation;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_collaborator_removed','task_collaborator',v_relation.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'userId',v_relation.user_id,
        'collaboratorVersion',v_relation.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'collaboratorId',v_relation.id,'userId',v_relation.user_id,
        'state',v_relation.state,'collaboratorVersion',v_relation.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_collaborator','aggregateId',v_relation.id,
      'aggregateVersion',v_relation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_collaborator',v_relation.id,v_relation.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_leave_task_collaboration(
  p_project_id uuid,
  p_task_id uuid,
  p_collaborator_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_relation public.task_collaborators%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,
    'collaboratorId',p_collaborator_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_leave_task_collaboration',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    exists(
      select 1 from public.task_collaborators c
      where c.id=p_collaborator_id and c.project_id=p_project_id
        and c.task_id=p_task_id and c.user_id=v_actor
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.projects p
  where p.id=p_project_id for update;
  perform 1 from public.tasks t
  where t.project_id=p_project_id and t.id=p_task_id for update;
  select * into v_relation from public.task_collaborators c
  where c.id=p_collaborator_id and c.project_id=p_project_id
    and c.task_id=p_task_id for update;

  if v_relation.id is null or v_relation.user_id is distinct from v_actor then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_relation.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_relation.version);
  elsif v_relation.state <> 'accepted' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_relation.version,
      jsonb_build_object('reason','collaboration_not_accepted')
    );
  else
    update public.task_collaborators
    set state='removed',removed_at=now(),version=version+1,updated_at=now()
    where id=v_relation.id
    returning * into v_relation;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_collaborator_left','task_collaborator',v_relation.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'userId',v_actor,'collaboratorVersion',v_relation.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'collaboratorId',v_relation.id,'userId',v_actor,
        'state',v_relation.state,'collaboratorVersion',v_relation.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_collaborator','aggregateId',v_relation.id,
      'aggregateVersion',v_relation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_collaborator',v_relation.id,v_relation.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

-- Collaborators can advance task work, but this does not grant final submission.
create or replace function public.cmd_update_task_progress(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer,
  p_status text, p_progress_text text, p_blocked_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version,
    'status',p_status,'progressText',p_progress_text,'blockedReason',p_blocked_reason
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_update_task_progress',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_task_participant(p_project_id,p_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects
  where id=p_project_id for update;
  select * into v_task from public.tasks
  where id=p_task_id and project_id=p_project_id for update;

  if not private.is_task_participant(p_project_id,p_task_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_status is null or p_status not in ('in_progress','blocked') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','status');
  elsif p_progress_text is null or char_length(btrim(p_progress_text)) not between 1 and 2000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','progressText');
  elsif p_status='blocked' and nullif(btrim(p_blocked_reason),'') is null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','blockedReason');
  else
    update public.tasks
    set status=p_status,
        progress_text=btrim(p_progress_text),
        blocked_reason=case when p_status='blocked' then btrim(p_blocked_reason) else null end,
        version=version+1,
        updated_at=now()
    where id=p_task_id
    returning * into v_task;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'task_progress_updated','task',
      p_task_id,p_request_id,jsonb_build_object('status',p_status,'version',v_task.version)
    );
    v_result:=jsonb_strip_nulls(jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'status',v_task.status,'progressText',v_task.progress_text,
        'blockedReason',v_task.blocked_reason,'updatedAt',v_task.updated_at
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version
    ));
    return private.complete_command(
      v_claim.command_id,v_result,'task',p_task_id,v_task.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

-- Existing file reservation/finalization/storage policies call this helper.
create or replace function private.is_current_task_file_actor(
  p_project_id uuid,
  p_task_id uuid,
  p_actor_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_active_member(p_project_id,p_actor_id)
    and exists (
      select 1
      from public.tasks t
      where t.id=p_task_id
        and t.project_id=p_project_id
        and (
          private.is_task_participant(p_project_id,p_task_id,p_actor_id)
          or t.created_by=p_actor_id
          or private.is_active_leader(p_project_id,p_actor_id)
        )
    );
$$;

-- Prevent an accepted collaborator from claiming the same task as primary.
create or replace function public.cmd_claim_task(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_claim_task',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects
  where id=p_project_id for update;
  select * into v_task from public.tasks
  where id=p_task_id and project_id=p_project_id for update;
  if not found then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_task.assignment_state<>'claimable' or v_task.assignee_id is not null then
    v_result:=private.failure(p_request_id,'TASK_ALREADY_CLAIMED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif exists (
    select 1
    from public.task_collaborators c
    where c.project_id=p_project_id
      and c.task_id=p_task_id
      and c.user_id=v_actor
      and c.state in ('pending','accepted')
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','collaboration_must_resolve_before_primary')
    );
  elsif v_task.deadline_at<=now() then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE');
  else
    update public.tasks
    set assignee_id=v_actor,assignment_state='assigned',accepted_at=now(),
        status='in_progress',version=version+1,updated_at=now()
    where id=p_task_id
    returning * into v_task;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'task_claimed','task',
      p_task_id,p_request_id,jsonb_build_object('version',v_task.version)
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'assigneeId',v_actor,'acceptedAt',v_task.accepted_at
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task',p_task_id,v_task.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_respond_to_task_assignment(
  p_project_id uuid, p_task_id uuid, p_assignment_offer_id uuid, p_action text,
  p_request_id uuid, p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_offer public.task_assignment_offers%rowtype;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,
    'assignmentOfferId',p_assignment_offer_id,'action',p_action,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_respond_to_task_assignment',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    exists(
      select 1 from public.task_assignment_offers o
      where o.id=p_assignment_offer_id and o.project_id=p_project_id
        and o.task_id=p_task_id and o.target_user_id=v_actor
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects
  where id=p_project_id for update;
  select * into v_task from public.tasks
  where id=p_task_id and project_id=p_project_id for update;
  select * into v_offer from public.task_assignment_offers
  where id=p_assignment_offer_id and task_id=p_task_id and project_id=p_project_id
  for update;

  if v_offer.state<>'pending' or v_task.assignment_state<>'pending_acceptance' then
    v_result:=private.failure(p_request_id,'ASSIGNMENT_NOT_PENDING');
  elsif p_expected_version is null or v_offer.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_offer.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_action is null or p_action not in ('accept','reject') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='accept' and exists (
    select 1
    from public.task_collaborators c
    where c.project_id=p_project_id
      and c.task_id=p_task_id
      and c.user_id=v_actor
      and c.state in ('pending','accepted')
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','collaboration_must_resolve_before_primary')
    );
  elsif p_action='accept' and v_task.deadline_at<=now() then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE');
  else
    update public.task_assignment_offers
    set state=case p_action when 'accept' then 'accepted' else 'rejected' end,
        version=version+1,responded_at=now(),updated_at=now()
    where id=v_offer.id
    returning * into v_offer;
    if p_action='accept' then
      update public.tasks
      set assignee_id=v_actor,accepted_at=now(),status='in_progress',
          assignment_state='assigned',version=version+1,updated_at=now()
      where id=v_task.id
      returning * into v_task;
    else
      update public.tasks
      set assignment_state='claimable',is_direct_assignment=false,
          version=version+1,updated_at=now()
      where id=v_task.id
      returning * into v_task;
    end if;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case p_action
        when 'accept' then 'task_assignment_accepted'
        else 'task_assignment_rejected'
      end,
      'assignment_offer',v_offer.id,p_request_id,
      jsonb_build_object('taskVersion',v_task.version)
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',v_task.id,'assignmentOfferId',v_offer.id,
        'outcome',case p_action when 'accept' then 'accepted' else 'rejected' end,
        'taskVersion',v_task.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','assignment_offer','aggregateId',v_offer.id,
      'aggregateVersion',v_offer.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'assignment_offer',v_offer.id,v_offer.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function private.notify_from_task_collaborator_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.tasks%rowtype;
  v_recipient uuid;
  v_actor_name text;
begin
  if new.event_type not in (
    'task_collaborator_invited',
    'task_collaborator_accepted',
    'task_collaborator_removed',
    'task_collaborator_left'
  ) then
    return new;
  end if;

  select * into v_task from public.tasks t
  where t.project_id=new.project_id
    and t.id=nullif(new.event_data->>'taskId','')::uuid;
  if not found then return new; end if;

  select coalesce(p.display_name,pm.display_name_snapshot,'成员')
    into v_actor_name
  from public.project_members pm
  left join public.profiles p on p.id=pm.user_id
  where pm.project_id=new.project_id and pm.user_id=new.actor_id
  limit 1;
  v_actor_name:=coalesce(v_actor_name,'成员');

  if new.event_type='task_collaborator_invited' then
    v_recipient:=nullif(new.event_data->>'userId','')::uuid;
    if private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_collaborator_invited','协作邀请',
        v_actor_name || '邀请你协作任务「' || v_task.title || '」。',
        'task',v_task.id
      );
    end if;

  elsif new.event_type='task_collaborator_removed' then
    v_recipient:=nullif(new.event_data->>'userId','')::uuid;
    if private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_collaborator_removed','协作已结束',
        '你已不再参与「' || v_task.title || '」。',
        'task',v_task.id
      );
    end if;

  elsif new.event_type='task_collaborator_accepted' then
    if v_task.created_by is not null
       and v_task.created_by is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_task.created_by) then
      perform private.create_notification(
        new.id,new.project_id,v_task.created_by,
        'task_collaborator_accepted','协作者已加入',
        v_actor_name || '已加入「' || v_task.title || '」协作。',
        'task',v_task.id
      );
    end if;
    if v_task.assignee_id is not null
       and v_task.assignee_id is distinct from new.actor_id
       and v_task.assignee_id is distinct from v_task.created_by
       and private.is_active_member(new.project_id,v_task.assignee_id) then
      perform private.create_notification(
        new.id,new.project_id,v_task.assignee_id,
        'task_collaborator_accepted','协作者已加入',
        v_actor_name || '已加入「' || v_task.title || '」协作。',
        'task',v_task.id
      );
    end if;

  elsif new.event_type='task_collaborator_left' then
    if v_task.created_by is not null
       and v_task.created_by is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_task.created_by) then
      perform private.create_notification(
        new.id,new.project_id,v_task.created_by,
        'task_collaborator_left','协作者已退出',
        v_actor_name || '已退出「' || v_task.title || '」协作。',
        'task',v_task.id
      );
    end if;
    if v_task.assignee_id is not null
       and v_task.assignee_id is distinct from new.actor_id
       and v_task.assignee_id is distinct from v_task.created_by
       and private.is_active_member(new.project_id,v_task.assignee_id) then
      perform private.create_notification(
        new.id,new.project_id,v_task.assignee_id,
        'task_collaborator_left','协作者已退出',
        v_actor_name || '已退出「' || v_task.title || '」协作。',
        'task',v_task.id
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger business_event_creates_task_collaborator_notification
after insert on public.business_events
for each row execute function private.notify_from_task_collaborator_event();

revoke all on function private.is_eligible_task_collaborator_member(uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.has_accepted_task_collaboration(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.is_task_participant(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.can_manage_task_collaborators(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.assert_task_collaborator_integrity()
  from public,anon,authenticated,service_role;
revoke all on function private.assert_task_primary_not_collaborator()
  from public,anon,authenticated,service_role;
revoke all on function private.notify_from_task_collaborator_event()
  from public,anon,authenticated,service_role;

revoke all on function public.cmd_invite_task_collaborator(
  uuid,uuid,uuid,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_invite_task_collaborator(
  uuid,uuid,uuid,uuid,integer
) to authenticated;

revoke all on function public.cmd_respond_to_task_collaborator(
  uuid,uuid,uuid,text,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_respond_to_task_collaborator(
  uuid,uuid,uuid,text,uuid,integer
) to authenticated;

revoke all on function public.cmd_remove_task_collaborator(
  uuid,uuid,uuid,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_remove_task_collaborator(
  uuid,uuid,uuid,uuid,integer
) to authenticated;

revoke all on function public.cmd_leave_task_collaboration(
  uuid,uuid,uuid,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_leave_task_collaboration(
  uuid,uuid,uuid,uuid,integer
) to authenticated;

comment on table public.task_collaborators is
  'Opt-in task collaboration lifecycle. tasks.assignee_id remains the sole primary assignee and final delivery owner.';
comment on function private.is_task_participant(uuid,uuid,uuid) is
  'Shared domain predicate for primary assignee or accepted collaborator; excludes observers and inactive members.';
