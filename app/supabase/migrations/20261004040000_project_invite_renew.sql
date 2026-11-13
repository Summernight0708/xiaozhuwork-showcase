create function public.cmd_renew_project_invite(
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
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects where id=p_project_id for update;
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

revoke all on function public.cmd_renew_project_invite(
  uuid,uuid,uuid,integer,integer
) from public, anon, authenticated, service_role;
grant execute on function public.cmd_renew_project_invite(
  uuid,uuid,uuid,integer,integer
) to authenticated;
