-- Enforce dependency-derived blocking at the review boundary without copying blocked state.

create or replace function public.cmd_submit_task_for_review(
  p_project_id uuid,
  p_task_id uuid,
  p_file_version_id uuid,
  p_request_id uuid,
  p_expected_version integer
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
  v_round_id uuid;
  v_round_number integer;
  v_submitted_at timestamptz;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_task_id is null or p_file_version_id is null then
    return private.failure(p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' when p_task_id is null then 'taskId' else 'fileVersionId' end);
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'fileVersionId',p_file_version_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(v_actor,'cmd_submit_task_for_review',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
    and exists(select 1 from public.tasks t where t.id=p_task_id and t.project_id=p_project_id and t.assignee_id=v_actor and t.assignment_state='assigned'),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_task from public.tasks t where t.id=p_task_id and t.project_id=p_project_id for update;

  if v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.id is null or v_task.assignee_id is distinct from v_actor or v_task.assignment_state <> 'assigned' then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> v_task.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_task.status not in ('in_progress','blocked') then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_task.version);
  elsif exists(select 1 from public.task_review_rounds rr where rr.task_id=p_task_id and rr.state='pending') then
    v_result:=private.failure(p_request_id,'REVIEW_NOT_PENDING',null,v_task.version);
  elsif exists(
    select 1
    from public.task_dependencies d
    join public.tasks upstream
      on upstream.project_id=d.project_id and upstream.id=d.upstream_task_id
    where d.project_id=p_project_id
      and d.downstream_task_id=p_task_id
      and upstream.status <> 'completed'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','upstream_tasks_incomplete')
    );
  elsif not exists(
    select 1 from public.task_file_versions fv
    join public.file_upload_reservations r on r.id=fv.reservation_id
    where fv.id=p_file_version_id and fv.project_id=p_project_id and fv.task_id=p_task_id and r.state='finalized'
  ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','fileVersionId');
  else
    select coalesce(max(rr.round_number),0)+1 into v_round_number
    from public.task_review_rounds rr where rr.task_id=p_task_id;
    v_round_id:=gen_random_uuid();
    v_submitted_at:=now();
    insert into public.task_review_rounds(
      id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,submitted_at
    ) values(v_round_id,p_project_id,p_task_id,v_round_number,p_file_version_id,v_actor,v_submitted_at);
    update public.tasks
    set status='awaiting_review',
        blocked_reason=null,
        first_submitted_at=coalesce(first_submitted_at,v_submitted_at),
        version=version+1,
        updated_at=now()
    where id=p_task_id
    returning * into v_task;
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'task_submitted_for_review','task_review_round',v_round_id,p_request_id,
      jsonb_build_object('taskId',p_task_id,'roundNumber',v_round_number,'fileVersionId',p_file_version_id,'taskVersion',v_task.version)
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object('taskId',p_task_id,'reviewRoundId',v_round_id,'roundNumber',v_round_number,'submittedAt',v_submitted_at),
      'requestId',p_request_id,'replayed',false,'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version
    );
    return private.complete_command(v_claim.command_id,v_result,'task',p_task_id,v_task.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_review_task_submission(
  p_project_id uuid,
  p_task_id uuid,
  p_review_round_id uuid,
  p_action text,
  p_rejection_reason text,
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
  v_task public.tasks%rowtype;
  v_round public.task_review_rounds%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_task_id is null or p_review_round_id is null then
    return private.failure(p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' when p_task_id is null then 'taskId' else 'reviewRoundId' end);
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'reviewRoundId',p_review_round_id,'action',p_action,
    'rejectionReason',p_rejection_reason,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(v_actor,'cmd_review_task_submission',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
    and exists(
      select 1 from public.tasks t
      where t.id=p_task_id and t.project_id=p_project_id
        and t.assignee_id is distinct from v_actor
        and (t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor))
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_task from public.tasks t where t.id=p_task_id and t.project_id=p_project_id for update;
  select * into v_round from public.task_review_rounds rr
   where rr.id=p_review_round_id and rr.project_id=p_project_id and rr.task_id=p_task_id for update;

  if v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.id is null or v_round.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> v_round.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_round.version);
  elsif v_task.status <> 'awaiting_review' or v_round.state <> 'pending' then
    v_result:=private.failure(p_request_id,'REVIEW_NOT_PENDING',null,v_round.version);
  elsif p_action is null or p_action not in ('approve','reject','request_changes') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action');
  elsif p_action in ('reject','request_changes')
        and (p_rejection_reason is null or char_length(btrim(p_rejection_reason)) not between 1 and 2000) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','rejectionReason');
  elsif p_action='approve' and p_rejection_reason is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','rejectionReason');
  elsif p_action='approve' and exists(
    select 1
    from public.task_dependencies d
    join public.tasks upstream
      on upstream.project_id=d.project_id and upstream.id=d.upstream_task_id
    where d.project_id=p_project_id
      and d.downstream_task_id=p_task_id
      and upstream.status <> 'completed'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_round.version,
      jsonb_build_object('reason','upstream_tasks_incomplete')
    );
  else
    update public.task_review_rounds
    set state=case when p_action='approve' then 'approved' else 'rejected' end,
        decision=p_action,
        reviewed_by=v_actor,
        reviewed_at=now(),
        rejection_reason=case when p_action='approve' then null else btrim(p_rejection_reason) end,
        version=version+1,
        updated_at=now()
    where id=p_review_round_id
    returning * into v_round;

    if p_action='approve' then
      update public.tasks
      set status='completed',completed_at=now(),blocked_reason=null,version=version+1,updated_at=now()
      where id=p_task_id returning * into v_task;
    else
      update public.tasks
      set status='in_progress',completed_at=null,blocked_reason=null,version=version+1,updated_at=now()
      where id=p_task_id returning * into v_task;
    end if;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case p_action when 'approve' then 'task_submission_approved' when 'request_changes' then 'task_submission_changes_requested' else 'task_submission_rejected' end,
      'task_review_round',p_review_round_id,p_request_id,
      jsonb_strip_nulls(jsonb_build_object('taskId',p_task_id,'action',p_action,'reason',case when p_action='approve' then null else btrim(p_rejection_reason) end,'taskVersion',v_task.version))
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_strip_nulls(jsonb_build_object(
        'taskId',p_task_id,'reviewRoundId',p_review_round_id,'outcome',p_action,
        'taskStatus',v_task.status,'reviewedAt',v_round.reviewed_at,'rejectionReason',v_round.rejection_reason
      )),
      'requestId',p_request_id,'replayed',false,'aggregateType','task_review_round',
      'aggregateId',p_review_round_id,'aggregateVersion',v_round.version
    );
    return private.complete_command(v_claim.command_id,v_result,'task_review_round',p_review_round_id,v_round.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_submit_task_for_review(uuid,uuid,uuid,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_submit_task_for_review(uuid,uuid,uuid,uuid,integer)
to authenticated;

revoke all on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
to authenticated;
