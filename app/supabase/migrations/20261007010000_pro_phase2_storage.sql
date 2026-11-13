-- Pro Phase 2 A: additive project storage and upload capacity.
-- G alone activates premium capability codes in a later migration.
alter table public.file_upload_reservations
  add column reserved_envelope_bytes bigint;
update public.file_upload_reservations
  set reserved_envelope_bytes = 52428800 where state = 'reserved';
alter table public.file_upload_reservations
  add constraint file_upload_reservations_envelope_positive
  check (reserved_envelope_bytes is null or reserved_envelope_bytes > 0);
alter table public.file_upload_reservations
  drop constraint file_upload_reservations_size;
alter table public.file_upload_reservations
  add constraint file_upload_reservations_size
  check (declared_size_bytes > 0 and declared_size_bytes <= 209715200
    and (state <> 'reserved' or
         declared_size_bytes <= coalesce(reserved_envelope_bytes,52428800)));
-- Finalized history/rollback rows deliberately have no reservation envelope;
-- their preserved 200 MiB physical objects must remain restorable.
alter table public.task_file_versions drop constraint task_file_versions_size;
alter table public.task_file_versions
  add constraint task_file_versions_size
  check (size_bytes > 0 and
  (size_bytes <= 52428800 or
   (size_bytes > 52428800 and size_bytes <= 209715200)));

create index if not exists phase2_task_file_versions_project_path
  on public.task_file_versions(project_id,object_path);
create index if not exists phase2_reservations_project_expiry
  on public.file_upload_reservations(project_id,expires_at)
  where state = 'reserved';

create or replace function private.phase2_upload_file_limit(p_project_id uuid)
returns bigint language plpgsql stable security definer set search_path = '' as $$
declare
  v_capability text := 'file_large_upload';
  v_entitlement record;
begin
  -- The release predicate is G-owned; evaluate it dynamically and independently
  -- from entitlement. Keep the base Free limit enforced even while unreleased.
  if private.capability_is_released(v_capability) then
    select * into v_entitlement
    from private.resolve_project_entitlement(p_project_id, transaction_timestamp());
    if coalesce(v_entitlement.state in ('active','grace'),false) then
      return 209715200::bigint;
    end if;
  end if;
  return 52428800::bigint;
end;
$$;
create or replace function private.phase2_project_storage_limit(p_project_id uuid)
returns bigint language plpgsql stable security definer set search_path = '' as $$
declare
  v_capability text := 'project_storage_quota';
  v_entitlement record;
begin
  if private.capability_is_released(v_capability) then
    select * into v_entitlement
    from private.resolve_project_entitlement(p_project_id, transaction_timestamp());
    if coalesce(v_entitlement.state in ('active','grace'),false) then
      return 5368709120::bigint;
    end if;
  end if;
  return 536870912::bigint;
end;
$$;

-- Each retained immutable physical path counts once. Live uploaded reservations
-- reserve max(actual bytes, original full envelope) until finalized.
-- Invalid/missing metadata for a still-present Storage object bills conservatively.
create or replace function private.phase2_project_storage_usage(
  p_project_id uuid, p_exclude_reservation_id uuid default null
) returns bigint language sql stable security definer set search_path = ''
as $$
  with refs as (
    select object_path, max(size_bytes)::bigint canonical_bytes
    from public.task_file_versions where project_id=p_project_id
    group by object_path
  ),
  finalized as (
    select coalesce(sum(greatest(v.canonical_bytes,
      case when coalesce(o.metadata->>'size','') ~ '^[0-9]{1,12}$'
                 and (o.metadata->>'size')::bigint between 1 and 209715200
        then (o.metadata->>'size')::bigint
        when o.id is null then v.canonical_bytes
        else 209715200::bigint end)),0)::bigint bytes
    from refs v left join storage.objects o on o.bucket_id='teamup-files'
      and o.name=v.object_path
  ),
  unfinalized_physical as (
    select coalesce(sum(greatest(
      case when coalesce(o.metadata->>'size','') ~ '^[0-9]{1,12}$'
                 and (o.metadata->>'size')::bigint between 1 and 209715200
        then (o.metadata->>'size')::bigint
        -- Legacy uploads physically could not exceed 50 MiB; retain that
        -- original reservation envelope when Storage metadata is absent.
        else coalesce((select max(coalesce(r.reserved_envelope_bytes,52428800))
          from public.file_upload_reservations r
          where r.project_id=p_project_id and r.object_path=o.name),
          209715200::bigint) end,
      coalesce((select max(coalesce(r.reserved_envelope_bytes,52428800))
        from public.file_upload_reservations r
        where r.project_id=p_project_id and r.object_path=o.name
          and r.state='reserved' and r.expires_at>transaction_timestamp()),0::bigint)
    )),0)::bigint bytes
    from storage.objects o
    where o.bucket_id='teamup-files'
      and o.name like ('pending/' || p_project_id::text || '/%')
      and not exists (select 1 from refs v where v.object_path=o.name)
      and (p_exclude_reservation_id is null or not exists (
        select 1 from public.file_upload_reservations r
        where r.id=p_exclude_reservation_id and r.project_id=p_project_id
          and r.object_path=o.name))
  ),
  unuploaded_live as (
    select coalesce(sum(coalesce(r.reserved_envelope_bytes,52428800)),0)::bigint bytes
    from public.file_upload_reservations r
    where r.project_id=p_project_id and r.state='reserved'
      and r.expires_at>transaction_timestamp()
      and (p_exclude_reservation_id is null or r.id<>p_exclude_reservation_id)
      and not exists (select 1 from storage.objects o
        where o.bucket_id='teamup-files' and o.name=r.object_path)
  )
  select finalized.bytes+unfinalized_physical.bytes+unuploaded_live.bytes
  from finalized,unfinalized_physical,unuploaded_live;
$$;

create or replace function public.get_project_storage_usage(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
 v_actor uuid := auth.uid();
 v_limit bigint;
 v_used bigint;
 v_reserved bigint;
begin
 if v_actor is null then return private.failure(null,'UNAUTHENTICATED'); end if;
 if p_project_id is null or not private.is_active_member(p_project_id,v_actor) then
   return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 v_limit:=private.phase2_project_storage_limit(p_project_id);
 v_used:=private.phase2_project_storage_usage(p_project_id);
 select coalesce(sum(coalesce(r.reserved_envelope_bytes,52428800)),0)::bigint
   into v_reserved from public.file_upload_reservations r
   where r.project_id=p_project_id and r.state='reserved'
     and r.expires_at>transaction_timestamp();
 return jsonb_build_object('ok',true,'data',jsonb_build_object(
   'schemaVersion',1,'projectId',p_project_id,'limitBytes',v_limit,
   'usedBytes',v_used,'availableBytes',greatest(0::bigint,v_limit-v_used),
   'reservedBytes',v_reserved,'overLimit',(v_used>v_limit)));
end;
$$;

create or replace function public.cmd_reserve_task_file_upload(
  p_project_id uuid,
  p_task_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_mode text,
  p_target_file_id uuid,
  p_original_name text,
  p_declared_mime_type text,
  p_declared_size_bytes bigint
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
  v_reservation_id uuid;
  v_safe_name text;
  v_object_path text;
  v_expires_at timestamptz;
  v_project_usage_bytes bigint;
  v_file_limit bigint;
  v_project_limit bigint;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if not exists (select 1 from public.projects p where p.id = p_project_id) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout', '5s', true);
  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id,
    'taskId', p_task_id,
    'expectedVersion', p_expected_version,
    'mode', p_mode,
    'targetFileId', p_target_file_id,
    'originalName', p_original_name,
    'declaredMimeType', p_declared_mime_type,
    'declaredSizeBytes', p_declared_size_bytes
  ));
  select * into v_claim
  from private.claim_command(
    v_actor, 'cmd_reserve_task_file_upload', p_request_id, v_hash, null, p_project_id
  );

  select * into v_project
  from public.projects p
  where p.id = p_project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id = p_task_id and t.project_id = p_project_id
  for update;

  if not found or not private.is_current_task_file_actor(p_project_id, p_task_id, v_actor) then
    v_result := private.reject_unless_authorized(
      false, p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
    );
    return v_result;
  end if;

  v_result := private.reject_unless_authorized(
    true, p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;
  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then
    return v_replay;
  end if;

  v_file_limit := private.phase2_upload_file_limit(p_project_id);
  v_project_limit := private.phase2_project_storage_limit(p_project_id);
  if v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id, 'PROJECT_NOT_ACTIVE', null, v_project.version);
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  if p_mode is null or p_mode not in ('new_file', 'new_version') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'mode');
  elsif (p_mode = 'new_file' and p_target_file_id is not null)
     or (p_mode = 'new_version' and p_target_file_id is null) then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'targetFileId');
  elsif p_original_name is null
     or char_length(btrim(p_original_name)) not between 1 and 255
     or strpos(p_original_name, '/') > 0
     or strpos(p_original_name, chr(92)) > 0
     or p_original_name ~ '[[:cntrl:]]' then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'originalName');
  elsif p_declared_mime_type is null or not private.is_allowed_task_file_mime(p_declared_mime_type) then
    v_result := private.failure(p_request_id, 'FILE_TYPE_NOT_ALLOWED', 'declaredMimeType');
  elsif p_declared_size_bytes is null or p_declared_size_bytes <= 0 then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'declaredSizeBytes');
  elsif p_declared_size_bytes > v_file_limit then
    v_result := private.failure(
      p_request_id, 'STORAGE_QUOTA_EXCEEDED', 'declaredSizeBytes', null,
      jsonb_build_object('scope', 'file', 'limitBytes', v_file_limit)
    );
  elsif p_mode = 'new_file' and (p_expected_version is null or p_expected_version <> v_task.version) then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_task.version);
  else
    if p_mode = 'new_version' then
      select * into v_file
      from public.task_files f
      where f.id = p_target_file_id
        and f.project_id = p_project_id
        and f.task_id = p_task_id
      for update;
      if not found then
        v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
      elsif p_expected_version is null or p_expected_version <> v_file.version then
        v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_file.version);
      end if;
    end if;
  end if;

  if v_result is null then
    select private.phase2_project_storage_usage(p_project_id, null) into v_project_usage_bytes;

    if v_project_usage_bytes + v_file_limit > v_project_limit then
      v_result := private.failure(
        p_request_id, 'STORAGE_QUOTA_EXCEEDED', null, null,
        jsonb_build_object('scope', 'project', 'limitBytes', v_project_limit)
      );
    end if;
  end if;

  if v_result is not null then
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  v_safe_name := private.sanitize_task_file_name(p_original_name);
  if v_safe_name is null or v_safe_name in ('', '.', '..') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'originalName');
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  v_reservation_id := gen_random_uuid();
  v_object_path := 'pending/' || p_project_id::text || '/' || v_reservation_id::text || '/' || v_safe_name;
  v_expires_at := now() + interval '15 minutes';

  insert into public.file_upload_reservations (
    id, project_id, task_id, actor_id, mode, target_file_id, target_file_version,
    object_path, original_name, declared_mime_type, declared_size_bytes,
    state, expires_at, version, reserved_envelope_bytes
  ) values (
    v_reservation_id, p_project_id, p_task_id, v_actor, p_mode, p_target_file_id,
    case when p_mode = 'new_version' then p_expected_version else null end,
    v_object_path, btrim(p_original_name), p_declared_mime_type, p_declared_size_bytes,
    'reserved', v_expires_at, 1, v_file_limit
  );

  perform private.emit_event(
    v_claim.command_id, 1, p_project_id, v_actor,
    'task_file_upload_reserved', 'file_upload_reservation', v_reservation_id,
    p_request_id, jsonb_build_object('taskId', p_task_id, 'mode', p_mode)
  );

  v_result := jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'reservationId', v_reservation_id,
      'objectPath', v_object_path,
      'expiresAt', v_expires_at
    ),
    'requestId', p_request_id,
    'replayed', false,
    'aggregateType', 'file_upload_reservation',
    'aggregateId', v_reservation_id,
    'aggregateVersion', 1
  );
  return private.complete_command(
    v_claim.command_id, v_result, 'file_upload_reservation', v_reservation_id, 1
  );
end;
$$;

create or replace function public.cmd_finalize_task_file_upload_service(
  p_actor_id uuid,
  p_reservation_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_actual_mime_type text,
  p_actual_size_bytes bigint,
  p_sha256_hex text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hint public.file_upload_reservations%rowtype;
  v_claim record;
  v_hash bytea;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_file public.task_files%rowtype;
  v_reservation public.file_upload_reservations%rowtype;
  v_storage_object storage.objects%rowtype;
  v_storage_size bigint;
  v_storage_mime text;
  v_file_id uuid;
  v_file_version_id uuid;
  v_version_number integer;
  v_project_usage_bytes bigint;
  v_file_limit bigint;
  v_project_limit bigint;
begin
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;

  select * into v_hint
  from public.file_upload_reservations r
  where r.id = p_reservation_id;
  if not found then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout', '5s', true);
  v_hash := private.payload_hash(jsonb_build_object(
    'actorId', p_actor_id,
    'reservationId', p_reservation_id,
    'expectedVersion', p_expected_version,
    'actualMimeType', p_actual_mime_type,
    'actualSizeBytes', p_actual_size_bytes,
    'sha256Hex', p_sha256_hex
  ));
  select * into v_claim
  from private.claim_command(
    p_actor_id, 'cmd_finalize_task_file_upload_service', p_request_id, v_hash, null, v_hint.project_id
  );

  select * into v_project
  from public.projects p
  where p.id = v_hint.project_id
  for update;

  select * into v_reservation
  from public.file_upload_reservations r
  where r.id = p_reservation_id and r.project_id = v_hint.project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id = v_reservation.task_id and t.project_id = v_reservation.project_id
  for update;

  if v_reservation.target_file_id is not null then
    select * into v_file
    from public.task_files f
    where f.id = v_reservation.target_file_id and f.project_id = v_reservation.project_id
      and f.task_id = v_reservation.task_id
    for update;
  end if;
  v_result := private.reject_unless_authorized(
    v_reservation.id is not null
      and v_reservation.actor_id = p_actor_id
      and private.is_current_task_file_actor(v_reservation.project_id, v_reservation.task_id, p_actor_id),
    p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;
  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then
    return v_replay;
  end if;

  v_file_limit := private.phase2_upload_file_limit(v_reservation.project_id);
  v_project_limit := private.phase2_project_storage_limit(v_reservation.project_id);
  if v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_reservation.state <> 'reserved' or v_reservation.expires_at <= now() then
    v_result := private.failure(p_request_id, 'UPLOAD_NOT_READY', null, v_reservation.version);
  elsif p_expected_version is null or p_expected_version <> v_reservation.version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_reservation.version);
  elsif p_actual_size_bytes > v_file_limit then
    v_result := private.failure(p_request_id,'STORAGE_QUOTA_EXCEEDED','actualSizeBytes',null,
      jsonb_build_object('scope','file','limitBytes',v_file_limit));
  elsif p_actual_size_bytes is null
     or p_actual_size_bytes <= 0
     or p_actual_size_bytes <> v_reservation.declared_size_bytes then
    v_result := private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualSizeBytes');
  elsif p_actual_mime_type is null
     or p_actual_mime_type <> v_reservation.declared_mime_type
     or not private.is_allowed_task_file_mime(p_actual_mime_type) then
    v_result := private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualMimeType');
  elsif p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-f]{64}$' then
    v_result := private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'sha256Hex');
  elsif v_reservation.mode = 'new_version'
     and (v_file.id is null or v_file.version <> v_reservation.target_file_version) then
    v_result := private.failure(
      p_request_id, 'STALE_VERSION', null,
      case when v_file.id is null then null else v_file.version end
    );
  end if;
  if v_result is not null then
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  select * into v_storage_object
  from storage.objects o
  where o.bucket_id = 'teamup-files'
    and o.name = v_reservation.object_path
  for update;
  if not found then
    return private.failure(p_request_id, 'UPLOAD_NOT_READY', null, v_reservation.version);
  end if;

  if v_reservation.object_path not like ('pending/' || v_reservation.project_id::text || '/%')
     or v_storage_object.owner_id is distinct from v_reservation.actor_id::text
     or coalesce(v_storage_object.metadata->>'size', '') !~ '^[0-9]{1,12}$'
     or v_storage_object.metadata->>'mimetype' is null then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'storageObject');
  end if;

  v_storage_size := (v_storage_object.metadata->>'size')::bigint;
  v_storage_mime := v_storage_object.metadata->>'mimetype';
  if v_storage_size > v_file_limit then
    return private.failure(p_request_id,'STORAGE_QUOTA_EXCEEDED','actualSizeBytes',null,
      jsonb_build_object('scope','file','limitBytes',v_file_limit));
  elsif v_storage_size <= 0
     or v_storage_size <> v_reservation.declared_size_bytes
     or v_storage_size <> p_actual_size_bytes then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualSizeBytes');
  elsif v_storage_mime <> v_reservation.declared_mime_type
     or v_storage_mime <> p_actual_mime_type
     or not private.is_allowed_task_file_mime(v_storage_mime) then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualMimeType');
  end if;

  select private.phase2_project_storage_usage(v_reservation.project_id, v_reservation.id) into v_project_usage_bytes;
  if v_project_usage_bytes + v_storage_size > v_project_limit then
    v_result := private.failure(
      p_request_id, 'STORAGE_QUOTA_EXCEEDED', null, null,
      jsonb_build_object('scope', 'project', 'limitBytes', v_project_limit)
    );
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  if v_reservation.mode = 'new_file' then
    v_file_id := gen_random_uuid();
    insert into public.task_files (
      id, project_id, task_id, logical_name, created_by, version
    ) values (
      v_file_id, v_reservation.project_id, v_reservation.task_id,
      v_reservation.original_name, p_actor_id, 1
    );
    v_version_number := 1;
  else
    v_file_id := v_file.id;
    v_version_number := v_file.version + 1;
  end if;

  v_file_version_id := gen_random_uuid();
  insert into public.task_file_versions (
    id, file_id, project_id, task_id, reservation_id, version_number,
    object_path, original_name, mime_type, size_bytes, sha256_hex,
    uploaded_by, restored_from_version_id
  ) values (
    v_file_version_id, v_file_id, v_reservation.project_id, v_reservation.task_id,
    v_reservation.id, v_version_number, v_reservation.object_path,
    v_reservation.original_name, v_storage_mime, v_storage_size,
    p_sha256_hex, p_actor_id, null
  );

  if v_reservation.mode = 'new_file' then
    update public.task_files
    set current_version_id = v_file_version_id, updated_at = now()
    where id = v_file_id;
  else
    update public.task_files
    set current_version_id = v_file_version_id,
        version = version + 1,
        updated_at = now()
    where id = v_file_id
    returning * into v_file;
  end if;

  update public.file_upload_reservations
  set state = 'finalized', version = version + 1, updated_at = now()
  where id = v_reservation.id
  returning * into v_reservation;

  perform private.emit_event(
    v_claim.command_id, 1, v_reservation.project_id, p_actor_id,
    'task_file_upload_finalized', 'task_file', v_file_id, p_request_id,
    jsonb_build_object(
      'reservationId', v_reservation.id,
      'fileVersionId', v_file_version_id,
      'versionNumber', v_version_number
    )
  );

  v_result := jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'reservationId', v_reservation.id,
      'fileId', v_file_id,
      'fileVersionId', v_file_version_id,
      'versionNumber', v_version_number
    ),
    'requestId', p_request_id,
    'replayed', false,
    'aggregateType', 'file_upload_reservation',
    'aggregateId', v_reservation.id,
    'aggregateVersion', v_reservation.version
  );
  return private.complete_command(
    v_claim.command_id, v_result, 'file_upload_reservation', v_reservation.id, v_reservation.version
  );
end;
$$;

-- Preserve the rejection RPC wire contract while ensuring rejection/finalize
-- compete for the same reservation lock in the same order.
create or replace function public.cmd_reject_task_file_upload_service(
  p_actor_id uuid,
  p_reservation_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_rejection_code text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hint public.file_upload_reservations%rowtype;
  v_claim record;
  v_hash bytea;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_file public.task_files%rowtype;
  v_reservation public.file_upload_reservations%rowtype;
begin
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;

  select * into v_hint
  from public.file_upload_reservations r
  where r.id = p_reservation_id;
  if not found then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  perform set_config('lock_timeout', '5s', true);
  v_hash := private.payload_hash(jsonb_build_object(
    'actorId', p_actor_id,
    'reservationId', p_reservation_id,
    'expectedVersion', p_expected_version,
    'rejectionCode', p_rejection_code
  ));
  select * into v_claim
  from private.claim_command(
    p_actor_id, 'cmd_reject_task_file_upload_service', p_request_id, v_hash, null, v_hint.project_id
  );

  select * into v_project
  from public.projects p
  where p.id = v_hint.project_id
  for update;

  -- Match finalize lock order: project -> reservation -> target file.
  select * into v_reservation
  from public.file_upload_reservations r
  where r.id = p_reservation_id and r.project_id = v_hint.project_id
  for update;

  select * into v_task
  from public.tasks t
  where t.id = v_reservation.task_id and t.project_id = v_reservation.project_id
  for update;

  if v_reservation.target_file_id is not null then
    select * into v_file
    from public.task_files f
    where f.id = v_reservation.target_file_id
      and f.project_id = v_reservation.project_id
      and f.task_id = v_reservation.task_id
    for update;
  end if;

  v_result := private.reject_unless_authorized(
    v_reservation.id is not null
      and v_reservation.actor_id = p_actor_id
      and private.is_current_task_file_actor(v_reservation.project_id, v_reservation.task_id, p_actor_id),
    p_request_id, v_claim.command_id, v_claim.prior_result, v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;
  v_replay := private.replay_or_reuse(p_request_id, v_claim.prior_result, v_claim.payload_matches);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_reservation.state <> 'reserved' then
    v_result := private.failure(p_request_id, 'UPLOAD_NOT_READY', null, v_reservation.version);
  elsif p_expected_version is null or p_expected_version <> v_reservation.version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_reservation.version);
  elsif p_rejection_code is null
     or p_rejection_code not in ('FILE_TYPE_NOT_ALLOWED', 'FILE_VALIDATION_FAILED', 'STORAGE_QUOTA_EXCEEDED') then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'rejectionCode');
  end if;
  if v_result is not null then
    return private.complete_command(v_claim.command_id, v_result);
  end if;

  update public.file_upload_reservations
  set state = 'rejected',
      rejection_code = p_rejection_code,
      version = version + 1,
      updated_at = now()
  where id = v_reservation.id
  returning * into v_reservation;

  perform private.emit_event(
    v_claim.command_id, 1, v_reservation.project_id, p_actor_id,
    'task_file_upload_rejected', 'file_upload_reservation', v_reservation.id,
    p_request_id, jsonb_build_object('rejectionCode', p_rejection_code)
  );

  v_result := jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'reservationId', v_reservation.id,
      'state', v_reservation.state,
      'rejectionCode', v_reservation.rejection_code
    ),
    'requestId', p_request_id,
    'replayed', false,
    'aggregateType', 'file_upload_reservation',
    'aggregateId', v_reservation.id,
    'aggregateVersion', v_reservation.version
  );
  return private.complete_command(
    v_claim.command_id, v_result, 'file_upload_reservation', v_reservation.id, v_reservation.version
  );
end;
$$;

-- This private service-only sweep atomically makes expired reservations terminal.
-- It emits only unreferenced physical deletion candidates. The G-owned scheduled
-- caller must DELETE each candidate via the Storage API, confirm success and
-- never directly delete storage.objects or assume returned paths are free space.
create or replace function private.phase2_reap_expired_uploads(
 p_before timestamptz,p_limit integer
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_item record;
 v_reservation public.file_upload_reservations%rowtype;
 v_candidates jsonb := '[]'::jsonb;
 v_limit integer := least(greatest(coalesce(p_limit,0),0),100);
begin
 if p_before is null then raise exception 'invalid sweep cutoff' using errcode='22023'; end if;
 for v_item in
   select r.id,r.project_id
   from public.file_upload_reservations r
   where r.expires_at <= p_before
     and (r.state='reserved' or
       (r.state='rejected' and exists
         (select 1 from storage.objects o
          where o.bucket_id='teamup-files' and o.name=r.object_path)))
   order by r.expires_at,r.id limit v_limit
 loop
   -- Project lock serializes with reserve/finalize; do NOT lock a reservation first.
   perform 1 from public.projects p where p.id=v_item.project_id for update;
   select * into v_reservation from public.file_upload_reservations r
     where r.id=v_item.id for update;
   if v_reservation.expires_at > p_before or
      v_reservation.state not in ('reserved','rejected') then continue; end if;
   if v_reservation.state='reserved' then
      update public.file_upload_reservations
        set state='rejected',rejection_code='UPLOAD_EXPIRED',version=version+1,
            updated_at=transaction_timestamp()
        where id=v_reservation.id;
   end if;
   if not exists(select 1 from public.task_file_versions fv
                 where fv.object_path=v_reservation.object_path)
      and exists(select 1 from storage.objects o where o.bucket_id='teamup-files'
                  and o.name=v_reservation.object_path) then
     v_candidates:=v_candidates||jsonb_build_array(jsonb_build_object(
       'projectId',v_reservation.project_id,'reservationId',v_reservation.id,
       'objectPath',v_reservation.object_path));
   end if;
 end loop;
 return jsonb_build_object('schemaVersion',1,'candidates',v_candidates);
end;
$$;

-- The Storage API can populate object metadata after INSERT RLS is checked.
-- Retain the existing exact-reservation/actor/path RLS (old regression contract),
-- enforce trusted persisted metadata plus the current tier under finalize locks.
-- An oversized forged upload never becomes a finalized version; its physical
-- orphan remains quota-accounted until verified Storage deletion.
update storage.buckets set file_size_limit=209715200 where id='teamup-files';
revoke all on function private.phase2_upload_file_limit(uuid),
  private.phase2_project_storage_limit(uuid),
  private.phase2_project_storage_usage(uuid,uuid),
  private.phase2_reap_expired_uploads(timestamptz,integer)
from public,anon,authenticated,service_role;
grant execute on function private.phase2_reap_expired_uploads(timestamptz,integer)
  to service_role;
revoke all on function public.get_project_storage_usage(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.get_project_storage_usage(uuid) to authenticated;
