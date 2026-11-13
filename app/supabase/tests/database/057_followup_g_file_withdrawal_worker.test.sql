begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_function('public','list_pending_file_withdrawals_service',
 array['integer'],'G has trusted pending withdrawal reader');
select ok(not has_function_privilege('authenticated',
 'public.list_pending_file_withdrawals_service(integer)','EXECUTE'),
 'browser cannot read original/quarantine object keys');
select ok(has_function_privilege('service_role',
 'public.list_pending_file_withdrawals_service(integer)','EXECUTE'),
 'service role can list pending withdrawals');
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select lives_ok('select * from public.list_pending_file_withdrawals_service(20)',
 'trusted queue reader executes for service role');
select throws_ok('select * from public.list_pending_file_withdrawals_service(999)',
 '22023','INVALID_BATCH_LIMIT','queue batch has upper limit');
reset role;
select ok(
 exists(select 1 from pg_policies where schemaname='storage'
   and tablename='objects' and policyname='teamup_files_select_finalized'
   and qual like '%teamup_visible_file_version_object%')
 and pg_get_functiondef('public.teamup_visible_file_version_object(text)'::regprocedure)
   like '%file_version_withdrawals%',
 'storage signing predicate excludes pending/withdrawn file versions');
select * from finish();
rollback;
