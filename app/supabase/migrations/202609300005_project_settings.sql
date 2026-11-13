-- Constrained project-settings command. Governance-heavy fields stay guarded.

create function public.cmd_update_project_settings(
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
  p_require_student_number boolean
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

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'expectedVersion',p_expected_version,'name',p_name,
    'courseName',p_course_name,'description',p_description,'deadlineAt',p_deadline_at,
    'timezone',p_timezone,'contributionMode',p_contribution_mode,
    'autoPenaltyEnabled',p_auto_penalty_enabled,'requireRealName',p_require_real_name,
    'requireStudentNumber',p_require_student_number
  ));
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
          deadline_at=p_deadline_at,
          timezone=p_timezone,
          contribution_mode=p_contribution_mode,
          require_real_name=p_require_real_name,
          require_student_number=p_require_student_number,
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

revoke all on function public.cmd_update_project_settings(
  uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_update_project_settings(
  uuid,uuid,integer,text,text,text,timestamptz,text,text,boolean,boolean,boolean
) to authenticated;
