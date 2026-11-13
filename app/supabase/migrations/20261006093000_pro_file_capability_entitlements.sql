-- P3: release verified Pro file capabilities and gate their public RPCs.
-- Business authorization remains independent from commercial entitlement:
-- business permission AND released capability entitlement.

create or replace function private.capability_is_released(
  p_capability text
) returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    p_capability = any(array[
      'file_full_history',
      'file_batch_rollback',
      'file_version_compare',
      'project_recovery_point'
    ]::text[]),
    false
  );
$$;

create or replace function private.project_has_capability(
  p_project_id uuid,
  p_capability text
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
begin
  if not private.capability_is_released(p_capability) then
    return false;
  end if;

  select *
  into v_entitlement
  from private.resolve_project_entitlement(
    p_project_id,
    transaction_timestamp()
  );

  return coalesce(v_entitlement.state in ('active','grace'), false);
end;
$$;

create or replace function private.project_capability_failure(
  p_project_id uuid,
  p_capability text,
  p_request_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.capability_is_released(p_capability) then
    return private.failure(p_request_id, 'CAPABILITY_NOT_AVAILABLE');
  end if;

  if not private.project_has_capability(p_project_id, p_capability) then
    return private.failure(p_request_id, 'CAPABILITY_REQUIRES_PRO');
  end if;

  return null;
end;
$$;

revoke all on function private.capability_is_released(text),
  private.project_has_capability(uuid,text),
  private.project_capability_failure(uuid,text,uuid)
from public, anon, authenticated, service_role;

-- Full history remains available to Free projects, but only inside the newest
-- ten-version window. Pro and Grace projects retain normal pagination across
-- the complete immutable history.
create or replace function public.get_task_file_history(
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
  v_has_full_history boolean;
  v_limit integer;
  v_oldest_allowed_version integer;
  v_versions jsonb;
begin
  if v_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;

  select *
  into v_file
  from public.task_files f
  where f.id = p_file_id;

  if not found or not private.is_active_member(v_file.project_id, v_actor) then
    return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_has_full_history := private.project_has_capability(
    v_file.project_id,
    'file_full_history'
  );

  v_limit := least(
    greatest(coalesce(p_limit, 50), 1),
    case when v_has_full_history then 100 else 10 end
  );

  if not v_has_full_history then
    select min(recent.version_number)
    into v_oldest_allowed_version
    from (
      select fv.version_number
      from public.task_file_versions fv
      where fv.file_id = v_file.id
      order by fv.version_number desc, fv.id desc
      limit 10
    ) recent;
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
  )
  into v_versions
  from (
    select *
    from public.task_file_versions fv
    where fv.file_id = v_file.id
      and (p_before_version is null or fv.version_number < p_before_version)
      and (
        v_has_full_history
        or v_oldest_allowed_version is null
        or fv.version_number >= v_oldest_allowed_version
      )
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

comment on function public.get_task_file_history(uuid,integer,integer) is
  'Reads immutable task-file history for active project members. Free projects are server-capped to the newest ten versions across pagination; released Pro/Grace projects can page through complete history.';

-- Keep the teammate implementations intact behind private implementation
-- functions. Public wrappers perform business authorization first, then the
-- centralized entitlement gate, then delegate to the original command logic.
alter function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  set schema private;
alter function private.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  rename to cmd_batch_rollback_task_files_impl;
revoke all on function private.cmd_batch_rollback_task_files_impl(uuid,uuid,integer,jsonb)
  from public, anon, authenticated, service_role;

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
  v_item jsonb;
  v_file_id uuid;
  v_restore_version_id uuid;
  v_file public.task_files%rowtype;
  v_source public.task_file_versions%rowtype;
  v_capability_failure jsonb;
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

  if not exists (
    select 1
    from public.projects p
    where p.id = p_project_id
  ) or not private.is_active_member(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  -- Resolve every referenced file and task-file authority before checking
  -- entitlement so Pro status cannot be inferred through an authorization
  -- error. The private implementation repeats and locks these checks.
  for v_item in select value from jsonb_array_elements(p_items) loop
    begin
      v_file_id := (v_item->>'fileId')::uuid;
      v_restore_version_id := (v_item->>'restoreVersionId')::uuid;
    exception
      when invalid_text_representation then
        return private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
    end;

    if v_file_id is null or v_restore_version_id is null then
      return private.failure(p_request_id, 'VALIDATION_FAILED', 'items');
    end if;

    select *
    into v_file
    from public.task_files f
    where f.id = v_file_id
      and f.project_id = p_project_id;

    if not found
       or not private.is_current_task_file_actor(
         v_file.project_id,
         v_file.task_id,
         v_actor
       ) then
      return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
    end if;

    select *
    into v_source
    from public.task_file_versions fv
    where fv.id = v_restore_version_id
      and fv.file_id = v_file.id
      and fv.project_id = p_project_id
      and fv.task_id = v_file.task_id;

    if not found then
      return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
    end if;
  end loop;

  v_capability_failure := private.project_capability_failure(
    p_project_id,
    'file_batch_rollback',
    p_request_id
  );
  if v_capability_failure is not null then
    return v_capability_failure;
  end if;

  return private.cmd_batch_rollback_task_files_impl(
    p_project_id,
    p_request_id,
    p_expected_version,
    p_items
  );
end;
$$;

revoke all on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb)
  to authenticated;

comment on function public.cmd_batch_rollback_task_files(uuid,uuid,integer,jsonb) is
  'Pro file batch rollback gate. Existing task/file authority is required before the released file_batch_rollback capability; the private implementation preserves atomic rollback, concurrency, and idempotency semantics.';

alter function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
  set schema private;
alter function private.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
  rename to cmd_compare_task_file_versions_impl;
revoke all on function private.cmd_compare_task_file_versions_impl(uuid,uuid,uuid,uuid)
  from public, anon, authenticated, service_role;

create function public.cmd_compare_task_file_versions(
  p_project_id uuid,
  p_base_file_version_id uuid,
  p_target_file_version_id uuid,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_capability_failure jsonb;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if p_project_id is null
     or p_base_file_version_id is null
     or p_target_file_version_id is null then
    return private.failure(
      p_request_id,
      'VALIDATION_FAILED',
      case
        when p_project_id is null then 'projectId'
        when p_base_file_version_id is null then 'baseFileVersionId'
        else 'targetFileVersionId'
      end
    );
  end if;

  if not exists (
    select 1 from public.projects p where p.id = p_project_id
  ) or not private.is_active_member(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_capability_failure := private.project_capability_failure(
    p_project_id,
    'file_version_compare',
    p_request_id
  );
  if v_capability_failure is not null then
    return v_capability_failure;
  end if;

  return private.cmd_compare_task_file_versions_impl(
    p_project_id,
    p_base_file_version_id,
    p_target_file_version_id,
    p_request_id
  );
end;
$$;

revoke all on function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
  to authenticated;

comment on function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid) is
  'Pro version-compare gate. Active project membership is required before the released file_version_compare capability; comparison scope remains metadata-first with degraded text-content orchestration.';

alter function public.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  set schema private;
alter function private.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  rename to cmd_create_project_recovery_point_impl;
revoke all on function private.cmd_create_project_recovery_point_impl(uuid,uuid,integer,text)
  from public, anon, authenticated, service_role;

create function public.cmd_create_project_recovery_point(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_label text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_capability_failure jsonb;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;

  if not exists (
    select 1 from public.projects p where p.id = p_project_id
  ) or not private.is_active_leader(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_capability_failure := private.project_capability_failure(
    p_project_id,
    'project_recovery_point',
    p_request_id
  );
  if v_capability_failure is not null then
    return v_capability_failure;
  end if;

  return private.cmd_create_project_recovery_point_impl(
    p_project_id,
    p_request_id,
    p_expected_version,
    p_label
  );
end;
$$;

revoke all on function public.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  to authenticated;

alter function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  set schema private;
alter function private.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  rename to cmd_restore_project_recovery_point_impl;
revoke all on function private.cmd_restore_project_recovery_point_impl(uuid,uuid,uuid,integer)
  from public, anon, authenticated, service_role;

create function public.cmd_restore_project_recovery_point(
  p_project_id uuid,
  p_recovery_point_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_capability_failure jsonb;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if p_project_id is null or p_recovery_point_id is null then
    return private.failure(
      p_request_id,
      'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'recoveryPointId' end
    );
  end if;

  if not exists (
    select 1 from public.projects p where p.id = p_project_id
  ) or not private.is_active_leader(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_capability_failure := private.project_capability_failure(
    p_project_id,
    'project_recovery_point',
    p_request_id
  );
  if v_capability_failure is not null then
    return v_capability_failure;
  end if;

  return private.cmd_restore_project_recovery_point_impl(
    p_project_id,
    p_recovery_point_id,
    p_request_id,
    p_expected_version
  );
end;
$$;

revoke all on function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  to authenticated;

comment on function public.cmd_create_project_recovery_point(uuid,uuid,integer,text) is
  'Pro recovery-point create gate. Active leader authorization is required before the released project_recovery_point capability. Scope remains project_file_pointers_v1.';
comment on function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer) is
  'Pro recovery-point restore gate. Active leader authorization is required before the released project_recovery_point capability. Restore remains append-only and limited to project_file_pointers_v1.';
