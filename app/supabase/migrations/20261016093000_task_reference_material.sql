-- Task reference material: distinguish creator-provided templates/source material
-- from participant deliverables while reusing the existing private Storage pipeline.

alter table public.task_files
  add column purpose text not null default 'deliverable';

alter table public.task_files
  add constraint task_files_purpose_check
  check (purpose in ('deliverable','reference'));

comment on column public.task_files.purpose is
  'Semantic file role. reference files are task inputs and must never be offered as submission deliverables.';

do $$
begin
  insert into private.lifecycle_pii_classifications
    (schema_name,table_name,column_name,data_type,classification,disposition)
  values ('public','task_files','purpose','text','structured','manual_review_required')
  on conflict (schema_name,table_name,column_name) do nothing;

  if not exists (
    select 1 from private.lifecycle_pii_classifications
    where schema_name='public' and table_name='task_files'
      and column_name='purpose' and data_type='text'
      and classification='structured'
      and disposition='manual_review_required'
  ) then
    raise exception 'TASK_FILE_PURPOSE_PRIVACY_CLASSIFICATION_MISMATCH';
  end if;
end;
$$;

create or replace view public.task_files_visible with(security_barrier=true) as
select t.id,
       t.project_id,
       t.task_id,
       case
         when exists(
           select 1
           from public.account_lifecycle_requests l
           where l.user_id=t.created_by
             and l.state in ('pending','blocked','redacted')
         )
           then '已注销成员文件'::text
         else t.logical_name
       end as logical_name,
       case
         when exists(
           select 1
           from public.account_lifecycle_requests l
           where l.user_id=t.created_by
             and l.state in ('pending','blocked','redacted')
         )
           then null::uuid
         else t.created_by
       end as created_by,
       t.current_version_id,
       t.version,
       t.created_at,
       t.updated_at,
       t.purpose
from public.task_files t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);

revoke all on public.task_files_visible
  from public,anon,authenticated,service_role;
grant select on public.task_files_visible to authenticated;

create function public.cmd_mark_task_file_reference(
  p_project_id uuid,
  p_task_id uuid,
  p_file_id uuid,
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
  v_file public.task_files%rowtype;
begin
  if v_actor is null then
    return private.failure(p_request_id,'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null,'VALIDATION_FAILED','requestId');
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash := private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'taskId',p_task_id,
    'fileId',p_file_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_mark_task_file_reference',p_request_id,v_hash,null,p_project_id
  );
  v_result := private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay := private.replay_or_reuse(
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

  select * into v_file
  from public.task_files f
  where f.id=p_file_id and f.project_id=p_project_id and f.task_id=p_task_id
  for update;

  if v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.id is null or v_file.id is null then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_task.created_by is distinct from v_actor
        and not private.is_active_leader(p_project_id,v_actor) then
    v_result := private.failure(p_request_id,'NOT_AUTHORIZED');
  elsif exists (
    select 1 from public.task_review_rounds r
    where r.project_id=p_project_id and r.task_id=p_task_id
  ) then
    v_result := private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_file.version,
      jsonb_build_object('reason','task_already_submitted')
    );
  elsif p_expected_version is null or v_file.version <> p_expected_version then
    v_result := private.failure(p_request_id,'STALE_VERSION',null,v_file.version);
  elsif v_file.purpose = 'reference' then
    v_result := jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',v_task.id,'fileId',v_file.id,'purpose','reference',
        'fileVersion',v_file.version,'changed',false
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_file','aggregateId',v_file.id,
      'aggregateVersion',v_file.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_file',v_file.id,v_file.version
    );
  else
    update public.task_files
    set purpose='reference',version=version+1,updated_at=now()
    where id=v_file.id
    returning * into v_file;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_reference_file_marked','task_file',v_file.id,p_request_id,
      jsonb_build_object(
        'taskId',v_task.id,'fileId',v_file.id,'fileVersion',v_file.version
      )
    );

    v_result := jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'taskId',v_task.id,'fileId',v_file.id,'purpose','reference',
        'fileVersion',v_file.version,'changed',true
      ),
      'requestId',p_request_id,'replayed',false,
      'aggregateType','task_file','aggregateId',v_file.id,
      'aggregateVersion',v_file.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_file',v_file.id,v_file.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_mark_task_file_reference(uuid,uuid,uuid,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_mark_task_file_reference(uuid,uuid,uuid,uuid,integer)
  to authenticated;

create function private.reject_reference_submission_attachment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.task_file_versions fv
    join public.task_files f
      on f.id=fv.file_id
     and f.project_id=fv.project_id
     and f.task_id=fv.task_id
    where fv.id=new.file_version_id
      and f.purpose='reference'
  ) then
    raise exception using
      errcode='23514',
      constraint='task_review_round_files_deliverable_only',
      message='Reference material cannot be submitted as a deliverable';
  end if;
  return new;
end;
$$;

revoke all on function private.reject_reference_submission_attachment()
  from public,anon,authenticated,service_role;

create trigger task_review_round_files_reject_reference
before insert or update of file_version_id
on public.task_review_round_files
for each row execute function private.reject_reference_submission_attachment();

create function private.reject_reference_final_designation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.task_file_versions fv
    join public.task_files f
      on f.id=fv.file_id
     and f.project_id=fv.project_id
     and f.task_id=fv.task_id
    where fv.id=new.file_version_id
      and f.purpose='reference'
  ) then
    raise exception using
      errcode='23514',
      constraint='task_file_final_designations_deliverable_only',
      message='Reference material cannot be marked as a final deliverable';
  end if;
  return new;
end;
$$;

revoke all on function private.reject_reference_final_designation()
  from public,anon,authenticated,service_role;

create trigger task_file_final_designations_reject_reference
before insert or update of file_version_id
on public.task_file_final_designations
for each row execute function private.reject_reference_final_designation();

create or replace function public.get_task_files_f2_unmasked(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_project_id uuid;
  v_files jsonb;
begin
  if v_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;

  select t.project_id into v_project_id
  from public.tasks t
  where t.id = p_task_id;

  if v_project_id is null or not private.is_active_member(v_project_id, v_actor) then
    return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fileId', f.id,
        'logicalName', f.logical_name,
        'purpose', f.purpose,
        'currentVersionId', f.current_version_id,
        'version', f.version,
        'createdBy', f.created_by,
        'createdAt', f.created_at,
        'updatedAt', f.updated_at,
        'versions', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'fileVersionId', v.id,
              'versionNumber', v.version_number,
              'objectPath', v.object_path,
              'originalName', v.original_name,
              'mimeType', v.mime_type,
              'sizeBytes', v.size_bytes,
              'sha256Hex', v.sha256_hex,
              'uploadedBy', v.uploaded_by,
              'restoredFromVersionId', v.restored_from_version_id,
              'createdAt', v.created_at
            )
            order by v.version_number
          )
          from public.task_file_versions v
          where v.file_id = f.id
        ), '[]'::jsonb)
      )
      order by f.created_at, f.id
    ),
    '[]'::jsonb
  ) into v_files
  from public.task_files f
  where f.task_id = p_task_id and f.project_id = v_project_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('taskId', p_task_id, 'files', v_files)
  );
end;
$$;

revoke all on function public.get_task_files_f2_unmasked(uuid)
  from public,anon,authenticated,service_role;
