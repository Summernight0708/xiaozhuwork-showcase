begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_function('public','dispatch_contribution_penalty_events_service',
 array['integer'],'G has bounded penalty drain');
select ok(not has_function_privilege('authenticated',
 'public.dispatch_contribution_penalty_events_service(integer)','EXECUTE'),
 'member cannot run penalty dispatcher');
select ok(not has_function_privilege('anon',
 'public.dispatch_contribution_penalty_events_service(integer)','EXECUTE'),
 'anon cannot run penalty dispatcher');
select ok(has_function_privilege('service_role',
 'public.dispatch_contribution_penalty_events_service(integer)','EXECUTE'),
 'service dispatcher grant is narrow');
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(public.dispatch_contribution_penalty_events_service(100)->>'ok',
 'true','service dispatch succeeds against empty queue');
select throws_ok('select public.dispatch_contribution_penalty_events_service(101)',
 '22023','INVALID_BATCH_LIMIT','batch is capped to avoid huge transactions');
reset role;
select * from finish();
rollback;
