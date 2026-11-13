-- Accept legacy Word 97–2003 DOC only after the shared CFB/Word validator
-- has checked the upload contents. Preserve the private bucket and existing caps.

create or replace function private.is_allowed_task_file_mime(p_mime text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_mime in (
    'application/pdf',
    'application/msword',
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

create or replace function private.task_submission_file_type_from_mime(p_mime text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case lower(p_mime)
    when 'application/pdf' then 'pdf'
    when 'application/msword' then 'doc'
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
revoke all on function private.task_submission_file_type_from_mime(text)
  from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from storage.buckets
    where id = 'teamup-files'
      and public is false
      and allowed_mime_types is not null
      and 'application/pdf' = any(allowed_mime_types)
      and 'image/png' = any(allowed_mime_types)
  ) then
    raise exception 'DOC_MIME_MIGRATION_REQUIRES_PRIVATE_RESTRICTED_BUCKET';
  end if;

  update storage.buckets
  set allowed_mime_types = array_append(allowed_mime_types, 'application/msword')
  where id = 'teamup-files'
    and not ('application/msword' = any(allowed_mime_types));

  if not exists (
    select 1
    from storage.buckets
    where id = 'teamup-files'
      and public is false
      and 'application/msword' = any(allowed_mime_types)
  ) then
    raise exception 'DOC_MIME_BUCKET_ALLOWLIST_UPDATE_FAILED';
  end if;
end;
$$;
