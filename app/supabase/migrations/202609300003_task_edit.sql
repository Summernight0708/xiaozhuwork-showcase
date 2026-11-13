-- Controlled task-definition editing. Assignment changes stay in assignment commands.

create function public.cmd_edit_task(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_title text,
  p_description text,
  p_deadline_at timestamptz,
  p_weight smallint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_actor_member public.project_members%rowtype;
  v_changed_fields jsonb:='[]'::jsonb;
  v_has_activity boolean;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version,
    'title',p_title,'description',p_description,'deadlineAt',p_deadline_at,'weight',p_weight
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_edit_task',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1 from public.tasks t
        where t.id=p_task_id and t.project_id=p_project_id
          and (t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor))
      ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_task
  from public.tasks t where t.id=p_task_id and t.project_id=p_project_id for update;
  select * into v_actor_member
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active';

  if v_task.id is null
     or v_actor_member.id is null
     or v_actor_member.role='observer'
     or (v_task.created_by is distinct from v_actor and v_actor_member.role<>'leader') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.status in ('awaiting_review','completed','canceled') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_definition_locked','status',v_task.status)
    );
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_description is not null and char_length(p_description)>4000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','description');
  elsif p_deadline_at is null then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_deadline_at is distinct from v_task.deadline_at
        and (p_deadline_at<=now() or p_deadline_at>v_project.deadline_at) then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif v_project.contribution_mode='weighted' and (p_weight is null or p_weight not between 1 and 5) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_task.accepted_at is not null and p_deadline_at is distinct from v_task.deadline_at then
    v_result:=private.failure(
      p_request_id,'CONFIRMATION_REQUIRED','deadlineAt',v_task.version,
      jsonb_build_object('reason','accepted_task_deadline_change')
    );
  else
    v_has_activity:=v_task.accepted_at is not null
      or v_task.first_submitted_at is not null
      or v_task.status<>'not_started'
      or nullif(btrim(coalesce(v_task.progress_text,'')),'') is not null
      or exists(select 1 from public.task_file_versions fv where fv.task_id=v_task.id)
      or exists(select 1 from public.task_review_rounds rr where rr.task_id=v_task.id);

    if v_has_activity and p_weight is distinct from v_task.weight then
      v_result:=private.failure(
        p_request_id,'CONFIRMATION_REQUIRED','weight',v_task.version,
        jsonb_build_object('reason','task_activity_weight_change')
      );
    else
      if btrim(p_title) is distinct from v_task.title then
        v_changed_fields:=v_changed_fields || jsonb_build_array('title');
      end if;
      if p_description is distinct from v_task.description then
        v_changed_fields:=v_changed_fields || jsonb_build_array('description');
      end if;
      if p_deadline_at is distinct from v_task.deadline_at then
        v_changed_fields:=v_changed_fields || jsonb_build_array('deadlineAt');
      end if;
      if p_weight is distinct from v_task.weight then
        v_changed_fields:=v_changed_fields || jsonb_build_array('weight');
      end if;

      if jsonb_array_length(v_changed_fields)=0 then
        v_result:=jsonb_build_object(
          'ok',true,
          'data',jsonb_build_object(
            'taskId',v_task.id,'taskVersion',v_task.version,'changed',false,
            'title',v_task.title,'description',v_task.description,'deadlineAt',v_task.deadline_at,'weight',v_task.weight
          ),
          'requestId',p_request_id,'replayed',false,'aggregateType','task',
          'aggregateId',v_task.id,'aggregateVersion',v_task.version
        );
        return private.complete_command(v_claim.command_id,v_result,'task',v_task.id,v_task.version);
      end if;

      update public.tasks
      set title=btrim(p_title),description=p_description,deadline_at=p_deadline_at,weight=p_weight,
          version=version+1,updated_at=now()
      where id=v_task.id
      returning * into v_task;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,'task_edited','task',v_task.id,p_request_id,
        jsonb_build_object(
          'changedFields',v_changed_fields,'taskVersion',v_task.version,
          'deadlineAt',v_task.deadline_at,'weight',v_task.weight
        )
      );
      v_result:=jsonb_build_object(
        'ok',true,
        'data',jsonb_build_object(
          'taskId',v_task.id,'taskVersion',v_task.version,'changed',true,
          'title',v_task.title,'description',v_task.description,'deadlineAt',v_task.deadline_at,'weight',v_task.weight
        ),
        'requestId',p_request_id,'replayed',false,'aggregateType','task',
        'aggregateId',v_task.id,'aggregateVersion',v_task.version
      );
      return private.complete_command(v_claim.command_id,v_result,'task',v_task.id,v_task.version);
    end if;
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_edit_task(uuid,uuid,uuid,integer,text,text,timestamptz,smallint)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_edit_task(uuid,uuid,uuid,integer,text,text,timestamptz,smallint)
  to authenticated;
