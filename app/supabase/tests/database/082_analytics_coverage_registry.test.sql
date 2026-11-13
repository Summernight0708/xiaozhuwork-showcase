begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'private',
  'analytics_coverage',
  'analytics coverage lives in the private schema'
);

select ok(
  not has_table_privilege('anon','private.analytics_coverage','SELECT'),
  'anon cannot read analytics coverage directly'
);
select ok(
  not has_table_privilege('authenticated','private.analytics_coverage','SELECT'),
  'authenticated cannot read analytics coverage directly'
);
select ok(
  not has_table_privilege('service_role','private.analytics_coverage','SELECT'),
  'service role must use the audited RPC boundary instead of direct table reads'
);

select throws_ok(
  $$insert into private.analytics_coverage(source,complete_since,definition_version,verified_at,note)
    values('browser',now(),1,now(),null)$$,
  '23514',
  null,
  'coverage source is constrained to the four approved sources'
);

select throws_ok(
  $$insert into private.analytics_coverage(source,complete_since,definition_version,verified_at,note)
    values('auth',now(),0,now(),null)$$,
  '23514',
  null,
  'definition version must be positive'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.cmd_set_analytics_coverage_service(text,timestamptz,integer,timestamptz,text)',
    'EXECUTE'
  ),
  'anon cannot set analytics coverage'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.cmd_set_analytics_coverage_service(text,timestamptz,integer,timestamptz,text)',
    'EXECUTE'
  ),
  'authenticated cannot set analytics coverage'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.cmd_set_analytics_coverage_service(text,timestamptz,integer,timestamptz,text)',
    'EXECUTE'
  ),
  'service role can set analytics coverage'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_analytics_coverage_service()',
    'EXECUTE'
  ),
  'anon cannot read analytics coverage'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_analytics_coverage_service()',
    'EXECUTE'
  ),
  'authenticated cannot read analytics coverage'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.get_analytics_coverage_service()',
    'EXECUTE'
  ),
  'service role can read analytics coverage'
);

select ok(
  not exists(
    select 1
    from information_schema.routine_privileges
    where routine_schema='public'
      and routine_name in (
        'cmd_set_analytics_coverage_service',
        'get_analytics_coverage_service'
      )
      and grantee='PUBLIC'
      and privilege_type='EXECUTE'
  ),
  'coverage RPCs have no PUBLIC execute grant'
);

create temp table coverage_results(label text primary key,result jsonb);
grant all on coverage_results to service_role;

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;

insert into coverage_results values(
  'auth-first',
  public.cmd_set_analytics_coverage_service(
    'auth',
    '2026-10-14T00:00:00Z',
    1,
    '2026-10-14T01:00:00Z',
    'auth beta coverage verified'
  )
);
insert into coverage_results values(
  'auth-repeat',
  public.cmd_set_analytics_coverage_service(
    'auth',
    '2026-10-14T00:00:00Z',
    1,
    '2026-10-14T01:00:00Z',
    'auth beta coverage verified'
  )
);
insert into coverage_results values(
  'umami',
  public.cmd_set_analytics_coverage_service(
    'umami',
    '2026-10-14T02:00:00Z',
    1,
    '2026-10-14T03:00:00Z',
    null
  )
);
insert into coverage_results values(
  'sentry',
  public.cmd_set_analytics_coverage_service(
    'sentry',
    '2026-10-14T04:00:00Z',
    2,
    '2026-10-14T05:00:00Z',
    'privacy scrub v2'
  )
);
insert into coverage_results values(
  'business',
  public.cmd_set_analytics_coverage_service(
    'business_analytics',
    '2026-10-14T06:00:00Z',
    3,
    '2026-10-14T07:00:00Z',
    'business semantic layer v3'
  )
);
insert into coverage_results values(
  'all',
  public.get_analytics_coverage_service()
);

reset role;

select is(
  (select result->>'ok' from coverage_results where label='auth-first'),
  'true',
  'service set succeeds'
);
select is(
  (select result from coverage_results where label='auth-repeat'),
  (select result from coverage_results where label='auth-first'),
  'repeating the same coverage write is idempotent'
);
select is(
  (select count(*)::integer from private.analytics_coverage where source='auth'),
  1,
  'idempotent write keeps one row per source'
);
select is(
  (select definition_version from private.analytics_coverage where source='sentry'),
  2,
  'definition version is persisted'
);
select is(
  (select note from private.analytics_coverage where source='business_analytics'),
  'business semantic layer v3',
  'non-sensitive operator note is persisted'
);
select is(
  jsonb_array_length((select result->'data' from coverage_results where label='all')),
  4,
  'coverage reader returns all four registered sources'
);
select ok(
  (select result->'data' from coverage_results where label='all')
    @> '[{"source":"auth"},{"source":"umami"},{"source":"sentry"},{"source":"business_analytics"}]'::jsonb,
  'coverage reader identifies every approved source'
);

select set_config('request.jwt.claim.role','',true);
select throws_ok(
  $$select public.get_analytics_coverage_service()$$,
  '42501',
  'SERVICE_ROLE_REQUIRED',
  'privileged SQL caller without service JWT role still fails closed'
);

select * from finish();
rollback;
