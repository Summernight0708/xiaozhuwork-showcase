begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(private.is_allowed_task_file_mime('video/mp4'),
  'audited video/mp4 now admitted to upload reservation and finalization');
select ok(private.is_allowed_task_file_mime('application/pdf'),
  'existing PDF upload remains admitted');
select ok(private.is_allowed_task_file_mime('image/png'),
  'existing PNG upload remains admitted');
select ok(private.is_allowed_task_file_mime('application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  'existing DOCX upload remains admitted');
select ok(not private.is_allowed_task_file_mime('video/webm'),
  'unreviewed WebM remains rejected');
select ok(not private.is_allowed_task_file_mime('application/x-msdownload'),
  'executables remain rejected');
select ok(not private.is_allowed_task_file_mime(null),
  'unknown or null MIME is fail-closed');
select ok(not has_function_privilege('authenticated',
  'private.is_allowed_task_file_mime(text)', 'EXECUTE'),
  'MIME policy function remains private to callers');
select ok(not has_function_privilege('anon',
  'private.is_allowed_task_file_mime(text)', 'EXECUTE'),
  'anon cannot call private MIME policy function');
select ok((
  select not public
    and allowed_mime_types is not null
    and 'video/mp4' = any(allowed_mime_types)
    and 'application/pdf' = any(allowed_mime_types)
    and 'image/png' = any(allowed_mime_types)
  from storage.buckets where id = 'teamup-files'
), 'private bucket retains existing MIME restrictions and admits MP4');
select is((
  select count(*)::bigint from (
    select unnest(allowed_mime_types) as value
    from storage.buckets where id = 'teamup-files'
  ) types where value = 'video/mp4'
), 1::bigint, 'MP4 Storage allowlist has no duplicate entries');
select ok((
  select file_size_limit >= 52428800
    and file_size_limit <= 209715200
  from storage.buckets where id = 'teamup-files'
), 'storage bucket retains bounded size limit');
select * from finish();
rollback;