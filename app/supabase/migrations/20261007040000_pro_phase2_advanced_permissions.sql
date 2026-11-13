-- Pro Phase 2 / D: fixed project permission templates, unpublished by design.
-- The version fence is public.project_members.version (not project.version).
create table public.project_permission_delegations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  membership_id uuid not null references public.project_members(id) on delete cascade,
  template_code text not null check (template_code in ('invitation_coordinator','intake_reviewer')),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default transaction_timestamp(),
  revoked_at timestamptz,
  version integer not null default 1 check (version > 0),
  constraint delegation_revocation_order check (revoked_at is null or revoked_at >= granted_at)
);
create unique index project_permission_delegations_active_unique
on public.project_permission_delegations(project_id,membership_id,template_code) where revoked_at is null;
create index project_permission_delegations_member_idx
on public.project_permission_delegations(membership_id,project_id,revoked_at);

alter table public.project_permission_delegations enable row level security;
revoke all on public.project_permission_delegations from public,anon,authenticated;
grant select on public.project_permission_delegations to authenticated;
create policy project_permission_delegations_select
on public.project_permission_delegations for select to authenticated
using (
  private.is_active_leader(project_id,(select auth.uid()))
  or (revoked_at is null and exists (
    select 1 from public.project_members pm
    where pm.id=membership_id
      and pm.project_id=project_permission_delegations.project_id
      and pm.user_id=(select auth.uid())
      and pm.member_state='active' and pm.role='member'
  ))
);

create function private.phase2_can_delegate_project_action(
  p_project_id uuid,p_actor_id uuid,p_action text
) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    p_actor_id is not null and p_actor_id=auth.uid()
    and p_action in ('project_invite_manage','project_join_review')
    and private.project_has_capability(p_project_id,'advanced_permissions')
    and exists (
      select 1 from public.project_members pm
      join public.project_permission_delegations d
        on d.project_id=pm.project_id and d.membership_id=pm.id
      where pm.project_id=p_project_id and pm.user_id=p_actor_id
        and pm.member_state='active' and pm.role='member'
        and d.revoked_at is null
        and d.template_code=case p_action
          when 'project_invite_manage' then 'invitation_coordinator'
          when 'project_join_review' then 'intake_reviewer' else null end
    ),false
  );
$$;
revoke all on function private.phase2_can_delegate_project_action(uuid,uuid,text)
from public,anon,authenticated,service_role;

create function public.cmd_set_project_permission_delegation(
  p_project_id uuid,p_membership_id uuid,p_template_code text,
  p_enabled boolean,p_expected_version integer,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_target public.project_members%rowtype;
  v_existing public.project_permission_delegations%rowtype;
  v_delegation_id uuid;
  v_changed boolean:=false;
  v_result jsonb;
  v_capability_failure jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'membershipId',p_membership_id,
    'templateCode',p_template_code,'enabled',p_enabled,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_set_project_permission_delegation',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_target from public.project_members
    where id=p_membership_id and project_id=p_project_id for update;

  if not private.is_active_leader(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_target.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_template_code is null or p_template_code not in
      ('invitation_coordinator','intake_reviewer') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','templateCode');
  elsif p_enabled is null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','enabled');
  elsif v_target.user_id is null or v_target.member_state<>'active'
      or v_target.role<>'member' then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_version is null or p_expected_version<>v_target.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_target.version);
  else
    v_capability_failure:=private.project_capability_failure(
      p_project_id,'advanced_permissions',p_request_id
    );
    if v_capability_failure is not null then
      return private.complete_command(v_claim.command_id,v_capability_failure);
    end if;
    select * into v_existing from public.project_permission_delegations
    where project_id=p_project_id and membership_id=p_membership_id
      and template_code=p_template_code and revoked_at is null for update;

    if p_enabled and v_existing.id is null then
      insert into public.project_permission_delegations(
        project_id,membership_id,template_code,granted_by
      ) values(p_project_id,p_membership_id,p_template_code,v_actor)
      returning id into v_delegation_id;
      v_changed:=true;
    elsif p_enabled then
      v_delegation_id:=v_existing.id;
    elsif not p_enabled and v_existing.id is not null then
      update public.project_permission_delegations
      set revoked_at=transaction_timestamp(),version=version+1
      where id=v_existing.id returning id into v_delegation_id;
      v_changed:=true;
    end if;
    if v_changed then
      update public.project_members set version=version+1
      where id=p_membership_id returning * into v_target;
      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        case when p_enabled then 'project_permission_delegation_granted'
          else 'project_permission_delegation_revoked' end,
        'project_permission_delegation',v_delegation_id,p_request_id,
        jsonb_build_object(
          'templateCode',p_template_code,'beforeEnabled',not p_enabled,
          'afterEnabled',p_enabled,'membershipVersionBefore',p_expected_version,
          'membershipVersionAfter',v_target.version
        )
      );
    end if;
    v_result:=jsonb_build_object(
      'ok',true,'data',jsonb_build_object(
        'projectId',p_project_id,'membershipId',p_membership_id,
        'templateCode',p_template_code,'enabled',p_enabled,
        'changed',v_changed,'membershipVersion',v_target.version,
        'effective',p_enabled and private.phase2_can_delegate_project_action(
          p_project_id,v_target.user_id,
          case p_template_code when 'invitation_coordinator' then 'project_invite_manage'
            else 'project_join_review' end
        )
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','project_member','aggregateId',p_membership_id,
      'aggregateVersion',v_target.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'project_member',p_membership_id,v_target.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.get_project_permission_delegations(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_released boolean;
  v_entitled boolean;
  v_items jsonb;
begin
  if v_actor is null then return private.failure(null,'UNAUTHENTICATED'); end if;
  select pm.role into v_role from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor
    and pm.member_state='active';
  if v_role is null then return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_released:=private.capability_is_released('advanced_permissions');
  v_entitled:=private.project_has_capability(p_project_id,'advanced_permissions');

  select coalesce(jsonb_agg(jsonb_build_object(
    'delegationId',d.id,'membershipId',d.membership_id,
    'templateCode',d.template_code,'grantedAt',d.granted_at,
    'revokedAt',d.revoked_at,'version',d.version,
    'membershipVersion',pm.version,
    'effective',v_entitled and d.revoked_at is null
      and pm.member_state='active' and pm.role='member'
  ) order by d.granted_at desc,d.id desc),'[]'::jsonb)
  into v_items
  from public.project_permission_delegations d
  join public.project_members pm on pm.id=d.membership_id
    and pm.project_id=d.project_id
  where d.project_id=p_project_id and (
    v_role='leader' or
    (v_role='member' and pm.user_id=v_actor and d.revoked_at is null)
  );

  return jsonb_build_object('ok',true,'data',jsonb_build_object(
    'schemaVersion',1,'projectId',p_project_id,'viewerRole',v_role,
    'capability',jsonb_build_object(
      'released',v_released,'entitled',v_entitled,'effective',v_entitled
    ),
    'delegations',case when v_role='observer' then '[]'::jsonb else v_items end
  ));
end;
$$;
revoke all on function public.cmd_set_project_permission_delegation(uuid,uuid,text,boolean,integer,uuid)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_set_project_permission_delegation(uuid,uuid,text,boolean,integer,uuid)
to authenticated;
revoke all on function public.get_project_permission_delegations(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.get_project_permission_delegations(uuid) to authenticated;

-- The four forward replacements below preserve each final business RPC's
-- quota, identity, idempotency, invitation and audit logic byte-for-byte,
-- except the narrowly scoped authorization OR and its post-lock recheck.


-- Effective final function cmd_create_project_invite
create or replace function public.cmd_create_project_invite(
  p_project_id uuid, p_request_id uuid, p_expected_version integer, p_mode text,
  p_expires_in_days integer default null, p_max_uses integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid(); v_hash bytea; v_claim record; v_replay jsonb;
  v_project public.projects%rowtype; v_invite_id uuid; v_token text; v_expires timestamptz; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash := private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version,'mode',p_mode,'expiresInDays',p_expires_in_days,'maxUses',p_max_uses));
  select * into v_claim from private.claim_command(v_actor,'cmd_create_project_invite',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized((private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  -- Revalidate authority under project lock after any concurrent revoke or role change.
  if not (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')) then
    return private.complete_command(v_claim.command_id,
      private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'));
  end if;
  if p_expected_version is null or v_project.version <> p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_mode is null or p_mode not in ('direct','approval') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','mode');
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


-- Effective final function cmd_revoke_project_invite
create or replace function public.cmd_revoke_project_invite(
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
  v_result:=private.reject_unless_authorized((private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  -- Revalidate authority under project lock after any concurrent revoke or role change.
  if not (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')) then
    return private.complete_command(v_claim.command_id,
      private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'));
  end if;
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


-- Effective final function cmd_renew_project_invite
create or replace function public.cmd_renew_project_invite(
  p_project_id uuid,
  p_invitation_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_extend_days integer default 7
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_invite public.project_invitations%rowtype;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash := private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'invitationId',p_invitation_id,
    'expectedVersion',p_expected_version,'extendDays',p_extend_days
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_renew_project_invite',p_request_id,v_hash,null,p_project_id
  );
  v_result := private.reject_unless_authorized(
    (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects where id=p_project_id for update;
  -- Revalidate authority under project lock after any concurrent revoke or role change.
  if not (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_invite_manage')) then
    return private.complete_command(v_claim.command_id,
      private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'));
  end if;
  select * into v_invite from public.project_invitations
    where id=p_invitation_id and project_id=p_project_id for update;

  if not found then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_invite.version<>p_expected_version then
    v_result := private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_extend_days is null or p_extend_days not between 1 and 30 then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','extendDays');
  elsif v_invite.revoked_at is not null then
    v_result := private.failure(
      p_request_id,'INVALID_TRANSITION','invitation',v_invite.version,
      jsonb_build_object('reason','revoked')
    );
  elsif v_invite.expires_at <= now() then
    v_result := private.failure(
      p_request_id,'INVALID_TRANSITION','invitation',v_invite.version,
      jsonb_build_object('reason','expired')
    );
  elsif v_invite.max_uses is not null and v_invite.uses_count >= v_invite.max_uses then
    v_result := private.failure(
      p_request_id,'INVALID_TRANSITION','invitation',v_invite.version,
      jsonb_build_object('reason','exhausted')
    );
  else
    update public.project_invitations
    set expires_at=expires_at+make_interval(days=>p_extend_days),
        version=version+1,
        updated_at=now()
    where id=p_invitation_id
    returning * into v_invite;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'project_invitation_renewed',
      'project_invitation',p_invitation_id,p_request_id,
      jsonb_build_object('expiresAt',v_invite.expires_at,'version',v_invite.version)
    );

    v_result := jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'invitationId',p_invitation_id,
        'expiresAt',v_invite.expires_at,
        'invitationVersion',v_invite.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','invitation','aggregateId',p_invitation_id,
      'aggregateVersion',v_invite.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'invitation',p_invitation_id,v_invite.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;


-- Effective final function cmd_review_project_join_request
create or replace function public.cmd_review_project_join_request(
  p_project_id uuid,
  p_join_request_id uuid,
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
  v_at timestamptz:=transaction_timestamp();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_invite public.project_invitations%rowtype;
  v_join public.project_join_requests%rowtype;
  v_profile public.profiles%rowtype;
  v_join_user_id uuid;
  v_prospective_state text;
  v_member_limit integer;
  v_current_members integer:=0;
  v_current_free_projects integer:=0;
  v_membership_id uuid;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'joinRequestId',p_join_request_id,
    'action',p_action,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_review_project_join_request',
    p_request_id,v_hash,null,p_project_id
  );

  v_result:=private.reject_unless_authorized(
    (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_join_review')),
    p_request_id,v_claim.command_id,
    v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  -- Resolve the target user without locking the join row so the global
  -- quota lock order can remain user -> project -> child rows.
  select j.user_id
  into v_join_user_id
  from public.project_join_requests j
  where j.id=p_join_request_id
    and j.project_id=p_project_id;

  if v_join_user_id is not null then
    select * into v_profile
    from public.profiles
    where id=v_join_user_id
    for update;
  end if;

  select * into v_project
  from public.projects
  where id=p_project_id
  for update;
  -- Revalidate authority under project lock after any concurrent revoke or role change.
  if not (private.is_active_leader(p_project_id,v_actor)
    or private.phase2_can_delegate_project_action(p_project_id,v_actor,'project_join_review')) then
    return private.complete_command(v_claim.command_id,
      private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'));
  end if;

  select i.*
  into v_invite
  from public.project_invitations i
  join public.project_join_requests j
    on j.invitation_id=i.id
  where j.id=p_join_request_id
    and j.project_id=p_project_id
  for update of i;

  select *
  into v_join
  from public.project_join_requests
  where id=p_join_request_id
    and project_id=p_project_id
  for update;

  if v_join.id is not null
     and v_join.user_id is not null
     and p_action='approve' then
    select count(*)::integer
    into v_current_members
    from public.project_members
    where project_id=p_project_id
      and member_state='active'
      and user_id is not null;

    select e.state
    into v_prospective_state
    from private.resolve_project_entitlement_with_prospective_member(
      p_project_id,v_join.user_id,'member',v_at
    ) e;

    v_member_limit :=
      private.project_member_limit_for_prospective_member(
        p_project_id,v_join.user_id,'member',v_at
      );
    v_current_free_projects :=
      private.account_active_free_project_count(v_join.user_id,v_at);
  end if;

  if v_join.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif private.is_active_member(p_project_id,v_join.user_id) then
    v_result:=private.failure(p_request_id,'ALREADY_MEMBER');
  elsif p_expected_version is null or v_join.version<>p_expected_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_join.version
    );
  elsif p_action='approve' and v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(
      p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version
    );
  elsif v_join.state<>'pending' then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','state');
  elsif p_action is null or p_action not in ('approve','reject') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='approve' and v_join.user_id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_action='approve' and v_profile.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_action='approve' and v_invite.revoked_at is not null then
    v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif p_action='approve'
        and v_invite.max_uses is not null
        and v_invite.uses_count>=v_invite.max_uses then
    v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif p_action='approve' and v_current_members>=v_member_limit then
    v_result:=private.failure(
      p_request_id,'PROJECT_MEMBER_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',v_member_limit,
        'current',v_current_members,
        'effectiveState',v_prospective_state
      )
    );
  elsif p_action='approve'
        and v_prospective_state='free'
        and not private.account_can_add_free_project(v_join.user_id,v_at) then
    v_result:=private.failure(
      p_request_id,'ACTIVE_FREE_PROJECT_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',5,
        'current',v_current_free_projects,
        'effectiveState','free'
      )
    );
  elsif p_action='approve'
        and v_project.require_real_name
        and nullif(btrim(v_profile.real_name),'') is null then
    v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','realName');
  elsif p_action='approve'
        and v_project.require_student_number
        and nullif(btrim(v_profile.student_number),'') is null then
    v_result:=private.failure(
      p_request_id,'CONFIRMATION_REQUIRED','studentNumber'
    );
  elsif p_action='approve' then
    insert into public.project_members(
      project_id,user_id,role,member_state,display_name_snapshot
    ) values(
      p_project_id,v_join.user_id,'member','active',v_profile.display_name
    ) returning id into v_membership_id;

    update public.project_invitations
    set uses_count=uses_count+1,
        version=version+1,
        updated_at=now()
    where id=v_invite.id;

    update public.project_join_requests
    set state='approved',
        version=version+1,
        reviewed_by=v_actor,
        reviewed_at=now(),
        updated_at=now()
    where id=v_join.id
    returning * into v_join;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'project_join_request_approved','project_join_request',
      v_join.id,p_request_id,
      jsonb_build_object('membershipId',v_membership_id)
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',p_project_id,
        'joinRequestId',v_join.id,
        'state','approved',
        'membershipId',v_membership_id
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','join_request',
      'aggregateId',v_join.id,
      'aggregateVersion',v_join.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,
      'join_request',v_join.id,v_join.version
    );
  else
    update public.project_join_requests
    set state='rejected',
        version=version+1,
        reviewed_by=v_actor,
        reviewed_at=now(),
        updated_at=now()
    where id=v_join.id
    returning * into v_join;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'project_join_request_rejected','project_join_request',
      v_join.id,p_request_id,'{}'
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',p_project_id,
        'joinRequestId',v_join.id,
        'state','rejected'
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','join_request',
      'aggregateId',v_join.id,
      'aggregateVersion',v_join.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,
      'join_request',v_join.id,v_join.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer),
  public.cmd_revoke_project_invite(uuid,uuid,uuid,integer),
  public.cmd_renew_project_invite(uuid,uuid,uuid,integer,integer),
  public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer),
  public.cmd_revoke_project_invite(uuid,uuid,uuid,integer),
  public.cmd_renew_project_invite(uuid,uuid,uuid,integer,integer),
  public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer)
to authenticated;
