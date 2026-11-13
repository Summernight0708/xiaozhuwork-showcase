create table public.file_upload_reservations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  task_id uuid not null,
  actor_id uuid not null references auth.users (id) on delete cascade,
  mode text not null,
  target_file_id uuid,
  target_file_version integer,
  object_path text not null unique,
  original_name text not null,
  declared_mime_type text not null,
  declared_size_bytes bigint not null,
  state text not null default 'reserved',
  rejection_code text,
  expires_at timestamptz not null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id) references public.tasks (project_id, id) on delete cascade,
  constraint file_upload_reservations_scope_path_unique unique (project_id, task_id, id, object_path),
  constraint file_upload_reservations_mode check (mode in ('new_file', 'new_version')),
  constraint file_upload_reservations_target check (
    (mode = 'new_file' and target_file_id is null and target_file_version is null) or
    (mode = 'new_version' and target_file_id is not null and target_file_version is not null and target_file_version > 0)
  ),
  constraint file_upload_reservations_state check (state in ('reserved', 'finalized', 'rejected')),
  constraint file_upload_reservations_rejection check (
    (state = 'rejected' and rejection_code is not null) or
    (state <> 'rejected' and rejection_code is null)
  ),
  constraint file_upload_reservations_name_length check (char_length(original_name) between 1 and 255),
  constraint file_upload_reservations_mime_length check (char_length(declared_mime_type) between 1 and 160),
  constraint file_upload_reservations_size check (declared_size_bytes > 0 and declared_size_bytes <= 52428800),
  constraint file_upload_reservations_version check (version > 0)
);

create table public.task_files (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  task_id uuid not null,
  logical_name text not null,
  created_by uuid references auth.users (id) on delete set null,
  current_version_id uuid,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, task_id) references public.tasks (project_id, id) on delete cascade,
  constraint task_files_logical_name_length check (char_length(logical_name) between 1 and 255),
  constraint task_files_version check (version > 0),
  constraint task_files_project_task_id_unique unique (project_id, task_id, id)
);

alter table public.file_upload_reservations
  add constraint file_upload_reservations_target_file_fkey
  foreign key (project_id, task_id, target_file_id)
  references public.task_files (project_id, task_id, id);

create table public.task_file_versions (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null,
  project_id uuid not null,
  task_id uuid not null,
  reservation_id uuid not null,
  version_number integer not null,
  object_path text not null,
  original_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  sha256_hex text not null,
  uploaded_by uuid references auth.users (id) on delete set null,
  restored_from_version_id uuid,
  created_at timestamptz not null default now(),
  foreign key (project_id, task_id, file_id)
    references public.task_files (project_id, task_id, id) on delete cascade,
  constraint task_file_versions_reservation_id_fkey
    foreign key (project_id, task_id, reservation_id, object_path)
    references public.file_upload_reservations (project_id, task_id, id, object_path),
  constraint task_file_versions_version_number check (version_number > 0),
  constraint task_file_versions_name_length check (char_length(original_name) between 1 and 255),
  constraint task_file_versions_mime_length check (char_length(mime_type) between 1 and 160),
  constraint task_file_versions_size check (size_bytes > 0 and size_bytes <= 52428800),
  constraint task_file_versions_sha256 check (sha256_hex ~ '^[0-9a-f]{64}$'),
  constraint task_file_versions_file_version_unique unique (file_id, version_number),
  constraint task_file_versions_object_path_unique unique (object_path),
  constraint task_file_versions_reservation_unique unique (reservation_id),
  constraint task_file_versions_file_id_id_unique unique (file_id, id)
);

alter table public.task_file_versions
  add constraint task_file_versions_restored_same_file_fkey
  foreign key (file_id, restored_from_version_id)
  references public.task_file_versions (file_id, id)
  deferrable initially deferred;

alter table public.task_files
  add constraint task_files_current_version_same_file_fkey
  foreign key (id, current_version_id)
  references public.task_file_versions (file_id, id)
  deferrable initially deferred;

create index file_upload_reservations_project_live_idx
  on public.file_upload_reservations (project_id, expires_at)
  where state = 'reserved';
create index file_upload_reservations_actor_state_idx
  on public.file_upload_reservations (actor_id, state);
create index file_upload_reservations_task_idx
  on public.file_upload_reservations (task_id);
create index task_files_task_idx on public.task_files (task_id, created_at);
create index task_file_versions_project_idx on public.task_file_versions (project_id, created_at);
create index task_file_versions_task_idx on public.task_file_versions (task_id, created_at);

create function private.is_allowed_task_file_mime(p_mime text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_mime in (
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/csv',
    'text/plain',
    'text/markdown',
    'application/json',
    'application/xml',
    'text/xml',
    'text/css',
    'text/javascript',
    'application/javascript',
    'text/typescript',
    'application/typescript',
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp'
  );
$$;

create function private.sanitize_task_file_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(btrim(p_name), '[^A-Za-z0-9._-]+', '_', 'g');
$$;

create function private.is_current_task_file_actor(
  p_project_id uuid,
  p_task_id uuid,
  p_actor_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_active_member(p_project_id, p_actor_id)
    and exists (
      select 1
      from public.tasks t
      where t.id = p_task_id
        and t.project_id = p_project_id
        and (
          t.assignee_id = p_actor_id
          or t.created_by = p_actor_id
          or private.is_active_leader(p_project_id, p_actor_id)
        )
    );
$$;

create function private.task_file_project_usage_bytes(
  p_project_id uuid,
  p_exclude_reservation_id uuid
) returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  with finalized as (
    select coalesce(sum(v.size_bytes), 0)::bigint as bytes
    from public.task_file_versions v
    where v.project_id = p_project_id
  ),
  physical_pending as (
    select coalesce(sum(
      case
        when coalesce(o.metadata->>'size', '') ~ '^[0-9]{1,8}$' then
          case
            when (o.metadata->>'size')::bigint > 0 then (o.metadata->>'size')::bigint
            else 52428800
          end
        else 52428800
      end
    ), 0)::bigint as bytes
    from storage.objects o
    left join public.file_upload_reservations r
      on r.object_path = o.name
    where o.bucket_id = 'teamup-files'
      and o.name like ('pending/' || p_project_id::text || '/%')
      and (p_exclude_reservation_id is null or r.id is distinct from p_exclude_reservation_id)
      and not exists (
        select 1
        from public.task_file_versions v
        where v.object_path = o.name
      )
  ),
  live_unuploaded as (
    select coalesce(count(*) * 52428800::bigint, 0)::bigint as bytes
    from public.file_upload_reservations r
    where r.project_id = p_project_id
      and r.state = 'reserved'
      and r.expires_at > now()
      and (p_exclude_reservation_id is null or r.id <> p_exclude_reservation_id)
      and not exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'teamup-files'
          and o.name = r.object_path
      )
  )
  select finalized.bytes + physical_pending.bytes + live_unuploaded.bytes
  from finalized, physical_pending, live_unuploaded;
$$;


create function private.reject_task_file_version_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'Task file versions are immutable';
end;
$$;

create trigger task_file_versions_immutable
before update or delete on public.task_file_versions
for each row execute function private.reject_task_file_version_mutation();

revoke all on function private.is_allowed_task_file_mime(text) from public, anon, authenticated;
revoke all on function private.sanitize_task_file_name(text) from public, anon, authenticated;
revoke all on function private.is_current_task_file_actor(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function private.task_file_project_usage_bytes(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.reject_task_file_version_mutation() from public, anon, authenticated;

alter table public.file_upload_reservations enable row level security;
alter table public.task_files enable row level security;
alter table public.task_file_versions enable row level security;

create policy file_upload_reservations_select_owner_or_leader
on public.file_upload_reservations for select to authenticated
using (
  actor_id = (select auth.uid())
  or exists (
    select 1
    from public.project_members pm
    where pm.project_id = file_upload_reservations.project_id
      and pm.user_id = (select auth.uid())
      and pm.role = 'leader'
      and pm.member_state = 'active'
  )
);

create policy task_files_select_active_member
on public.task_files for select to authenticated
using (public.is_active_project_member(project_id));

create policy task_file_versions_select_active_member
on public.task_file_versions for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.file_upload_reservations, public.task_files, public.task_file_versions from public, anon, authenticated, service_role;
grant select on public.file_upload_reservations, public.task_files, public.task_file_versions to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'teamup-files',
  'teamup-files',
  false,
  52428800,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/csv',
    'text/plain',
    'text/markdown',
    'application/json',
    'application/xml',
    'text/xml',
    'text/css',
    'text/javascript',
    'application/javascript',
    'text/typescript',
    'application/typescript',
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp'
  ]::text[]
)
on conflict (id) do update set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy teamup_files_insert_reserved
on storage.objects for insert to authenticated
with check (
  bucket_id = 'teamup-files'
  and exists (
    select 1
    from public.file_upload_reservations r
    join public.project_members pm
      on pm.project_id = r.project_id
     and pm.user_id = (select auth.uid())
     and pm.member_state = 'active'
    join public.tasks t
      on t.project_id = r.project_id
     and t.id = r.task_id
    where r.object_path = name
      and r.actor_id = (select auth.uid())
      and r.state = 'reserved'
      and r.expires_at > now()
      and (
        t.assignee_id = (select auth.uid())
        or t.created_by = (select auth.uid())
        or pm.role = 'leader'
      )
  )
);

create policy teamup_files_select_finalized
on storage.objects for select to authenticated
using (
  bucket_id = 'teamup-files'
  and exists (
    select 1
    from public.task_file_versions v
    where v.object_path = name
      and public.is_active_project_member(v.project_id)
  )
);

create function public.cmd_reserve_task_file_upload(
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
  elsif p_declared_size_bytes > 52428800 then
    v_result := private.failure(
      p_request_id, 'STORAGE_QUOTA_EXCEEDED', 'declaredSizeBytes', null,
      jsonb_build_object('scope', 'file', 'limitBytes', 52428800)
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
    select private.task_file_project_usage_bytes(p_project_id, null) into v_project_usage_bytes;

    if v_project_usage_bytes + 52428800 > 536870912 then
      v_result := private.failure(
        p_request_id, 'STORAGE_QUOTA_EXCEEDED', null, null,
        jsonb_build_object('scope', 'project', 'limitBytes', 536870912)
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
    state, expires_at, version
  ) values (
    v_reservation_id, p_project_id, p_task_id, v_actor, p_mode, p_target_file_id,
    case when p_mode = 'new_version' then p_expected_version else null end,
    v_object_path, btrim(p_original_name), p_declared_mime_type, p_declared_size_bytes,
    'reserved', v_expires_at, 1
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

create function public.cmd_finalize_task_file_upload_service(
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

  select * into v_task
  from public.tasks t
  where t.id = v_hint.task_id and t.project_id = v_hint.project_id
  for update;

  if v_hint.target_file_id is not null then
    select * into v_file
    from public.task_files f
    where f.id = v_hint.target_file_id
      and f.project_id = v_hint.project_id
      and f.task_id = v_hint.task_id
    for update;
  end if;

  select * into v_reservation
  from public.file_upload_reservations r
  where r.id = p_reservation_id
  for update;

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

  if v_reservation.state <> 'reserved' or v_reservation.expires_at <= now() then
    v_result := private.failure(p_request_id, 'UPLOAD_NOT_READY', null, v_reservation.version);
  elsif p_expected_version is null or p_expected_version <> v_reservation.version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_reservation.version);
  elsif p_actual_size_bytes is null
     or p_actual_size_bytes <= 0
     or p_actual_size_bytes > 52428800
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

  if v_storage_object.owner_id is distinct from v_reservation.actor_id::text
     or coalesce(v_storage_object.metadata->>'size', '') !~ '^[0-9]{1,8}$'
     or v_storage_object.metadata->>'mimetype' is null then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'storageObject');
  end if;

  v_storage_size := (v_storage_object.metadata->>'size')::bigint;
  v_storage_mime := v_storage_object.metadata->>'mimetype';
  if v_storage_size <= 0
     or v_storage_size > 52428800
     or v_storage_size <> v_reservation.declared_size_bytes
     or v_storage_size <> p_actual_size_bytes then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualSizeBytes');
  elsif v_storage_mime <> v_reservation.declared_mime_type
     or v_storage_mime <> p_actual_mime_type
     or not private.is_allowed_task_file_mime(v_storage_mime) then
    return private.failure(p_request_id, 'FILE_VALIDATION_FAILED', 'actualMimeType');
  end if;

  select private.task_file_project_usage_bytes(v_reservation.project_id, v_reservation.id) into v_project_usage_bytes;
  if v_project_usage_bytes + v_storage_size > 536870912 then
    v_result := private.failure(
      p_request_id, 'STORAGE_QUOTA_EXCEEDED', null, null,
      jsonb_build_object('scope', 'project', 'limitBytes', 536870912)
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

create function public.cmd_reject_task_file_upload_service(
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

  select * into v_task
  from public.tasks t
  where t.id = v_hint.task_id and t.project_id = v_hint.project_id
  for update;

  if v_hint.target_file_id is not null then
    select * into v_file
    from public.task_files f
    where f.id = v_hint.target_file_id
      and f.project_id = v_hint.project_id
      and f.task_id = v_hint.task_id
    for update;
  end if;

  select * into v_reservation
  from public.file_upload_reservations r
  where r.id = p_reservation_id
  for update;

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

create function public.get_task_files(p_task_id uuid)
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

revoke all on function public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)
  from public, anon, authenticated, service_role;
revoke all on function public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_task_files(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.cmd_reserve_task_file_upload(uuid,uuid,uuid,integer,text,uuid,text,text,bigint)
  to authenticated;
grant execute on function public.cmd_finalize_task_file_upload_service(uuid,uuid,uuid,integer,text,bigint,text)
  to service_role;
grant execute on function public.cmd_reject_task_file_upload_service(uuid,uuid,uuid,integer,text)
  to service_role;
grant execute on function public.get_task_files(uuid)
  to authenticated;

revoke all on schema private from service_role;
revoke all on all functions in schema private from service_role;

comment on table public.file_upload_reservations is 'Short-lived upload authority and validation lifecycle; object paths are unique and never overwritten.';
comment on table public.task_files is 'Logical task files whose current_version_id points to an immutable version belonging to the same file.';
comment on table public.task_file_versions is 'Append-only finalized task-file history; restored_from_version_id is reserved for future copy-forward restoration.';
