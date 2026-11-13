-- D6 task change confirmation: server-authoritative deadline/weight proposal workflow.

create table public.task_change_proposals (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  proposed_by uuid not null,
  proposer_name_snapshot text,
  state text not null default 'pending',
  old_deadline_at timestamptz not null,
  new_deadline_at timestamptz not null,
  old_weight smallint,
  new_weight smallint,
  base_task_version integer not null,
  required_confirmer_id uuid not null,
  required_confirmer_name_snapshot text,
  decided_at timestamptz,
  decided_by uuid,
  decision_reason text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id) references public.tasks(project_id, id) on delete cascade,
  constraint task_change_proposals_state check (state in ('pending','approved','rejected')),
  constraint task_change_proposals_base_version_positive check (base_task_version > 0),
  constraint task_change_proposals_version_positive check (version > 0),
  constraint task_change_proposals_weight_range check (
    (old_weight is null or old_weight between 1 and 5)
    and (new_weight is null or new_weight between 1 and 5)
  ),
  constraint task_change_proposals_has_change check (
    new_deadline_at is distinct from old_deadline_at
    or new_weight is distinct from old_weight
  ),
  constraint task_change_proposals_decision_state check (
    (state='pending' and decided_at is null and decided_by is null and decision_reason is null)
    or
    (state='approved' and decided_at is not null and decided_by is not null and decision_reason is null)
    or
    (state='rejected' and decided_at is not null and decided_by is not null)
  ),
  constraint task_change_proposals_reason_length check (
    decision_reason is null or char_length(decision_reason) between 1 and 1000
  )
);

create unique index task_change_proposals_one_pending_idx
  on public.task_change_proposals(task_id)
  where state='pending';
create index task_change_proposals_project_created_idx
  on public.task_change_proposals(project_id, created_at desc);
create index task_change_proposals_required_pending_idx
  on public.task_change_proposals(required_confirmer_id, created_at desc)
  where state='pending';

alter table public.task_change_proposals enable row level security;

create policy task_change_proposals_select_active_member
on public.task_change_proposals for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_change_proposals from public,anon,authenticated,service_role;
grant select on public.task_change_proposals to authenticated;

create function public.cmd_propose_task_change(
  p_project_id uuid,
  p_task_id uuid,
  p_deadline_at timestamptz,
  p_weight smallint,
  p_request_id uuid,
  p_expected_task_version integer
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
  v_actor_member public.project_members%rowtype;
  v_confirmer_member public.project_members%rowtype;
  v_proposal public.task_change_proposals%rowtype;
  v_has_activity boolean;
  v_deadline_changed boolean;
  v_weight_changed boolean;
begin
  if v_actor is null then
    return private.failure(p_request_id,'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null,'VALIDATION_FAILED','requestId');
  end if;
  if p_project_id is null or p_task_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'taskId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'taskId',p_task_id,
    'deadlineAt',p_deadline_at,
    'weight',p_weight,
    'expectedTaskVersion',p_expected_task_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_propose_task_change',p_request_id,v_hash,null,p_project_id
  );

  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1
        from public.tasks t
        where t.id=p_task_id and t.project_id=p_project_id
          and (t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor))
      ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p
  where p.id=p_project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id=p_task_id and t.project_id=p_project_id
  for update;

  select * into v_actor_member
  from public.project_members pm
  where pm.project_id=p_project_id
    and pm.user_id=v_actor
    and pm.member_state='active';

  if v_task.id is not null and v_task.assignee_id is not null then
    select * into v_confirmer_member
    from public.project_members pm
    where pm.project_id=p_project_id
      and pm.user_id=v_task.assignee_id
      and pm.member_state='active';
  end if;

  if v_task.id is null
     or v_actor_member.id is null
     or v_actor_member.role='observer'
     or (v_task.created_by is distinct from v_actor and v_actor_member.role<>'leader') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_task_version is null or p_expected_task_version<>v_task.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_task.status in ('awaiting_review','completed','canceled') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_definition_locked','status',v_task.status)
    );
  elsif v_task.assignment_state<>'assigned'
        or v_task.assignee_id is null
        or v_confirmer_member.id is null
        or v_confirmer_member.role='observer' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_responsibility_unavailable')
    );
  else
    v_deadline_changed:=p_deadline_at is distinct from v_task.deadline_at;
    v_weight_changed:=p_weight is distinct from v_task.weight;

    if not v_deadline_changed and not v_weight_changed then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED',null,v_task.version,
        jsonb_build_object('reason','no_change')
      );
    elsif p_deadline_at is null then
      v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt',v_task.version);
    elsif v_deadline_changed and (p_deadline_at<=now() or p_deadline_at>v_project.deadline_at) then
      v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt',v_task.version);
    elsif v_project.contribution_mode='weighted'
          and (p_weight is null or p_weight not between 1 and 5) then
      v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight',v_task.version);
    elsif v_project.contribution_mode='facts_only' and p_weight is not null then
      v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight',v_task.version);
    else
      v_has_activity:=v_task.accepted_at is not null
        or v_task.first_submitted_at is not null
        or v_task.status<>'not_started'
        or nullif(btrim(coalesce(v_task.progress_text,'')),'') is not null
        or exists(select 1 from public.task_file_versions fv where fv.task_id=v_task.id)
        or exists(select 1 from public.task_review_rounds rr where rr.task_id=v_task.id);

      if not (
        (v_deadline_changed and v_task.accepted_at is not null)
        or (v_weight_changed and v_has_activity)
      ) then
        v_result:=private.failure(
          p_request_id,'INVALID_TRANSITION',null,v_task.version,
          jsonb_build_object('reason','confirmation_not_required')
        );
      elsif exists(
        select 1 from public.task_change_proposals p
        where p.task_id=v_task.id and p.state='pending'
      ) then
        v_result:=private.failure(
          p_request_id,'INVALID_TRANSITION',null,v_task.version,
          jsonb_build_object('reason','task_change_already_pending')
        );
      else
        insert into public.task_change_proposals(
          project_id,task_id,proposed_by,proposer_name_snapshot,state,
          old_deadline_at,new_deadline_at,old_weight,new_weight,
          base_task_version,required_confirmer_id,required_confirmer_name_snapshot
        ) values(
          p_project_id,v_task.id,v_actor,
          coalesce(v_actor_member.display_name_snapshot,(select pr.display_name from public.profiles pr where pr.id=v_actor)),
          'pending',
          v_task.deadline_at,p_deadline_at,v_task.weight,p_weight,
          v_task.version,v_task.assignee_id,
          coalesce(v_confirmer_member.display_name_snapshot,(select pr.display_name from public.profiles pr where pr.id=v_task.assignee_id))
        )
        returning * into v_proposal;

        perform private.emit_event(
          v_claim.command_id,1,p_project_id,v_actor,
          'task_change_proposed','task_change_proposal',v_proposal.id,p_request_id,
          jsonb_strip_nulls(jsonb_build_object(
            'taskId',v_task.id,
            'proposerId',v_actor,
            'requiredConfirmerId',v_proposal.required_confirmer_id,
            'baseTaskVersion',v_proposal.base_task_version,
            'oldDeadlineAt',v_proposal.old_deadline_at,
            'newDeadlineAt',v_proposal.new_deadline_at,
            'oldWeight',v_proposal.old_weight,
            'newWeight',v_proposal.new_weight
          ))
        );

        v_result:=jsonb_build_object(
          'ok',true,
          'data',jsonb_build_object(
            'proposalId',v_proposal.id,
            'taskId',v_task.id,
            'state',v_proposal.state,
            'proposalVersion',v_proposal.version,
            'createdAt',v_proposal.created_at
          ),
          'requestId',p_request_id,
          'replayed',false,
          'aggregateType','task_change_proposal',
          'aggregateId',v_proposal.id,
          'aggregateVersion',v_proposal.version
        );
        return private.complete_command(
          v_claim.command_id,v_result,'task_change_proposal',v_proposal.id,v_proposal.version
        );
      end if;
    end if;
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_respond_to_task_change(
  p_project_id uuid,
  p_task_id uuid,
  p_proposal_id uuid,
  p_action text,
  p_rejection_reason text,
  p_request_id uuid,
  p_expected_proposal_version integer
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
  v_proposal public.task_change_proposals%rowtype;
  v_confirmer_member public.project_members%rowtype;
  v_decided_at timestamptz;
begin
  if v_actor is null then
    return private.failure(p_request_id,'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null,'VALIDATION_FAILED','requestId');
  end if;
  if p_project_id is null or p_task_id is null or p_proposal_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case
        when p_project_id is null then 'projectId'
        when p_task_id is null then 'taskId'
        else 'proposalId'
      end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'taskId',p_task_id,
    'proposalId',p_proposal_id,
    'action',p_action,
    'rejectionReason',p_rejection_reason,
    'expectedProposalVersion',p_expected_proposal_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_respond_to_task_change',p_request_id,v_hash,null,p_project_id
  );

  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1
        from public.task_change_proposals p
        where p.id=p_proposal_id
          and p.project_id=p_project_id
          and p.task_id=p_task_id
          and p.required_confirmer_id=v_actor
      ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p
  where p.id=p_project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id=p_task_id and t.project_id=p_project_id
  for update;

  select * into v_proposal
  from public.task_change_proposals p
  where p.id=p_proposal_id
    and p.project_id=p_project_id
    and p.task_id=p_task_id
  for update;

  select * into v_confirmer_member
  from public.project_members pm
  where pm.project_id=p_project_id
    and pm.user_id=v_actor
    and pm.member_state='active';

  if v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.id is null or v_proposal.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_proposal_version is null
        or p_expected_proposal_version<>v_proposal.version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_proposal.version
    );
  elsif v_proposal.state<>'pending' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_proposal.version,
      jsonb_build_object('reason','task_change_not_pending')
    );
  elsif p_action is null or p_action not in ('approve','reject') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','action',v_proposal.version);
  elsif p_action='approve' and p_rejection_reason is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','rejectionReason',v_proposal.version);
  elsif p_action='reject'
        and p_rejection_reason is not null
        and char_length(btrim(p_rejection_reason)) not between 1 and 1000 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','rejectionReason',v_proposal.version);
  elsif v_task.status in ('awaiting_review','completed','canceled') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_proposal.version,
      jsonb_build_object('reason','task_definition_locked','status',v_task.status)
    );
  elsif v_confirmer_member.id is null
        or v_confirmer_member.role='observer'
        or v_proposal.required_confirmer_id is distinct from v_actor
        or v_task.assignment_state<>'assigned'
        or v_task.assignee_id is distinct from v_proposal.required_confirmer_id then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_proposal.version,
      jsonb_build_object('reason','task_responsibility_changed')
    );
  elsif v_task.deadline_at is distinct from v_proposal.old_deadline_at
        or v_task.weight is distinct from v_proposal.old_weight then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_proposal.version,
      jsonb_build_object('reason','task_definition_changed')
    );
  elsif p_action='approve'
        and v_proposal.new_deadline_at is distinct from v_proposal.old_deadline_at
        and (
          v_proposal.new_deadline_at<=now()
          or v_proposal.new_deadline_at>v_project.deadline_at
        ) then
    v_result:=private.failure(
      p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt',v_proposal.version
    );
  elsif p_action='approve'
        and v_project.contribution_mode='weighted'
        and (v_proposal.new_weight is null or v_proposal.new_weight not between 1 and 5) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','weight',v_proposal.version
    );
  elsif p_action='approve'
        and v_project.contribution_mode='facts_only'
        and v_proposal.new_weight is not null then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','weight',v_proposal.version
    );
  else
    v_decided_at:=now();

    if p_action='approve' then
      update public.tasks
      set deadline_at=v_proposal.new_deadline_at,
          weight=v_proposal.new_weight,
          accepted_at=v_decided_at,
          version=version+1,
          updated_at=v_decided_at
      where id=v_task.id
      returning * into v_task;
    end if;

    update public.task_change_proposals
    set state=case when p_action='approve' then 'approved' else 'rejected' end,
        decided_at=v_decided_at,
        decided_by=v_actor,
        decision_reason=case
          when p_action='reject' then nullif(btrim(p_rejection_reason),'')
          else null
        end,
        version=version+1,
        updated_at=v_decided_at
    where id=v_proposal.id
    returning * into v_proposal;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case when p_action='approve' then 'task_change_approved' else 'task_change_rejected' end,
      'task_change_proposal',v_proposal.id,p_request_id,
      jsonb_strip_nulls(jsonb_build_object(
        'taskId',v_task.id,
        'proposerId',v_proposal.proposed_by,
        'requiredConfirmerId',v_proposal.required_confirmer_id,
        'baseTaskVersion',v_proposal.base_task_version,
        'taskVersion',v_task.version,
        'proposalVersion',v_proposal.version,
        'oldDeadlineAt',v_proposal.old_deadline_at,
        'newDeadlineAt',v_proposal.new_deadline_at,
        'oldWeight',v_proposal.old_weight,
        'newWeight',v_proposal.new_weight,
        'reason',v_proposal.decision_reason
      ))
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_strip_nulls(jsonb_build_object(
        'proposalId',v_proposal.id,
        'taskId',v_task.id,
        'state',v_proposal.state,
        'proposalVersion',v_proposal.version,
        'taskVersion',v_task.version,
        'decidedAt',v_proposal.decided_at,
        'decisionReason',v_proposal.decision_reason
      )),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','task_change_proposal',
      'aggregateId',v_proposal.id,
      'aggregateVersion',v_proposal.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_change_proposal',v_proposal.id,v_proposal.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

-- Keep notifications event-driven. The notification target remains the task so the
-- existing recipient and project membership checks in resolve_notification_target
-- continue to fail closed without granting a new client navigation authority.
create function private.notify_from_task_change_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_task_id uuid;
begin
  if new.event_type not in (
    'task_change_proposed','task_change_approved','task_change_rejected'
  ) then
    return new;
  end if;

  begin
    v_task_id:=nullif(new.event_data->>'taskId','')::uuid;
  exception when invalid_text_representation then
    return new;
  end;

  if v_task_id is null or not exists(
    select 1 from public.tasks t
    where t.id=v_task_id and t.project_id=new.project_id
  ) then
    return new;
  end if;

  if new.event_type='task_change_proposed' then
    begin
      v_recipient:=nullif(new.event_data->>'requiredConfirmerId','')::uuid;
    exception when invalid_text_representation then
      return new;
    end;
    if v_recipient is null or not private.is_active_member(new.project_id,v_recipient) then
      return new;
    end if;
    perform private.create_notification(
      new.id,new.project_id,v_recipient,
      'task_change_confirmation','任务重要变更待确认',
      '任务的截止时间或权重有待你确认的变更。',
      'task',v_task_id
    );
  elsif new.event_type='task_change_approved' then
    begin
      v_recipient:=nullif(new.event_data->>'proposerId','')::uuid;
    exception when invalid_text_representation then
      return new;
    end;
    if v_recipient is null or not private.is_active_member(new.project_id,v_recipient) then
      return new;
    end if;
    perform private.create_notification(
      new.id,new.project_id,v_recipient,
      'task_change_approved','任务变更已通过',
      '你提出的任务重要变更已由负责人确认。',
      'task',v_task_id
    );
  else
    begin
      v_recipient:=nullif(new.event_data->>'proposerId','')::uuid;
    exception when invalid_text_representation then
      return new;
    end;
    if v_recipient is null or not private.is_active_member(new.project_id,v_recipient) then
      return new;
    end if;
    perform private.create_notification(
      new.id,new.project_id,v_recipient,
      'task_change_rejected','任务变更未通过',
      '你提出的任务重要变更已被负责人拒绝。',
      'task',v_task_id
    );
  end if;

  return new;
end;
$$;

create trigger business_event_creates_task_change_notification
after insert on public.business_events
for each row execute function private.notify_from_task_change_event();

revoke all on function public.cmd_propose_task_change(
  uuid,uuid,timestamptz,smallint,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_propose_task_change(
  uuid,uuid,timestamptz,smallint,uuid,integer
) to authenticated;

revoke all on function public.cmd_respond_to_task_change(
  uuid,uuid,uuid,text,text,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_respond_to_task_change(
  uuid,uuid,uuid,text,text,uuid,integer
) to authenticated;

revoke all on function private.notify_from_task_change_event()
  from public,anon,authenticated,service_role;

comment on table public.task_change_proposals is
  'Server-authoritative pending/decided deadline and weight change proposals. Browser roles may read through RLS but may mutate only through command RPCs.';
comment on column public.task_change_proposals.base_task_version is
  'Task version observed when proposal was created; approval additionally verifies responsibility and old definition snapshots so compatible task progress does not silently invalidate the proposal.';
