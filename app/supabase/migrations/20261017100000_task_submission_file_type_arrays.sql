-- Canonical multi-format submission requirements with legacy scalar compatibility.
-- The array is authoritative. Existing scalar RPCs remain supported and project
-- their single value to a one-element array; v2 RPCs persist the complete set.

create function private.normalize_submission_file_types(p_types text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(t order by array_position(
    array['pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts','png','jpg','gif','webp']::text[],
    t
  )), '{}'::text[])
  from (
    select distinct x as t
    from unnest(coalesce(p_types, '{}'::text[])) as u(x)
    where x = any(array[
      'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    ]::text[])
  ) normalized;
$$;

create function private.is_valid_submission_file_types(p_types text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_types is not null
    and array_position(p_types, null) is null
    and cardinality(p_types) = (
      select count(distinct x)::integer
      from unnest(p_types) as values_set(x)
    )
    and not exists (
      select 1
      from unnest(p_types) as values_set(x)
      where x <> all(array[
        'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
        'png','jpg','gif','webp'
      ]::text[])
    )
    and p_types = private.normalize_submission_file_types(p_types);
$$;

-- The scalar projection must depend only on the payload. Deriving it from
-- current task state would make retries hash differently after a successful edit.
create function private.compat_submission_file_type(p_types text[])
returns text
language sql
immutable
set search_path = ''
as $$
  select case when cardinality(p_types)>0 then p_types[1] else null end;
$$;

revoke all on function private.normalize_submission_file_types(text[]) from public, anon, authenticated, service_role;
revoke all on function private.is_valid_submission_file_types(text[]) from public, anon, authenticated, service_role;
revoke all on function private.compat_submission_file_type(text[]) from public, anon, authenticated, service_role;

alter table public.tasks
  add column required_submission_file_types text[] not null default '{}'::text[];
update public.tasks
set required_submission_file_types = case
  when required_submission_file_type is null then '{}'::text[]
  else array[required_submission_file_type]::text[]
end;

alter table public.task_change_proposals
  add column old_required_submission_file_types text[] not null default '{}'::text[],
  add column new_required_submission_file_types text[] not null default '{}'::text[];
update public.task_change_proposals
set old_required_submission_file_types = case
      when old_required_submission_file_type is null then '{}'::text[]
      else array[old_required_submission_file_type]::text[]
    end,
    new_required_submission_file_types = case
      when new_required_submission_file_type is null then '{}'::text[]
      else array[new_required_submission_file_type]::text[]
    end;

alter table public.task_review_rounds
  add column required_submission_file_types_snapshot text[] not null default '{}'::text[];

-- This is a one-time schema backfill of immutable historical evidence. The
-- existing history trigger correctly blocks application-level edits to
-- terminal rounds, so disable only that trigger for the bounded backfill and
-- restore it immediately. Because migrations run transactionally, any failure
-- also rolls the trigger state back.
alter table public.task_review_rounds
  disable trigger task_review_rounds_protect_history;

update public.task_review_rounds
set required_submission_file_types_snapshot = case
  when required_submission_file_type_snapshot is null then '{}'::text[]
  else array[required_submission_file_type_snapshot]::text[]
end;

alter table public.task_review_rounds
  enable trigger task_review_rounds_protect_history;

alter table public.tasks drop constraint if exists tasks_required_submission_file_type;
alter table public.tasks
  add constraint tasks_required_submission_file_type check (
    required_submission_file_type is null or required_submission_file_type in (
      'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    )
  ),
  add constraint tasks_required_submission_file_types_valid check (
    private.is_valid_submission_file_types(required_submission_file_types)
  );

alter table public.task_change_proposals
  drop constraint if exists task_change_proposals_required_submission_file_type,
  add constraint task_change_proposals_required_submission_file_type check (
    (old_required_submission_file_type is null or old_required_submission_file_type in (
      'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    ))
    and
    (new_required_submission_file_type is null or new_required_submission_file_type in (
      'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    ))
  ),
  add constraint task_change_proposals_old_required_submission_file_types_valid check (
    private.is_valid_submission_file_types(old_required_submission_file_types)
  ),
  add constraint task_change_proposals_new_required_submission_file_types_valid check (
    private.is_valid_submission_file_types(new_required_submission_file_types)
  ),
  drop constraint if exists task_change_proposals_has_change,
  add constraint task_change_proposals_has_change check (
    new_deadline_at is distinct from old_deadline_at
    or new_weight is distinct from old_weight
    or new_required_submission_file_types is distinct from old_required_submission_file_types
  );

alter table public.task_review_rounds
  drop constraint if exists task_review_rounds_required_submission_file_type,
  add constraint task_review_rounds_required_submission_file_type check (
    required_submission_file_type_snapshot is null or required_submission_file_type_snapshot in (
      'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
      'png','jpg','gif','webp'
    )
  ),
  add constraint task_review_rounds_required_submission_file_types_valid check (
    private.is_valid_submission_file_types(required_submission_file_types_snapshot)
  );

-- Record the complete v2 payload separately because legacy RPC idempotency hashes
-- contain only the scalar projection. This prevents a reused request ID from
-- silently replaying a different set that happens to share the same first item.
create table private.task_submission_file_type_command_payloads (
  project_id uuid not null,
  actor_id uuid not null,
  command_name text not null,
  request_id uuid not null,
  required_types text[] not null,
  created_at timestamptz not null default transaction_timestamp(),
  primary key (project_id, actor_id, command_name, request_id),
  constraint task_submission_file_type_command_payloads_valid
    check (private.is_valid_submission_file_types(required_types))
);
alter table private.task_submission_file_type_command_payloads enable row level security;
revoke all on private.task_submission_file_type_command_payloads from public, anon, authenticated, service_role;

create function private.claim_task_submission_file_types_payload(
  p_project_id uuid,
  p_command_name text,
  p_request_id uuid,
  p_types text[]
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_existing text[];
begin
  if v_actor is null or p_project_id is null or p_command_name is null or p_request_id is null then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_project_id::text || ':' || v_actor::text || ':' || p_command_name || ':' || p_request_id::text,
    170017
  ));
  select required_types into v_existing
  from private.task_submission_file_type_command_payloads
  where project_id=p_project_id and actor_id=v_actor
    and command_name=p_command_name and request_id=p_request_id
  for update;
  if found then
    return v_existing = p_types;
  end if;
  insert into private.task_submission_file_type_command_payloads(
    project_id,actor_id,command_name,request_id,required_types
  ) values (p_project_id,v_actor,p_command_name,p_request_id,p_types);
  return true;
end;
$$;
revoke all on function private.claim_task_submission_file_types_payload(uuid,text,uuid,text[])
  from public, anon, authenticated, service_role;

create function private.sync_task_submission_file_types()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_override text;
  v_types text[];
begin
  v_override := nullif(current_setting('teamup.required_submission_file_types', true), '');
  if v_override is not null then
    if jsonb_typeof(v_override::jsonb) <> 'array' then
      raise exception using errcode='22023', message='INVALID_SUBMISSION_FILE_TYPES_OVERRIDE';
    end if;
    select coalesce(array_agg(value order by ordinality), '{}'::text[])
      into v_types
    from jsonb_array_elements_text(v_override::jsonb) with ordinality as e(value,ordinality);
    if not private.is_valid_submission_file_types(v_types) then
      raise exception using errcode='22023', message='INVALID_SUBMISSION_FILE_TYPES_OVERRIDE';
    end if;
    perform set_config('teamup.required_submission_file_types','',true);
  elsif tg_op='UPDATE'
        and new.required_submission_file_types is distinct from old.required_submission_file_types then
    v_types := private.normalize_submission_file_types(new.required_submission_file_types);
  elsif tg_op='UPDATE'
        and new.required_submission_file_type is not distinct from old.required_submission_file_type then
    v_types := old.required_submission_file_types;
  elsif new.required_submission_file_type is null then
    v_types := '{}'::text[];
  else
    v_types := array[new.required_submission_file_type]::text[];
  end if;

  if not private.is_valid_submission_file_types(v_types) then
    raise exception using errcode='23514', message='INVALID_SUBMISSION_FILE_TYPES';
  end if;
  new.required_submission_file_types := v_types;
  new.required_submission_file_type := case
    when cardinality(v_types)>0 then v_types[1] else null end;
  return new;
end;
$$;
revoke all on function private.sync_task_submission_file_types() from public, anon, authenticated, service_role;
create trigger tasks_sync_submission_file_types
before insert or update on public.tasks
for each row execute function private.sync_task_submission_file_types();

create function private.sync_task_change_proposal_submission_file_types()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_override text;
  v_types text[];
  v_task_types text[];
begin
  if tg_op='INSERT' then
    select t.required_submission_file_types
      into v_task_types
    from public.tasks t
    where t.id=new.task_id and t.project_id=new.project_id;
    if not found then
      raise exception using errcode='23503', message='TASK_REQUIRED_FOR_SUBMISSION_TYPE_PROPOSAL';
    end if;
    new.old_required_submission_file_types := v_task_types;
    v_override := nullif(current_setting('teamup.required_submission_file_types', true), '');
    if v_override is not null then
      if jsonb_typeof(v_override::jsonb) <> 'array' then
        raise exception using errcode='22023', message='INVALID_SUBMISSION_FILE_TYPES_OVERRIDE';
      end if;
      select coalesce(array_agg(value order by ordinality), '{}'::text[])
        into v_types
      from jsonb_array_elements_text(v_override::jsonb) with ordinality as e(value,ordinality);
      if not private.is_valid_submission_file_types(v_types) then
        raise exception using errcode='22023', message='INVALID_SUBMISSION_FILE_TYPES_OVERRIDE';
      end if;
      new.new_required_submission_file_types := v_types;
      perform set_config('teamup.required_submission_file_types','',true);
    elsif new.new_required_submission_file_type is null then
      new.new_required_submission_file_types := '{}'::text[];
    else
      new.new_required_submission_file_types := array[new.new_required_submission_file_type]::text[];
    end if;
  elsif tg_op='UPDATE' then
    if not private.is_valid_submission_file_types(new.old_required_submission_file_types)
       or not private.is_valid_submission_file_types(new.new_required_submission_file_types) then
      raise exception using errcode='23514', message='INVALID_SUBMISSION_FILE_TYPES';
    end if;

  end if;

  if not private.is_valid_submission_file_types(new.old_required_submission_file_types)
     or not private.is_valid_submission_file_types(new.new_required_submission_file_types) then
    raise exception using errcode='23514', message='INVALID_SUBMISSION_FILE_TYPES';
  end if;
  new.old_required_submission_file_type := case
    when cardinality(new.old_required_submission_file_types)>0 then new.old_required_submission_file_types[1]
    else null end;
  new.new_required_submission_file_type := case
    when cardinality(new.new_required_submission_file_types)>0 then new.new_required_submission_file_types[1]
    else null end;
  return new;
end;
$$;
revoke all on function private.sync_task_change_proposal_submission_file_types() from public, anon, authenticated, service_role;
create trigger task_change_proposals_sync_submission_file_types
before insert or update on public.task_change_proposals
for each row execute function private.sync_task_change_proposal_submission_file_types();

create function private.sync_task_review_round_submission_file_types()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
begin
  if tg_op='INSERT' then
    select t.required_submission_file_types into v_types
    from public.tasks t
    where t.id=new.task_id and t.project_id=new.project_id;
    if not found then
      raise exception using errcode='23503', message='TASK_REQUIRED_FOR_REVIEW_SNAPSHOT';
    end if;
    new.required_submission_file_types_snapshot := v_types;
    new.required_submission_file_type_snapshot := case
      when cardinality(v_types)>0 then v_types[1] else null end;
  elsif new.required_submission_file_types_snapshot is distinct from old.required_submission_file_types_snapshot
     or new.required_submission_file_type_snapshot is distinct from old.required_submission_file_type_snapshot then
    raise exception using errcode='23514', message='REVIEW_ROUND_SUBMISSION_REQUIREMENT_SNAPSHOT_IMMUTABLE';
  end if;
  return new;
end;
$$;
revoke all on function private.sync_task_review_round_submission_file_types() from public, anon, authenticated, service_role;
create trigger task_review_rounds_sync_submission_file_types
before insert or update on public.task_review_rounds
for each row execute function private.sync_task_review_round_submission_file_types();

create or replace view public.task_change_proposals_visible with(security_barrier=true) as
select t.id,
       t.project_id,
       t.task_id,
       t.proposed_by,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.proposed_by and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.proposer_name_snapshot end as proposer_name_snapshot,
       t.state,
       t.old_deadline_at,
       t.new_deadline_at,
       t.old_weight,
       t.new_weight,
       t.base_task_version,
       t.required_confirmer_id,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.required_confirmer_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.required_confirmer_name_snapshot end as required_confirmer_name_snapshot,
       t.decided_at,
       t.decided_by,
       t.decision_reason,
       t.version,
       t.created_at,
       t.updated_at,
       t.old_required_submission_file_type,
       t.new_required_submission_file_type,
       t.old_required_submission_file_types,
       t.new_required_submission_file_types
from public.task_change_proposals t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);

revoke all on public.task_change_proposals_visible from public, anon, authenticated, service_role;
grant select on public.task_change_proposals_visible to authenticated;

-- Extend the privacy inventory for the new structured array columns and the
-- private idempotency records. These are classifications for review, not PII
-- erasure approvals.
insert into private.lifecycle_pii_classifications(
  schema_name,table_name,column_name,data_type,classification
)
select c->>'schema',c->>'table',c->>'column',c->>'type','structured'
from jsonb_array_elements(private.f2_privacy_schema()->'columns') c
where (c->>'schema',c->>'table',c->>'column') in (
  ('public','tasks','required_submission_file_types'),
  ('public','task_change_proposals','old_required_submission_file_types'),
  ('public','task_change_proposals','new_required_submission_file_types'),
  ('public','task_review_rounds','required_submission_file_types_snapshot'),
  ('private','task_submission_file_type_command_payloads','required_types'),
  ('private','task_submission_file_type_command_payloads','command_name'),
  ('private','task_submission_file_type_command_payloads','created_at')
)
on conflict(schema_name,table_name,column_name) do update
set data_type=excluded.data_type,classification=excluded.classification;
insert into private.lifecycle_pii_classifications(
  schema_name,table_name,column_name,data_type,classification
)
select c->>'schema',c->>'table',c->>'column',c->>'type','identity_reference'
from jsonb_array_elements(private.f2_privacy_schema()->'columns') c
where (c->>'schema',c->>'table',c->>'column') in (
  ('private','task_submission_file_type_command_payloads','project_id'),
  ('private','task_submission_file_type_command_payloads','actor_id'),
  ('private','task_submission_file_type_command_payloads','request_id')
)
on conflict(schema_name,table_name,column_name) do update
set data_type=excluded.data_type,classification=excluded.classification;

create function public.cmd_create_task_v2(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_title text,
  p_description text default null,
  p_deadline_at timestamptz default null,
  p_weight smallint default null,
  p_assignment_mode text default 'claimable',
  p_assignee_id uuid default null,
  p_required_submission_file_types text[] default '{}'::text[],
  p_requires_review boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[] := private.normalize_submission_file_types(p_required_submission_file_types);
  v_result jsonb;
  v_compat text;
begin
  if auth.uid() is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not private.is_valid_submission_file_types(p_required_submission_file_types) then
    return private.failure(p_request_id,'VALIDATION_FAILED','requiredSubmissionFileTypes');
  end if;
  if not private.claim_task_submission_file_types_payload(
    p_project_id,'cmd_create_task_v2',p_request_id,v_types
  ) then
    return private.failure(p_request_id,'IDEMPOTENCY_KEY_REUSED');
  end if;
  v_compat := case when cardinality(v_types)>0 then v_types[1] else null end;
  perform set_config('teamup.required_submission_file_types',to_json(v_types)::text,true);
  v_result := public.cmd_create_task(
    p_project_id,p_request_id,p_expected_version,p_title,p_description,p_deadline_at,
    p_weight,p_assignment_mode,p_assignee_id,v_compat,p_requires_review
  );
  perform set_config('teamup.required_submission_file_types','',true);
  return v_result;
end;
$$;
revoke all on function public.cmd_create_task_v2(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text[],boolean)
  from public, anon, service_role;
grant execute on function public.cmd_create_task_v2(uuid,uuid,integer,text,text,timestamptz,smallint,text,uuid,text[],boolean)
  to authenticated;

create function public.cmd_edit_task_v2(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_title text,
  p_description text,
  p_deadline_at timestamptz,
  p_weight smallint,
  p_required_submission_file_types text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[] := private.normalize_submission_file_types(p_required_submission_file_types);
  v_compat text;
  v_result jsonb;
begin
  if auth.uid() is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not private.is_valid_submission_file_types(p_required_submission_file_types) then
    return private.failure(p_request_id,'VALIDATION_FAILED','requiredSubmissionFileTypes');
  end if;
  if not private.claim_task_submission_file_types_payload(
    p_project_id,'cmd_edit_task_v2',p_request_id,v_types
  ) then
    return private.failure(p_request_id,'IDEMPOTENCY_KEY_REUSED');
  end if;
  v_compat := private.compat_submission_file_type(v_types);
  perform set_config('teamup.required_submission_file_types',to_json(v_types)::text,true);
  v_result := public.cmd_edit_task(
    p_project_id,p_task_id,p_request_id,p_expected_version,p_title,p_description,
    p_deadline_at,p_weight,v_compat
  );
  perform set_config('teamup.required_submission_file_types','',true);
  return v_result;
end;
$$;
revoke all on function public.cmd_edit_task_v2(uuid,uuid,uuid,integer,text,text,timestamptz,smallint,text[])
  from public, anon, service_role;
grant execute on function public.cmd_edit_task_v2(uuid,uuid,uuid,integer,text,text,timestamptz,smallint,text[])
  to authenticated;

create function public.cmd_propose_task_change_v2(
  p_project_id uuid,
  p_task_id uuid,
  p_deadline_at timestamptz,
  p_weight smallint,
  p_request_id uuid,
  p_expected_task_version integer,
  p_required_submission_file_types text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[] := private.normalize_submission_file_types(p_required_submission_file_types);
  v_compat text;
  v_result jsonb;
begin
  if auth.uid() is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not private.is_valid_submission_file_types(p_required_submission_file_types) then
    return private.failure(p_request_id,'VALIDATION_FAILED','requiredSubmissionFileTypes');
  end if;
  if not private.claim_task_submission_file_types_payload(
    p_project_id,'cmd_propose_task_change_v2',p_request_id,v_types
  ) then
    return private.failure(p_request_id,'IDEMPOTENCY_KEY_REUSED');
  end if;
  v_compat := private.compat_submission_file_type(v_types);
  perform set_config('teamup.required_submission_file_types',to_json(v_types)::text,true);
  v_result := public.cmd_propose_task_change(
    p_project_id,p_task_id,p_deadline_at,p_weight,p_request_id,
    p_expected_task_version,v_compat
  );
  perform set_config('teamup.required_submission_file_types','',true);
  return v_result;
end;
$$;
revoke all on function public.cmd_propose_task_change_v2(uuid,uuid,timestamptz,smallint,uuid,integer,text[])
  from public, anon, service_role;
grant execute on function public.cmd_propose_task_change_v2(uuid,uuid,timestamptz,smallint,uuid,integer,text[])
  to authenticated;


-- Keep the scalar RPC compatibility validators aware of the newly supported DOC type.

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
  v_required_types text[];
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
          'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
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

    select required_submission_file_types into v_required_types
    from public.tasks where id=v_task_id;

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
        'requiredSubmissionFileTypes',v_required_types,
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
          case when v_offer_id is null then null else 1 end,
        'requiredSubmissionFileTypes',v_required_types
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

create or replace function public.cmd_edit_task(
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
  v_required_override text;
  v_requested_required_submission_file_types text[];
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
          'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
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
    v_required_override:=nullif(current_setting('teamup.required_submission_file_types',true),'');
    if v_required_override is not null then
      select coalesce(array_agg(value order by ordinality),'{}'::text[])
        into v_requested_required_submission_file_types
      from jsonb_array_elements_text(v_required_override::jsonb) with ordinality as e(value,ordinality);
    elsif p_required_submission_file_type is not distinct from v_task.required_submission_file_type then
      v_requested_required_submission_file_types:=v_task.required_submission_file_types;
    elsif p_required_submission_file_type is null then
      v_requested_required_submission_file_types:='{}'::text[];
    else
      v_requested_required_submission_file_types:=array[p_required_submission_file_type]::text[];
    end if;

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
          and v_requested_required_submission_file_types is distinct from v_task.required_submission_file_types then
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
      if v_requested_required_submission_file_types is distinct from v_task.required_submission_file_types then
        v_changed_fields:=v_changed_fields || jsonb_build_array('requiredSubmissionFileTypes');
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
            'requiredSubmissionFileType',v_task.required_submission_file_type,
            'requiredSubmissionFileTypes',v_task.required_submission_file_types
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
          'requiredSubmissionFileType',v_task.required_submission_file_type,
          'requiredSubmissionFileTypes',v_task.required_submission_file_types
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
          'requiredSubmissionFileType',v_task.required_submission_file_type,
          'requiredSubmissionFileTypes',v_task.required_submission_file_types
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

create or replace function public.cmd_propose_task_change(
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
  v_required_override text;
  v_requested_required_submission_file_types text[];
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
          'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType',v_task.version
    );
  else
    v_required_override:=nullif(current_setting('teamup.required_submission_file_types',true),'');
    if v_required_override is not null then
      select coalesce(array_agg(value order by ordinality),'{}'::text[])
        into v_requested_required_submission_file_types
      from jsonb_array_elements_text(v_required_override::jsonb) with ordinality as e(value,ordinality);
    elsif p_required_submission_file_type is not distinct from v_task.required_submission_file_type then
      v_requested_required_submission_file_types:=v_task.required_submission_file_types;
    elsif p_required_submission_file_type is null then
      v_requested_required_submission_file_types:='{}'::text[];
    else
      v_requested_required_submission_file_types:=array[p_required_submission_file_type]::text[];
    end if;

    v_deadline_changed:=p_deadline_at is distinct from v_task.deadline_at;
    v_weight_changed:=p_weight is distinct from v_task.weight;
    v_requirement_changed:=
      v_requested_required_submission_file_types is distinct from v_task.required_submission_file_types;

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
            'newRequiredSubmissionFileType',v_proposal.new_required_submission_file_type,
            'oldRequiredSubmissionFileTypes',v_proposal.old_required_submission_file_types,
            'newRequiredSubmissionFileTypes',v_proposal.new_required_submission_file_types
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

-- Submission checks use the complete array with OR semantics.

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
    elsif cardinality(v_task.required_submission_file_types)>0
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
                  = any(v_task.required_submission_file_types)
          ) then
      v_result:=private.failure(
        p_request_id,'VALIDATION_FAILED','fileVersionIds',v_task.version,
        jsonb_build_object(
          'reason','required_file_type_missing',
          'requiredFileType',v_task.required_submission_file_type,
          'requiredFileTypes',v_task.required_submission_file_types
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
          'requiredSubmissionFileTypes',
            v_task.required_submission_file_types,
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


-- Approval must set the array override before updating the task; the proposal UPDATE occurs afterwards.
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
           is distinct from v_proposal.old_required_submission_file_type
        or v_task.required_submission_file_types
           is distinct from v_proposal.old_required_submission_file_types then
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
          'pdf','doc','docx','xlsx','pptx','csv','txt','md','json','xml','css','js','ts',
          'png','jpg','gif','webp'
        ) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','requiredSubmissionFileType',
      v_proposal.version
    );
  else
    v_decided_at:=now();

    if p_action='approve' then
      perform set_config(
        'teamup.required_submission_file_types',
        to_json(v_proposal.new_required_submission_file_types)::text,
        true
      );
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
        'oldRequiredSubmissionFileTypes',
          v_proposal.old_required_submission_file_types,
        'newRequiredSubmissionFileTypes',
          v_proposal.new_required_submission_file_types,
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
