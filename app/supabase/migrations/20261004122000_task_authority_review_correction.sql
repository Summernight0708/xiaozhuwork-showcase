-- Workstream A: deterministic task authority, append-only review correction,
-- and explicit primary-assignee handoff/unassignment.

create or replace function private.is_active_non_observer_member(
  p_project_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.project_members pm
    where pm.project_id=p_project_id
      and pm.user_id=p_user_id
      and pm.member_state='active'
      and pm.role<>'observer'
      and pm.is_observer is false
  );
$$;

revoke all on function private.is_active_non_observer_member(uuid,uuid)
from public,anon,authenticated,service_role;

alter table public.task_review_rounds
  add column correction_of_review_round_id uuid,
  add constraint task_review_rounds_correction_source_fk
    foreign key (correction_of_review_round_id)
    references public.task_review_rounds(id);

create unique index task_review_rounds_one_correction_per_source_idx
  on public.task_review_rounds(correction_of_review_round_id)
  where correction_of_review_round_id is not null;

create or replace function private.protect_task_review_round()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_submitter_anonymized boolean;
  v_reviewer_anonymized boolean;
begin
  if tg_op='UPDATE' then
    v_submitter_anonymized :=
      old.submitted_by is not null and new.submitted_by is null;
    v_reviewer_anonymized :=
      old.reviewed_by is not null and new.reviewed_by is null;

    if (v_submitter_anonymized or v_reviewer_anonymized)
       and (new.submitted_by is not distinct from old.submitted_by or v_submitter_anonymized)
       and (new.reviewed_by is not distinct from old.reviewed_by or v_reviewer_anonymized)
       and (to_jsonb(new)-'submitted_by'-'reviewed_by')
           = (to_jsonb(old)-'submitted_by'-'reviewed_by') then
      return new;
    end if;
  end if;

  if tg_op='DELETE' then
    raise exception using errcode='55000', message='Task review rounds cannot be deleted';
  end if;
  if old.state<>'pending' then
    raise exception using errcode='55000', message='Terminal task review rounds are immutable';
  end if;
  if new.id is distinct from old.id
     or new.project_id is distinct from old.project_id
     or new.task_id is distinct from old.task_id
     or new.round_number is distinct from old.round_number
     or new.submitted_file_version_id is distinct from old.submitted_file_version_id
     or new.submission_text_snapshot is distinct from old.submission_text_snapshot
     or new.required_submission_file_type_snapshot is distinct from old.required_submission_file_type_snapshot
     or new.correction_of_review_round_id is distinct from old.correction_of_review_round_id
     or new.submitted_by is distinct from old.submitted_by
     or new.submitted_at is distinct from old.submitted_at
     or new.created_at is distinct from old.created_at then
    raise exception using errcode='55000', message='Task review round identity is immutable';
  end if;
  return new;
end;
$$;

create table public.task_primary_handoffs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  from_user_id uuid references auth.users(id) on delete set null,
  to_user_id uuid references auth.users(id) on delete set null,
  from_user_name_snapshot text not null,
  to_user_name_snapshot text not null,
  state text not null default 'pending',
  created_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  canceled_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id,task_id)
    references public.tasks(project_id,id) on delete cascade,
  constraint task_primary_handoffs_state
    check (state in ('pending','accepted','rejected','canceled')),
  constraint task_primary_handoffs_version_positive check (version>0),
  constraint task_primary_handoffs_distinct_users
    check (from_user_id is null or to_user_id is null or from_user_id<>to_user_id),
  constraint task_primary_handoffs_state_timestamps check (
    (state='pending' and responded_at is null and canceled_at is null)
    or (state in ('accepted','rejected') and responded_at is not null and canceled_at is null)
    or (state='canceled' and responded_at is null and canceled_at is not null)
  )
);

create unique index task_primary_handoffs_one_pending_idx
  on public.task_primary_handoffs(task_id)
  where state='pending';
create index task_primary_handoffs_project_created_idx
  on public.task_primary_handoffs(project_id,created_at desc);
create index task_primary_handoffs_target_pending_idx
  on public.task_primary_handoffs(to_user_id,created_at desc)
  where state='pending' and to_user_id is not null;

alter table public.task_primary_handoffs enable row level security;

create policy task_primary_handoffs_select_active_member
on public.task_primary_handoffs for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_primary_handoffs
from public,anon,authenticated,service_role;
grant select on public.task_primary_handoffs to authenticated;

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
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_project public.projects%rowtype;
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
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
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

  if not private.is_active_non_observer_member(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_deadline_at is null or p_deadline_at<=now() or p_deadline_at>v_project.deadline_at then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_assignment_mode is null or p_assignment_mode not in ('claimable','direct') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assignmentMode');
  elsif v_project.contribution_mode='weighted'
        and (p_weight is null or p_weight not between 1 and 5) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif p_assignment_mode='claimable' and p_assignee_id is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assigneeId');
  elsif p_assignment_mode='direct'
        and (p_assignee_id is null
             or not private.is_active_non_observer_member(p_project_id,p_assignee_id)) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','assigneeId');
  elsif p_required_submission_file_type is not null
        and p_required_submission_file_type not in (
          'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType'
    );
  elsif (
    select count(*)
    from public.tasks
    where project_id=p_project_id and status not in ('completed','canceled')
  )>=20 then
    v_result:=private.failure(
      p_request_id,'QUOTA_EXCEEDED',null,null,jsonb_build_object('limit',20)
    );
  else
    insert into public.tasks(
      project_id,title,description,created_by,deadline_at,status,weight,
      is_direct_assignment,assignment_state,required_submission_file_type
    ) values(
      p_project_id,btrim(p_title),p_description,v_actor,p_deadline_at,'not_started',
      p_weight,p_assignment_mode='direct',
      case when p_assignment_mode='direct' then 'pending_acceptance' else 'claimable' end,
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
        'assignmentOfferVersion',case when v_offer_id is null then null else 1 end
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','project',
      'aggregateId',p_project_id,
      'aggregateVersion',v_project.version
    ));
    return private.complete_command(
      v_claim.command_id,v_result,'project',p_project_id,v_project.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_request_task_primary_handoff(
  p_project_id uuid,
  p_task_id uuid,
  p_target_user_id uuid,
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
  v_handoff public.task_primary_handoffs%rowtype;
  v_from_name text;
  v_to_name text;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if p_task_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','taskId'); end if;
  if p_target_user_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','targetUserId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'targetUserId',p_target_user_id,
    'expectedTaskVersion',p_expected_task_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_request_task_primary_handoff',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor)
    and exists(
      select 1 from public.tasks t
      where t.project_id=p_project_id and t.id=p_task_id
        and t.assignee_id=v_actor and t.assignment_state='assigned'
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  perform set_config('lock_timeout','5s',true);
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task
  from public.tasks
  where project_id=p_project_id and id=p_task_id
  for update;

  perform 1
  from public.project_members pm
  where pm.project_id=p_project_id
    and pm.user_id in (v_actor,p_target_user_id)
  order by pm.user_id
  for update;

  select * into v_handoff
  from public.task_primary_handoffs h
  where h.project_id=p_project_id and h.task_id=p_task_id and h.state='pending'
  for update;

  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or v_task.assignee_id is distinct from v_actor
     or v_task.assignment_state<>'assigned' then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_task_version is null
        or v_task.version<>p_expected_task_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif p_target_user_id=v_actor then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','targetUserId');
  elsif not private.is_active_non_observer_member(p_project_id,p_target_user_id) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','targetUserId');
  elsif v_handoff.id is not null then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_handoff_already_pending')
    );
  elsif exists(
    select 1 from public.task_change_proposals p
    where p.task_id=p_task_id and p.state='pending'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_change_pending')
    );
  elsif v_task.status not in ('not_started','in_progress','blocked')
        or v_task.first_submitted_at is not null
        or exists(select 1 from public.task_review_rounds r where r.task_id=p_task_id) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_handoff_not_safe')
    );
  else
    select coalesce(p.display_name,pm.display_name_snapshot,'成员')
      into v_from_name
    from public.project_members pm
    left join public.profiles p on p.id=pm.user_id
    where pm.project_id=p_project_id and pm.user_id=v_actor;

    select coalesce(p.display_name,pm.display_name_snapshot,'成员')
      into v_to_name
    from public.project_members pm
    left join public.profiles p on p.id=pm.user_id
    where pm.project_id=p_project_id and pm.user_id=p_target_user_id;

    insert into public.task_primary_handoffs(
      project_id,task_id,from_user_id,to_user_id,
      from_user_name_snapshot,to_user_name_snapshot,created_by
    ) values(
      p_project_id,p_task_id,v_actor,p_target_user_id,
      v_from_name,v_to_name,v_actor
    )
    returning * into v_handoff;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_primary_handoff_requested','task_primary_handoff',v_handoff.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'fromUserId',v_actor,'toUserId',p_target_user_id,
        'handoffVersion',v_handoff.version,'taskVersion',v_task.version
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'handoffId',v_handoff.id,
        'fromUserId',v_actor,'toUserId',p_target_user_id,
        'state',v_handoff.state,'handoffVersion',v_handoff.version,
        'taskVersion',v_task.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_primary_handoff','aggregateId',v_handoff.id,
      'aggregateVersion',v_handoff.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_primary_handoff',v_handoff.id,v_handoff.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_respond_task_primary_handoff(
  p_project_id uuid,
  p_task_id uuid,
  p_handoff_id uuid,
  p_action text,
  p_request_id uuid,
  p_expected_handoff_version integer,
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
  v_handoff public.task_primary_handoffs%rowtype;
  v_collaborator public.task_collaborators%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if p_task_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','taskId'); end if;
  if p_handoff_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','handoffId'); end if;
  if p_action is null or p_action not in ('accept','reject') then
    return private.failure(p_request_id,'VALIDATION_FAILED','action');
  end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'handoffId',p_handoff_id,
    'action',p_action,'expectedHandoffVersion',p_expected_handoff_version,
    'expectedTaskVersion',p_expected_task_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_respond_task_primary_handoff',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor)
    and exists(
      select 1 from public.task_primary_handoffs h
      where h.project_id=p_project_id and h.task_id=p_task_id
        and h.id=p_handoff_id and h.to_user_id=v_actor
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  perform set_config('lock_timeout','5s',true);
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task
  from public.tasks
  where project_id=p_project_id and id=p_task_id
  for update;
  select * into v_handoff
  from public.task_primary_handoffs h
  where h.project_id=p_project_id and h.task_id=p_task_id and h.id=p_handoff_id
  for update;

  perform 1
  from public.project_members pm
  where pm.project_id=p_project_id
    and pm.user_id in (v_handoff.from_user_id,v_actor)
  order by pm.user_id
  for update;

  select * into v_collaborator
  from public.task_collaborators c
  where c.project_id=p_project_id and c.task_id=p_task_id
    and c.user_id=v_actor and c.state in ('pending','accepted')
  order by c.id
  limit 1
  for update;

  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or v_handoff.to_user_id is distinct from v_actor then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_handoff_version is null
        or v_handoff.version<>p_expected_handoff_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_handoff.version);
  elsif p_expected_task_version is null
        or v_task.version<>p_expected_task_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_handoff.state<>'pending' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_handoff.version,
      jsonb_build_object('reason','primary_handoff_not_pending')
    );
  elsif v_task.assignee_id is distinct from v_handoff.from_user_id
        or v_task.assignment_state<>'assigned'
        or not private.is_active_non_observer_member(p_project_id,v_handoff.from_user_id) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_handoff_not_safe')
    );
  elsif p_action='accept' and exists(
    select 1 from public.task_change_proposals p
    where p.task_id=p_task_id and p.state='pending'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_change_pending')
    );
  elsif p_action='accept'
        and (
          v_task.status not in ('not_started','in_progress','blocked')
          or v_task.first_submitted_at is not null
          or exists(select 1 from public.task_review_rounds r where r.task_id=p_task_id)
        ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_handoff_not_safe')
    );
  elsif p_action='reject' then
    update public.task_primary_handoffs
    set state='rejected',responded_at=now(),version=version+1,updated_at=now()
    where id=v_handoff.id
    returning * into v_handoff;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_primary_handoff_rejected','task_primary_handoff',v_handoff.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'fromUserId',v_handoff.from_user_id,'toUserId',v_actor,
        'handoffVersion',v_handoff.version,'taskVersion',v_task.version
      )
    );
  else
    if v_collaborator.id is not null then
      update public.task_collaborators
      set state='removed',removed_at=now(),version=version+1,updated_at=now()
      where id=v_collaborator.id
      returning * into v_collaborator;
    end if;

    update public.tasks
    set assignee_id=v_actor,assignment_state='assigned',
        accepted_at=now(),version=version+1,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.task_primary_handoffs
    set state='accepted',responded_at=now(),version=version+1,updated_at=now()
    where id=v_handoff.id
    returning * into v_handoff;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_primary_handoff_accepted','task_primary_handoff',v_handoff.id,p_request_id,
      jsonb_strip_nulls(jsonb_build_object(
        'taskId',p_task_id,'fromUserId',v_handoff.from_user_id,'toUserId',v_actor,
        'handoffVersion',v_handoff.version,'taskVersion',v_task.version,
        'promotedCollaboratorId',v_collaborator.id
      ))
    );
  end if;

  if v_result is not null then
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  v_result:=jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'taskId',p_task_id,'handoffId',v_handoff.id,
      'fromUserId',v_handoff.from_user_id,'toUserId',v_handoff.to_user_id,
      'state',v_handoff.state,'handoffVersion',v_handoff.version,
      'taskVersion',v_task.version
    ),
    'requestId',p_request_id,'replayed',false,
    'aggregateType','task_primary_handoff','aggregateId',v_handoff.id,
    'aggregateVersion',v_handoff.version
  );
  return private.complete_command(
    v_claim.command_id,v_result,'task_primary_handoff',v_handoff.id,v_handoff.version
  );
end;
$$;

create function public.cmd_cancel_task_primary_handoff(
  p_project_id uuid,
  p_task_id uuid,
  p_handoff_id uuid,
  p_request_id uuid,
  p_expected_handoff_version integer,
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
  v_handoff public.task_primary_handoffs%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if p_task_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','taskId'); end if;
  if p_handoff_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','handoffId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'handoffId',p_handoff_id,
    'expectedHandoffVersion',p_expected_handoff_version,
    'expectedTaskVersion',p_expected_task_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_cancel_task_primary_handoff',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor)
    and exists(
      select 1
      from public.task_primary_handoffs h
      join public.tasks t on t.project_id=h.project_id and t.id=h.task_id
      where h.project_id=p_project_id and h.task_id=p_task_id
        and h.id=p_handoff_id and h.from_user_id=v_actor
        and t.assignee_id=v_actor
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  perform set_config('lock_timeout','5s',true);
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task
  from public.tasks where project_id=p_project_id and id=p_task_id for update;
  select * into v_handoff
  from public.task_primary_handoffs
  where project_id=p_project_id and task_id=p_task_id and id=p_handoff_id
  for update;

  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or v_task.assignee_id is distinct from v_actor
     or v_handoff.from_user_id is distinct from v_actor then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_handoff_version is null
        or v_handoff.version<>p_expected_handoff_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_handoff.version);
  elsif p_expected_task_version is null
        or v_task.version<>p_expected_task_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_handoff.state<>'pending' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_handoff.version,
      jsonb_build_object('reason','primary_handoff_not_pending')
    );
  else
    update public.task_primary_handoffs
    set state='canceled',canceled_at=now(),version=version+1,updated_at=now()
    where id=v_handoff.id
    returning * into v_handoff;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_primary_handoff_canceled','task_primary_handoff',v_handoff.id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'fromUserId',v_actor,'toUserId',v_handoff.to_user_id,
        'handoffVersion',v_handoff.version,'taskVersion',v_task.version
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'handoffId',v_handoff.id,
        'fromUserId',v_handoff.from_user_id,'toUserId',v_handoff.to_user_id,
        'state',v_handoff.state,'handoffVersion',v_handoff.version,
        'taskVersion',v_task.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_primary_handoff','aggregateId',v_handoff.id,
      'aggregateVersion',v_handoff.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_primary_handoff',v_handoff.id,v_handoff.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_unassign_task_primary(
  p_project_id uuid,
  p_task_id uuid,
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
  v_handoff public.task_primary_handoffs%rowtype;
  v_seq integer:=1;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if p_task_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','taskId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,
    'expectedTaskVersion',p_expected_task_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_unassign_task_primary',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor)
    and exists(
      select 1 from public.tasks t
      where t.project_id=p_project_id and t.id=p_task_id
        and t.assignee_id=v_actor and t.assignment_state='assigned'
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  perform set_config('lock_timeout','5s',true);
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task
  from public.tasks where project_id=p_project_id and id=p_task_id for update;
  select * into v_handoff
  from public.task_primary_handoffs h
  where h.project_id=p_project_id and h.task_id=p_task_id and h.state='pending'
  for update;

  perform 1
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor
  for update;

  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or v_task.assignee_id is distinct from v_actor
     or v_task.assignment_state<>'assigned' then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_task_version is null
        or v_task.version<>p_expected_task_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif exists(
    select 1 from public.task_change_proposals p
    where p.task_id=p_task_id and p.state='pending'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_change_pending')
    );
  elsif v_task.status not in ('not_started','in_progress','blocked')
        or v_task.first_submitted_at is not null
        or exists(select 1 from public.task_review_rounds r where r.task_id=p_task_id) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','primary_unassign_not_safe')
    );
  else
    if v_handoff.id is not null then
      update public.task_primary_handoffs
      set state='canceled',canceled_at=now(),version=version+1,updated_at=now()
      where id=v_handoff.id
      returning * into v_handoff;

      perform private.emit_event(
        v_claim.command_id,v_seq,p_project_id,v_actor,
        'task_primary_handoff_canceled','task_primary_handoff',v_handoff.id,p_request_id,
        jsonb_build_object(
          'taskId',p_task_id,'fromUserId',v_actor,'toUserId',v_handoff.to_user_id,
          'handoffVersion',v_handoff.version,'taskVersion',v_task.version
        )
      );
      v_seq:=v_seq+1;
    end if;

    update public.tasks
    set assignee_id=null,assignment_state='claimable',is_direct_assignment=false,
        accepted_at=null,status='not_started',progress_text=null,blocked_reason=null,
        version=version+1,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    perform private.emit_event(
      v_claim.command_id,v_seq,p_project_id,v_actor,
      'task_primary_unassigned','task',p_task_id,p_request_id,
      jsonb_build_object(
        'taskId',p_task_id,'fromUserId',v_actor,'taskVersion',v_task.version
      )
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'taskVersion',v_task.version,
        'assignmentState',v_task.assignment_state
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',v_task.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task',p_task_id,v_task.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_correct_task_review_request_changes(
  p_project_id uuid,
  p_task_id uuid,
  p_review_round_id uuid,
  p_request_id uuid,
  p_expected_task_version integer,
  p_expected_review_version integer
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
  v_source public.task_review_rounds%rowtype;
  v_latest public.task_review_rounds%rowtype;
  v_new public.task_review_rounds%rowtype;
  v_decision_task_version integer;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if p_task_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','taskId'); end if;
  if p_review_round_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','reviewRoundId'); end if;
  if not exists(select 1 from public.projects where id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'taskId',p_task_id,'reviewRoundId',p_review_round_id,
    'expectedTaskVersion',p_expected_task_version,
    'expectedReviewVersion',p_expected_review_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_correct_task_review_request_changes',p_request_id,v_hash,null,p_project_id
  );
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;
  v_result:=private.reject_unless_authorized(
    private.is_active_non_observer_member(p_project_id,v_actor)
    and exists(
      select 1
      from public.tasks t
      join public.task_review_rounds r
        on r.project_id=t.project_id and r.task_id=t.id
      where t.project_id=p_project_id and t.id=p_task_id and r.id=p_review_round_id
        and r.reviewed_by=v_actor
        and r.submitted_by is distinct from v_actor
        and t.assignee_id is distinct from v_actor
        and (t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor))
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;

  perform set_config('lock_timeout','5s',true);
  select * into v_project from public.projects where id=p_project_id for update;
  select * into v_task
  from public.tasks where project_id=p_project_id and id=p_task_id for update;
  select * into v_source
  from public.task_review_rounds
  where project_id=p_project_id and task_id=p_task_id and id=p_review_round_id
  for update;
  select * into v_latest
  from public.task_review_rounds
  where project_id=p_project_id and task_id=p_task_id
  order by round_number desc
  limit 1
  for update;

  perform 1
  from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor
  for update;

  select nullif(e.event_data->>'taskVersion','')::integer
    into v_decision_task_version
  from public.business_events e
  where e.project_id=p_project_id
    and e.event_type='task_submission_changes_requested'
    and e.entity_type='task_review_round'
    and e.entity_id=p_review_round_id
  order by e.id desc
  limit 1;

  if not private.is_active_non_observer_member(p_project_id,v_actor)
     or v_source.reviewed_by is distinct from v_actor
     or v_source.submitted_by is not distinct from v_actor
     or v_task.assignee_id is not distinct from v_actor
     or not (v_task.created_by=v_actor or private.is_active_leader(p_project_id,v_actor)) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_task_version is null
        or v_task.version<>p_expected_task_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif p_expected_review_version is null
        or v_source.version<>p_expected_review_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_source.version);
  elsif v_latest.id is distinct from v_source.id then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_source.version,
      jsonb_build_object('reason','review_correction_not_latest')
    );
  elsif v_source.state<>'rejected'
        or v_source.decision<>'request_changes'
        or v_task.status<>'in_progress'
        or v_decision_task_version is null
        or v_decision_task_version<>v_task.version
        or exists(
          select 1 from public.task_review_rounds r
          where r.task_id=p_task_id and r.state='pending'
        ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_source.version,
      jsonb_build_object('reason','review_correction_no_longer_available')
    );
  else
    insert into public.task_review_rounds(
      project_id,task_id,round_number,submitted_file_version_id,submitted_by,
      submitted_at,state,version,submission_text_snapshot,
      required_submission_file_type_snapshot,correction_of_review_round_id
    ) values(
      p_project_id,p_task_id,v_source.round_number+1,
      v_source.submitted_file_version_id,v_source.submitted_by,
      v_source.submitted_at,'pending',1,v_source.submission_text_snapshot,
      v_source.required_submission_file_type_snapshot,v_source.id
    )
    returning * into v_new;

    insert into public.task_review_round_files(
      review_round_id,project_id,task_id,file_version_id,position
    )
    select
      v_new.id,rf.project_id,rf.task_id,rf.file_version_id,rf.position
    from public.task_review_round_files rf
    where rf.review_round_id=v_source.id
    order by rf.position;

    update public.tasks
    set status='awaiting_review',blocked_reason=null,version=version+1,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_review_correction_opened','task_review_round',v_new.id,p_request_id,
      jsonb_strip_nulls(jsonb_build_object(
        'taskId',p_task_id,'sourceReviewRoundId',v_source.id,
        'reviewRoundId',v_new.id,'submittedBy',v_source.submitted_by,
        'taskVersion',v_task.version,'reviewRoundVersion',v_new.version
      ))
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',p_task_id,'sourceReviewRoundId',v_source.id,
        'reviewRoundId',v_new.id,'roundNumber',v_new.round_number,
        'taskVersion',v_task.version,'reviewRoundVersion',v_new.version
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_review_round','aggregateId',v_new.id,
      'aggregateVersion',v_new.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_review_round',v_new.id,v_new.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function private.notify_from_task_authority_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_recipient uuid;
begin
  if new.event_type='task_primary_handoff_requested' then
    v_recipient:=nullif(new.event_data->>'toUserId','')::uuid;
    if v_recipient is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_primary_handoff_requested','主负责人移交请求',
        '当前主负责人希望将任务主责移交给你，请确认是否接受。',
        'task',nullif(new.event_data->>'taskId','')::uuid
      );
    end if;

  elsif new.event_type='task_primary_handoff_rejected' then
    v_recipient:=nullif(new.event_data->>'fromUserId','')::uuid;
    if v_recipient is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_primary_handoff_rejected','主负责人移交被拒绝',
        '对方拒绝了任务主负责人移交请求。',
        'task',nullif(new.event_data->>'taskId','')::uuid
      );
    end if;

  elsif new.event_type='task_primary_handoff_canceled' then
    v_recipient:=nullif(new.event_data->>'toUserId','')::uuid;
    if v_recipient is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_primary_handoff_canceled','主负责人移交已撤回',
        '一条等待你确认的主负责人移交请求已被撤回。',
        'task',nullif(new.event_data->>'taskId','')::uuid
      );
    end if;

  elsif new.event_type='task_primary_handoff_accepted' then
    v_task_id:=nullif(new.event_data->>'taskId','')::uuid;
    for v_recipient in
      select distinct q.recipient_id
      from (
        select nullif(new.event_data->>'fromUserId','')::uuid as recipient_id
        union all
        select t.created_by from public.tasks t
          where t.project_id=new.project_id and t.id=v_task_id
        union all
        select p.leader_id from public.projects p where p.id=new.project_id
      ) q
      where q.recipient_id is not null
        and q.recipient_id is distinct from new.actor_id
    loop
      if private.is_active_member(new.project_id,v_recipient) then
        perform private.create_notification(
          new.id,new.project_id,v_recipient,
          'task_primary_handoff_accepted','主负责人已变更',
          '任务主负责人移交已完成。',
          'task',v_task_id
        );
      end if;
    end loop;

  elsif new.event_type='task_primary_unassigned' then
    v_task_id:=nullif(new.event_data->>'taskId','')::uuid;
    for v_recipient in
      select distinct q.recipient_id
      from (
        select t.created_by as recipient_id
        from public.tasks t where t.project_id=new.project_id and t.id=v_task_id
        union all
        select p.leader_id from public.projects p where p.id=new.project_id
        union all
        select c.user_id
        from public.task_collaborators c
        where c.project_id=new.project_id and c.task_id=v_task_id
          and c.state='accepted' and c.user_id is not null
      ) q
      where q.recipient_id is not null
        and q.recipient_id is distinct from new.actor_id
    loop
      if private.is_active_member(new.project_id,v_recipient) then
        perform private.create_notification(
          new.id,new.project_id,v_recipient,
          'task_primary_unassigned','任务主负责人已卸任',
          '任务已回到待认领状态，需要重新确认主负责人。',
          'task',v_task_id
        );
      end if;
    end loop;

  elsif new.event_type='task_review_correction_opened' then
    v_recipient:=nullif(new.event_data->>'submittedBy','')::uuid;
    if v_recipient is distinct from new.actor_id
       and private.is_active_member(new.project_id,v_recipient) then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,
        'task_review_correction_opened','验收打回已纠正',
        '原验收打回记录已保留，同一份提交已重新进入待验收。',
        'task_review_round',new.entity_id
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists business_event_creates_task_authority_notification
on public.business_events;
create trigger business_event_creates_task_authority_notification
after insert on public.business_events
for each row execute function private.notify_from_task_authority_event();

revoke all on function private.notify_from_task_authority_event()
from public,anon,authenticated,service_role;

revoke all on function public.cmd_request_task_primary_handoff(uuid,uuid,uuid,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_request_task_primary_handoff(uuid,uuid,uuid,uuid,integer)
to authenticated;

revoke all on function public.cmd_respond_task_primary_handoff(uuid,uuid,uuid,text,uuid,integer,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_respond_task_primary_handoff(uuid,uuid,uuid,text,uuid,integer,integer)
to authenticated;

revoke all on function public.cmd_cancel_task_primary_handoff(uuid,uuid,uuid,uuid,integer,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_cancel_task_primary_handoff(uuid,uuid,uuid,uuid,integer,integer)
to authenticated;

revoke all on function public.cmd_unassign_task_primary(uuid,uuid,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_unassign_task_primary(uuid,uuid,uuid,integer)
to authenticated;

revoke all on function public.cmd_correct_task_review_request_changes(uuid,uuid,uuid,uuid,integer,integer)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_correct_task_review_request_changes(uuid,uuid,uuid,uuid,integer,integer)
to authenticated;

revoke all on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text)
from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text)
to authenticated;
