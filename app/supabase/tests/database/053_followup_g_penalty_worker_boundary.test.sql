begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function('public','process_contribution_penalty_event_service',
  array['bigint'],'G exposes a narrowly scoped public service dispatcher');
select ok(not has_schema_privilege('service_role','private','USAGE'),
  'service role cannot address arbitrary private functions');
select ok(not has_function_privilege('anon',
  'public.process_contribution_penalty_event_service(bigint)','EXECUTE'),
  'anonymous role cannot run contribution penalty worker');
select ok(not has_function_privilege('authenticated',
  'public.process_contribution_penalty_event_service(bigint)','EXECUTE'),
  'authenticated role cannot run contribution penalty worker');
select ok(has_function_privilege('service_role',
  'public.process_contribution_penalty_event_service(bigint)','EXECUTE'),
  'service role can run the guarded dispatcher');
select ok(not has_function_privilege('service_role',
  'private.process_contribution_penalty_event(bigint)','EXECUTE'),
  'service role cannot invoke E private worker directly');

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(
  (public.process_contribution_penalty_event_service(-1)->>'code'),
  'SOURCE_NOT_FOUND',
  'service role dispatcher delegates safely and denies missing event');
reset role;

select * from finish();
rollback;
