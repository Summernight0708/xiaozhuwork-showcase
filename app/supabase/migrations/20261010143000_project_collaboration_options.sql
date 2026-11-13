-- Project-scoped task creation permission. Trailing defaults keep old calls valid
-- without retaining ambiguous PostgREST overloads.
alter table public.projects
  add column allow_member_task_creation boolean not null default true;

drop function public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz);
drop function public.cmd_update_project_settings(uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean,timestamptz);

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
  p_start_at timestamptz default null,
  p_allow_member_task_creation boolean default true
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
    -- Preserve hashes of commands recorded before this migration with default behavior.
    || case when p_allow_member_task_creation then '{}'::jsonb
       else jsonb_build_object('allowMemberTaskCreation', p_allow_member_task_creation) end
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
  elsif p_allow_member_task_creation is null then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','allowMemberTaskCreation');
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
      require_real_name,require_student_number,allow_member_task_creation,leader_id,created_by,version
    ) values(
      btrim(p_name),p_course_name,p_description,coalesce(p_timezone,'Asia/Shanghai'),
      p_start_at,p_deadline_at,coalesce(p_contribution_mode,'weighted'),
      coalesce(p_require_real_name,false),coalesce(p_require_student_number,false),
      p_allow_member_task_creation,v_actor,v_actor,1
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

create or replace function public.cmd_update_project_settings(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_name text,
  p_course_name text,
  p_description text,
  p_deadline_at timestamptz,
  p_timezone text,
  p_contribution_mode text,
  p_auto_penalty_enabled boolean,
  p_require_real_name boolean,
  p_require_student_number boolean,
  p_start_at timestamptz default null,
  p_allow_member_task_creation boolean default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_changed_fields jsonb:='[]'::jsonb;
  v_active_members integer;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(
    jsonb_build_object(
      'projectId',p_project_id,'expectedVersion',p_expected_version,'name',p_name,
      'courseName',p_course_name,'description',p_description,'deadlineAt',p_deadline_at,
      'timezone',p_timezone,'contributionMode',p_contribution_mode,
      'autoPenaltyEnabled',p_auto_penalty_enabled,'requireRealName',p_require_real_name,
      'requireStudentNumber',p_require_student_number
    )
    -- Omitted by old clients: retain the current setting and the legacy payload hash.
    || case when p_allow_member_task_creation is null then '{}'::jsonb
       else jsonb_build_object('allowMemberTaskCreation',p_allow_member_task_creation) end
    || case
      when p_start_at is null then '{}'::jsonb
      else jsonb_build_object('startAt',p_start_at)
    end
  );
  select * into v_claim from private.claim_command(
    v_actor,'cmd_update_project_settings',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;

  if not private.is_active_leader(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','name');
  elsif p_course_name is not null and char_length(p_course_name)>120 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','courseName');
  elsif p_description is not null and char_length(p_description)>2000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','description');
  elsif p_deadline_at is null then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_start_at is not null and p_start_at>=p_deadline_at then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','startAt',v_project.version,
      jsonb_build_object('reason','start_must_precede_deadline')
    );
  elsif p_deadline_at is distinct from v_project.deadline_at and p_deadline_at<=now() then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_deadline_at is distinct from v_project.deadline_at and exists(
    select 1 from public.tasks t
    where t.project_id=p_project_id and t.deadline_at>p_deadline_at
  ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','deadlineAt',v_project.version,
      jsonb_build_object('reason','before_existing_task_deadline')
    );
  elsif p_timezone is null
     or char_length(p_timezone) not between 1 and 80
     or not exists(select 1 from pg_catalog.pg_timezone_names tz where tz.name=p_timezone) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','timezone');
  elsif p_contribution_mode is null or p_contribution_mode not in ('weighted','facts_only') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','contributionMode');
  elsif p_auto_penalty_enabled is null
     or p_require_real_name is null
     or p_require_student_number is null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED');
  elsif p_auto_penalty_enabled is distinct from v_project.auto_penalty_enabled then
    v_result:=private.failure(
      p_request_id,'FEATURE_DISABLED','autoPenaltyEnabled',v_project.version,
      jsonb_build_object('reason','penalty_engine_not_implemented')
    );
  elsif p_contribution_mode is distinct from v_project.contribution_mode
     and exists(select 1 from public.tasks t where t.project_id=p_project_id) then
    v_result:=private.failure(
      p_request_id,'CONFIRMATION_REQUIRED','contributionMode',v_project.version,
      jsonb_build_object('reason','contribution_mode_governance_required')
    );
  else
    select count(*)::integer into v_active_members
    from public.project_members pm
    where pm.project_id=p_project_id and pm.member_state='active' and pm.user_id is not null;

    if (
      (not v_project.require_real_name and p_require_real_name)
      or (not v_project.require_student_number and p_require_student_number)
    ) and v_active_members>1 then
      v_result:=private.failure(
        p_request_id,'CONFIRMATION_REQUIRED',
        case
          when not v_project.require_real_name and p_require_real_name then 'requireRealName'
          else 'requireStudentNumber'
        end,
        v_project.version,
        jsonb_build_object('reason','existing_members_require_unanimous_consent')
      );
    else
      if btrim(p_name) is distinct from v_project.name then
        v_changed_fields:=v_changed_fields || jsonb_build_array('name');
      end if;
      if p_course_name is distinct from v_project.course_name then
        v_changed_fields:=v_changed_fields || jsonb_build_array('courseName');
      end if;
      if p_description is distinct from v_project.description then
        v_changed_fields:=v_changed_fields || jsonb_build_array('description');
      end if;
      if p_start_at is distinct from v_project.start_at then
        v_changed_fields:=v_changed_fields || jsonb_build_array('startAt');
      end if;
      if p_deadline_at is distinct from v_project.deadline_at then
        v_changed_fields:=v_changed_fields || jsonb_build_array('deadlineAt');
      end if;
      if p_timezone is distinct from v_project.timezone then
        v_changed_fields:=v_changed_fields || jsonb_build_array('timezone');
      end if;
      if p_contribution_mode is distinct from v_project.contribution_mode then
        v_changed_fields:=v_changed_fields || jsonb_build_array('contributionMode');
      end if;
      if p_require_real_name is distinct from v_project.require_real_name then
        v_changed_fields:=v_changed_fields || jsonb_build_array('requireRealName');
      end if;
      if p_require_student_number is distinct from v_project.require_student_number then
        v_changed_fields:=v_changed_fields || jsonb_build_array('requireStudentNumber');
      end if;

      if p_allow_member_task_creation is not null
         and p_allow_member_task_creation is distinct from v_project.allow_member_task_creation then
        v_changed_fields:=v_changed_fields || jsonb_build_array('allowMemberTaskCreation');
      end if;

      if jsonb_array_length(v_changed_fields)=0 then
        v_result:=jsonb_build_object(
          'ok',true,
          'data',jsonb_build_object(
            'projectId',v_project.id,'projectVersion',v_project.version,'changed',false
          ),
          'requestId',p_request_id,'replayed',false,'aggregateType','project',
          'aggregateId',v_project.id,'aggregateVersion',v_project.version
        );
        return private.complete_command(v_claim.command_id,v_result,'project',v_project.id,v_project.version);
      end if;

      update public.projects
      set name=btrim(p_name),
          course_name=p_course_name,
          description=p_description,
          start_at=p_start_at,
          deadline_at=p_deadline_at,
          timezone=p_timezone,
          contribution_mode=p_contribution_mode,
          require_real_name=p_require_real_name,
          require_student_number=p_require_student_number,
          allow_member_task_creation=coalesce(p_allow_member_task_creation,v_project.allow_member_task_creation),
          version=version+1,
          updated_at=now()
      where id=p_project_id
      returning * into v_project;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,'project_settings_updated','project',
        p_project_id,p_request_id,jsonb_build_object(
          'changedFields',v_changed_fields,'projectVersion',v_project.version
        )
      );
      v_result:=jsonb_build_object(
        'ok',true,
        'data',jsonb_build_object(
          'projectId',v_project.id,'projectVersion',v_project.version,'changed',true
        ),
        'requestId',p_request_id,'replayed',false,'aggregateType','project',
        'aggregateId',v_project.id,'aggregateVersion',v_project.version
      );
      return private.complete_command(v_claim.command_id,v_result,'project',v_project.id,v_project.version);
    end if;
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

  -- Recheck current membership and the setting after acquiring project/member locks.
  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or (not v_project.allow_member_task_creation and not exists (
       select 1 from public.project_members pm
       where pm.project_id=p_project_id and pm.user_id=v_actor
         and pm.member_state='active' and pm.role in ('leader','admin')
         and not pm.is_observer
     )) then
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

revoke all on function public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean) from public, anon;
grant execute on function public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean) to authenticated;
revoke all on function public.cmd_update_project_settings(uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean,timestamptz,boolean) from public, anon;
grant execute on function public.cmd_update_project_settings(uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean,timestamptz,boolean) to authenticated;
