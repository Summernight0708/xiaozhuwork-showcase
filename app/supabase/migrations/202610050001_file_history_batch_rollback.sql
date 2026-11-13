-- Full task-file history and DB-atomic batch rollback.
-- Rollbacks append new version rows that reference an existing finalized object.

alter table public.task_file_versions
  drop constraint if exists task_file_versions_object_path_unique;

alter table public.file_upload_reservations
  drop constraint if exists file_upload_reservations_object_path_key;

create unique index if not exists task_file_versions_uploaded_object_path_unique_idx
  on public.task_file_versions (object_path)
  where restored_from_version_id is null;

create unique index if not exists file_upload_reservations_live_object_path_unique
  on public.file_upload_reservations (object_path)
  where state = 'reserved';

create function public.get_task_file_history(
  p_file_id uuid,
  p_limit integer default 50,
  p_before_version integer default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_file public.task_files%rowtype;
  v_limit integer;
  v_versions jsonb;
begin
  if v_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);

  select * into v_file
  from public.task_files f
  where f.id = p_file_id;

  if not found or not private.is_active_member(v_file.project_id, v_actor) then
    return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fileVersionId', v.id,
        'versionNumber', v.version_number,
        'originalName', v.original_name,
        'mimeType', v.mime_type,
        'sizeBytes', v.size_bytes,
        'sha256Hex', v.sha256_hex,
        'uploadedBy', v.uploaded_by,
        'restoredFromVersionId', v.restored_from_version_id,
        'createdAt', v.created_at
      )
      order by v.version_number desc, v.id desc
    ),
    '[]'::jsonb
  ) into v_versions
  from (
    select *
    from public.task_file_versions fv
    where fv.file_id = v_file.id
      and (p_before_version is null or fv.version_number < p_before_version)
    order by fv.version_number desc, fv.id desc
    limit v_limit
  ) v;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'fileId', v_file.id,
      'projectId', v_file.project_id,
      'taskId', v_file.task_id,
      'currentVersionId', v_file.current_version_id,
      'currentFileVersion', v_file.version,
      'limit', v_limit,
      'beforeVersion', p_before_version,
      'versions', v_versions
    )
  );
end;
$$;

create function public.cmd_batch_rollback_task_files(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_items jsonb
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
  v_item jsonb;
  v_item_count integer;
  v_file_id uuid;
  v_restore_version_id uuid;
  v_expected_file_version integer;
  v_file public.task_files%rowtype;
  v_source public.task_file_versions%rowtype;
  v_reservation_id uuid;
  v_new_version_id uuid;
  v_new_version_number integer;
  v_details jsonb := '[]'::jsonb;
  v_seq integer := 0;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if p_project_id is null then
    return private.failure(p_request_id, 'VALIDATION_FAILED', 'projectId');
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
  end if;

  select jsonb_array_length(p_items) into v_item_count;
  if v_item_count < 1 or v_item_count > 50 then
    return private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
  end if;

  if exists (
    select 1
    from (
      select item->>'fileId' as file_id
      from jsonb_array_elements(p_items) item
    ) d
    group by d.file_id
    having count(*) > 1
  ) then
    return private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
  end if;

  perform set_config('lock_timeout', '5s', true);

  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id,
    'expectedVersion', p_expected_version,
    'items', p_items
  ));
  select * into v_claim
  from private.claim_command(
    v_actor, 'cmd_batch_rollback_task_files', p_request_id, v_hash, null, p_project_id
  );

  select * into v_project
  from public.projects p
  where p.id = p_project_id
  for update;

  v_result := private.reject_unless_authorized(
    v_project.id is not null and private.is_active_member(p_project_id, v_actor),
    p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;

  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then
    return v_replay;
  end if;

  if p_expected_version is null or p_expected_version <> v_project.version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_project.version);
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    begin
      v_file_id := (v_item->>'fileId')::uuid;
      v_restore_version_id := (v_item->>'restoreVersionId')::uuid;
      v_expected_file_version := (v_item->>'expectedVersion')::integer;
    exception
      when invalid_text_representation then
        v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
        return private.complete_command(v_claim.command_id, v_result);
    end;

    if v_file_id is null or v_restore_version_id is null or v_expected_file_version is null then
      v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    select * into v_file
    from public.task_files f
    where f.id = v_file_id
      and f.project_id = p_project_id
    for update;

    if not found then
      v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    if not private.is_current_task_file_actor(v_file.project_id, v_file.task_id, v_actor) then
      v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    select * into v_source
    from public.task_file_versions fv
    where fv.id = v_restore_version_id
      and fv.file_id = v_file.id
      and fv.project_id = p_project_id
      and fv.task_id = v_file.task_id;

    if not found then
      v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    if v_file.current_version_id = v_restore_version_id then
      v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'restoreVersionId');
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    if v_file.version <> v_expected_file_version then
      v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_file.version);
      return private.complete_command(v_claim.command_id, v_result);
    end if;

    v_reservation_id := extensions.gen_random_uuid();
    v_new_version_id := extensions.gen_random_uuid();
    v_new_version_number := v_file.version + 1;

    insert into public.file_upload_reservations (
      id, project_id, task_id, actor_id, mode, target_file_id, target_file_version,
      object_path, original_name, declared_mime_type, declared_size_bytes,
      state, expires_at, version
    ) values (
      v_reservation_id, p_project_id, v_file.task_id, v_actor, 'new_version',
      v_file.id, v_file.version, v_source.object_path, v_source.original_name,
      v_source.mime_type, v_source.size_bytes, 'finalized', now(), 2
    );

    insert into public.task_file_versions (
      id, file_id, project_id, task_id, reservation_id, version_number,
      object_path, original_name, mime_type, size_bytes, sha256_hex,
      uploaded_by, restored_from_version_id
    ) values (
      v_new_version_id, v_file.id, p_project_id, v_file.task_id,
      v_reservation_id, v_new_version_number, v_source.object_path,
      v_source.original_name, v_source.mime_type, v_source.size_bytes,
      v_source.sha256_hex, v_actor, v_source.id
    );

    update public.task_files
    set current_version_id = v_new_version_id,
        version = version + 1,
        updated_at = now()
    where id = v_file.id;

    v_seq := v_seq + 1;
    perform private.emit_event(
      v_claim.command_id, v_seq, p_project_id, v_actor,
      'task_file_version_rolled_back', 'task_file', v_file.id, p_request_id,
      jsonb_build_object(
        'taskId', v_file.task_id,
        'fileId', v_file.id,
        'restoredFromVersionId', v_source.id,
        'newFileVersionId', v_new_version_id,
        'previousFileVersionId', v_file.current_version_id,
        'previousVersionNumber', v_file.version,
        'newVersionNumber', v_new_version_number
      )
    );

    v_details := v_details || jsonb_build_array(jsonb_build_object(
      'fileId', v_file.id,
      'taskId', v_file.task_id,
      'restoredFromVersionId', v_source.id,
      'newFileVersionId', v_new_version_id,
      'previousFileVersionId', v_file.current_version_id,
      'previousVersionNumber', v_file.version,
      'newVersionNumber', v_new_version_number
    ));
  end loop;

  update public.projects
  set version = version + 1,
      updated_at = now()
  where id = p_project_id
  returning * into v_project;

  v_result := jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'projectId', p_project_id,
      'rolledBack', v_details
    ),
    'requestId', p_request_id,
    'replayed', false,
    'aggregateType', 'project',
    'aggregateId', p_project_id,
    'aggregateVersion', v_project.version
  );

  return private.complete_command(
    v_claim.command_id, v_result, 'project', p_project_id, v_project.version
  );
end;
$$;

revoke all on function public.get_task_file_history(uuid,integer,integer)
  from public, anon, authenticated, service_role;
revoke all on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  from public, anon, authenticated, service_role;

grant execute on function public.get_task_file_history(uuid,integer,integer)
  to authenticated;
grant execute on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  to authenticated;

comment on function public.get_task_file_history(uuid,integer,integer) is
  'Reads stable, newest-first immutable task-file history for active project members without exposing cross-project files.';
comment on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb) is
  'DB-atomic append-only rollback command. Each item has fileId, restoreVersionId, and expectedVersion; no Storage mutation is performed.';
