begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function('public','lifecycle_pii_preflight_service',
  array['uuid'],'service-only account PII preflight entry exists');
select ok(not has_function_privilege('authenticated',
  'public.lifecycle_pii_preflight_service(uuid)','EXECUTE'),
  'authenticated user cannot enumerate per-account PII references');
select ok(not has_function_privilege('anon',
  'public.lifecycle_pii_preflight_service(uuid)','EXECUTE'),
  'anon cannot enumerate PII reference locations');
select ok(has_function_privilege('service_role',
  'public.lifecycle_pii_preflight_service(uuid)','EXECUTE'),
  'trusted service may execute metadata-only preflight');

insert into auth.users(id,email)
values ('f6100000-0000-0000-0000-000000000001','f-pii-preflight@example.test');
-- The Auth signup trigger creates the corresponding profile automatically.
update public.profiles set display_name='Sensitive Display',
  real_name='Sensitive Real', student_number='Sensitive Student'
where id='f6100000-0000-0000-0000-000000000001';
insert into public.account_lifecycle_requests(
  user_id,state,generation,version,requested_at,cancel_until)
values ('f6100000-0000-0000-0000-000000000001',
  'pending',1,1,now()-interval '8 days',now()+interval '22 days');

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select is(public.lifecycle_pii_preflight_service(
  'f6100000-0000-0000-0000-000000000001')->>'redactionAllowed',
  'false','preflight cannot approve redaction');
select is(public.lifecycle_pii_preflight_service(
  'f6100000-0000-0000-0000-000000000001')->>'irreversibleDeletes',
  '0','preflight cannot delete anything');
select ok(
  (public.lifecycle_pii_preflight_service(
    'f6100000-0000-0000-0000-000000000001')->>'directReferenceColumnsScanned')::int > 10,
  'live schema is scanned across multiple identities, not hardcoded single table');
select ok(
  public.lifecycle_pii_preflight_service(
    'f6100000-0000-0000-0000-000000000001')->'directReferenceHits'
      @> '[{"schema":"public","table":"profiles","column":"id","linkedRows":1}]'::jsonb,
  'own profile identity found without leaking actual personal details');
select ok(
  public.lifecycle_pii_preflight_service(
    'f6100000-0000-0000-0000-000000000001')->'possibleIndirectPiiFields'
      @> '[{"schema":"public","table":"contribution_items","column":"member_display_name_snapshot"}]'::jsonb,
  'immutable contribution snapshots flagged for separate review');
select ok(
  public.lifecycle_pii_preflight_service(
    'f6100000-0000-0000-0000-000000000001')->'possibleIndirectPiiFields'
      @> '[{"schema":"auth","table":"users","column":"email"}]'::jsonb,
  'Auth account email is in risk inventory');
select is(public.lifecycle_pii_preflight_service(
  'f6200000-0000-0000-0000-000000000001')->>'code',
  'NO_ACTIVE_LIFECYCLE_REQUEST','no lifecycle case cannot be audited as eligible');
reset role;
select is((select state from public.account_lifecycle_requests
  where user_id='f6100000-0000-0000-0000-000000000001'),
  'pending','preflight never advances state');
select is((select real_name from public.profiles
  where id='f6100000-0000-0000-0000-000000000001'),
  'Sensitive Real','preflight never mutates sensitive profile');
select * from finish();
rollback;
