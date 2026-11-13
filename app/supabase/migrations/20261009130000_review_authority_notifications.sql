-- Creator reviews normally, leader one-vote override is optional, self review forbidden, independent delegate random; downstream reject-only.
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
      join public.task_review_rounds rr
        on rr.project_id=t.project_id and rr.task_id=t.id
       and rr.id=p_review_round_id
      where t.id=p_task_id and t.project_id=p_project_id
        and t.assignee_id is distinct from v_actor
        and rr.submitted_by is distinct from v_actor
        and (
          t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor)
          or (
            rr.delegation_required
            and rr.delegated_reviewer_id=v_actor
            and private.is_active_non_observer_member(p_project_id,v_actor)
            and not exists (
              select 1 from public.task_collaborators c
              where c.project_id=p_project_id and c.task_id=p_task_id
                and c.user_id=v_actor and c.state in ('pending','accepted')
            )
          )
          or (
            p_action in ('reject','request_changes')
            and exists (
              select 1 from public.task_dependencies dep
              join public.tasks downstream on downstream.project_id=dep.project_id
                and downstream.id=dep.downstream_task_id
              where dep.project_id=p_project_id
                and dep.upstream_task_id=p_task_id
                and downstream.assignee_id=v_actor
                and private.is_active_non_observer_member(p_project_id,v_actor)
                and downstream.assignment_state='assigned'
                and downstream.status <> 'canceled'
            )
          )
        )
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
revoke all on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
  to authenticated;

create or replace function private.notify_review_recipients_from_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_task_id uuid;
  v_leader_id uuid;
  v_assignee_id uuid;
  v_submitted_by uuid;
  v_delegate_id uuid;
begin
  if new.event_type <> 'task_submitted_for_review' then return new; end if;
  v_task_id:=nullif(new.event_data->>'taskId','')::uuid;
  select p.leader_id,t.assignee_id,rr.submitted_by,rr.delegated_reviewer_id
    into v_leader_id,v_assignee_id,v_submitted_by,v_delegate_id
  from public.task_review_rounds rr
  join public.tasks t on t.project_id=rr.project_id and t.id=rr.task_id
  join public.projects p on p.id=rr.project_id
  where rr.id=new.entity_id and rr.project_id=new.project_id
    and rr.task_id=v_task_id and rr.state='pending';
  -- The leader can choose to act, but is never auto-voted.
  if v_leader_id is not null
     and v_leader_id is distinct from v_assignee_id
     and v_leader_id is distinct from v_submitted_by
     and v_leader_id is distinct from new.actor_id
     and private.is_active_leader(new.project_id,v_leader_id) then
    perform private.create_notification(
      new.id,new.project_id,v_leader_id,'task_review_submitted',
      '任务已提交验收','项目中有任务等待验收（组长可选择是否介入）。',
      'task_review_round',new.entity_id);
  end if;
  if v_delegate_id is not null
     and v_delegate_id is distinct from v_submitted_by
     and v_delegate_id is distinct from v_assignee_id
     and v_delegate_id is distinct from new.actor_id
     and private.is_active_non_observer_member(new.project_id,v_delegate_id) then
    perform private.create_notification(
      new.id,new.project_id,v_delegate_id,'task_review_submitted',
      '待你验收的任务','你被指派为本轮独立验收人，请查看任务提交。',
      'task_review_round',new.entity_id);
  end if;
  return new;
end;
$$;
revoke all on function private.notify_review_recipients_from_event()
  from public,anon,authenticated,service_role;
create trigger business_event_notifies_review_recipients
after insert on public.business_events
for each row execute function private.notify_review_recipients_from_event();