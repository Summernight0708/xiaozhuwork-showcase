-- Optional review is fixed at task creation. Dependency edges remain a DAG and
-- remain visible, but they no longer veto submissions or review approvals.
-- Existing tasks retain requires_review=true and the original manual review flow.
alter table public.tasks
  add column requires_review boolean not null default true;

-- Keep the immutable submission snapshot without inventing a human reviewer.
alter table public.task_review_rounds
  drop constraint task_review_rounds_state,
  drop constraint task_review_rounds_decision,
  add constraint task_review_rounds_state
    check (state in ('pending','approved','rejected','completed_without_review')),
  add constraint task_review_rounds_decision check (
    (state='pending' and decision is null and reviewed_at is null and rejection_reason is null)
    or (state='approved' and decision is not null and decision='approve'
      and reviewed_at is not null and rejection_reason is null)
    or (state='rejected' and decision is not null and decision in ('reject','request_changes')
      and reviewed_at is not null and rejection_reason is not null
      and char_length(btrim(rejection_reason)) between 1 and 2000)
    or (state='completed_without_review' and decision is null
      and reviewed_by is null and reviewed_at is null and rejection_reason is null)
  );

-- Changing the argument list replaces the old RPC rather than leaving an
-- ambiguous default-argument overload in PostgREST.
drop function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text);

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
  p_required_submission_file_type text default null,
  p_requires_review boolean default true
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
  ) || case when p_requires_review then '{}'::jsonb
    else jsonb_build_object('requiresReview',false) end);

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
  elsif p_requires_review is null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','requiresReview');
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
      is_direct_assignment,assignment_state,required_submission_file_type,requires_review
    ) values(
      p_project_id,btrim(p_title),p_description,v_actor,p_deadline_at,'not_started',
      p_weight,p_assignment_mode='direct',
      case
        when p_assignment_mode='direct' then 'pending_acceptance'
        else 'claimable'
      end,
      p_required_submission_file_type,p_requires_review
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
        'requiredSubmissionFileType',p_required_submission_file_type,
        'requiresReview',p_requires_review
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

revoke all on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text,boolean)
  to authenticated;

create or replace function private.assign_review_delegate_on_round_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.state='pending' then
    perform private.refresh_independent_review_delegate(new.id,'submission');
  end if;
  return null;
end;
$$;

create or replace function public.cmd_submit_task_for_review(
  p_project_id uuid,
  p_task_id uuid,
  p_submission_text text,
  p_file_version_ids uuid[],
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
  v_round_id uuid;
  v_round_number integer;
  v_submitted_at timestamptz;
  v_submission_text text;
  v_valid_file_count integer;
  v_first_file_version_id uuid;
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
  if p_file_version_ids is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED','fileVersionIds'
    );
  end if;
  if array_position(p_file_version_ids,null) is not null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED','fileVersionIds'
    );
  end if;

  v_submission_text:=nullif(btrim(coalesce(p_submission_text,'')),'');
  if v_submission_text is not null and char_length(v_submission_text)>4000 then
    return private.failure(
      p_request_id,'VALIDATION_FAILED','submissionText'
    );
  end if;
  if v_submission_text is null and cardinality(p_file_version_ids)=0 then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',null,null,
      jsonb_build_object('reason','empty_submission')
    );
  end if;
  if cardinality(p_file_version_ids) <> (
    select count(distinct x.id)::integer
    from unnest(p_file_version_ids) as x(id)
  ) then
    return private.failure(
      p_request_id,'VALIDATION_FAILED','fileVersionIds',null,
      jsonb_build_object('reason','duplicate_file_version')
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'taskId',p_task_id,
    'submissionText',v_submission_text,
    'fileVersionIds',p_file_version_ids,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_submit_task_for_review',p_request_id,v_hash,null,p_project_id
  );

  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1
        from public.tasks t
        where t.id=p_task_id
          and t.project_id=p_project_id
          and t.assignee_id=v_actor
          and t.assignment_state='assigned'
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

  if v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(
      p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version
    );
  elsif v_task.id is null
        or v_task.assignee_id is distinct from v_actor
        or v_task.assignment_state <> 'assigned' then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> v_task.version then
    v_result:=private.failure(
      p_request_id,'STALE_VERSION',null,v_task.version
    );
  elsif v_task.status not in ('in_progress','blocked') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version
    );
  elsif exists(
    select 1
    from public.task_review_rounds rr
    where rr.task_id=p_task_id and rr.state='pending'
  ) then
    v_result:=private.failure(
      p_request_id,'REVIEW_NOT_PENDING',null,v_task.version
    );
  else
    select count(*)::integer
    into v_valid_file_count
    from public.task_file_versions fv
    join public.file_upload_reservations r
      on r.id=fv.reservation_id
     and r.project_id=fv.project_id
     and r.task_id=fv.task_id
    where fv.project_id=p_project_id
      and fv.task_id=p_task_id
      and fv.id=any(p_file_version_ids)
      and r.state='finalized';

    if v_valid_file_count <> cardinality(p_file_version_ids) then
      v_result:=private.failure(
        p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','fileVersionIds',
        v_task.version
      );
    elsif v_task.required_submission_file_type is not null
          and not exists(
            select 1
            from public.task_file_versions fv
            join public.file_upload_reservations r
              on r.id=fv.reservation_id
             and r.project_id=fv.project_id
             and r.task_id=fv.task_id
            where fv.project_id=p_project_id
              and fv.task_id=p_task_id
              and fv.id=any(p_file_version_ids)
              and r.state='finalized'
              and private.task_submission_file_type_from_mime(fv.mime_type)
                  =v_task.required_submission_file_type
          ) then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED','fileVersionIds',v_task.version,
        jsonb_build_object(
          'reason','required_file_type_missing',
          'requiredFileType',v_task.required_submission_file_type
        )
      );
    else
      select coalesce(max(rr.round_number),0)+1
      into v_round_number
      from public.task_review_rounds rr
      where rr.task_id=p_task_id;

      v_round_id:=gen_random_uuid();
      v_submitted_at:=now();
      if cardinality(p_file_version_ids)>0 then
        v_first_file_version_id:=p_file_version_ids[1];
      end if;

      insert into public.task_review_rounds(
        id,project_id,task_id,round_number,
        submitted_file_version_id,submission_text_snapshot,
        required_submission_file_type_snapshot,
        submitted_by,submitted_at,state
      ) values(
        v_round_id,p_project_id,p_task_id,v_round_number,
        v_first_file_version_id,v_submission_text,
        v_task.required_submission_file_type,
        v_actor,v_submitted_at,
        case when v_task.requires_review then 'pending'
             else 'completed_without_review' end
      );

      insert into public.task_review_round_files(
        review_round_id,project_id,task_id,file_version_id,position
      )
      select
        v_round_id,p_project_id,p_task_id,x.file_version_id,x.position::integer
      from unnest(p_file_version_ids) with ordinality
        as x(file_version_id,position);

      update public.tasks
      set status=case when v_task.requires_review then 'awaiting_review'
                      else 'completed' end,
          completed_at=case when v_task.requires_review then null else v_submitted_at end,
          blocked_reason=null,
          first_submitted_at=coalesce(first_submitted_at,v_submitted_at),
          version=version+1,
          updated_at=now()
      where id=p_task_id
      returning * into v_task;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        case when v_task.requires_review then 'task_submitted_for_review'
             else 'task_submitted_without_review' end,
        'task_review_round',v_round_id,p_request_id,
        jsonb_strip_nulls(jsonb_build_object(
          'taskId',p_task_id,
          'roundNumber',v_round_number,
          'fileVersionId',v_first_file_version_id,
          'fileVersionIds',p_file_version_ids,
          'hasSubmissionText',v_submission_text is not null,
          'requiredSubmissionFileType',
            v_task.required_submission_file_type,
          'taskVersion',v_task.version,
          'requiresReview',v_task.requires_review,
          'taskStatus',v_task.status
        ))
      );

      v_result:=jsonb_build_object(
        'ok',true,
        'data',jsonb_build_object(
          'taskId',p_task_id,
          'reviewRoundId',v_round_id,
          'roundNumber',v_round_number,
          'submittedAt',v_submitted_at,
          'taskStatus',v_task.status,
          'autoCompleted',not v_task.requires_review
        ),
        'requestId',p_request_id,
        'replayed',false,
        'aggregateType','task',
        'aggregateId',p_task_id,
        'aggregateVersion',v_task.version
      );
      return private.complete_command(
        v_claim.command_id,v_result,'task',p_task_id,v_task.version
      );
    end if;
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

-- Service-side source-of-truth submission facts must be written for either
-- terminal status, without inventing an 'approved' event for no-review work.
create or replace function private.followup_record_first_submission(
 p_project_id uuid,p_task_id uuid,p_actor_id uuid,p_command_id uuid,
 p_request_id uuid,p_submitted_at timestamptz,p_aggregate_version integer
) returns void language plpgsql security definer set search_path='' as $$
declare
 t public.tasks%rowtype;
 e public.task_responsibility_epochs%rowtype;
 v_late boolean;
 v_inserted boolean;
begin
 select * into t from public.tasks where project_id=p_project_id and id=p_task_id;
 if t.id is null or t.first_submitted_at is distinct from p_submitted_at
 or t.version<>p_aggregate_version or not (
      (t.requires_review and t.status='awaiting_review')
      or (not t.requires_review and t.status='completed')
    ) then
  raise exception 'C first submission snapshot mismatch';
 end if;
 select * into e from public.task_responsibility_epochs where project_id=p_project_id
 and task_id=p_task_id and responsible_user_id=t.assignee_id and closed_at is null;
 v_late:=coalesce(e.id is not null and not e.blocked_exempt and e.effective_start_at is not null
 and e.effective_deadline_at>e.effective_start_at and p_submitted_at>e.effective_deadline_at,false);
 insert into public.task_first_submission_facts(task_id,project_id,responsibility_epoch_id,
 first_submitted_at,deadline_snapshot,effective_start_snapshot,responsible_user_id,blocked_exempt,eligible_late)
 values(p_task_id,p_project_id,e.id,p_submitted_at,coalesce(e.effective_deadline_at,t.deadline_at),
 e.effective_start_at,t.assignee_id,coalesce(e.blocked_exempt,true),v_late)
 on conflict(task_id) do nothing returning true into v_inserted;
 if coalesce(v_inserted,false) and v_late then
  perform private.emit_event(p_command_id,2,p_project_id,p_actor_id,'task_first_submitted_late','task',
   p_task_id,p_request_id,jsonb_build_object(
   'schemaVersion',1,'policyVersion',1,'occurrenceKey','task:'||p_task_id||':first_late',
   'occurredAt',p_submitted_at,'aggregateVersion',p_aggregate_version,
   'taskId',p_task_id,'responsibleUserId',e.responsible_user_id,
   'responsibilityEpochId',e.id,'acceptedAt',e.accepted_at,'effectiveStartAt',e.effective_start_at,
   'effectiveDeadlineAt',e.effective_deadline_at,'freeAbandonUntil',e.free_abandon_until,
   'firstSubmittedAt',p_submitted_at,'blockedExempt',e.blocked_exempt,
   'exemptionReason',e.exemption_reason,'weightSnapshot',e.weight_snapshot,
   'expectedShareBpsSnapshot',e.expected_share_bps_snapshot,
   'acceptedExpectedContribution',e.accepted_expected_contribution::text,
   'projectContributionMode',e.project_contribution_mode,
   'autoPenaltyEnabledSnapshot',e.auto_penalty_enabled_snapshot,'triggerSource','first_submission'));
 end if;
end;
$$;

create or replace function private.g_record_first_submission_from_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_task public.tasks%rowtype;
  v_round public.task_review_rounds%rowtype;
begin
  if new.event_type not in ('task_submitted_for_review','task_submitted_without_review')
     or new.entity_type<>'task_review_round'
     or new.command_request_id is null
     or new.event_seq is distinct from 1 then
    return new;
  end if;
  select * into v_round from public.task_review_rounds
   where id=new.entity_id and project_id=new.project_id;
  if v_round.id is null or v_round.round_number<>1 then
    return new;
  end if;
  select * into v_task from public.tasks
   where id=v_round.task_id and project_id=new.project_id;
  if v_task.id is null or v_task.first_submitted_at is null
     or v_task.first_submitted_at is distinct from v_round.submitted_at
     or not (
       (new.event_type='task_submitted_for_review'
         and v_task.requires_review and v_task.status='awaiting_review')
       or (new.event_type='task_submitted_without_review'
         and not v_task.requires_review and v_task.status='completed')
     )
     or (new.event_data->>'taskId') is distinct from v_task.id::text then
    raise exception using errcode='23514',message='G_FIRST_SUBMISSION_AUTHORITY_MISMATCH';
  end if;

  perform private.followup_record_first_submission(
    new.project_id,v_task.id,new.actor_id,new.command_request_id,
    new.request_id,v_task.first_submitted_at,v_task.version
  );
  return new;
end;
$$;

drop trigger g_record_first_submission_on_authoritative_event on public.business_events;
create trigger g_record_first_submission_on_authoritative_event
after insert on public.business_events
for each row when (new.event_type in ('task_submitted_for_review','task_submitted_without_review'))
execute function private.g_record_first_submission_from_event();

-- Manual reviews retain all creator/leader/delegate and anti-self-review
-- authorization checks; only the upstream completion veto is removed.
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
