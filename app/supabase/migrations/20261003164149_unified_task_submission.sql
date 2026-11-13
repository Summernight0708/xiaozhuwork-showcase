-- Unified task submission: immutable text + 0..N finalized file versions and optional required file type.

alter table public.tasks
  add column required_submission_file_type text,
  add constraint tasks_required_submission_file_type check (
    required_submission_file_type is null
    or required_submission_file_type in (
      'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    )
  );

alter table public.task_review_rounds
  alter column submitted_file_version_id drop not null,
  add column submission_text_snapshot text,
  add column required_submission_file_type_snapshot text,
  add constraint task_review_rounds_submission_text_length check (
    submission_text_snapshot is null
    or char_length(submission_text_snapshot) between 1 and 4000
  ),
  add constraint task_review_rounds_required_submission_file_type check (
    required_submission_file_type_snapshot is null
    or required_submission_file_type_snapshot in (
      'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    )
  ),
  add constraint task_review_rounds_project_task_id_unique
    unique (project_id, task_id, id);

create table public.task_review_round_files (
  review_round_id uuid not null,
  project_id uuid not null,
  task_id uuid not null,
  file_version_id uuid not null,
  position integer not null,
  created_at timestamptz not null default now(),
  primary key (review_round_id, file_version_id),
  foreign key (project_id, task_id, review_round_id)
    references public.task_review_rounds (project_id, task_id, id) on delete cascade,
  foreign key (project_id, task_id, file_version_id)
    references public.task_file_versions (project_id, task_id, id),
  constraint task_review_round_files_position_positive check (position > 0),
  constraint task_review_round_files_round_position_unique
    unique (review_round_id, position)
);

create index task_review_round_files_project_task_idx
  on public.task_review_round_files (project_id, task_id, review_round_id, position);

insert into public.task_review_round_files(
  review_round_id,project_id,task_id,file_version_id,position
)
select id,project_id,task_id,submitted_file_version_id,1
from public.task_review_rounds
where submitted_file_version_id is not null
on conflict do nothing;

do $$
begin
  if exists(
    select 1
    from public.task_review_rounds rr
    where rr.submitted_file_version_id is not null
      and not exists(
        select 1
        from public.task_review_round_files rf
        where rf.review_round_id=rr.id
          and rf.project_id=rr.project_id
          and rf.task_id=rr.task_id
          and rf.file_version_id=rr.submitted_file_version_id
          and rf.position=1
      )
  ) then
    raise exception 'Legacy task review file backfill incomplete';
  end if;
end;
$$;

create function private.reject_task_review_round_file_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode='55000',
    message='Task review round files are immutable';
end;
$$;

create trigger task_review_round_files_immutable
before update or delete on public.task_review_round_files
for each row execute function private.reject_task_review_round_file_mutation();

alter table public.task_review_round_files enable row level security;

create policy task_review_round_files_select_member
on public.task_review_round_files
for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_review_round_files
from public,anon,authenticated,service_role;
grant select on public.task_review_round_files to authenticated;

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

  if tg_op = 'DELETE' then
    raise exception using errcode='55000', message='Task review rounds cannot be deleted';
  end if;
  if old.state <> 'pending' then
    raise exception using errcode='55000', message='Terminal task review rounds are immutable';
  end if;
  if new.id is distinct from old.id
     or new.project_id is distinct from old.project_id
     or new.task_id is distinct from old.task_id
     or new.round_number is distinct from old.round_number
     or new.submitted_file_version_id is distinct from old.submitted_file_version_id
     or new.submission_text_snapshot is distinct from old.submission_text_snapshot
     or new.required_submission_file_type_snapshot is distinct from old.required_submission_file_type_snapshot
     or new.submitted_by is distinct from old.submitted_by
     or new.submitted_at is distinct from old.submitted_at
     or new.created_at is distinct from old.created_at then
    raise exception using errcode='55000', message='Task review round identity is immutable';
  end if;
  return new;
end;
$$;

create function private.task_submission_file_type_from_mime(p_mime text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case lower(p_mime)
    when 'application/pdf' then 'pdf'
    when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
    when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'xlsx'
    when 'application/vnd.openxmlformats-officedocument.presentationml.presentation' then 'pptx'
    when 'text/csv' then 'csv'
    when 'text/plain' then 'txt'
    when 'text/markdown' then 'md'
    when 'application/json' then 'json'
    when 'application/xml' then 'xml'
    when 'text/xml' then 'xml'
    when 'text/css' then 'css'
    when 'text/javascript' then 'js'
    when 'application/javascript' then 'js'
    when 'text/typescript' then 'ts'
    when 'application/typescript' then 'ts'
    when 'image/png' then 'png'
    when 'image/jpeg' then 'jpg'
    when 'image/gif' then 'gif'
    when 'image/webp' then 'webp'
    else null
  end;
$$;

revoke all on function private.reject_task_review_round_file_mutation()
from public,anon,authenticated,service_role;
revoke all on function private.task_submission_file_type_from_mime(text)
from public,anon,authenticated,service_role;

alter table public.task_change_proposals
  add column old_required_submission_file_type text,
  add column new_required_submission_file_type text,
  add constraint task_change_proposals_required_submission_file_type check (
    (old_required_submission_file_type is null
      or old_required_submission_file_type in (
        'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
        'png','jpg','gif','webp'
      ))
    and
    (new_required_submission_file_type is null
      or new_required_submission_file_type in (
        'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
        'png','jpg','gif','webp'
      ))
  );

alter table public.task_change_proposals
  drop constraint task_change_proposals_has_change,
  add constraint task_change_proposals_has_change check (
    new_deadline_at is distinct from old_deadline_at
    or new_weight is distinct from old_weight
    or new_required_submission_file_type is distinct from old_required_submission_file_type
  );

drop function public.cmd_create_task(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid);

create function public.cmd_create_task(
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
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects
  where id=p_project_id
  for update;

  if p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_project.lifecycle_state <> 'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_title is null or char_length(btrim(p_title)) not between 1 and 240 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','title');
  elsif p_deadline_at is null or p_deadline_at<=now() or p_deadline_at>v_project.deadline_at then
    v_result:=private.failure(p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt');
  elsif p_assignment_mode is null or p_assignment_mode not in ('claimable','direct') then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assignmentMode');
  elsif v_project.contribution_mode='weighted' and (p_weight is null or p_weight not between 1 and 5) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif p_assignment_mode='claimable' and p_assignee_id is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','assigneeId');
  elsif p_assignment_mode='direct'
        and (p_assignee_id is null or not private.is_active_member(p_project_id,p_assignee_id)) then
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

drop function public.cmd_edit_task(uuid,uuid,uuid,integer,text,text,timestamptz,smallint);

create function public.cmd_edit_task(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_title text,
  p_description text,
  p_deadline_at timestamptz,
  p_weight smallint,
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
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_actor_member public.project_members%rowtype;
  v_changed_fields jsonb:='[]'::jsonb;
  v_has_activity boolean;
  v_has_review_history boolean;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'taskId',p_task_id,
    'expectedVersion',p_expected_version,
    'title',p_title,
    'description',p_description,
    'deadlineAt',p_deadline_at,
    'weight',p_weight,
    'requiredSubmissionFileType',p_required_submission_file_type
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,'cmd_edit_task',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1
        from public.tasks t
        where t.id=p_task_id
          and t.project_id=p_project_id
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
  elsif v_project.contribution_mode='weighted'
        and (p_weight is null or p_weight not between 1 and 5) then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif v_project.contribution_mode='facts_only' and p_weight is not null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','weight');
  elsif p_required_submission_file_type is not null
        and p_required_submission_file_type not in (
          'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType',v_task.version
    );
  elsif v_task.accepted_at is not null
        and p_deadline_at is distinct from v_task.deadline_at then
    v_result:=private.failure(
      p_request_id,'CONFIRMATION_REQUIRED','deadlineAt',v_task.version,
      jsonb_build_object('reason','accepted_task_deadline_change')
    );
  else
    v_has_activity:=v_task.accepted_at is not null
      or v_task.first_submitted_at is not null
      or v_task.status<>'not_started'
      or nullif(btrim(coalesce(v_task.progress_text,'')),'') is not null
      or exists(
        select 1 from public.task_file_versions fv where fv.task_id=v_task.id
      )
      or exists(
        select 1 from public.task_review_rounds rr where rr.task_id=v_task.id
      );
    v_has_review_history:=exists(
      select 1 from public.task_review_rounds rr where rr.task_id=v_task.id
    );

    if v_has_activity and p_weight is distinct from v_task.weight then
      v_result:=private.failure(
        p_request_id,'CONFIRMATION_REQUIRED','weight',v_task.version,
        jsonb_build_object('reason','task_activity_weight_change')
      );
    elsif v_has_review_history
          and p_required_submission_file_type is distinct from v_task.required_submission_file_type then
      v_result:=private.failure(
        p_request_id,'CONFIRMATION_REQUIRED','requiredSubmissionFileType',v_task.version,
        jsonb_build_object('reason','submission_requirement_change')
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
      if p_required_submission_file_type is distinct from v_task.required_submission_file_type then
        v_changed_fields:=v_changed_fields || jsonb_build_array('requiredSubmissionFileType');
      end if;

      if jsonb_array_length(v_changed_fields)=0 then
        v_result:=jsonb_build_object(
          'ok',true,
          'data',jsonb_strip_nulls(jsonb_build_object(
            'taskId',v_task.id,
            'taskVersion',v_task.version,
            'changed',false,
            'title',v_task.title,
            'description',v_task.description,
            'deadlineAt',v_task.deadline_at,
            'weight',v_task.weight,
            'requiredSubmissionFileType',v_task.required_submission_file_type
          )),
          'requestId',p_request_id,
          'replayed',false,
          'aggregateType','task',
          'aggregateId',v_task.id,
          'aggregateVersion',v_task.version
        );
        return private.complete_command(
          v_claim.command_id,v_result,'task',v_task.id,v_task.version
        );
      end if;

      update public.tasks
      set title=btrim(p_title),
          description=p_description,
          deadline_at=p_deadline_at,
          weight=p_weight,
          required_submission_file_type=p_required_submission_file_type,
          version=version+1,
          updated_at=now()
      where id=v_task.id
      returning * into v_task;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        'task_edited','task',v_task.id,p_request_id,
        jsonb_strip_nulls(jsonb_build_object(
          'changedFields',v_changed_fields,
          'taskVersion',v_task.version,
          'deadlineAt',v_task.deadline_at,
          'weight',v_task.weight,
          'requiredSubmissionFileType',v_task.required_submission_file_type
        ))
      );

      v_result:=jsonb_build_object(
        'ok',true,
        'data',jsonb_strip_nulls(jsonb_build_object(
          'taskId',v_task.id,
          'taskVersion',v_task.version,
          'changed',true,
          'title',v_task.title,
          'description',v_task.description,
          'deadlineAt',v_task.deadline_at,
          'weight',v_task.weight,
          'requiredSubmissionFileType',v_task.required_submission_file_type
        )),
        'requestId',p_request_id,
        'replayed',false,
        'aggregateType','task',
        'aggregateId',v_task.id,
        'aggregateVersion',v_task.version
      );
      return private.complete_command(
        v_claim.command_id,v_result,'task',v_task.id,v_task.version
      );
    end if;
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

drop function public.cmd_propose_task_change(
  uuid,uuid,timestamptz,smallint,uuid,integer
);

create function public.cmd_propose_task_change(
  p_project_id uuid,
  p_task_id uuid,
  p_deadline_at timestamptz,
  p_weight smallint,
  p_request_id uuid,
  p_expected_task_version integer,
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
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_actor_member public.project_members%rowtype;
  v_confirmer_member public.project_members%rowtype;
  v_proposal public.task_change_proposals%rowtype;
  v_has_activity boolean;
  v_has_review_history boolean;
  v_deadline_changed boolean;
  v_weight_changed boolean;
  v_requirement_changed boolean;
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
    'requiredSubmissionFileType',p_required_submission_file_type,
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
        where t.id=p_task_id
          and t.project_id=p_project_id
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
  elsif p_required_submission_file_type is not null
        and p_required_submission_file_type not in (
          'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType',v_task.version
    );
  else
    v_deadline_changed:=p_deadline_at is distinct from v_task.deadline_at;
    v_weight_changed:=p_weight is distinct from v_task.weight;
    v_requirement_changed:=
      p_required_submission_file_type is distinct from v_task.required_submission_file_type;

    if not v_deadline_changed and not v_weight_changed and not v_requirement_changed then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED',null,v_task.version,
        jsonb_build_object('reason','no_change')
      );
    elsif p_deadline_at is null then
      v_result:=private.failure(
        p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt',v_task.version
      );
    elsif v_deadline_changed
          and (p_deadline_at<=now() or p_deadline_at>v_project.deadline_at) then
      v_result:=private.failure(
        p_request_id,'DDL_NOT_IN_FUTURE','deadlineAt',v_task.version
      );
    elsif v_project.contribution_mode='weighted'
          and (p_weight is null or p_weight not between 1 and 5) then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED','weight',v_task.version
      );
    elsif v_project.contribution_mode='facts_only' and p_weight is not null then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED','weight',v_task.version
      );
    else
      v_has_activity:=v_task.accepted_at is not null
        or v_task.first_submitted_at is not null
        or v_task.status<>'not_started'
        or nullif(btrim(coalesce(v_task.progress_text,'')),'') is not null
        or exists(
          select 1 from public.task_file_versions fv where fv.task_id=v_task.id
        )
        or exists(
          select 1 from public.task_review_rounds rr where rr.task_id=v_task.id
        );
      v_has_review_history:=exists(
        select 1 from public.task_review_rounds rr where rr.task_id=v_task.id
      );

      if not (
        (v_deadline_changed and v_task.accepted_at is not null)
        or (v_weight_changed and v_has_activity)
        or (v_requirement_changed and v_has_review_history)
      ) then
        v_result:=private.failure(
          p_request_id,'INVALID_TRANSITION',null,v_task.version,
          jsonb_build_object('reason','confirmation_not_required')
        );
      elsif exists(
        select 1
        from public.task_change_proposals p
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
          old_required_submission_file_type,new_required_submission_file_type,
          base_task_version,required_confirmer_id,required_confirmer_name_snapshot
        ) values(
          p_project_id,v_task.id,v_actor,
          coalesce(
            v_actor_member.display_name_snapshot,
            (select pr.display_name from public.profiles pr where pr.id=v_actor)
          ),
          'pending',
          v_task.deadline_at,p_deadline_at,v_task.weight,p_weight,
          v_task.required_submission_file_type,p_required_submission_file_type,
          v_task.version,v_task.assignee_id,
          coalesce(
            v_confirmer_member.display_name_snapshot,
            (select pr.display_name
             from public.profiles pr
             where pr.id=v_task.assignee_id)
          )
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
            'newWeight',v_proposal.new_weight,
            'oldRequiredSubmissionFileType',v_proposal.old_required_submission_file_type,
            'newRequiredSubmissionFileType',v_proposal.new_required_submission_file_type
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
          v_claim.command_id,v_result,
          'task_change_proposal',v_proposal.id,v_proposal.version
        );
      end if;
    end if;
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create or replace function public.cmd_respond_to_task_change(
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
    v_result:=private.failure(
      p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version
    );
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
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','action',v_proposal.version
    );
  elsif p_action='approve' and p_rejection_reason is not null then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','rejectionReason',v_proposal.version
    );
  elsif p_action='reject'
        and p_rejection_reason is not null
        and char_length(btrim(p_rejection_reason)) not between 1 and 1000 then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','rejectionReason',v_proposal.version
    );
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
        or v_task.weight is distinct from v_proposal.old_weight
        or v_task.required_submission_file_type
           is distinct from v_proposal.old_required_submission_file_type then
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
        and (
          v_proposal.new_weight is null
          or v_proposal.new_weight not between 1 and 5
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','weight',v_proposal.version
    );
  elsif p_action='approve'
        and v_project.contribution_mode='facts_only'
        and v_proposal.new_weight is not null then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','weight',v_proposal.version
    );
  elsif p_action='approve'
        and v_proposal.new_required_submission_file_type is not null
        and v_proposal.new_required_submission_file_type not in (
          'pdf','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType',
      v_proposal.version
    );
  else
    v_decided_at:=now();

    if p_action='approve' then
      update public.tasks
      set deadline_at=v_proposal.new_deadline_at,
          weight=v_proposal.new_weight,
          required_submission_file_type=
            v_proposal.new_required_submission_file_type,
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
      case when p_action='approve'
        then 'task_change_approved'
        else 'task_change_rejected'
      end,
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
        'oldRequiredSubmissionFileType',
          v_proposal.old_required_submission_file_type,
        'newRequiredSubmissionFileType',
          v_proposal.new_required_submission_file_type,
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
      v_claim.command_id,v_result,
      'task_change_proposal',v_proposal.id,v_proposal.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

drop function public.cmd_submit_task_for_review(uuid,uuid,uuid,uuid,integer);

create function public.cmd_submit_task_for_review(
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
  elsif exists(
    select 1
    from public.task_dependencies d
    join public.tasks upstream
      on upstream.project_id=d.project_id
     and upstream.id=d.upstream_task_id
    where d.project_id=p_project_id
      and d.downstream_task_id=p_task_id
      and upstream.status <> 'completed'
  ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','upstream_tasks_incomplete')
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
        submitted_by,submitted_at
      ) values(
        v_round_id,p_project_id,p_task_id,v_round_number,
        v_first_file_version_id,v_submission_text,
        v_task.required_submission_file_type,
        v_actor,v_submitted_at
      );

      insert into public.task_review_round_files(
        review_round_id,project_id,task_id,file_version_id,position
      )
      select
        v_round_id,p_project_id,p_task_id,x.file_version_id,x.position::integer
      from unnest(p_file_version_ids) with ordinality
        as x(file_version_id,position);

      update public.tasks
      set status='awaiting_review',
          blocked_reason=null,
          first_submitted_at=coalesce(first_submitted_at,v_submitted_at),
          version=version+1,
          updated_at=now()
      where id=p_task_id
      returning * into v_task;

      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,
        'task_submitted_for_review','task_review_round',v_round_id,p_request_id,
        jsonb_strip_nulls(jsonb_build_object(
          'taskId',p_task_id,
          'roundNumber',v_round_number,
          'fileVersionId',v_first_file_version_id,
          'fileVersionIds',p_file_version_ids,
          'hasSubmissionText',v_submission_text is not null,
          'requiredSubmissionFileType',
            v_task.required_submission_file_type,
          'taskVersion',v_task.version
        ))
      );

      v_result:=jsonb_build_object(
        'ok',true,
        'data',jsonb_build_object(
          'taskId',p_task_id,
          'reviewRoundId',v_round_id,
          'roundNumber',v_round_number,
          'submittedAt',v_submitted_at
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

create or replace function private.notify_from_task_change_event()
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
    select 1
    from public.tasks t
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
    if v_recipient is null
       or not private.is_active_member(new.project_id,v_recipient) then
      return new;
    end if;
    perform private.create_notification(
      new.id,new.project_id,v_recipient,
      'task_change_confirmation','任务重要变更待确认',
      '任务的重要要求发生变更，等待你确认。',
      'task',v_task_id
    );
  elsif new.event_type='task_change_approved' then
    begin
      v_recipient:=nullif(new.event_data->>'proposerId','')::uuid;
    exception when invalid_text_representation then
      return new;
    end;
    if v_recipient is null
       or not private.is_active_member(new.project_id,v_recipient) then
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
    if v_recipient is null
       or not private.is_active_member(new.project_id,v_recipient) then
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

revoke all on function public.cmd_create_task(
  uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_task(
  uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text
) to authenticated;

revoke all on function public.cmd_edit_task(
  uuid,uuid,uuid,integer,text,text,timestamptz,smallint,text
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_edit_task(
  uuid,uuid,uuid,integer,text,text,timestamptz,smallint,text
) to authenticated;

revoke all on function public.cmd_propose_task_change(
  uuid,uuid,timestamptz,smallint,uuid,integer,text
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_propose_task_change(
  uuid,uuid,timestamptz,smallint,uuid,integer,text
) to authenticated;

revoke all on function public.cmd_submit_task_for_review(
  uuid,uuid,text,uuid[],uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_submit_task_for_review(
  uuid,uuid,text,uuid[],uuid,integer
) to authenticated;

revoke all on function public.cmd_respond_to_task_change(
  uuid,uuid,uuid,text,text,uuid,integer
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_respond_to_task_change(
  uuid,uuid,uuid,text,text,uuid,integer
) to authenticated;

revoke all on function private.notify_from_task_change_event()
from public,anon,authenticated,service_role;

comment on table public.task_review_round_files is
  'Immutable finalized file-version bindings captured by one formal task review round.';
comment on column public.tasks.required_submission_file_type is
  'Optional canonical file type that each formal submission must include at least once; not an allowlist.';
comment on column public.task_review_rounds.submission_text_snapshot is
  'Immutable normalized completion text submitted with this review round.';
comment on column public.task_review_rounds.required_submission_file_type_snapshot is
  'Immutable requirement in force when this review round was submitted.';
