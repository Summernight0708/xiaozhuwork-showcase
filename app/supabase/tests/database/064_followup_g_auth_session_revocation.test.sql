begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function('public','lifecycle_list_expired_revocation_candidates_service',
  array['integer'],'G exposes service-only revocation candidate reader');
select has_function('public','lifecycle_finalize_auth_revocation_service',
  array['uuid','integer'],'G exposes generation-fenced revocation completion');
select ok(not has_function_privilege('authenticated',
 'public.lifecycle_finalize_auth_revocation_service(uuid,integer)','EXECUTE'),
 'ordinary user cannot revoke auth credentials');
select ok(not has_function_privilege('anon',
 'public.lifecycle_list_expired_revocation_candidates_service(integer)','EXECUTE'),
 'anon cannot enumerate expired user identities');

insert into auth.users(id,email) values
('c2100000-0000-0000-0000-000000000001','g-expired-auth-user@example.test');
insert into public.account_lifecycle_requests(
 user_id,state,generation,version,requested_at,cancel_until
) values('c2100000-0000-0000-0000-000000000001','pending',3,3,
 now()-interval '40 days',now()-interval '10 days');
insert into auth.sessions(id,user_id)
values('c2300000-0000-0000-0000-000000000001',
 'c2100000-0000-0000-0000-000000000001');
insert into auth.refresh_tokens(token,user_id,session_id,revoked)
values ('isolated-pgtap-token-which-must-be-revoked',
 'c2100000-0000-0000-0000-000000000001',
 'c2300000-0000-0000-0000-000000000001',false);

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is((select count(*)::int from
 public.lifecycle_list_expired_revocation_candidates_service(25)
 where user_id='c2100000-0000-0000-0000-000000000001'),1,
 'expired pending account appears in service queue');
select is(public.lifecycle_finalize_auth_revocation_service(
 'c2100000-0000-0000-0000-000000000001',3)->>'code',
 'AUTH_BAN_NOT_VERIFIED','cannot claim revocation before Auth ban');
reset role;

update auth.users set banned_until=now()+interval '365 days'
where id='c2100000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(public.lifecycle_finalize_auth_revocation_service(
 'c2100000-0000-0000-0000-000000000001',2)->>'code',
 'REVOCATION_NOT_DUE','stale generation cannot revoke another cycle');
select is(public.lifecycle_finalize_auth_revocation_service(
 'c2100000-0000-0000-0000-000000000001',3)->>'ok',
 'true','external Auth ban + verified session cleanup marks checkpoint');
select is(public.lifecycle_finalize_auth_revocation_service(
 'c2100000-0000-0000-0000-000000000001',3)->>'replayed',
 'true','subsequent dispatch is idempotent');
reset role;

select is((select count(*)::integer from auth.sessions where
 user_id='c2100000-0000-0000-0000-000000000001'),0,
 'actual Auth sessions removed');
select is((select count(*)::integer from auth.refresh_tokens where
 user_id='c2100000-0000-0000-0000-000000000001'),0,
 'actual refresh tokens removed');
select ok((select auth_revoked_at is not null
 from public.account_lifecycle_requests where
 user_id='c2100000-0000-0000-0000-000000000001'),
 'revocation evidence recorded only after both Auth barriers pass');
select is((select count(*)::integer from private.account_lifecycle_audit
 where user_id='c2100000-0000-0000-0000-000000000001'
 and action='auth_sessions_revoked'),1,
 'revocation checkpoint audited once');

select * from finish();
rollback;
