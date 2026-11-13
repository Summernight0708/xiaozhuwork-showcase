-- Per-round independent review delegation for self-assigned creator/leader deadlocks.
-- Keep ordinary creator/leader review and all downstream rework rights unchanged.
alter table public.task_review_rounds
  add column delegation_required boolean not null default false,
  add column delegated_reviewer_id uuid;

create index task_review_rounds_pending_delegate_idx on public.task_review_rounds
  (project_id,delegated_reviewer_id)
  where state='pending' and delegated_reviewer_id is not null;

create table private.task_review_delegation_events(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  review_round_id uuid not null references public.task_review_rounds(id),
  old_reviewer_id uuid,
  new_reviewer_id uuid,
  old_required boolean not null,
  new_required boolean not null,
  reason text not null,
  occurred_at timestamptz not null default clock_timestamp(),
  foreign key (project_id,task_id) references public.tasks(project_id,id)
);
create index task_review_delegation_events_round_idx
  on private.task_review_delegation_events(review_round_id,occurred_at);
revoke all on private.task_review_delegation_events from public,anon,authenticated,service_role;

create or replace function private.reject_review_delegation_event_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
  raise exception using errcode='55000',message='Review delegation audit is immutable';
end;
$$;
create trigger review_delegation_events_immutable
  before update or delete on private.task_review_delegation_events
  for each row execute function private.reject_review_delegation_event_mutation();

create or replace function private.refresh_independent_review_delegate(
  p_review_round_id uuid,p_reason text default 'refresh'
) returns void language plpgsql security definer set search_path='' as $$
declare
  v_round public.task_review_rounds%rowtype;
  v_task public.tasks%rowtype;
  v_normal_exists boolean;
  v_candidate uuid;
  v_required boolean;
begin
  select * into v_round from public.task_review_rounds
  where id=p_review_round_id for update;
  if v_round.id is null or v_round.state<>'pending' then return; end if;
  select * into v_task from public.tasks
  where project_id=v_round.project_id and id=v_round.task_id;
  if v_task.id is null then return; end if;

  select exists(
    select 1 from public.project_members pm
    where pm.project_id=v_round.project_id
      and pm.user_id is not null
      and pm.member_state='active'
      and pm.role<>'observer' and pm.is_observer is false
      and (pm.user_id=v_task.created_by or pm.role='leader')
      and pm.user_id is distinct from v_task.assignee_id
      and pm.user_id is distinct from v_round.submitted_by
  ) into v_normal_exists;

  v_required:=not v_normal_exists;
  if v_required then
    select pm.user_id into v_candidate from public.project_members pm
    where pm.project_id=v_round.project_id
      and pm.user_id is not null
      and pm.member_state='active'
      and pm.role<>'observer' and pm.is_observer is false
      and pm.user_id is distinct from v_task.assignee_id
      and pm.user_id is distinct from v_round.submitted_by
      and not exists(
        select 1 from public.task_collaborators c
        where c.project_id=v_round.project_id
          and c.task_id=v_round.task_id
          and c.user_id=pm.user_id
          and c.state in ('pending','accepted')
      )
    -- Keep a still-eligible delegate; otherwise randomize fairly.
    order by (pm.user_id is distinct from v_round.delegated_reviewer_id),random()
    limit 1;
  end if;

  if v_round.delegation_required is distinct from v_required
     or v_round.delegated_reviewer_id is distinct from v_candidate then
    update public.task_review_rounds
    set delegation_required=v_required,delegated_reviewer_id=v_candidate
    where id=v_round.id;
    insert into private.task_review_delegation_events(
      project_id,task_id,review_round_id,old_reviewer_id,new_reviewer_id,
      old_required,new_required,reason
    ) values (
      v_round.project_id,v_round.task_id,v_round.id,
      v_round.delegated_reviewer_id,v_candidate,
      v_round.delegation_required,v_required,p_reason
    );
  end if;
end;
$$;

create or replace function private.assign_review_delegate_on_round_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform private.refresh_independent_review_delegate(new.id,'submission');
  return null;
end;
$$;
create trigger task_review_round_delegation_assign
  after insert on public.task_review_rounds
  for each row execute function private.assign_review_delegate_on_round_insert();

create or replace function private.refresh_review_delegates_on_member_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_project_id uuid; v_round_id uuid;
begin
  if tg_op='DELETE' then v_project_id:=old.project_id;
  else v_project_id:=new.project_id; end if;
  for v_round_id in
    select rr.id from public.task_review_rounds rr
    where rr.project_id=v_project_id and rr.state='pending'
    order by rr.id
  loop
    perform private.refresh_independent_review_delegate(v_round_id,'membership_change');
  end loop;
  return null;
end;
$$;
create trigger task_review_delegate_member_change
  after insert or update of user_id,member_state,role,is_observer or delete
  on public.project_members for each row
  execute function private.refresh_review_delegates_on_member_change();

create or replace function private.refresh_review_delegate_on_collaborator_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_project_id uuid; v_task_id uuid; v_round_id uuid;
begin
  if tg_op='DELETE' then
    v_project_id:=old.project_id;v_task_id:=old.task_id;
  else
    v_project_id:=new.project_id;v_task_id:=new.task_id;
  end if;
  for v_round_id in
    select rr.id from public.task_review_rounds rr
    where rr.project_id=v_project_id and rr.task_id=v_task_id
      and rr.state='pending'
  loop
    perform private.refresh_independent_review_delegate(v_round_id,'collaborator_change');
  end loop;
  return null;
end;
$$;
create trigger task_review_delegate_collaborator_change
  after insert or update of state,user_id or delete
  on public.task_collaborators for each row
  execute function private.refresh_review_delegate_on_collaborator_change();

-- Include older stuck rounds. No automatic approval and no status transitions.
do $$
declare v_round_id uuid;
begin
  for v_round_id in
    select rr.id from public.task_review_rounds rr
    where rr.state='pending' order by rr.id
  loop
    perform private.refresh_independent_review_delegate(v_round_id,'migration_backfill');
  end loop;
end;
$$;

-- Keep all existing command fences and event side-effects, expand only authorization.
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

revoke all on function private.refresh_independent_review_delegate(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function private.assign_review_delegate_on_round_insert()
  from public,anon,authenticated,service_role;
revoke all on function private.refresh_review_delegates_on_member_change()
  from public,anon,authenticated,service_role;
revoke all on function private.refresh_review_delegate_on_collaborator_change()
  from public,anon,authenticated,service_role;
revoke all on function private.reject_review_delegation_event_mutation()
  from public,anon,authenticated,service_role;

revoke all on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer)
  to authenticated;
comment on column public.task_review_rounds.delegation_required is
  'True when no independent normal reviewer exists for this pending round.';
comment on column public.task_review_rounds.delegated_reviewer_id is
  'One independent reviewer authorized for only this review round.';
