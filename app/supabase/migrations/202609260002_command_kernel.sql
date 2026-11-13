do $$
begin
  if exists (select 1 from public.command_requests) then
    raise exception 'command_requests must be empty before installing the command kernel';
  end if;
end;
$$;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.command_requests drop constraint command_requests_pkey;
alter table public.command_requests alter column project_id drop not null;
alter table public.command_requests
  add column id uuid not null default gen_random_uuid(),
  add column account_id uuid references auth.users (id) on delete cascade,
  add column payload_hash bytea not null,
  add column state text not null default 'in_progress',
  add column resulting_entity_type text,
  add column resulting_entity_id uuid,
  add column updated_at timestamptz not null default now(),
  add column completed_at timestamptz,
  add constraint command_requests_pkey primary key (id),
  add constraint command_requests_scope_xor check (num_nonnulls(account_id, project_id) = 1),
  add constraint command_requests_state check (state in ('in_progress', 'completed')),
  add constraint command_requests_completion check (
    (state = 'in_progress' and completed_at is null) or
    (state = 'completed' and completed_at is not null and result is not null)
  );
alter table public.command_requests rename column resulting_version to resulting_entity_version;
alter table public.command_requests
  alter constraint command_requests_project_id_fkey deferrable initially deferred;
create unique index command_requests_account_key_idx
  on public.command_requests (account_id, actor_id, command_name, request_id)
  where account_id is not null;
create unique index command_requests_project_key_idx
  on public.command_requests (project_id, actor_id, command_name, request_id)
  where project_id is not null;

drop index public.business_events_request_unique_idx;
alter table public.business_events
  add column command_request_id uuid references public.command_requests (id),
  add column event_seq integer,
  add constraint business_events_command_sequence check (
    (command_request_id is null and event_seq is null) or
    (command_request_id is not null and event_seq is not null and event_seq > 0)
  );
create unique index business_events_command_sequence_idx
  on public.business_events (command_request_id, event_seq)
  where command_request_id is not null;
create index business_events_command_request_idx on public.business_events (command_request_id)
  where command_request_id is not null;

create unique index project_members_one_active_leader_idx
  on public.project_members (project_id)
  where role = 'leader' and member_state = 'active';

create table public.project_invitations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  created_by uuid references auth.users (id) on delete set null,
  token_hash bytea not null unique,
  mode text not null,
  expires_at timestamptz not null,
  max_uses integer,
  uses_count integer not null default 0,
  revoked_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_invitations_mode check (mode in ('direct', 'approval')),
  constraint project_invitations_max_uses check (max_uses is null or max_uses > 0),
  constraint project_invitations_uses_count check (uses_count >= 0),
  constraint project_invitations_version check (version > 0)
);
create index project_invitations_project_idx on public.project_invitations (project_id);

create table public.project_join_requests (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.project_invitations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  state text not null default 'pending',
  version integer not null default 1,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_join_requests_state check (state in ('pending', 'approved', 'rejected', 'canceled')),
  constraint project_join_requests_version check (version > 0)
);
create unique index project_join_requests_one_pending_idx
  on public.project_join_requests (project_id, user_id) where state = 'pending';
create index project_join_requests_invitation_state_idx
  on public.project_join_requests (invitation_id, state);
create index project_join_requests_user_state_idx
  on public.project_join_requests (user_id, state);

alter table public.tasks
  add column assignment_state text not null default 'claimable',
  add column progress_text text,
  add constraint tasks_assignment_state check (assignment_state in ('claimable', 'pending_acceptance', 'assigned')),
  add constraint tasks_progress_text_length check (progress_text is null or char_length(progress_text) <= 2000);
update public.tasks
set assignment_state = case when assignee_id is null then 'claimable' else 'assigned' end;

create table public.task_assignment_offers (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null,
  project_id uuid not null references public.projects (id) on delete cascade,
  target_user_id uuid not null references auth.users (id) on delete cascade,
  state text not null default 'pending',
  version integer not null default 1,
  created_by uuid references auth.users (id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id) references public.tasks (project_id, id) on delete cascade,
  constraint task_assignment_offers_state check (state in ('pending', 'accepted', 'rejected')),
  constraint task_assignment_offers_version check (version > 0)
);
create unique index task_assignment_offers_one_pending_idx
  on public.task_assignment_offers (task_id) where state = 'pending';
create index task_assignment_offers_target_state_idx
  on public.task_assignment_offers (target_user_id, state);
create index task_assignment_offers_project_idx on public.task_assignment_offers (project_id);

alter table public.project_invitations enable row level security;
alter table public.project_join_requests enable row level security;
alter table public.task_assignment_offers enable row level security;

create policy project_join_requests_select_self_or_leader
on public.project_join_requests for select to authenticated
using (
  user_id = (select auth.uid()) or exists (
    select 1 from public.project_members pm
    where pm.project_id = project_join_requests.project_id
      and pm.user_id = (select auth.uid())
      and pm.role = 'leader' and pm.member_state = 'active'
  )
);
create policy task_assignment_offers_select_target_or_leader
on public.task_assignment_offers for select to authenticated
using (
  target_user_id = (select auth.uid()) or exists (
    select 1 from public.project_members pm
    where pm.project_id = task_assignment_offers.project_id
      and pm.user_id = (select auth.uid())
      and pm.role = 'leader' and pm.member_state = 'active'
  )
);

revoke all on public.project_invitations, public.project_join_requests, public.task_assignment_offers
  from anon, authenticated;
grant select on public.project_join_requests, public.task_assignment_offers to authenticated;

create function private.failure(
  p_request_id uuid,
  p_code text,
  p_field text default null,
  p_current_version integer default null,
  p_details jsonb default null
) returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'ok', false, 'code', p_code, 'requestId', p_request_id,
    'replayed', false, 'field', p_field, 'currentVersion', p_current_version,
    'details', p_details
  ));
$$;

create function private.payload_hash(p_payload jsonb)
returns bytea language sql immutable set search_path = '' as $$
  select extensions.digest(convert_to(p_payload::text, 'utf8'), 'sha256');
$$;

create function private.claim_command(
  p_actor_id uuid,
  p_command_name text,
  p_request_id uuid,
  p_payload_hash bytea,
  p_account_id uuid default null,
  p_project_id uuid default null
) returns table(command_id uuid, prior_result jsonb, payload_matches boolean)
language plpgsql security definer set search_path = '' as $$
declare v_row public.command_requests%rowtype;
begin
  insert into public.command_requests (
    account_id, project_id, actor_id, command_name, request_id, payload_hash
  ) values (
    p_account_id, p_project_id, p_actor_id, p_command_name, p_request_id, p_payload_hash
  ) on conflict do nothing;

  select * into v_row
  from public.command_requests cr
  where cr.actor_id = p_actor_id and cr.command_name = p_command_name and cr.request_id = p_request_id
    and cr.account_id is not distinct from p_account_id
    and cr.project_id is not distinct from p_project_id
  for update;

  command_id := v_row.id;
  prior_result := case when v_row.state = 'completed' then v_row.result else null end;
  payload_matches := v_row.payload_hash = p_payload_hash;
  return next;
end;
$$;

create function private.complete_command(
  p_command_id uuid,
  p_result jsonb,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_entity_version integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  update public.command_requests set
    state = 'completed', result = p_result,
    resulting_entity_type = p_entity_type,
    resulting_entity_id = p_entity_id,
    resulting_entity_version = p_entity_version,
    updated_at = now(), completed_at = now()
  where id = p_command_id;
  return p_result;
end;
$$;

create function private.replay_or_reuse(
  p_request_id uuid, p_prior_result jsonb, p_payload_matches boolean
) returns jsonb language sql immutable set search_path = '' as $$
  select case
    when not p_payload_matches then private.failure(p_request_id, 'IDEMPOTENCY_KEY_REUSED')
    when p_prior_result is not null then jsonb_set(p_prior_result, '{replayed}', 'true'::jsonb)
    else null
  end;
$$;

create function private.reject_unless_authorized(
  p_authorized boolean,
  p_request_id uuid,
  p_command_id uuid,
  p_prior_result jsonb,
  p_payload_matches boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if p_payload_matches is not true then
    return private.failure(p_request_id, 'IDEMPOTENCY_KEY_REUSED');
  end if;
  if p_authorized then
    return null;
  end if;
  if p_prior_result is not null then
    if p_prior_result->>'ok' = 'false' then
      return jsonb_set(p_prior_result, '{replayed}', 'true'::jsonb);
    end if;
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  return private.complete_command(p_command_id, v_result);
end;
$$;

create function private.is_active_member(p_project_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members pm
    where pm.project_id = p_project_id and pm.user_id = p_user_id and pm.member_state = 'active'
  );
$$;

create function private.is_active_leader(p_project_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members pm
    where pm.project_id = p_project_id and pm.user_id = p_user_id
      and pm.role = 'leader' and pm.member_state = 'active'
  );
$$;

create function private.emit_event(
  p_command_id uuid, p_seq integer, p_project_id uuid, p_actor_id uuid,
  p_event_type text, p_entity_type text, p_entity_id uuid, p_request_id uuid,
  p_data jsonb default '{}'::jsonb
) returns void language sql security definer set search_path = '' as $$
  insert into public.business_events (
    command_request_id, event_seq, project_id, actor_id, event_type,
    entity_type, entity_id, request_id, event_data
  ) values (
    p_command_id, p_seq, p_project_id, p_actor_id, p_event_type,
    p_entity_type, p_entity_id, p_request_id, p_data
  );
$$;

revoke all on all functions in schema private from public, anon, authenticated;

create function public.cmd_create_project(
  p_request_id uuid,
  p_expected_version integer default 0,
  p_name text default null,
  p_deadline_at timestamptz default null,
  p_course_name text default null,
  p_description text default null,
  p_timezone text default null,
  p_contribution_mode text default null,
  p_require_real_name boolean default null,
  p_require_student_number boolean default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project_id uuid;
  v_membership_id uuid;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id, 'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  v_hash := private.payload_hash(jsonb_build_object(
    'expectedVersion', p_expected_version, 'name', p_name, 'deadlineAt', p_deadline_at,
    'courseName', p_course_name, 'description', p_description, 'timezone', p_timezone,
    'contributionMode', p_contribution_mode, 'requireRealName', p_require_real_name,
    'requireStudentNumber', p_require_student_number
  ));
  select * into v_claim from private.claim_command(v_actor, 'cmd_create_project', p_request_id, v_hash, v_actor, null);
  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.profiles where id=v_actor for update;
  if not found then
    v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> 0 then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, null);
  elsif p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'name');
  elsif p_deadline_at is null or p_deadline_at <= now() then
    v_result := private.failure(p_request_id, 'DDL_NOT_IN_FUTURE', 'deadlineAt');
  elsif coalesce(p_contribution_mode, 'weighted') not in ('weighted', 'facts_only') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'contributionMode');
  elsif (select count(*) from public.project_members pm join public.projects p on p.id=pm.project_id
         where pm.user_id=v_actor and pm.member_state='active' and p.archived_at is null) >= 5 then
    v_result := private.failure(p_request_id, 'QUOTA_EXCEEDED', null, null, jsonb_build_object('limit', 5));
  else
    insert into public.projects (
      name, course_name, description, timezone, deadline_at, contribution_mode,
      require_real_name, require_student_number, leader_id, created_by, version
    ) values (
      btrim(p_name), p_course_name, p_description, coalesce(p_timezone, 'Asia/Shanghai'),
      p_deadline_at, coalesce(p_contribution_mode, 'weighted'),
      coalesce(p_require_real_name, false), coalesce(p_require_student_number, false),
      v_actor, v_actor, 1
    ) returning id into v_project_id;
    insert into public.project_members (project_id, user_id, role, member_state)
      values (v_project_id, v_actor, 'leader', 'active') returning id into v_membership_id;
    perform private.emit_event(v_claim.command_id, 1, v_project_id, v_actor,
      'project_created', 'project', v_project_id, p_request_id, jsonb_build_object('version',1));
    v_result := jsonb_build_object(
      'ok', true, 'data', jsonb_build_object('projectId',v_project_id,'leaderMembershipId',v_membership_id),
      'requestId',p_request_id,'replayed',false,'aggregateType','project',
      'aggregateId',v_project_id,'aggregateVersion',1
    );
    return private.complete_command(v_claim.command_id, v_result, 'project', v_project_id, 1);
  end if;
  return private.complete_command(v_claim.command_id, v_result);
end;
$$;

create function public.cmd_create_project_invite(
  p_project_id uuid, p_request_id uuid, p_expected_version integer, p_mode text,
  p_expires_in_days integer default null, p_max_uses integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_hash bytea; v_claim record; v_replay jsonb;
  v_project public.projects%rowtype; v_invite_id uuid; v_token text; v_expires timestamptz; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash := private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version,'mode',p_mode,'expiresInDays',p_expires_in_days,'maxUses',p_max_uses));
  select * into v_claim from private.claim_command(v_actor,'cmd_create_project_invite',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  if p_expected_version is null or v_project.version <> p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif p_mode not in ('direct','approval') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','mode');
  elsif coalesce(p_expires_in_days,7) not between 1 and 30 then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','expiresInDays');
  elsif p_max_uses is not null and p_max_uses <= 0 then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','maxUses');
  else
    v_token := encode(extensions.gen_random_bytes(32),'hex');
    v_expires := now() + make_interval(days => coalesce(p_expires_in_days,7));
    insert into public.project_invitations(project_id,created_by,token_hash,mode,expires_at,max_uses)
      values(p_project_id,v_actor,extensions.digest(convert_to(v_token,'utf8'),'sha256'),p_mode,v_expires,p_max_uses)
      returning id into v_invite_id;
    update public.projects set version=version+1,updated_at=now() where id=p_project_id returning version into v_project.version;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'project_invitation_created','project_invitation',v_invite_id,p_request_id,jsonb_build_object('mode',p_mode));
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('invitationId',v_invite_id,'token',v_token,'expiresAt',v_expires,'invitationVersion',1),'requestId',p_request_id,'replayed',false,'aggregateType','project','aggregateId',p_project_id,'aggregateVersion',v_project.version);
    return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_project.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_revoke_project_invite(
  p_project_id uuid, p_invitation_id uuid, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb;
  v_project public.projects%rowtype; v_invite public.project_invitations%rowtype;
  v_count integer; v_seq integer:=1; v_req record; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'invitationId',p_invitation_id,'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_revoke_project_invite',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_invite from public.project_invitations where id=p_invitation_id and project_id=p_project_id for update;
  if not found then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_invite.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  else
    update public.project_invitations set revoked_at=coalesce(revoked_at,now()),version=version+1,updated_at=now() where id=p_invitation_id returning * into v_invite;
    perform private.emit_event(v_claim.command_id,v_seq,p_project_id,v_actor,'project_invitation_revoked','project_invitation',p_invitation_id,p_request_id,jsonb_build_object('version',v_invite.version));
    for v_req in select * from public.project_join_requests where invitation_id=p_invitation_id and state='pending' order by id for update loop
      v_seq:=v_seq+1;
      update public.project_join_requests set state='canceled',version=version+1,reviewed_at=now(),updated_at=now() where id=v_req.id;
      perform private.emit_event(v_claim.command_id,v_seq,p_project_id,v_actor,'project_join_request_canceled','project_join_request',v_req.id,p_request_id,jsonb_build_object('reason','invitation_revoked'));
    end loop;
    v_count:=v_seq-1;
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('invitationId',p_invitation_id,'revokedAt',v_invite.revoked_at,'canceledJoinRequestCount',v_count),'requestId',p_request_id,'replayed',false,'aggregateType','invitation','aggregateId',p_invitation_id,'aggregateVersion',v_invite.version);
    return private.complete_command(v_claim.command_id,v_result,'invitation',p_invitation_id,v_invite.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.preview_project_invite(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_invite public.project_invitations%rowtype; v_project public.projects%rowtype;
begin
  if p_token is null or p_token='' then return null; end if;
  select * into v_invite from public.project_invitations where token_hash=extensions.digest(convert_to(p_token,'utf8'),'sha256');
  if not found then return null; end if;
  select * into v_project from public.projects where id=v_invite.project_id;
  return jsonb_build_object('projectId',v_project.id,'projectName',v_project.name,'projectDeadlineAt',v_project.deadline_at,'requireRealName',v_project.require_real_name,'requireStudentNumber',v_project.require_student_number,'mode',v_invite.mode,'expiresAt',v_invite.expires_at,'available',(v_invite.revoked_at is null and v_invite.expires_at>now() and (v_invite.max_uses is null or v_invite.uses_count<v_invite.max_uses)),'invitationVersion',v_invite.version);
end;
$$;

create function public.cmd_join_project_via_invite(
  p_token text, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_token_hash bytea; v_project_id uuid; v_hash bytea; v_claim record; v_replay jsonb;
  v_project public.projects%rowtype; v_invite public.project_invitations%rowtype; v_profile public.profiles%rowtype;
  v_id uuid; v_result jsonb; v_seq integer:=1; v_req record;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if p_token is null or p_token='' then return private.failure(p_request_id,'INVITE_UNAVAILABLE'); end if;
  v_token_hash:=extensions.digest(convert_to(p_token,'utf8'),'sha256');
  select project_id into v_project_id from public.project_invitations where token_hash=v_token_hash;
  if v_project_id is null then return private.failure(p_request_id,'INVITE_UNAVAILABLE'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('tokenHash',encode(v_token_hash,'hex'),'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_join_project_via_invite',p_request_id,v_hash,null,v_project_id);
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=v_project_id for update;
  select * into v_invite from public.project_invitations where token_hash=v_token_hash and project_id=v_project_id for update;
  select * into v_profile from public.profiles where id=v_actor;
  if p_expected_version is null then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_invite.revoked_at is not null or v_invite.expires_at<=now() then v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif private.is_active_member(v_project_id,v_actor) then v_result:=private.failure(p_request_id,'ALREADY_MEMBER');
  elsif v_project.require_real_name and nullif(btrim(v_profile.real_name),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','realName');
  elsif v_project.require_student_number and nullif(btrim(v_profile.student_number),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','studentNumber');
  elsif v_invite.mode='direct' and v_invite.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_invite.mode='approval' and p_expected_version<>0 then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_invite.max_uses is not null and v_invite.uses_count>=v_invite.max_uses then v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif v_invite.mode='direct' and (select count(*) from public.project_members where project_id=v_project_id and member_state='active')>=8 then v_result:=private.failure(p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',8));
  elsif v_invite.mode='approval' and exists(select 1 from public.project_join_requests where project_id=v_project_id and user_id=v_actor and state='pending') then v_result:=private.failure(p_request_id,'JOIN_REQUEST_PENDING');
  elsif v_invite.mode='direct' then
    for v_req in select id from public.project_join_requests where project_id=v_project_id and user_id=v_actor and state='pending' order by id for update loop
      null;
    end loop;
    insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values(v_project_id,v_actor,'member','active',v_profile.display_name) returning id into v_id;
    update public.project_invitations set uses_count=uses_count+1,version=version+1,updated_at=now() where id=v_invite.id returning * into v_invite;
    perform private.emit_event(v_claim.command_id,1,v_project_id,v_actor,'project_member_joined','project_member',v_id,p_request_id,jsonb_build_object('invitationId',v_invite.id));
    for v_req in select id from public.project_join_requests where project_id=v_project_id and user_id=v_actor and state='pending' order by id loop
      v_seq:=v_seq+1;
      update public.project_join_requests set state='canceled',version=version+1,reviewed_at=now(),updated_at=now() where id=v_req.id;
      perform private.emit_event(v_claim.command_id,v_seq,v_project_id,v_actor,'project_join_request_canceled','project_join_request',v_req.id,p_request_id,jsonb_build_object('reason','joined_directly'));
    end loop;
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('projectId',v_project_id,'outcome','joined','membershipId',v_id,'invitationVersion',v_invite.version),'requestId',p_request_id,'replayed',false,'aggregateType','invitation','aggregateId',v_invite.id,'aggregateVersion',v_invite.version);
    return private.complete_command(v_claim.command_id,v_result,'invitation',v_invite.id,v_invite.version);
  else
    insert into public.project_join_requests(invitation_id,project_id,user_id) values(v_invite.id,v_project_id,v_actor) returning id into v_id;
    perform private.emit_event(v_claim.command_id,1,v_project_id,v_actor,'project_join_requested','project_join_request',v_id,p_request_id,jsonb_build_object('invitationId',v_invite.id));
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('projectId',v_project_id,'outcome','pending_approval','joinRequestId',v_id,'invitationVersion',v_invite.version),'requestId',p_request_id,'replayed',false,'aggregateType','join_request','aggregateId',v_id,'aggregateVersion',1);
    return private.complete_command(v_claim.command_id,v_result,'join_request',v_id,1);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_review_project_join_request(
  p_project_id uuid, p_join_request_id uuid, p_action text, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype;
  v_invite public.project_invitations%rowtype; v_join public.project_join_requests%rowtype; v_profile public.profiles%rowtype;
  v_membership_id uuid; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'joinRequestId',p_join_request_id,'action',p_action,'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_review_project_join_request',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  select i.* into v_invite from public.project_invitations i join public.project_join_requests j on j.invitation_id=i.id where j.id=p_join_request_id and j.project_id=p_project_id for update of i;
  select * into v_join from public.project_join_requests where id=p_join_request_id and project_id=p_project_id for update;
  if not found then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif private.is_active_member(p_project_id,v_join.user_id) then v_result:=private.failure(p_request_id,'ALREADY_MEMBER');
  elsif p_expected_version is null or v_join.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_join.version);
  elsif v_join.state<>'pending' then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','state');
  elsif p_action is null or p_action not in ('approve','reject') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='approve' and v_invite.revoked_at is not null then v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif p_action='approve' and v_invite.max_uses is not null and v_invite.uses_count>=v_invite.max_uses then v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif p_action='approve' and (select count(*) from public.project_members where project_id=p_project_id and member_state='active')>=8 then v_result:=private.failure(p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',8));
  else
    select * into v_profile from public.profiles where id=v_join.user_id;
    if p_action='approve' and v_project.require_real_name and nullif(btrim(v_profile.real_name),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','realName');
    elsif p_action='approve' and v_project.require_student_number and nullif(btrim(v_profile.student_number),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','studentNumber');
    elsif p_action='approve' then
      insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values(p_project_id,v_join.user_id,'member','active',v_profile.display_name) returning id into v_membership_id;
      update public.project_invitations set uses_count=uses_count+1,version=version+1,updated_at=now() where id=v_invite.id;
      update public.project_join_requests set state='approved',version=version+1,reviewed_by=v_actor,reviewed_at=now(),updated_at=now() where id=v_join.id returning * into v_join;
      perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'project_join_request_approved','project_join_request',v_join.id,p_request_id,jsonb_build_object('membershipId',v_membership_id));
      v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('projectId',p_project_id,'joinRequestId',v_join.id,'state','approved','membershipId',v_membership_id),'requestId',p_request_id,'replayed',false,'aggregateType','join_request','aggregateId',v_join.id,'aggregateVersion',v_join.version);
      return private.complete_command(v_claim.command_id,v_result,'join_request',v_join.id,v_join.version);
    else
      update public.project_join_requests set state='rejected',version=version+1,reviewed_by=v_actor,reviewed_at=now(),updated_at=now() where id=v_join.id returning * into v_join;
      perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'project_join_request_rejected','project_join_request',v_join.id,p_request_id,'{}');
      v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('projectId',p_project_id,'joinRequestId',v_join.id,'state','rejected'),'requestId',p_request_id,'replayed',false,'aggregateType','join_request','aggregateId',v_join.id,'aggregateVersion',v_join.version);
      return private.complete_command(v_claim.command_id,v_result,'join_request',v_join.id,v_join.version);
    end if;
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_create_task(
  p_project_id uuid, p_request_id uuid, p_expected_version integer, p_title text,
  p_description text default null, p_deadline_at timestamptz default null, p_weight smallint default null,
  p_assignment_mode text default 'claimable', p_assignee_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype;
  v_task_id uuid; v_offer_id uuid; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version,'title',p_title,'description',p_description,'deadlineAt',p_deadline_at,'weight',p_weight,'assignmentMode',p_assignment_mode,'assigneeId',p_assignee_id));
  select * into v_claim from private.claim_command(v_actor,'cmd_create_task',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_member(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  if p_expected_version is null or v_project.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_deadline_at is null or p_deadline_at<=now() or p_deadline_at>v_project.deadline_at then v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_assignment_mode not in ('claimable','direct') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assignmentMode');
  elsif v_project.contribution_mode='weighted' and (p_weight is null or p_weight not between 1 and 5) then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif p_assignment_mode='claimable' and p_assignee_id is not null then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assigneeId');
  elsif p_assignment_mode='direct' and (p_assignee_id is null or not private.is_active_member(p_project_id,p_assignee_id)) then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','assigneeId');
  elsif (select count(*) from public.tasks where project_id=p_project_id and status not in ('completed','canceled'))>=20 then v_result:=private.failure(p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',20));
  else
    insert into public.tasks(project_id,title,description,created_by,deadline_at,status,weight,is_direct_assignment,assignment_state)
      values(p_project_id,btrim(p_title),p_description,v_actor,p_deadline_at,'not_started',p_weight,p_assignment_mode='direct',case when p_assignment_mode='direct' then 'pending_acceptance' else 'claimable' end)
      returning id into v_task_id;
    if p_assignment_mode='direct' then
      insert into public.task_assignment_offers(task_id,project_id,target_user_id,created_by) values(v_task_id,p_project_id,p_assignee_id,v_actor) returning id into v_offer_id;
    end if;
    update public.projects set version=version+1,updated_at=now() where id=p_project_id returning version into v_project.version;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'task_created','task',v_task_id,p_request_id,jsonb_build_object('assignmentMode',p_assignment_mode));
    v_result:=jsonb_strip_nulls(jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',v_task_id,'taskVersion',1,'assignmentOfferId',v_offer_id,'assignmentOfferVersion',case when v_offer_id is null then null else 1 end),'requestId',p_request_id,'replayed',false,'aggregateType','project','aggregateId',p_project_id,'aggregateVersion',v_project.version));
    return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_project.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_claim_task(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_claim_task',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_member(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task from public.tasks where id=p_task_id and project_id=p_project_id for update;
  if not found then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_task.assignment_state<>'claimable' or v_task.assignee_id is not null then v_result:=private.failure(p_request_id,'TASK_ALREADY_CLAIMED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_task.deadline_at<=now() then v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE');
  else
    update public.tasks set assignee_id=v_actor,assignment_state='assigned',accepted_at=now(),status='in_progress',version=version+1,updated_at=now() where id=p_task_id returning * into v_task;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'task_claimed','task',p_task_id,p_request_id,jsonb_build_object('version',v_task.version));
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',p_task_id,'assigneeId',v_actor,'acceptedAt',v_task.accepted_at),'requestId',p_request_id,'replayed',false,'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version);
    return private.complete_command(v_claim.command_id,v_result,'task',p_task_id,v_task.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_respond_to_task_assignment(
  p_project_id uuid, p_task_id uuid, p_assignment_offer_id uuid, p_action text,
  p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_offer public.task_assignment_offers%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,'assignmentOfferId',p_assignment_offer_id,'action',p_action,'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_respond_to_task_assignment',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(exists(select 1 from public.task_assignment_offers where id=p_assignment_offer_id and project_id=p_project_id and task_id=p_task_id and target_user_id=v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task from public.tasks where id=p_task_id and project_id=p_project_id for update;
  select * into v_offer from public.task_assignment_offers where id=p_assignment_offer_id and task_id=p_task_id and project_id=p_project_id for update;
  if v_offer.state<>'pending' or v_task.assignment_state<>'pending_acceptance' then v_result:=private.failure(p_request_id,'ASSIGNMENT_NOT_PENDING');
  elsif p_expected_version is null or v_offer.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_offer.version);
  elsif p_action is null or p_action not in ('accept','reject') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='accept' and v_task.deadline_at<=now() then v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE');
  else
    update public.task_assignment_offers set state=case p_action when 'accept' then 'accepted' else 'rejected' end,version=version+1,responded_at=now(),updated_at=now() where id=v_offer.id returning * into v_offer;
    if p_action='accept' then
      update public.tasks set assignee_id=v_actor,accepted_at=now(),status='in_progress',assignment_state='assigned',version=version+1,updated_at=now() where id=v_task.id returning * into v_task;
    else
      update public.tasks set assignment_state='claimable',is_direct_assignment=false,version=version+1,updated_at=now() where id=v_task.id returning * into v_task;
    end if;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,case p_action when 'accept' then 'task_assignment_accepted' else 'task_assignment_rejected' end,'assignment_offer',v_offer.id,p_request_id,jsonb_build_object('taskVersion',v_task.version));
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',v_task.id,'assignmentOfferId',v_offer.id,'outcome',case p_action when 'accept' then 'accepted' else 'rejected' end,'taskVersion',v_task.version),'requestId',p_request_id,'replayed',false,'aggregateType','assignment_offer','aggregateId',v_offer.id,'aggregateVersion',v_offer.version);
    return private.complete_command(v_claim.command_id,v_result,'assignment_offer',v_offer.id,v_offer.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_update_task_progress(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer,
  p_status text, p_progress_text text, p_blocked_reason text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then raise exception using errcode='22004', message='request_id is required'; end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version,'status',p_status,'progressText',p_progress_text,'blockedReason',p_blocked_reason));
  select * into v_claim from private.claim_command(v_actor,'cmd_update_task_progress',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(exists(select 1 from public.tasks where id=p_task_id and project_id=p_project_id and assignee_id=v_actor and assignment_state='assigned'),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task from public.tasks where id=p_task_id and project_id=p_project_id for update;
  if v_task.assignee_id is distinct from v_actor or v_task.assignment_state<>'assigned' then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif p_status not in ('in_progress','blocked') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','status');
  elsif p_progress_text is null or char_length(btrim(p_progress_text)) not between 1 and 2000 then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','progressText');
  elsif p_status='blocked' and nullif(btrim(p_blocked_reason),'') is null then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','blockedReason');
  else
    update public.tasks set status=p_status,progress_text=btrim(p_progress_text),blocked_reason=case when p_status='blocked' then btrim(p_blocked_reason) else null end,version=version+1,updated_at=now() where id=p_task_id returning * into v_task;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'task_progress_updated','task',p_task_id,p_request_id,jsonb_build_object('status',p_status,'version',v_task.version));
    v_result:=jsonb_strip_nulls(jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',p_task_id,'status',v_task.status,'progressText',v_task.progress_text,'blockedReason',v_task.blocked_reason,'updatedAt',v_task.updated_at),'requestId',p_request_id,'replayed',false,'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version));
    return private.complete_command(v_claim.command_id,v_result,'task',p_task_id,v_task.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean) from public, anon, authenticated;
revoke all on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer) from public, anon, authenticated;
revoke all on function public.cmd_revoke_project_invite(uuid,uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.preview_project_invite(text) from public, anon, authenticated;
revoke all on function public.cmd_join_project_via_invite(text,uuid,integer) from public, anon, authenticated;
revoke all on function public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer) from public, anon, authenticated;
revoke all on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid) from public, anon, authenticated;
revoke all on function public.cmd_claim_task(uuid,uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.cmd_respond_to_task_assignment(uuid,uuid,uuid,text,uuid,integer) from public, anon, authenticated;
revoke all on function public.cmd_update_task_progress(uuid,uuid,uuid,integer,text,text,text) from public, anon, authenticated;

grant execute on function public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean) to authenticated;
grant execute on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer) to authenticated;
grant execute on function public.cmd_revoke_project_invite(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.preview_project_invite(text) to anon, authenticated;
grant execute on function public.cmd_join_project_via_invite(text,uuid,integer) to authenticated;
grant execute on function public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid) to authenticated;
grant execute on function public.cmd_claim_task(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_respond_to_task_assignment(uuid,uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_update_task_progress(uuid,uuid,uuid,integer,text,text,text) to authenticated;

comment on table public.project_invitations is 'Invite capability records store only SHA-256 token hashes; plaintext tokens exist only in protected command results.';
comment on table public.project_join_requests is 'Versioned approval workflow; clients cannot write directly.';
comment on table public.task_assignment_offers is 'Versioned direct-assignment offers; task assignment occurs only after acceptance.';
