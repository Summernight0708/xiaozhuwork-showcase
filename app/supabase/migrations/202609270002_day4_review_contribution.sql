alter table public.projects
  add column lifecycle_state text not null default 'active',
  add column completed_at timestamptz,
  add constraint projects_lifecycle_state check (lifecycle_state in ('active','contribution_review','completed')),
  add constraint projects_completion_state check (
    (lifecycle_state = 'completed' and completed_at is not null) or
    (lifecycle_state <> 'completed' and completed_at is null)
  );

alter table public.task_file_versions
  add constraint task_file_versions_project_task_id_unique unique (project_id, task_id, id);

create table public.task_review_rounds (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  task_id uuid not null,
  round_number integer not null,
  submitted_file_version_id uuid not null,
  submitted_by uuid references auth.users (id) on delete set null,
  submitted_at timestamptz not null default now(),
  state text not null default 'pending',
  decision text,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id) references public.tasks (project_id, id) on delete cascade,
  foreign key (project_id, task_id, submitted_file_version_id)
    references public.task_file_versions (project_id, task_id, id),
  constraint task_review_rounds_round_number check (round_number > 0),
  constraint task_review_rounds_state check (state in ('pending','approved','rejected')),
  constraint task_review_rounds_decision check (
    (state = 'pending' and decision is null and reviewed_at is null and rejection_reason is null) or
    (state = 'approved' and decision is not null and decision = 'approve' and reviewed_at is not null and rejection_reason is null) or
    (state = 'rejected' and decision is not null and decision in ('reject','request_changes') and reviewed_at is not null
      and rejection_reason is not null and char_length(btrim(rejection_reason)) between 1 and 2000)
  ),
  constraint task_review_rounds_version check (version > 0),
  constraint task_review_rounds_task_round_unique unique (task_id, round_number)
);
create unique index task_review_rounds_one_pending_idx on public.task_review_rounds (task_id) where state='pending';
create index task_review_rounds_project_idx on public.task_review_rounds (project_id, submitted_at desc);

create table public.contribution_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.projects (id) on delete cascade,
  state text not null default 'draft',
  contribution_mode text not null,
  source_project_version integer not null,
  eligible_member_count integer not null,
  required_confirmation_count integer not null,
  created_by uuid references auth.users (id) on delete set null,
  formalized_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contribution_reports_state check (state in ('draft','formal')),
  constraint contribution_reports_mode check (contribution_mode in ('weighted','facts_only')),
  constraint contribution_reports_source_version check (source_project_version > 0),
  constraint contribution_reports_eligible_count check (eligible_member_count > 0),
  constraint contribution_reports_required_count check (
    required_confirmation_count = (eligible_member_count / 2) + 1
    and required_confirmation_count <= eligible_member_count
  ),
  constraint contribution_reports_version check (version > 0),
  constraint contribution_reports_formalization check (
    (state='draft' and formalized_at is null) or (state='formal' and formalized_at is not null)
  )
);

create table public.contribution_items (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.contribution_reports (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  task_id uuid not null references public.tasks (id),
  member_user_id uuid references auth.users (id) on delete set null,
  member_display_name_snapshot text not null,
  task_weight numeric(12,4),
  share numeric(5,4) not null,
  contribution_value numeric(12,4),
  task_title_snapshot text not null,
  completed_at_snapshot timestamptz not null,
  created_at timestamptz not null default now(),
  constraint contribution_items_task_unique unique (report_id, task_id),
  constraint contribution_items_share check (share > 0 and share <= 1.0000),
  constraint contribution_items_weight check (task_weight is null or task_weight between 1.0000 and 5.0000),
  constraint contribution_items_value_mode check (
    (task_weight is null and contribution_value is null) or
    (task_weight is not null and contribution_value is not null)
  )
);
create index contribution_items_project_member_idx on public.contribution_items (project_id, member_user_id);

create table public.contribution_confirmations (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.contribution_reports (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  confirmed_at timestamptz not null default now()
);
create unique index contribution_confirmations_user_unique_idx
  on public.contribution_confirmations (report_id, user_id) where user_id is not null;
create index contribution_confirmations_project_idx on public.contribution_confirmations (project_id, confirmed_at);

create function private.protect_task_review_round()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode='55000', message='Task review rounds cannot be deleted';
  end if;
  if old.state <> 'pending' then
    raise exception using errcode='55000', message='Terminal task review rounds are immutable';
  end if;
  if new.id <> old.id
     or new.project_id <> old.project_id
     or new.task_id <> old.task_id
     or new.round_number <> old.round_number
     or new.submitted_file_version_id <> old.submitted_file_version_id
     or new.submitted_by is distinct from old.submitted_by
     or new.submitted_at <> old.submitted_at
     or new.created_at <> old.created_at then
    raise exception using errcode='55000', message='Task review round identity is immutable';
  end if;
  return new;
end;
$$;
create trigger task_review_rounds_protect_history
before update or delete on public.task_review_rounds
for each row execute function private.protect_task_review_round();

create function private.reject_contribution_item_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode='55000', message='Contribution items are immutable';
end;
$$;
create trigger contribution_items_immutable
before update or delete on public.contribution_items
for each row execute function private.reject_contribution_item_mutation();

create function private.reject_contribution_confirmation_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op='UPDATE'
     and old.user_id is not null
     and new.user_id is null
     and (to_jsonb(new)-'user_id')=(to_jsonb(old)-'user_id') then
    return new;
  end if;
  raise exception using errcode='55000', message='Contribution confirmations are immutable';
end;
$$;
create trigger contribution_confirmations_immutable
before update or delete on public.contribution_confirmations
for each row execute function private.reject_contribution_confirmation_mutation();

revoke all on function private.protect_task_review_round() from public, anon, authenticated, service_role;
revoke all on function private.reject_contribution_item_mutation() from public, anon, authenticated, service_role;
revoke all on function private.reject_contribution_confirmation_mutation() from public, anon, authenticated, service_role;

alter table public.task_review_rounds enable row level security;
alter table public.contribution_reports enable row level security;
alter table public.contribution_items enable row level security;
alter table public.contribution_confirmations enable row level security;

create policy task_review_rounds_select_member on public.task_review_rounds
for select to authenticated using (public.is_active_project_member(project_id));
create policy contribution_reports_select_member on public.contribution_reports
for select to authenticated using (public.is_active_project_member(project_id));
create policy contribution_items_select_member on public.contribution_items
for select to authenticated using (public.is_active_project_member(project_id));
create policy contribution_confirmations_select_member on public.contribution_confirmations
for select to authenticated using (public.is_active_project_member(project_id));

revoke all on public.task_review_rounds, public.contribution_reports, public.contribution_items, public.contribution_confirmations
from public, anon, authenticated, service_role;
grant select on public.task_review_rounds, public.contribution_reports, public.contribution_items, public.contribution_confirmations
to authenticated;

create function public.cmd_submit_task_for_review(
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

create function public.cmd_review_task_submission(
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

create function public.cmd_create_contribution_report(
  p_project_id uuid,
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
  v_report_id uuid;
  v_item_count integer;
  v_eligible integer;
  v_required integer;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','projectId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version));
  select * into v_claim from private.claim_command(v_actor,'cmd_create_contribution_report',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;

  if p_expected_version is null or p_expected_version <> v_project.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif exists(select 1 from public.contribution_reports r where r.project_id=p_project_id) then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_project.version);
  elsif not exists(select 1 from public.tasks t where t.project_id=p_project_id and t.status='completed') then
    v_result:=private.failure(p_request_id,'REPORT_NOT_READY',null,v_project.version);
  elsif exists(select 1 from public.tasks t where t.project_id=p_project_id and t.status not in ('completed','canceled')) then
    v_result:=private.failure(p_request_id,'REPORT_NOT_READY',null,v_project.version);
  elsif exists(select 1 from public.tasks t where t.project_id=p_project_id and t.status='completed' and t.completed_at is null) then
    v_result:=private.failure(p_request_id,'REPORT_NOT_READY',null,v_project.version);
  elsif exists(select 1 from public.file_upload_reservations r where r.project_id=p_project_id and r.state='reserved' and r.expires_at>now()) then
    v_result:=private.failure(p_request_id,'REPORT_NOT_READY',null,v_project.version);
  else
    select count(*)::integer into v_eligible
    from public.project_members pm
    where pm.project_id=p_project_id and pm.member_state='active' and not pm.is_observer and pm.user_id is not null;
    v_required:=floor(v_eligible::numeric/2)::integer+1;

    v_report_id:=gen_random_uuid();
    insert into public.contribution_reports(
      id,project_id,state,contribution_mode,source_project_version,
      eligible_member_count,required_confirmation_count,created_by,version
    ) values(
      v_report_id,p_project_id,'draft',v_project.contribution_mode,v_project.version,
      v_eligible,v_required,v_actor,1
    );

    insert into public.contribution_items(
      report_id,project_id,task_id,member_user_id,member_display_name_snapshot,
      task_weight,share,contribution_value,task_title_snapshot,completed_at_snapshot
    )
    select
      v_report_id,t.project_id,t.id,t.assignee_id,
      coalesce(
        nullif(btrim(pm.display_name_snapshot),''),
        nullif(btrim(pr.display_name),''),
        nullif(btrim(pr.real_name),''),
        case when t.assignee_id is null then '已注销成员' else '成员-' || left(t.assignee_id::text,8) end
      ),
      case when v_project.contribution_mode='weighted' then round(t.weight::numeric,4) else null end,
      1.0000::numeric(5,4),
      case when v_project.contribution_mode='weighted' then round(t.weight::numeric,4) else null end,
      t.title,t.completed_at
    from public.tasks t
    left join public.project_members pm on pm.project_id=t.project_id and pm.user_id=t.assignee_id
    left join public.profiles pr on pr.id=t.assignee_id
    where t.project_id=p_project_id and t.status='completed'
    order by t.id;
    get diagnostics v_item_count=row_count;

    update public.projects
    set lifecycle_state='contribution_review',version=version+1,updated_at=now()
    where id=p_project_id returning * into v_project;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'contribution_report_created','contribution_report',v_report_id,p_request_id,
      jsonb_build_object('itemCount',v_item_count,'sourceProjectVersion',v_project.version-1,'contributionMode',v_project.contribution_mode)
    );
    perform private.emit_event(
      v_claim.command_id,2,p_project_id,v_actor,'project_contribution_review_started','project',p_project_id,p_request_id,
      jsonb_build_object('reportId',v_report_id,'projectVersion',v_project.version)
    );

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object('projectId',p_project_id,'reportId',v_report_id,'reportVersion',1,'itemCount',v_item_count,'state','draft'),
      'requestId',p_request_id,'replayed',false,'aggregateType','project','aggregateId',p_project_id,'aggregateVersion',v_project.version
    );
    return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_project.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_confirm_contribution_report(
  p_project_id uuid,
  p_report_id uuid,
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
  v_report public.contribution_reports%rowtype;
  v_eligible integer;
  v_confirmed integer;
  v_required integer;
  v_formalized boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_report_id is null then
    return private.failure(p_request_id,'VALIDATION_FAILED',case when p_project_id is null then 'projectId' else 'reportId' end);
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout','5s',true);
  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'reportId',p_report_id,'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(v_actor,'cmd_confirm_contribution_report',p_request_id,v_hash,null,p_project_id);
  v_result:=private.reject_unless_authorized(
    exists(
      select 1 from public.project_members pm
      where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active' and not pm.is_observer
    ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_report from public.contribution_reports r
   where r.id=p_report_id and r.project_id=p_project_id for update;

  if v_report.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> v_report.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_report.version);
  elsif v_project.lifecycle_state <> 'contribution_review' or v_report.state <> 'draft' then
    v_result:=private.failure(p_request_id,'REPORT_NOT_READY',null,v_report.version);
  elsif exists(select 1 from public.contribution_confirmations c where c.report_id=p_report_id and c.user_id=v_actor) then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_report.version);
  else
    insert into public.contribution_confirmations(report_id,project_id,user_id)
    values(p_report_id,p_project_id,v_actor);

    v_eligible:=v_report.eligible_member_count;
    v_required:=v_report.required_confirmation_count;

    select count(*)::integer into v_confirmed
    from public.contribution_confirmations c
    where c.report_id=p_report_id;

    v_formalized:=v_confirmed>=v_required;
    update public.contribution_reports
    set state=case when v_formalized then 'formal' else 'draft' end,
        formalized_at=case when v_formalized then now() else null end,
        version=version+1,
        updated_at=now()
    where id=p_report_id returning * into v_report;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,'contribution_report_confirmed','contribution_report',p_report_id,p_request_id,
      jsonb_build_object('confirmedCount',v_confirmed,'eligibleCount',v_eligible,'requiredCount',v_required,'reportVersion',v_report.version)
    );

    if v_formalized then
      update public.projects
      set lifecycle_state='completed',completed_at=now(),version=version+1,updated_at=now()
      where id=p_project_id returning * into v_project;
      perform private.emit_event(
        v_claim.command_id,2,p_project_id,v_actor,'contribution_report_formalized','contribution_report',p_report_id,p_request_id,
        jsonb_build_object('confirmedCount',v_confirmed,'requiredCount',v_required,'reportVersion',v_report.version)
      );
      perform private.emit_event(
        v_claim.command_id,3,p_project_id,v_actor,'project_completed','project',p_project_id,p_request_id,
        jsonb_build_object('reportId',p_report_id,'projectVersion',v_project.version)
      );
    end if;

    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'projectId',p_project_id,'reportId',p_report_id,'state',v_report.state,
        'confirmedCount',v_confirmed,'eligibleCount',v_eligible,'requiredCount',v_required,'formalized',v_formalized
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','contribution_report',
      'aggregateId',p_report_id,'aggregateVersion',v_report.version
    );
    return private.complete_command(v_claim.command_id,v_result,'contribution_report',p_report_id,v_report.version);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.get_project_contribution_report(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_report public.contribution_reports%rowtype;
  v_eligible integer;
  v_confirmed integer;
begin
  if v_actor is null then return private.failure(null,'UNAUTHENTICATED'); end if;
  if p_project_id is null or not private.is_active_member(p_project_id,v_actor) then
    return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  select * into v_report from public.contribution_reports r where r.project_id=p_project_id;
  if v_report.id is null then return private.failure(null,'REPORT_NOT_READY'); end if;

  v_eligible:=v_report.eligible_member_count;
  select count(*)::integer into v_confirmed
  from public.contribution_confirmations c
  where c.report_id=v_report.id;

  return jsonb_build_object(
    'projectId',p_project_id,
    'reportId',v_report.id,
    'state',v_report.state,
    'contributionMode',v_report.contribution_mode,
    'version',v_report.version,
    'formalizedAt',v_report.formalized_at,
    'eligibleCount',v_eligible,
    'confirmedCount',v_confirmed,
    'requiredCount',v_report.required_confirmation_count,
    'items',coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'taskId',i.task_id,'memberUserId',i.member_user_id,'taskWeight',i.task_weight,
        'share',i.share,'contributionValue',i.contribution_value,'taskTitle',i.task_title_snapshot,
        'completedAt',i.completed_at_snapshot
      )) order by i.task_id)
      from public.contribution_items i where i.report_id=v_report.id
    ),'[]'::jsonb)
  );
end;
$$;

create function public.get_project_report_export(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_report public.contribution_reports%rowtype;
  v_project public.projects%rowtype;
  v_confirmed integer;
begin
  if v_actor is null then return private.failure(null,'UNAUTHENTICATED'); end if;
  if p_report_id is null then return private.failure(null,'VALIDATION_FAILED','reportId'); end if;

  select r.* into v_report
  from public.contribution_reports r
  where r.id=p_report_id;

  if v_report.id is null or not private.is_active_member(v_report.project_id,v_actor) then
    return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  select * into v_project from public.projects p where p.id=v_report.project_id;
  select count(*)::integer into v_confirmed
  from public.contribution_confirmations c
  where c.report_id=v_report.id;

  return jsonb_build_object(
    'schemaVersion',1,
    'projectId',v_project.id,
    'projectName',v_project.name,
    'reportId',v_report.id,
    'reportState',v_report.state,
    'statusLabel',case when v_report.state='draft' then 'DRAFT' else 'FORMAL' end,
    'contributionMode',v_report.contribution_mode,
    'sourceProjectVersion',v_report.source_project_version,
    'reportVersion',v_report.version,
    'createdAt',v_report.created_at,
    'formalizedAt',v_report.formalized_at,
    'eligibleCount',v_report.eligible_member_count,
    'confirmedCount',v_confirmed,
    'requiredCount',v_report.required_confirmation_count,
    'disclaimer','仅供参考，不代表教师评分或成员能力评价',
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'taskId',i.task_id,
        'taskTitle',i.task_title_snapshot,
        'memberUserId',i.member_user_id,
        'memberDisplayName',i.member_display_name_snapshot,
        'taskWeightAuthority',case when i.task_weight is null then null else to_char(i.task_weight,'FM9999999990.0000') end,
        'taskWeightDisplay',case when i.task_weight is null then null else to_char(round(i.task_weight,2),'FM9999999990.00') end,
        'shareAuthority',to_char(i.share,'FM9999999990.0000'),
        'shareDisplay',to_char(round(i.share,2),'FM9999999990.00'),
        'contributionValueAuthority',case when i.contribution_value is null then null else to_char(i.contribution_value,'FM9999999990.0000') end,
        'contributionValueDisplay',case when i.contribution_value is null then null else to_char(round(i.contribution_value,2),'FM9999999990.00') end,
        'completedAt',i.completed_at_snapshot
      ) order by i.task_id)
      from public.contribution_items i
      where i.report_id=v_report.id
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.cmd_submit_task_for_review(uuid,uuid,uuid,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_create_contribution_report(uuid,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.cmd_confirm_contribution_report(uuid,uuid,uuid,integer) from public, anon, authenticated, service_role;
revoke all on function public.get_project_contribution_report(uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_project_report_export(uuid) from public, anon, authenticated, service_role;

grant execute on function public.cmd_submit_task_for_review(uuid,uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_review_task_submission(uuid,uuid,uuid,text,text,uuid,integer) to authenticated;
grant execute on function public.cmd_create_contribution_report(uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_confirm_contribution_report(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.get_project_contribution_report(uuid) to authenticated;
grant execute on function public.get_project_report_export(uuid) to authenticated;
