begin;

select plan(16);

select ok(
  private.is_valid_submission_file_types('{}'::text[]),
  'an empty required type set is valid and means no type restriction'
);

select is(
  private.normalize_submission_file_types(array['xlsx','pdf','xlsx','doc']::text[]),
  array['pdf','doc','xlsx']::text[],
  'normalization deduplicates and uses stable whitelist order'
);

select ok(
  private.is_valid_submission_file_types(array['pdf','doc','xlsx']::text[]),
  'a normalized multi-format requirement is valid'
);

select ok(
  not private.is_valid_submission_file_types(array['pdf','pdf']::text[]),
  'duplicate entries cannot be persisted as a canonical set'
);

select ok(
  not private.is_valid_submission_file_types(array['pdf','exe']::text[]),
  'unapproved file types cannot be persisted'
);

select is(
  private.task_submission_file_type_from_mime('application/msword'),
  'doc',
  'legacy Word MIME maps to the doc submission type'
);

select ok(
  private.is_allowed_task_file_mime('application/msword'),
  'legacy Word MIME is included in the private upload MIME contract'
);

select ok(
  not private.is_allowed_task_file_mime('application/x-msdownload'),
  'the DOC allowlist change does not allow arbitrary executable MIME'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tasks'
      and column_name='required_submission_file_types'
      and data_type='ARRAY'
  ),
  'tasks stores the canonical required type array'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='task_change_proposals'
      and column_name='old_required_submission_file_types'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='task_change_proposals'
      and column_name='new_required_submission_file_types'
  ),
  'change proposals preserve both old and new type arrays'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='task_review_rounds'
      and column_name='required_submission_file_types_snapshot'
  ),
  'review rounds snapshot the canonical type array'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='task_change_proposals_visible'
      and column_name='old_required_submission_file_types'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='task_change_proposals_visible'
      and column_name='new_required_submission_file_types'
  ),
  'the authorization-scoped proposal view exposes the array contract'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id='teamup-files' and public is false
      and allowed_mime_types is not null
      and 'application/msword'=any(allowed_mime_types)
      and 'application/pdf'=any(allowed_mime_types)
  ),
  'DOC is enabled without making the existing file bucket public'
);

select ok(
  to_regprocedure('public.cmd_create_task_v2(uuid,uuid,integer,text,text,timestamp with time zone,smallint,text,uuid,text[],boolean)') is not null,
  'the v2 task creation RPC accepts a file type array'
);

select ok(
  to_regprocedure('public.cmd_edit_task_v2(uuid,uuid,uuid,integer,text,text,timestamp with time zone,smallint,text[])') is not null
  and to_regprocedure('public.cmd_propose_task_change_v2(uuid,uuid,timestamp with time zone,smallint,uuid,integer,text[])') is not null,
  'edit and proposal v2 RPCs accept a file type array'
);

select ok(
  has_function_privilege('authenticated','public.cmd_create_task_v2(uuid,uuid,integer,text,text,timestamp with time zone,smallint,text,uuid,text[],boolean)','EXECUTE')
  and not has_function_privilege('anon','public.cmd_create_task_v2(uuid,uuid,integer,text,text,timestamp with time zone,smallint,text,uuid,text[],boolean)','EXECUTE'),
  'v2 command access is granted to authenticated users only'
);

select * from finish();

rollback;
