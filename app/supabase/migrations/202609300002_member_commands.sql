-- Controlled membership role, removal, voluntary-leave, and leadership-transfer commands.

create function public.cmd_update_project_member_role(
  p_project_id uuid,
  p_membership_id uuid,
  p_target_role text,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_actor_member public.project_members%rowtype;
  v_target public.project_members%rowtype;
  v_old_role text;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'membershipId',p_membership_id,'targetRole',p_target_role,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_update_project_member_role',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_project_manager(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_actor_member
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active'
  for update;
  select * into v_target
  from public.project_members pm
  where pm.id=p_membership_id and pm.project_id=p_project_id
  for update;

  if v_target.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_actor_member.role not in ('leader','admin') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_version is null or v_target.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_target.version);
  elsif v_target.member_state<>'active' or v_target.user_id is null then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  elsif p_target_role is null or p_target_role not in ('admin','member','observer') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','targetRole');
  elsif v_target.role='leader' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_target.version,
      jsonb_build_object('reason','use_leadership_transfer')
    );
  elsif v_actor_member.role='admin'
        and (v_target.role not in ('member','observer') or p_target_role not in ('member','observer')) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_target_role='observer' and (
    exists(
      select 1 from public.tasks t
      where t.project_id=p_project_id and t.assignee_id=v_target.user_id
        and t.status not in ('completed','canceled')
    )
    or exists(
      select 1 from public.task_assignment_offers o
      where o.project_id=p_project_id and o.target_user_id=v_target.user_id and o.state='pending'
    )
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_target.version,
      jsonb_build_object('reason','active_responsibility')
    );
  elsif v_target.role=p_target_role then
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'membershipId',v_target.id,'role',v_target.role,'membershipVersion',v_target.version,
        'projectVersion',v_project.version,'changed',false
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','project_member',
      'aggregateId',v_target.id,'aggregateVersion',v_target.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project_member',v_target.id,v_target.version);
  else
    v_old_role:=v_target.role;
    update public.project_members
    set role=p_target_role,is_observer=(p_target_role='observer'),version=version+1
    where id=v_target.id returning * into v_target;
    update public.projects set version=version+1,updated_at=now()
    where id=p_project_id returning * into v_project;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'project_member_role_changed','project_member',
      v_target.id,p_request_id,jsonb_build_object(
        'oldRole',v_old_role,'newRole',v_target.role,'membershipVersion',v_target.version,
        'projectVersion',v_project.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'membershipId',v_target.id,'role',v_target.role,'membershipVersion',v_target.version,
        'projectVersion',v_project.version,'changed',true
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','project_member',
      'aggregateId',v_target.id,'aggregateVersion',v_target.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project_member',v_target.id,v_target.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_remove_project_member(
  p_project_id uuid,
  p_membership_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_actor_member public.project_members%rowtype;
  v_target public.project_members%rowtype;
  v_task public.tasks%rowtype;
  v_offer public.task_assignment_offers%rowtype;
  v_seq integer:=1;
  v_released integer:=0;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'membershipId',p_membership_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_remove_project_member',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_project_manager(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_actor_member
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active'
  for update;
  select * into v_target
  from public.project_members pm
  where pm.id=p_membership_id and pm.project_id=p_project_id
  for update;

  if v_target.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_actor_member.role not in ('leader','admin') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_version is null or v_target.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_target.version);
  elsif v_target.member_state<>'active' or v_target.user_id is null then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  elsif v_target.role='leader' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_target.version,
      jsonb_build_object('reason','last_leader_protected')
    );
  elsif v_actor_member.role='admin' and v_target.role not in ('member','observer') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif exists(
    select 1 from public.tasks t
    where t.project_id=p_project_id and t.assignee_id=v_target.user_id and t.status='awaiting_review'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_target.version,
      jsonb_build_object('reason','pending_review')
    );
  else
    for v_offer in
      select * from public.task_assignment_offers o
      where o.project_id=p_project_id and o.target_user_id=v_target.user_id and o.state='pending'
      order by o.id for update
    loop
      update public.task_assignment_offers
      set state='rejected',responded_at=now(),version=version+1,updated_at=now()
      where id=v_offer.id;
      update public.tasks
      set assignment_state='claimable',is_direct_assignment=false,version=version+1,updated_at=now()
      where id=v_offer.task_id and assignment_state='pending_acceptance';
      v_seq:=v_seq+1;
      perform private.emit_event(
        v_claim.command_id,v_seq,p_project_id,v_actor,'task_assignment_released','task',
        v_offer.task_id,p_request_id,jsonb_build_object(
          'reason','member_removed','formerUserId',v_target.user_id
        )
      );
      v_released:=v_released+1;
    end loop;

    for v_task in
      select * from public.tasks t
      where t.project_id=p_project_id and t.assignee_id=v_target.user_id
        and t.status not in ('completed','canceled','awaiting_review')
      order by t.id for update
    loop
      update public.tasks
      set assignee_id=null,accepted_at=null,assignment_state='claimable',
          is_direct_assignment=false,status='not_started',blocked_reason=null,
          version=version+1,updated_at=now()
      where id=v_task.id;
      v_seq:=v_seq+1;
      perform private.emit_event(
        v_claim.command_id,v_seq,p_project_id,v_actor,'task_assignment_released','task',
        v_task.id,p_request_id,jsonb_build_object(
          'reason','member_removed','formerUserId',v_target.user_id,'previousStatus',v_task.status
        )
      );
      v_released:=v_released+1;
    end loop;

    update public.project_members
    set member_state='removed',departed_at=now(),version=version+1
    where id=v_target.id returning * into v_target;
    update public.projects set version=version+1,updated_at=now()
    where id=p_project_id returning * into v_project;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'project_member_removed','project_member',
      v_target.id,p_request_id,jsonb_build_object(
        'role',v_target.role,'membershipVersion',v_target.version,'projectVersion',v_project.version,
        'releasedTaskCount',v_released
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'membershipId',v_target.id,'state',v_target.member_state,'membershipVersion',v_target.version,
        'projectVersion',v_project.version,'releasedTaskCount',v_released
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','project_member',
      'aggregateId',v_target.id,'aggregateVersion',v_target.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project_member',v_target.id,v_target.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_transfer_project_leadership(
  p_project_id uuid,
  p_target_membership_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_source public.project_members%rowtype;
  v_target public.project_members%rowtype;
  v_target_old_role text;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'targetMembershipId',p_target_membership_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_transfer_project_leadership',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_source
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active'
  for update;
  select * into v_target
  from public.project_members pm
  where pm.id=p_target_membership_id and pm.project_id=p_project_id
  for update;

  if v_source.role<>'leader' or v_project.leader_id is distinct from v_actor then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_target.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_target.member_state<>'active' or v_target.user_id is null or v_target.user_id=v_actor then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  elsif v_target.role not in ('admin','member') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_target.version,
      jsonb_build_object('reason','observer_cannot_lead')
    );
  else
    v_target_old_role:=v_target.role;
    update public.project_members
    set role='member',is_observer=false,version=version+1
    where id=v_source.id returning * into v_source;
    update public.project_members
    set role='leader',is_observer=false,version=version+1
    where id=v_target.id returning * into v_target;
    update public.projects
    set leader_id=v_target.user_id,version=version+1,updated_at=now()
    where id=p_project_id returning * into v_project;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'project_member_role_changed','project_member',
      v_source.id,p_request_id,jsonb_build_object(
        'oldRole','leader','newRole','member','membershipVersion',v_source.version
      )
    );
    perform private.emit_event(
      v_claim.command_id,2,p_project_id,v_actor,'project_member_role_changed','project_member',
      v_target.id,p_request_id,jsonb_build_object(
        'oldRole',v_target_old_role,'newRole','leader','membershipVersion',v_target.version
      )
    );
    perform private.emit_event(
      v_claim.command_id,3,p_project_id,v_actor,'project_leadership_transferred','project',
      p_project_id,p_request_id,jsonb_build_object(
        'formerLeaderUserId',v_actor,'newLeaderUserId',v_target.user_id,
        'targetMembershipId',v_target.id,'projectVersion',v_project.version
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',p_project_id,'leaderUserId',v_target.user_id,
        'leaderMembershipId',v_target.id,'projectVersion',v_project.version
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','project',
      'aggregateId',p_project_id,'aggregateVersion',v_project.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_project.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_leave_project(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_member public.project_members%rowtype;
  v_task public.tasks%rowtype;
  v_offer public.task_assignment_offers%rowtype;
  v_seq integer:=1;
  v_released integer:=0;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_leave_project',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor),
    p_request_id,v_claim.command_id,null,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_member
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active'
  for update;

  if v_member.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_member.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_member.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_member.role='leader' or v_project.leader_id=v_actor then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_member.version,
      jsonb_build_object('reason','leader_must_transfer_first')
    );
  elsif exists(
    select 1 from public.tasks t
    where t.project_id=p_project_id and t.assignee_id=v_actor
      and t.status not in ('completed','canceled')
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_member.version,
      jsonb_build_object('reason','active_responsibility_requires_handoff')
    );
  else
    for v_offer in
      select * from public.task_assignment_offers o
      where o.project_id=p_project_id and o.target_user_id=v_actor and o.state='pending'
      order by o.id for update
    loop
      update public.task_assignment_offers
      set state='rejected',responded_at=now(),version=version+1,updated_at=now()
      where id=v_offer.id;
      update public.tasks
      set assignment_state='claimable',is_direct_assignment=false,version=version+1,updated_at=now()
      where id=v_offer.task_id and assignment_state='pending_acceptance';
      v_seq:=v_seq+1;
      perform private.emit_event(
        v_claim.command_id,v_seq,p_project_id,v_actor,'task_assignment_released','task',
        v_offer.task_id,p_request_id,jsonb_build_object(
          'reason','member_left','formerUserId',v_actor
        )
      );
      v_released:=v_released+1;
    end loop;

    update public.project_members
    set member_state='left',departed_at=now(),version=version+1
    where id=v_member.id returning * into v_member;
    update public.projects set version=version+1,updated_at=now()
    where id=p_project_id returning * into v_project;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'project_member_left','project_member',
      v_member.id,p_request_id,jsonb_build_object(
        'role',v_member.role,'membershipVersion',v_member.version,
        'projectVersion',v_project.version,'releasedTaskCount',v_released
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'membershipId',v_member.id,'state','left','membershipVersion',v_member.version,
        'projectVersion',v_project.version,'releasedTaskCount',v_released
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','project_member',
      'aggregateId',v_member.id,'aggregateVersion',v_member.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project_member',v_member.id,v_member.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_update_project_member_role(uuid,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_remove_project_member(uuid,uuid,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_transfer_project_leadership(uuid,uuid,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_leave_project(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.cmd_update_project_member_role(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_remove_project_member(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_transfer_project_leadership(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_leave_project(uuid,uuid,integer) to authenticated;
