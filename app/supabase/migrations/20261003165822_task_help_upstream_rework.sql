-- Task Help & Upstream Rework: durable facts, commands, and notifications.

create table public.task_help_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  requested_by uuid not null,
  target_user_id uuid not null,
  message text not null,
  marks_task_blocked boolean not null default false,
  blocked_task_version integer,
  state text not null default 'open',
  resolved_by uuid,
  resolved_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id,task_id) references public.tasks(project_id,id) on delete cascade,
  constraint task_help_requests_message_length check (char_length(btrim(message)) between 1 and 2000),
  constraint task_help_requests_state check (state in ('open','resolved')),
  constraint task_help_requests_version_positive check (version > 0),
  constraint task_help_requests_block_version_positive check (blocked_task_version is null or blocked_task_version > 0),
  constraint task_help_requests_block_fact_consistency check (
    (marks_task_blocked and blocked_task_version is not null)
    or (not marks_task_blocked and blocked_task_version is null)
  ),
  constraint task_help_requests_resolution_consistency check (
    (state='open' and resolved_by is null and resolved_at is null)
    or (state='resolved' and resolved_by is not null and resolved_at is not null)
  )
);

create index task_help_requests_project_task_created_idx
  on public.task_help_requests(project_id,task_id,created_at desc);
create index task_help_requests_target_open_idx
  on public.task_help_requests(target_user_id,created_at desc)
  where state='open';

create table public.upstream_rework_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  downstream_task_id uuid not null,
  upstream_task_id uuid not null,
  requested_by uuid not null,
  requirement text not null,
  state text not null default 'pending',
  upstream_completed_version integer not null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id,downstream_task_id) references public.tasks(project_id,id) on delete cascade,
  foreign key (project_id,upstream_task_id) references public.tasks(project_id,id) on delete cascade,
  constraint upstream_rework_requests_distinct_tasks check (downstream_task_id <> upstream_task_id),
  constraint upstream_rework_requests_requirement_length check (char_length(btrim(requirement)) between 1 and 2000),
  constraint upstream_rework_requests_state check (state in ('pending','approved','rejected')),
  constraint upstream_rework_requests_completed_version_positive check (upstream_completed_version > 0),
  constraint upstream_rework_requests_version_positive check (version > 0),
  constraint upstream_rework_requests_review_consistency check (
    (state='pending' and reviewed_by is null and reviewed_at is null)
    or (state in ('approved','rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);

create unique index upstream_rework_one_pending_per_upstream_idx
  on public.upstream_rework_requests(upstream_task_id)
  where state='pending';
create index upstream_rework_project_downstream_created_idx
  on public.upstream_rework_requests(project_id,downstream_task_id,created_at desc);
create index upstream_rework_project_upstream_created_idx
  on public.upstream_rework_requests(project_id,upstream_task_id,created_at desc);

alter table public.task_help_requests enable row level security;
alter table public.upstream_rework_requests enable row level security;

create policy task_help_select_member
on public.task_help_requests for select to authenticated
using (public.is_active_project_member(project_id));

create policy upstream_rework_select_member
on public.upstream_rework_requests for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_help_requests, public.upstream_rework_requests
  from public,anon,authenticated,service_role;
grant select on public.task_help_requests, public.upstream_rework_requests to authenticated;
create function public.cmd_create_task_help_request(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_message text,
  p_target_user_id uuid default null,
  p_marks_task_blocked boolean default false
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
  v_target_id uuid;
  v_help public.task_help_requests%rowtype;
  v_message text:=btrim(p_message);
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_task_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'taskId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version,
    'message',p_message,'targetUserId',p_target_user_id,
    'marksTaskBlocked',coalesce(p_marks_task_blocked,false)
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_create_task_help_request',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
    and private.is_task_participant(p_project_id,p_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p where p.id=p_project_id for update;
  select * into v_task
  from public.tasks t
  where t.id=p_task_id and t.project_id=p_project_id
  for update;

  if p_target_user_id is null then
    select pm.user_id into v_target_id
    from public.project_members pm
    where pm.project_id=p_project_id
      and pm.role='leader'
      and pm.member_state='active'
    order by pm.created_at,pm.id
    limit 1;
  else
    select pm.user_id into v_target_id
    from public.project_members pm
    where pm.project_id=p_project_id
      and pm.user_id=p_target_user_id
      and pm.member_state='active'
      and pm.role<>'observer'
    limit 1;
  end if;

  if v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.id is null
        or not private.is_task_participant(p_project_id,p_task_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_message is null or char_length(v_message) not between 1 and 2000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','message',v_task.version);
  elsif v_target_id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','targetUserId',v_task.version);
  elsif v_task.status not in ('not_started','in_progress','blocked') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_state_not_helpable','status',v_task.status)
    );
  elsif coalesce(p_marks_task_blocked,false) and v_task.status='blocked' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_already_blocked')
    );
  else
    if coalesce(p_marks_task_blocked,false) then
      update public.tasks
      set status='blocked',blocked_reason=v_message,version=version+1,updated_at=now()
      where id=v_task.id
      returning * into v_task;
    end if;

    insert into public.task_help_requests(
      project_id,task_id,requested_by,target_user_id,message,
      marks_task_blocked,blocked_task_version
    ) values(
      p_project_id,p_task_id,v_actor,v_target_id,v_message,
      coalesce(p_marks_task_blocked,false),
      case when coalesce(p_marks_task_blocked,false) then v_task.version else null end
    )
    returning * into v_help;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_help_requested','task_help_request',v_help.id,p_request_id,
      jsonb_build_object(
        'taskId',v_task.id,'helpVersion',v_help.version,'taskVersion',v_task.version,
        'targetUserId',v_target_id,'marksTaskBlocked',v_help.marks_task_blocked
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'helpRequestId',v_help.id,'state',v_help.state,'helpVersion',v_help.version,
        'taskVersion',v_task.version,'taskResumed',false
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_help_request','aggregateId',v_help.id,'aggregateVersion',v_help.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_help_request',v_help.id,v_help.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_resolve_task_help_request(
  p_project_id uuid,
  p_help_request_id uuid,
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
  v_help public.task_help_requests%rowtype;
  v_task public.tasks%rowtype;
  v_task_id uuid;
  v_task_resumed boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_help_request_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'helpRequestId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'helpRequestId',p_help_request_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_resolve_task_help_request',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
    and exists(
      select 1 from public.task_help_requests h
      where h.id=p_help_request_id and h.project_id=p_project_id
        and (
          h.requested_by=v_actor
          or h.target_user_id=v_actor
          or private.is_active_leader(p_project_id,v_actor)
        )
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p where p.id=p_project_id for update;
  select h.task_id into v_task_id
  from public.task_help_requests h
  where h.id=p_help_request_id and h.project_id=p_project_id;
  if v_task_id is not null then
    select * into v_task
    from public.tasks t
    where t.id=v_task_id and t.project_id=p_project_id
    for update;
  end if;
  select * into v_help
  from public.task_help_requests h
  where h.id=p_help_request_id and h.project_id=p_project_id
  for update;

  if v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_help.id is null or v_task.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif not (
    v_help.requested_by=v_actor
    or v_help.target_user_id=v_actor
    or private.is_active_leader(p_project_id,v_actor)
  ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_help.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_help.version);
  elsif v_help.state<>'open' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_help.version,
      jsonb_build_object('reason','help_request_not_open','state',v_help.state)
    );
  else
    update public.task_help_requests
    set state='resolved',resolved_by=v_actor,resolved_at=now(),
        version=version+1,updated_at=now()
    where id=v_help.id
    returning * into v_help;

    if v_help.marks_task_blocked
       and v_help.blocked_task_version is not null
       and v_task.status='blocked'
       and v_task.version=v_help.blocked_task_version
       and v_task.blocked_reason=v_help.message then
      update public.tasks
      set status='in_progress',blocked_reason=null,version=version+1,updated_at=now()
      where id=v_task.id
      returning * into v_task;
      v_task_resumed:=true;
    end if;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_help_resolved','task_help_request',v_help.id,p_request_id,
      jsonb_build_object(
        'taskId',v_task.id,'helpVersion',v_help.version,'taskVersion',v_task.version,
        'taskResumed',v_task_resumed,'targetUserId',v_help.target_user_id
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'helpRequestId',v_help.id,'state',v_help.state,'helpVersion',v_help.version,
        'taskVersion',v_task.version,'taskResumed',v_task_resumed
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_help_request','aggregateId',v_help.id,'aggregateVersion',v_help.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_help_request',v_help.id,v_help.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_create_task_help_request(uuid,uuid,uuid,integer,text,uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_task_help_request(uuid,uuid,uuid,integer,text,uuid,boolean)
  to authenticated;

revoke all on function public.cmd_resolve_task_help_request(uuid,uuid,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_resolve_task_help_request(uuid,uuid,uuid,integer)
  to authenticated;
create function public.cmd_request_upstream_rework(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_upstream_task_id uuid,
  p_request_id uuid,
  p_expected_downstream_version integer,
  p_expected_upstream_version integer,
  p_requirement text
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
  v_downstream public.tasks%rowtype;
  v_upstream public.tasks%rowtype;
  v_request public.upstream_rework_requests%rowtype;
  v_requirement text:=btrim(p_requirement);
  v_is_leader boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_downstream_task_id is null or p_upstream_task_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case
        when p_project_id is null then 'projectId'
        when p_downstream_task_id is null then 'downstreamTaskId'
        else 'upstreamTaskId'
      end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'downstreamTaskId',p_downstream_task_id,
    'upstreamTaskId',p_upstream_task_id,'expectedDownstreamVersion',p_expected_downstream_version,
    'expectedUpstreamVersion',p_expected_upstream_version,'requirement',p_requirement
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_request_upstream_rework',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
    and (
      private.is_active_leader(p_project_id,v_actor)
      or private.is_task_participant(p_project_id,p_downstream_task_id,v_actor)
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p where p.id=p_project_id for update;

  perform t.id
  from public.tasks t
  where t.project_id=p_project_id
    and t.id in (p_downstream_task_id,p_upstream_task_id)
  order by t.id
  for update;

  select * into v_downstream
  from public.tasks t
  where t.id=p_downstream_task_id and t.project_id=p_project_id;
  select * into v_upstream
  from public.tasks t
  where t.id=p_upstream_task_id and t.project_id=p_project_id;

  v_is_leader:=private.is_active_leader(p_project_id,v_actor);

  if v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_downstream.id is null or v_upstream.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif not v_is_leader
        and not private.is_task_participant(
          p_project_id,p_downstream_task_id,v_actor
        ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_downstream_version is null
        or v_downstream.version<>p_expected_downstream_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_downstream.version,
      jsonb_build_object('entity','downstreamTask')
    );
  elsif p_expected_upstream_version is null
        or v_upstream.version<>p_expected_upstream_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_upstream.version,
      jsonb_build_object('entity','upstreamTask')
    );
  elsif v_requirement is null or char_length(v_requirement) not between 1 and 2000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','requirement');
  elsif not exists(
    select 1 from public.task_dependencies d
    where d.project_id=p_project_id
      and d.downstream_task_id=p_downstream_task_id
      and d.upstream_task_id=p_upstream_task_id
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_downstream.version,
      jsonb_build_object('reason','not_direct_upstream')
    );
  elsif v_upstream.status<>'completed' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_upstream.version,
      jsonb_build_object('reason','upstream_not_completed','status',v_upstream.status)
    );
  elsif exists(
    select 1 from public.upstream_rework_requests r
    where r.upstream_task_id=p_upstream_task_id and r.state='pending'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_upstream.version,
      jsonb_build_object('reason','upstream_rework_already_pending')
    );
  else
    if v_is_leader then
      insert into public.upstream_rework_requests(
        project_id,downstream_task_id,upstream_task_id,requested_by,requirement,
        state,upstream_completed_version,reviewed_by,reviewed_at
      ) values(
        p_project_id,p_downstream_task_id,p_upstream_task_id,v_actor,v_requirement,
        'approved',v_upstream.version,v_actor,now()
      )
      returning * into v_request;

      update public.tasks
      set status='in_progress',completed_at=null,blocked_reason=null,
          version=version+1,updated_at=now()
      where id=v_upstream.id and project_id=p_project_id
      returning * into v_upstream;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        'upstream_rework_approved','upstream_rework_request',v_request.id,p_request_id,
        jsonb_build_object(
          'downstreamTaskId',v_downstream.id,'upstreamTaskId',v_upstream.id,
          'requestVersion',v_request.version,'upstreamTaskVersion',v_upstream.version,
          'directByLeader',true
        )
      );
    else
      insert into public.upstream_rework_requests(
        project_id,downstream_task_id,upstream_task_id,requested_by,requirement,
        state,upstream_completed_version
      ) values(
        p_project_id,p_downstream_task_id,p_upstream_task_id,v_actor,v_requirement,
        'pending',v_upstream.version
      )
      returning * into v_request;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        'upstream_rework_requested','upstream_rework_request',v_request.id,p_request_id,
        jsonb_build_object(
          'downstreamTaskId',v_downstream.id,'upstreamTaskId',v_upstream.id,
          'requestVersion',v_request.version,'upstreamTaskVersion',v_upstream.version
        )
      );
    end if;

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'reworkRequestId',v_request.id,'state',v_request.state,
        'requestVersion',v_request.version,'downstreamTaskVersion',v_downstream.version,
        'upstreamTaskVersion',v_upstream.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','upstream_rework_request','aggregateId',v_request.id,
      'aggregateVersion',v_request.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'upstream_rework_request',v_request.id,v_request.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_review_upstream_rework(
  p_project_id uuid,
  p_rework_request_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_action text
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
  v_snapshot public.upstream_rework_requests%rowtype;
  v_request public.upstream_rework_requests%rowtype;
  v_downstream public.tasks%rowtype;
  v_upstream public.tasks%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_rework_request_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'reworkRequestId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'reworkRequestId',p_rework_request_id,
    'expectedVersion',p_expected_version,'action',p_action
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_review_upstream_rework',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor)
    and exists(
      select 1 from public.upstream_rework_requests r
      where r.id=p_rework_request_id and r.project_id=p_project_id
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p where p.id=p_project_id for update;

  select * into v_snapshot
  from public.upstream_rework_requests r
  where r.id=p_rework_request_id and r.project_id=p_project_id;

  if v_snapshot.id is not null then
    perform t.id
    from public.tasks t
    where t.project_id=p_project_id
      and t.id in (v_snapshot.downstream_task_id,v_snapshot.upstream_task_id)
    order by t.id
    for update;
  end if;

  select * into v_request
  from public.upstream_rework_requests r
  where r.id=p_rework_request_id and r.project_id=p_project_id
  for update;

  if v_request.id is not null then
    select * into v_downstream
    from public.tasks t
    where t.id=v_request.downstream_task_id and t.project_id=p_project_id;
    select * into v_upstream
    from public.tasks t
    where t.id=v_request.upstream_task_id and t.project_id=p_project_id;
  end if;

  if v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_request.id is null or v_downstream.id is null or v_upstream.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_request.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_request.version);
  elsif v_request.state<>'pending' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_request.version,
      jsonb_build_object('reason','rework_request_not_pending','state',v_request.state)
    );
  elsif p_action is null or p_action not in ('approve','reject') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action',v_request.version);
  elsif not exists(
    select 1 from public.task_dependencies d
    where d.project_id=p_project_id
      and d.downstream_task_id=v_request.downstream_task_id
      and d.upstream_task_id=v_request.upstream_task_id
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_request.version,
      jsonb_build_object('reason','dependency_no_longer_direct')
    );
  elsif p_action='approve' and v_upstream.status<>'completed' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_request.version,
      jsonb_build_object('reason','upstream_not_completed','status',v_upstream.status)
    );
  elsif p_action='approve' and v_upstream.version<>v_request.upstream_completed_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_upstream.version,
      jsonb_build_object('entity','upstreamTask','expectedVersion',v_request.upstream_completed_version)
    );
  else
    update public.upstream_rework_requests
    set state=case when p_action='approve' then 'approved' else 'rejected' end,
        reviewed_by=v_actor,reviewed_at=now(),version=version+1,updated_at=now()
    where id=v_request.id
    returning * into v_request;

    if p_action='approve' then
      update public.tasks
      set status='in_progress',completed_at=null,blocked_reason=null,
          version=version+1,updated_at=now()
      where id=v_upstream.id and project_id=p_project_id
      returning * into v_upstream;
    end if;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case when p_action='approve' then 'upstream_rework_approved' else 'upstream_rework_rejected' end,
      'upstream_rework_request',v_request.id,p_request_id,
      jsonb_build_object(
        'downstreamTaskId',v_downstream.id,'upstreamTaskId',v_upstream.id,
        'requestVersion',v_request.version,'upstreamTaskVersion',v_upstream.version
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'reworkRequestId',v_request.id,'state',v_request.state,
        'requestVersion',v_request.version,'downstreamTaskVersion',v_downstream.version,
        'upstreamTaskVersion',v_upstream.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','upstream_rework_request','aggregateId',v_request.id,
      'aggregateVersion',v_request.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'upstream_rework_request',v_request.id,v_request.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_request_upstream_rework(uuid,uuid,uuid,uuid,integer,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_request_upstream_rework(uuid,uuid,uuid,uuid,integer,integer,text)
  to authenticated;

revoke all on function public.cmd_review_upstream_rework(uuid,uuid,uuid,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_review_upstream_rework(uuid,uuid,uuid,integer,text)
  to authenticated;
create function private.notify_task_help_rework_from_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_help public.task_help_requests%rowtype;
  v_rework public.upstream_rework_requests%rowtype;
  v_recipient uuid;
  v_downstream record;
begin
  if new.event_type in ('task_help_requested','task_help_resolved') then
    select * into v_help
    from public.task_help_requests h
    where h.id=new.entity_id and h.project_id=new.project_id;

    if v_help.id is null then
      return new;
    end if;

    if new.event_type='task_help_requested' then
      if v_help.target_user_id is distinct from new.actor_id
         and exists(
           select 1 from public.project_members pm
           where pm.project_id=new.project_id
             and pm.user_id=v_help.target_user_id
             and pm.member_state='active'
         ) then
        perform private.create_notification(
          new.id,new.project_id,v_help.target_user_id,
          'task_help_requested','收到任务求助',
          '一项与你相关的任务正在请求协助。','task',v_help.task_id
        );
      end if;
    else
      for v_recipient in
        select distinct x.user_id
        from (values (v_help.requested_by),(v_help.target_user_id)) as x(user_id)
        join public.project_members pm
          on pm.project_id=new.project_id
         and pm.user_id=x.user_id
         and pm.member_state='active'
        where x.user_id is distinct from new.actor_id
      loop
        perform private.create_notification(
          new.id,new.project_id,v_recipient,
          'task_help_resolved','任务求助已解决',
          '一项与你相关的任务求助已被解决。','task',v_help.task_id
        );
      end loop;
    end if;

  elsif new.event_type in (
    'upstream_rework_requested','upstream_rework_approved','upstream_rework_rejected'
  ) then
    select * into v_rework
    from public.upstream_rework_requests r
    where r.id=new.entity_id and r.project_id=new.project_id;

    if v_rework.id is null then
      return new;
    end if;

    if new.event_type='upstream_rework_requested' then
      for v_recipient in
        select distinct pm.user_id
        from public.project_members pm
        where pm.project_id=new.project_id
          and pm.role='leader'
          and pm.member_state='active'
          and pm.user_id is distinct from new.actor_id
      loop
        perform private.create_notification(
          new.id,new.project_id,v_recipient,
          'upstream_rework_requested','收到上游返工申请',
          '一个直接上游任务收到返工申请，等待组长处理。','task',v_rework.downstream_task_id
        );
      end loop;
    else
      if v_rework.requested_by is distinct from new.actor_id
         and exists(
           select 1 from public.project_members pm
           where pm.project_id=new.project_id
             and pm.user_id=v_rework.requested_by
             and pm.member_state='active'
         ) then
        perform private.create_notification(
          new.id,new.project_id,v_rework.requested_by,
          case when new.event_type='upstream_rework_approved'
            then 'upstream_rework_approved' else 'upstream_rework_rejected' end,
          case when new.event_type='upstream_rework_approved'
            then '上游返工已批准' else '上游返工未批准' end,
          case when new.event_type='upstream_rework_approved'
            then '你的上游返工申请已批准。' else '你的上游返工申请未获批准。' end,
          'task',v_rework.downstream_task_id
        );
      end if;

      if new.event_type='upstream_rework_approved' then
        select t.assignee_id into v_recipient
        from public.tasks t
        where t.id=v_rework.upstream_task_id and t.project_id=new.project_id;

        if v_recipient is distinct from new.actor_id
           and exists(
             select 1 from public.project_members pm
             where pm.project_id=new.project_id
               and pm.user_id=v_recipient
               and pm.member_state='active'
           ) then
          perform private.create_notification(
            new.id,new.project_id,v_recipient,
            'upstream_rework_approved','上游任务需要返工',
            '你负责的任务已被重新打开，需要继续处理。','task',v_rework.upstream_task_id
          );
        end if;

        for v_downstream in
          select distinct t.assignee_id as recipient_id,t.id as task_id
          from public.task_dependencies d
          join public.tasks t
            on t.project_id=d.project_id
           and t.id=d.downstream_task_id
          join public.project_members pm
            on pm.project_id=t.project_id
           and pm.user_id=t.assignee_id
           and pm.member_state='active'
          where d.project_id=new.project_id
            and d.upstream_task_id=v_rework.upstream_task_id
            and t.status not in ('completed','canceled')
            and t.assignee_id is not null
          order by t.assignee_id,t.id
        loop
          if v_downstream.recipient_id is distinct from new.actor_id then
            perform private.create_notification(
              new.id,new.project_id,v_downstream.recipient_id,
              'upstream_rework_approved','直接上游已进入返工',
              '你负责的任务有一个直接上游被重新打开。','task',v_downstream.task_id
            );
          end if;
        end loop;
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.notify_task_help_rework_from_event()
  from public,anon,authenticated,service_role;

create trigger business_event_notifies_task_help_rework
after insert on public.business_events
for each row execute function private.notify_task_help_rework_from_event();
