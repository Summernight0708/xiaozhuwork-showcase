begin;

select plan(5);

select is(
  private.task_submission_file_type_from_mime('application/msword'),
  'doc',
  'legacy Word MIME maps to the doc submission requirement'
);

select ok(
  private.is_allowed_task_file_mime('application/msword'),
  'legacy Word MIME is allowed by the server MIME contract'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id = 'teamup-files'
      and public is false
      and allowed_mime_types is not null
      and 'application/msword' = any(allowed_mime_types)
  ),
  'legacy Word MIME is allowed only in the existing private restricted bucket'
);

select ok(
  not private.is_allowed_task_file_mime('application/x-msdownload'),
  'the DOC change does not permit arbitrary executable MIME types'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id = 'teamup-files'
      and public is false
      and allowed_mime_types is not null
      and 'application/pdf' = any(allowed_mime_types)
      and 'image/png' = any(allowed_mime_types)
  ),
  'the bucket remains private and retains its existing restricted allowlist'
);

select * from finish();

rollback;
