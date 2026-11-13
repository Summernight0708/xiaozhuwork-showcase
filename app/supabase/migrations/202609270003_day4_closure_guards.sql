-- Day 4 closure guards: forward overrides for pre-existing command RPCs.
-- Lifecycle checks run after command replay and optimistic-lock gates where applicable.

create or replace function public.cmd_create_project(
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
  if p_request_id is null then return private.failure(null, 'VALIDATION_FAILED', 'requestId'); end if;
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
  v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
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

create or replace function public.cmd_join_project_via_invite(
  p_token text, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_token_hash bytea; v_project_id uuid; v_hash bytea; v_claim record; v_replay jsonb;
  v_project public.projects%rowtype; v_invite public.project_invitations%rowtype; v_profile public.profiles%rowtype;
  v_id uuid; v_result jsonb; v_seq integer:=1; v_req record;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
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
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_invite.revoked_at is not null or v_invite.expires_at<=now() then v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif private.is_active_member(v_project_id,v_actor) then v_result:=private.failure(p_request_id,'ALREADY_MEMBER');
  elsif v_project.require_real_name and nullif(btrim(v_profile.real_name),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','realName');
  elsif v_project.require_student_number and nullif(btrim(v_profile.student_number),'') is null then v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','studentNumber');
  elsif v_invite.mode='direct' and v_invite.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_invite.mode='approval' and p_expected_version<>0 then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_invite.max_uses is not null and v_invite.uses_count>=v_invite.max_uses then v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif v_invite.mode='direct' and (select count(*) from public.project_members where project_id=v_project_id and member_state='active' and user_id is not null)>=8 then v_result:=private.failure(p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',8));
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

create or replace function public.cmd_review_project_join_request(
  p_project_id uuid, p_join_request_id uuid, p_action text, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype;
  v_invite public.project_invitations%rowtype; v_join public.project_join_requests%rowtype; v_profile public.profiles%rowtype;
  v_membership_id uuid; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
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
  elsif p_action='approve' and v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_join.state<>'pending' then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','state');
  elsif p_action is null or p_action not in ('approve','reject') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action='approve' and v_join.user_id is null then v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_action='approve' and v_invite.revoked_at is not null then v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif p_action='approve' and v_invite.max_uses is not null and v_invite.uses_count>=v_invite.max_uses then v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif p_action='approve' and (select count(*) from public.project_members where project_id=p_project_id and member_state='active' and user_id is not null)>=8 then v_result:=private.failure(p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',8));
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

create or replace function public.cmd_create_task(
  p_project_id uuid, p_request_id uuid, p_expected_version integer, p_title text,
  p_description text default null, p_deadline_at timestamptz default null, p_weight smallint default null,
  p_assignment_mode text default 'claimable', p_assignee_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype;
  v_task_id uuid; v_offer_id uuid; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version,'title',p_title,'description',p_description,'deadlineAt',p_deadline_at,'weight',p_weight,'assignmentMode',p_assignment_mode,'assigneeId',p_assignee_id));
  select * into v_claim from private.claim_command(v_actor,'cmd_create_task',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(private.is_active_member(p_project_id,v_actor),p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches); if v_replay is not null then return v_replay; end if;
  select * into v_project from public.projects where id=p_project_id for update;
  if p_expected_version is null or v_project.version<>p_expected_version then v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_deadline_at is null or p_deadline_at<=now() or p_deadline_at>v_project.deadline_at then v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_assignment_mode is null or p_assignment_mode not in ('claimable','direct') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assignmentMode');
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

create or replace function public.cmd_claim_task(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
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
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
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

create or replace function public.cmd_respond_to_task_assignment(
  p_project_id uuid, p_task_id uuid, p_assignment_offer_id uuid, p_action text,
  p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_offer public.task_assignment_offers%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
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
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
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

create or replace function public.cmd_update_task_progress(
  p_project_id uuid, p_task_id uuid, p_request_id uuid, p_expected_version integer,
  p_status text, p_progress_text text, p_blocked_reason text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash bytea; v_claim record; v_replay jsonb; v_project public.projects%rowtype; v_task public.tasks%rowtype; v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
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
  elsif v_project.lifecycle_state <> 'active' then v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_status is null or p_status not in ('in_progress','blocked') then v_result:=private.failure(p_request_id,'VALIDATION_FAILED','status');
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

create or replace function public.cmd_reserve_task_file_upload(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_mode text,
  p_target_file_id uuid,
  p_original_name text,
  p_declared_mime_type text,
  p_declared_size_bytes bigint
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
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_file public.task_files%rowtype;
  v_reservation_id uuid;
  v_safe_name text;
  v_object_path text;
  v_expires_at timestamptz;
  v_project_usage_bytes bigint;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if not exists (select 1 from public.projects p where p.id = p_project_id) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout', '5s', true);
  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id,
    'taskId', p_task_id,
    'expectedVersion', p_expected_version,
    'mode', p_mode,
    'targetFileId', p_target_file_id,
    'originalName', p_original_name,
    'declaredMimeType', p_declared_mime_type,
    'declaredSizeBytes', p_declared_size_bytes
  ));
  select * into v_claim
  from private.claim_command(
    v_actor, 'cmd_reserve_task_file_upload', p_request_id, v_hash, null, p_project_id
  );

  select * into v_project
  from public.projects p
  where p.id = p_project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id = p_task_id and t.project_id = p_project_id
  for update;

  if not found or not private.is_current_task_file_actor(p_project_id, p_task_id, v_actor) then
    v_result := private.reject_unless_authorized(
      false, p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
    );
    return v_result;
  end if;

  v_result := private.reject_unless_authorized(
    true, p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;
  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id, 'PROJECT_NOT_ACTIVE', null, v_project.version);
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  if p_mode is null or p_mode not in ('new_file', 'new_version') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'mode');
  elsif (p_mode = 'new_file' and p_target_file_id is not null)
     or (p_mode = 'new_version' and p_target_file_id is null) then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'targetFileId');
  elsif p_original_name is null
     or char_length(btrim(p_original_name)) not between 1 and 255
     or strpos(p_original_name, '/') > 0
     or strpos(p_original_name, chr(92)) > 0
     or p_original_name ~ '[[:cntrl:]]' then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'originalName');
  elsif p_declared_mime_type is null or not private.is_allowed_task_file_mime(p_declared_mime_type) then
    v_result := private.failure(p_request_id, 'FILE_TYPE_NOT_ALLOWED', 'declaredMimeType');
  elsif p_declared_size_bytes is null or p_declared_size_bytes <= 0 then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'declaredSizeBytes');
  elsif p_declared_size_bytes > 52428800 then
    v_result := private.failure(
      p_request_id, 'STORAGE_QUOTA_EXCEEDED', 'declaredSizeBytes', null,
      jsonb_build_object('scope', 'file', 'limitBytes', 52428800)
    );
  elsif p_mode = 'new_file' and (p_expected_version is null or p_expected_version <> v_task.version) then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_task.version);
  else
    if p_mode = 'new_version' then
      select * into v_file
      from public.task_files f
      where f.id = p_target_file_id
        and f.project_id = p_project_id
        and f.task_id = p_task_id
      for update;
      if not found then
        v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
      elsif p_expected_version is null or p_expected_version <> v_file.version then
        v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_file.version);
      end if;
    end if;
  end if;

  if v_result is null then
    select private.task_file_project_usage_bytes(p_project_id, null) into v_project_usage_bytes;

    if v_project_usage_bytes + 52428800 > 536870912 then
      v_result := private.failure(
        p_request_id, 'STORAGE_QUOTA_EXCEEDED', null, null,
        jsonb_build_object('scope', 'project', 'limitBytes', 536870912)
      );
    end if;
  end if;

  if v_result is not null then
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  v_safe_name := private.sanitize_task_file_name(p_original_name);
  if v_safe_name is null or v_safe_name in ('', '.', '..') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'originalName');
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  v_reservation_id := gen_random_uuid();
  v_object_path := 'pending/' || p_project_id::text || '/' || v_reservation_id::text || '/' || v_safe_name;
  v_expires_at := now() + interval '15 minutes';

  insert into public.file_upload_reservations (
    id, project_id, task_id, actor_id, mode, target_file_id, target_file_version,
    object_path, original_name, declared_mime_type, declared_size_bytes,
    state, expires_at, version
  ) values (
    v_reservation_id, p_project_id, p_task_id, v_actor, p_mode, p_target_file_id,
    case when p_mode = 'new_version' then p_expected_version else null end,
    v_object_path, btrim(p_original_name), p_declared_mime_type, p_declared_size_bytes,
    'reserved', v_expires_at, 1
  );

  perform private.emit_event(
    v_claim.command_id, 1, p_project_id, v_actor,
    'task_file_upload_reserved', 'file_upload_reservation', v_reservation_id,
    p_request_id, jsonb_build_object('taskId', p_task_id, 'mode', p_mode)
  );

  v_result := jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'reservationId', v_reservation_id,
      'objectPath', v_object_path,
      'expiresAt', v_expires_at
    ),
    'requestId', p_request_id,
    'replayed', false,
    'aggregateType', 'file_upload_reservation',
    'aggregateId', v_reservation_id,
    'aggregateVersion', 1
  );
  return private.complete_command(
    v_claim.command_id, v_result, 'file_upload_reservation', v_reservation_id, 1
  );
end;
$$;

revoke all on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_join_project_via_invite(text,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.cmd_claim_task(uuid,uuid,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_respond_to_task_assignment(uuid,uuid,uuid,text,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_update_task_progress(uuid,uuid,uuid,integer,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint) from public, anon, authenticated, service_role;
grant execute on function public.cmd_create_project_invite(uuid,uuid,integer,text,integer,integer) to authenticated;
grant execute on function public.cmd_join_project_via_invite(text,uuid,integer) to authenticated;
grant execute on function public.cmd_review_project_join_request(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid) to authenticated;
grant execute on function public.cmd_claim_task(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_respond_to_task_assignment(uuid,uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_update_task_progress(uuid,uuid,uuid,integer,text,text,text) to authenticated;
grant execute on function public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint) to authenticated;
