begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('c1400000-0000-0000-0000-000000000001','c1-source-test@example.test'),
 ('c1400000-0000-0000-0000-000000000002','c1-source-gift@example.test'),
 ('c1400000-0000-0000-0000-000000000003','c1-source-commercial@example.test'),
 ('c1400000-0000-0000-0000-000000000004','c1-source-other@example.test'),
 ('c1400000-0000-0000-0000-000000000005','c1-source-legacy-reject@example.test'),
 ('c1400000-0000-0000-0000-000000000006','c1-source-arbitrary-reject@example.test'),
 ('c1400000-0000-0000-0000-000000000007','c1-source-legacy-store@example.test'),
 ('c1400000-0000-0000-0000-000000000008','c1-source-arbitrary-store@example.test');

create temporary table c1_results(label text primary key,result jsonb);
grant all on c1_results to service_role;

set local role service_role;
insert into c1_results values(
 'test',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000001',
   'c1490000-0000-0000-0000-000000000001',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'test','c1 test source'
 )
);
insert into c1_results values(
 'gift',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000002',
   'c1490000-0000-0000-0000-000000000002',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'gift','c1 gift source'
 )
);
insert into c1_results values(
 'commercial',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000003',
   'c1490000-0000-0000-0000-000000000003',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'commercial','c1 commercial source'
 )
);
insert into c1_results values(
 'other',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000004',
   'c1490000-0000-0000-0000-000000000004',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'other','c1 other source'
 )
);
insert into c1_results values(
 'legacy-rejected',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000005',
   'c1490000-0000-0000-0000-000000000005',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'legacy_unknown','legacy must not be a new write'
 )
);
insert into c1_results values(
 'arbitrary-rejected',
 public.cmd_set_account_entitlement_service(
   'c1400000-0000-0000-0000-000000000006',
   'c1490000-0000-0000-0000-000000000006',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',0,
   null,'manual_workbench','old arbitrary source must fail'
 )
);
reset role;

select is(
 (select result->>'ok' from c1_results where label='test'),
 'true',
 'test is accepted as a new grant source'
);
select is(
 (select result->>'ok' from c1_results where label='gift'),
 'true',
 'gift is accepted as a new grant source'
);
select is(
 (select result->>'ok' from c1_results where label='commercial'),
 'true',
 'commercial is accepted as a new grant source'
);
select is(
 (select result->>'ok' from c1_results where label='other'),
 'true',
 'other is accepted as a new grant source'
);
select is(
 (select result->>'code' from c1_results where label='legacy-rejected'),
 'VALIDATION_FAILED',
 'legacy_unknown cannot be used by a new service mutation'
);
select is(
 (select result->>'field' from c1_results where label='legacy-rejected'),
 'grantSource',
 'legacy_unknown rejection identifies grantSource'
);
select is(
 (select result->>'code' from c1_results where label='arbitrary-rejected'),
 'VALIDATION_FAILED',
 'old arbitrary source cannot be used by a new service mutation'
);
select is(
 (select result->>'field' from c1_results where label='arbitrary-rejected'),
 'grantSource',
 'arbitrary-source rejection identifies grantSource'
);

select is(
 (select grant_source from public.account_entitlements
  where user_id='c1400000-0000-0000-0000-000000000001'),
 'test',
 'accepted source persists exactly'
);
select is(
 (select grant_source from public.account_entitlements
  where user_id='c1400000-0000-0000-0000-000000000002'),
 'gift',
 'gift source persists exactly'
);
select is(
 (select grant_source from public.account_entitlements
  where user_id='c1400000-0000-0000-0000-000000000003'),
 'commercial',
 'commercial source persists exactly'
);
select is(
 (select grant_source from public.account_entitlements
  where user_id='c1400000-0000-0000-0000-000000000004'),
 'other',
 'other source persists exactly'
);

insert into public.account_entitlements(
 user_id,plan,status,starts_at,expires_at,granted_at,granted_by,
 grant_source,note,version
) values(
 'c1400000-0000-0000-0000-000000000007',
 'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',
 now(),null,'legacy_unknown','normalized historical row',1
);

select is(
 (select grant_source from public.account_entitlements
  where user_id='c1400000-0000-0000-0000-000000000007'),
 'legacy_unknown',
 'storage contract preserves normalized historical source'
);

select throws_ok(
 $$insert into public.account_entitlements(
   user_id,plan,status,starts_at,expires_at,granted_at,granted_by,
   grant_source,note,version
 ) values(
   'c1400000-0000-0000-0000-000000000008',
   'pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',
   now(),null,'manual_workbench','invalid stored source',1
 )$$,
 '23514',
 null,
 'stored entitlement rejects source outside the five-value contract'
);

insert into public.account_entitlement_audit(
 user_id,request_id,action,plan,status,starts_at,expires_at,granted_at,
 granted_by,grant_source,note,entitlement_version
) values(
 'c1400000-0000-0000-0000-000000000007',
 'c1490000-0000-0000-0000-000000000007',
 'granted','pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',
 now(),null,'legacy_unknown','normalized historical audit',1
);

select throws_ok(
 $$insert into public.account_entitlement_audit(
   user_id,request_id,action,plan,status,starts_at,expires_at,granted_at,
   granted_by,grant_source,note,entitlement_version
 ) values(
   'c1400000-0000-0000-0000-000000000008',
   'c1490000-0000-0000-0000-000000000008',
   'granted','pro','active','2026-10-01T00:00:00Z','2027-10-01T00:00:00Z',
   now(),null,'operator_manual','invalid historical source',1
 )$$,
 '23514',
 null,
 'stored audit rejects source outside the five-value contract'
);

select is(
 (
   select count(*)::integer
   from public.account_entitlement_audit
   where request_id in (
     'c1490000-0000-0000-0000-000000000001',
     'c1490000-0000-0000-0000-000000000002',
     'c1490000-0000-0000-0000-000000000003',
     'c1490000-0000-0000-0000-000000000004',
     'c1490000-0000-0000-0000-000000000007'
   )
     and action='granted'
     and grant_source='commercial'
 ),
 1,
 'commercial-grant aggregation counts only source commercial'
);
select is(
 (
   select count(*)::integer
   from public.account_entitlement_audit
   where request_id in (
     'c1490000-0000-0000-0000-000000000001',
     'c1490000-0000-0000-0000-000000000002',
     'c1490000-0000-0000-0000-000000000004',
     'c1490000-0000-0000-0000-000000000007'
   )
     and grant_source in ('test','gift','other','legacy_unknown')
 ),
 4,
 'test gift other and legacy_unknown remain excluded noncommercial facts'
);

select ok(
 not exists(
   select 1 from public.account_entitlements
   where grant_source not in ('test','gift','commercial','other','legacy_unknown')
 ),
 'post-migration entitlement rows contain only frozen stored sources'
);
select ok(
 not exists(
   select 1 from public.account_entitlement_audit
   where grant_source not in ('test','gift','commercial','other','legacy_unknown')
 ),
 'post-migration audit rows contain only frozen stored sources'
);
select ok(
 exists(
   select 1
   from pg_trigger
   where tgrelid='public.account_entitlement_audit'::regclass
     and tgname='account_entitlement_audit_immutable'
     and tgenabled='O'
     and not tgisinternal
 ),
 'account entitlement audit immutable trigger is enabled'
);
select throws_ok(
 $$update public.account_entitlement_audit
   set grant_source='commercial'
   where request_id='c1490000-0000-0000-0000-000000000007'$$,
 '55000',
 'Account entitlement audit is immutable',
 'historical normalization does not weaken audit immutability'
);
select throws_ok(
 $$delete from public.account_entitlement_audit
   where request_id='c1490000-0000-0000-0000-000000000007'$$,
 '55000',
 'Account entitlement audit is immutable',
 'historical audit rows remain undeletable'
);

select * from finish();
rollback;
