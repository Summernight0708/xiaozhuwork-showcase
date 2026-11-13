-- P1: enforce account/project Pro quotas with prospective-state admission and stable locking.

create or replace function private.project_member_limit_from_state(p_state text)
returns integer
language sql
immutable
security definer
set search_path = ''
as $$
  select case when p_state in ('active','grace') then 20 else 8 end;
$$;

revoke all on function private.project_member_limit_from_state(text)
  from public, anon, authenticated, service_role;

create or replace function private.project_member_limit(
  p_project_id uuid,
  p_at timestamptz
) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select private.project_member_limit_from_state(e.state)
  from private.resolve_project_entitlement(p_project_id,p_at) e;
$$;

create or replace function private.resolve_project_entitlement_with_prospective_member(
  p_project_id uuid,
  p_user_id uuid,
  p_role text,
  p_at timestamptz
) returns table(
  plan text,
  state text,
  source text,
  grace_expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current record;
begin
  select *
  into v_current
  from private.resolve_project_entitlement(p_project_id,p_at);

  if v_current.state in ('active','grace') then
    return query
    select v_current.plan,v_current.state,v_current.source,v_current.grace_expires_at;
    return;
  end if;

  if p_user_id is not null
     and p_role in ('leader','admin','member')
     and private.is_account_pro(p_user_id,p_at) then
    return query
    select 'pro'::text,'active'::text,'account_member'::text,null::timestamptz;
    return;
  end if;

  return query
  select v_current.plan,v_current.state,v_current.source,v_current.grace_expires_at;
end;
$$;

revoke all on function private.resolve_project_entitlement_with_prospective_member(
  uuid,uuid,text,timestamptz
) from public, anon, authenticated, service_role;

create or replace function private.project_member_limit_for_prospective_member(
  p_project_id uuid,
  p_user_id uuid,
  p_role text,
  p_at timestamptz
) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select private.project_member_limit_from_state(e.state)
  from private.resolve_project_entitlement_with_prospective_member(
    p_project_id,p_user_id,p_role,p_at
  ) e;
$$;

revoke all on function private.project_member_limit_for_prospective_member(
  uuid,uuid,text,timestamptz
) from public, anon, authenticated, service_role;

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
  p_require_student_number boolean default null,
  p_start_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_at timestamptz := transaction_timestamp();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project_id uuid;
  v_membership_id uuid;
  v_current_free_projects integer := 0;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id, 'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null, 'VALIDATION_FAILED', 'requestId'); end if;
  v_hash := private.payload_hash(
    jsonb_build_object(
      'expectedVersion', p_expected_version, 'name', p_name, 'deadlineAt', p_deadline_at,
      'courseName', p_course_name, 'description', p_description, 'timezone', p_timezone,
      'contributionMode', p_contribution_mode, 'requireRealName', p_require_real_name,
      'requireStudentNumber', p_require_student_number
    )
    || case
      when p_start_at is null then '{}'::jsonb
      else jsonb_build_object('startAt', p_start_at)
    end
  );
  select * into v_claim
  from private.claim_command(v_actor,'cmd_create_project',p_request_id,v_hash,v_actor,null);
  v_replay := private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  -- Global quota lock ordering starts with the account row.
  perform 1 from public.profiles where id=v_actor for update;
  if found then
    v_current_free_projects :=
      private.account_active_free_project_count(v_actor,v_at);
  end if;

  if not found then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> 0 then
    v_result := private.failure(p_request_id,'STALE_VERSION',null,null);
  elsif p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','name');
  elsif p_deadline_at is null or p_deadline_at <= now() then
    v_result := private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_start_at is not null and p_start_at >= p_deadline_at then
    v_result := private.failure(
      p_request_id,'VALIDATION_FAILED','startAt',null,
      jsonb_build_object('reason','start_must_precede_deadline')
    );
  elsif coalesce(p_contribution_mode,'weighted') not in ('weighted','facts_only') then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','contributionMode');
  elsif not private.account_can_add_free_project(v_actor,v_at) then
    v_result := private.failure(
      p_request_id,'ACTIVE_FREE_PROJECT_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',5,
        'current',v_current_free_projects,
        'effectiveState','free'
      )
    );
  else
    insert into public.projects(
      name,course_name,description,timezone,start_at,deadline_at,contribution_mode,
      require_real_name,require_student_number,leader_id,created_by,version
    ) values(
      btrim(p_name),p_course_name,p_description,coalesce(p_timezone,'Asia/Shanghai'),
      p_start_at,p_deadline_at,coalesce(p_contribution_mode,'weighted'),
      coalesce(p_require_real_name,false),coalesce(p_require_student_number,false),
      v_actor,v_actor,1
    ) returning id into v_project_id;

    insert into public.project_members(project_id,user_id,role,member_state)
    values(v_project_id,v_actor,'leader','active')
    returning id into v_membership_id;

    perform private.emit_event(
      v_claim.command_id,1,v_project_id,v_actor,
      'project_created','project',v_project_id,p_request_id,
      jsonb_build_object('version',1)
    );

    v_result := jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',v_project_id,
        'leaderMembershipId',v_membership_id
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','project',
      'aggregateId',v_project_id,
      'aggregateVersion',1
    );
    return private.complete_command(
      v_claim.command_id,v_result,'project',v_project_id,1
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_join_project_via_invite(
  p_token text,
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
  v_token_hash bytea;
  v_project_id uuid;
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_invite public.project_invitations%rowtype;
  v_profile public.profiles%rowtype;
  v_prospective_state text;
  v_member_limit integer;
  v_current_members integer:=0;
  v_current_free_projects integer:=0;
  v_id uuid;
  v_result jsonb;
  v_seq integer:=1;
  v_req record;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_token is null or p_token='' then return private.failure(p_request_id,'INVITE_UNAVAILABLE'); end if;

  v_token_hash:=extensions.digest(convert_to(p_token,'utf8'),'sha256');
  select project_id into v_project_id
  from public.project_invitations
  where token_hash=v_token_hash;
  if v_project_id is null then
    return private.failure(p_request_id,'INVITE_UNAVAILABLE');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'tokenHash',encode(v_token_hash,'hex'),
    'expectedVersion',p_expected_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_join_project_via_invite',p_request_id,v_hash,null,v_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  -- Quota lock order: joining user first, then project, then invite.
  select * into v_profile
  from public.profiles
  where id=v_actor
  for update;

  select * into v_project
  from public.projects
  where id=v_project_id
  for update;

  select * into v_invite
  from public.project_invitations
  where token_hash=v_token_hash
    and project_id=v_project_id
  for update;

  select count(*)::integer
  into v_current_members
  from public.project_members
  where project_id=v_project_id
    and member_state='active'
    and user_id is not null;

  if v_invite.mode='direct' then
    select e.state
    into v_prospective_state
    from private.resolve_project_entitlement_with_prospective_member(
      v_project_id,v_actor,'member',v_at
    ) e;

    v_member_limit :=
      private.project_member_limit_for_prospective_member(
        v_project_id,v_actor,'member',v_at
      );
    v_current_free_projects :=
      private.account_active_free_project_count(v_actor,v_at);
  end if;

  if v_profile.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_invite.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(
      p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version
    );
  elsif v_invite.revoked_at is not null or v_invite.expires_at<=now() then
    v_result:=private.failure(p_request_id,'INVITE_UNAVAILABLE');
  elsif private.is_active_member(v_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'ALREADY_MEMBER');
  elsif v_project.require_real_name
        and nullif(btrim(v_profile.real_name),'') is null then
    v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','realName');
  elsif v_project.require_student_number
        and nullif(btrim(v_profile.student_number),'') is null then
    v_result:=private.failure(p_request_id,'CONFIRMATION_REQUIRED','studentNumber');
  elsif v_invite.mode='direct' and v_invite.version<>p_expected_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_invite.version
    );
  elsif v_invite.mode='approval' and p_expected_version<>0 then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_invite.version
    );
  elsif v_invite.max_uses is not null
        and v_invite.uses_count>=v_invite.max_uses then
    v_result:=private.failure(p_request_id,'INVITE_EXHAUSTED');
  elsif v_invite.mode='direct' and v_current_members>=v_member_limit then
    v_result:=private.failure(
      p_request_id,'PROJECT_MEMBER_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',v_member_limit,
        'current',v_current_members,
        'effectiveState',v_prospective_state
      )
    );
  elsif v_invite.mode='direct'
        and v_prospective_state='free'
        and not private.account_can_add_free_project(v_actor,v_at) then
    v_result:=private.failure(
      p_request_id,'ACTIVE_FREE_PROJECT_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',5,
        'current',v_current_free_projects,
        'effectiveState','free'
      )
    );
  elsif v_invite.mode='approval'
        and exists(
          select 1
          from public.project_join_requests
          where project_id=v_project_id
            and user_id=v_actor
            and state='pending'
        ) then
    v_result:=private.failure(p_request_id,'JOIN_REQUEST_PENDING');
  elsif v_invite.mode='direct' then
    for v_req in
      select id
      from public.project_join_requests
      where project_id=v_project_id
        and user_id=v_actor
        and state='pending'
      order by id
      for update
    loop
      null;
    end loop;

    insert into public.project_members(
      project_id,user_id,role,member_state,display_name_snapshot
    ) values(
      v_project_id,v_actor,'member','active',v_profile.display_name
    ) returning id into v_id;

    update public.project_invitations
    set uses_count=uses_count+1,
        version=version+1,
        updated_at=now()
    where id=v_invite.id
    returning * into v_invite;

    perform private.emit_event(
      v_claim.command_id,1,v_project_id,v_actor,
      'project_member_joined','project_member',v_id,p_request_id,
      jsonb_build_object('invitationId',v_invite.id)
    );

    for v_req in
      select id
      from public.project_join_requests
      where project_id=v_project_id
        and user_id=v_actor
        and state='pending'
      order by id
    loop
      v_seq:=v_seq+1;
      update public.project_join_requests
      set state='canceled',
          version=version+1,
          reviewed_at=now(),
          updated_at=now()
      where id=v_req.id;
      perform private.emit_event(
        v_claim.command_id,v_seq,v_project_id,v_actor,
        'project_join_request_canceled','project_join_request',
        v_req.id,p_request_id,
        jsonb_build_object('reason','joined_directly')
      );
    end loop;

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',v_project_id,
        'outcome','joined',
        'membershipId',v_id,
        'invitationVersion',v_invite.version
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','invitation',
      'aggregateId',v_invite.id,
      'aggregateVersion',v_invite.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'invitation',v_invite.id,v_invite.version
    );
  else
    insert into public.project_join_requests(
      invitation_id,project_id,user_id
    ) values(
      v_invite.id,v_project_id,v_actor
    ) returning id into v_id;

    perform private.emit_event(
      v_claim.command_id,1,v_project_id,v_actor,
      'project_join_requested','project_join_request',
      v_id,p_request_id,
      jsonb_build_object('invitationId',v_invite.id)
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',v_project_id,
        'outcome','pending_approval',
        'joinRequestId',v_id,
        'invitationVersion',v_invite.version
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','join_request',
      'aggregateId',v_id,
      'aggregateVersion',1
    );
    return private.complete_command(
      v_claim.command_id,v_result,'join_request',v_id,1
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

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
    private.is_active_leader(p_project_id,v_actor),
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

create or replace function public.cmd_create_task(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_title text,
  p_description text default null,
  p_deadline_at timestamptz default null,
  p_weight smallint default null,
  p_assignment_mode text default 'claimable',
  p_assignee_id uuid default null,
  p_required_submission_file_type text default null
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
  v_entitlement record;
  v_task_limit integer;
  v_current_tasks integer:=0;
  v_task_id uuid;
  v_offer_id uuid;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'expectedVersion',p_expected_version,
    'title',p_title,
    'description',p_description,
    'deadlineAt',p_deadline_at,
    'weight',p_weight,
    'assignmentMode',p_assignment_mode,
    'assigneeId',p_assignee_id,
    'requiredSubmissionFileType',p_required_submission_file_type
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_create_task',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor),
    p_request_id,v_claim.command_id,
    v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  select * into v_project
  from public.projects
  where id=p_project_id
  for update;

  perform 1
  from public.project_members pm
  where pm.project_id=p_project_id
    and pm.user_id in (v_actor,p_assignee_id)
  order by pm.user_id
  for update;

  select *
  into v_entitlement
  from private.resolve_project_entitlement(p_project_id,v_at);

  v_task_limit :=
    private.project_concurrent_task_limit(p_project_id,v_at);

  select count(*)::integer
  into v_current_tasks
  from public.tasks
  where project_id=p_project_id
    and status not in ('completed','canceled');

  if not private.is_active_non_observer_member(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_project.version
    );
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(
      p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version
    );
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_deadline_at is null
        or p_deadline_at<=now()
        or p_deadline_at>v_project.deadline_at then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_assignment_mode is null
        or p_assignment_mode not in ('claimable','direct') then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','assignmentMode'
    );
  elsif v_project.contribution_mode='weighted'
        and (p_weight is null or p_weight not between 1 and 5) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif p_assignment_mode='claimable' and p_assignee_id is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assigneeId');
  elsif p_assignment_mode='direct'
        and (
          p_assignee_id is null
          or not private.is_active_non_observer_member(
            p_project_id,p_assignee_id
          )
        ) then
    v_result:=private.failure(
      p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','assigneeId'
    );
  elsif p_required_submission_file_type is not null
        and p_required_submission_file_type not in (
          'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType'
    );
  elsif v_current_tasks>=v_task_limit then
    v_result:=private.failure(
      p_request_id,'CONCURRENT_TASK_LIMIT_REACHED',null,null,
      jsonb_build_object(
        'limit',v_task_limit,
        'current',v_current_tasks,
        'effectiveState',v_entitlement.state
      )
    );
  else
    insert into public.tasks(
      project_id,title,description,created_by,deadline_at,status,weight,
      is_direct_assignment,assignment_state,required_submission_file_type
    ) values(
      p_project_id,btrim(p_title),p_description,v_actor,p_deadline_at,'not_started',
      p_weight,p_assignment_mode='direct',
      case
        when p_assignment_mode='direct' then 'pending_acceptance'
        else 'claimable'
      end,
      p_required_submission_file_type
    )
    returning id into v_task_id;

    if p_assignment_mode='direct' then
      insert into public.task_assignment_offers(
        task_id,project_id,target_user_id,created_by
      ) values(
        v_task_id,p_project_id,p_assignee_id,v_actor
      ) returning id into v_offer_id;
    end if;

    update public.projects
    set version=version+1,updated_at=now()
    where id=p_project_id
    returning version into v_project.version;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_created','task',v_task_id,p_request_id,
      jsonb_strip_nulls(jsonb_build_object(
        'assignmentMode',p_assignment_mode,
        'requiredSubmissionFileType',p_required_submission_file_type
      ))
    );

    v_result:=jsonb_strip_nulls(jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',v_task_id,
        'taskVersion',1,
        'assignmentOfferId',v_offer_id,
        'assignmentOfferVersion',
          case when v_offer_id is null then null else 1 end
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','project',
      'aggregateId',p_project_id,
      'aggregateVersion',v_project.version
    ));
    return private.complete_command(
      v_claim.command_id,v_result,
      'project',p_project_id,v_project.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;
