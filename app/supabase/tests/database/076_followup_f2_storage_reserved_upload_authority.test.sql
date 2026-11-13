begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_function(
 'public','teamup_storage_reserved_upload_allowed',array['text'],
 'Storage upload predicate lives behind a boolean RPC');
select ok(
 has_function_privilege('authenticated',
  'public.teamup_storage_reserved_upload_allowed(text)','EXECUTE'),
 'ordinary member upload policy can call trusted predicate');
select ok(
 not has_function_privilege('anon',
  'public.teamup_storage_reserved_upload_allowed(text)','EXECUTE'),
 'anonymous caller cannot probe reservation predicate');
select ok(
 not has_column_privilege('authenticated',
  'public.file_upload_reservations','actor_id','SELECT'),
 'Storage authorization does not reopen raw reservation actor UUID');
select ok(
 not has_column_privilege('authenticated',
  'public.task_file_versions','uploaded_by','SELECT'),
 'Storage permission repair does not reopen historical uploader UUID');
select ok(
 (select with_check like '%teamup_storage_reserved_upload_allowed%'
  from pg_catalog.pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname='teamup_files_insert_reserved'),
 'Storage INSERT policy uses the scoped definer predicate');
select ok(
 (select with_check like '%teamup_active_upload_reservation%'
  from pg_catalog.pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname='teamup_files_reject_archived_upload'),
 'archived reservation protection is preserved unchanged');
select is(
 public.teamup_storage_reserved_upload_allowed('not-an-upload-path'),
 false,'missing reservation remains denied');
create temp table f2_storage_denial(value boolean);
grant all on f2_storage_denial to authenticated;
select set_config('request.jwt.claim.sub',
 'f7c00000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f2_storage_denial values (
 public.teamup_storage_reserved_upload_allowed('pending/unknown/unknown')
);
reset role;
select is((select value from f2_storage_denial),false,
 'authenticated actor with no active reservation is denied');
select * from finish();
rollback;
