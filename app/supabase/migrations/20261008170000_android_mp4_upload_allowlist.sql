-- Android H.264 MP4 uploads: allow one audited MIME type end-to-end.
-- Preserve all existing file types, private bucket status and per-project quota.
create or replace function private.is_allowed_task_file_mime(p_mime text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_mime in (
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/csv', 'text/plain', 'text/markdown',
    'application/json', 'application/xml', 'text/xml', 'text/css',
    'text/javascript', 'application/javascript',
    'text/typescript', 'application/typescript',
    'image/png', 'image/jpeg', 'image/gif', 'image/webp',
    'video/mp4'
  ), false);
$$;
revoke all on function private.is_allowed_task_file_mime(text)
  from public, anon, authenticated;

do $$
begin
  -- A missing/unrestricted bucket must not be silently configured by a feature migration.
  if not exists (
    select 1 from storage.buckets
    where id = 'teamup-files'
      and public is false
      and allowed_mime_types is not null
      and 'application/pdf' = any(allowed_mime_types)
      and 'image/png' = any(allowed_mime_types)
  ) then
    raise exception 'MP4_MIME_MIGRATION_REQUIRES_PRIVATE_RESTRICTED_BUCKET';
  end if;

  -- Existing file_size_limit is intentionally untouched.
  update storage.buckets
  set allowed_mime_types = array_append(allowed_mime_types, 'video/mp4')
  where id = 'teamup-files'
    and not ('video/mp4' = any(allowed_mime_types));
end;
$$;