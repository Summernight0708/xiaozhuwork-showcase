begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Owner tests still exercise the unreleased -> released transition after G publishes.
-- Keep this override transaction-local; ROLLBACK restores the migrated release allowlist.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
  select coalesce(p_capability = any(array[
    'file_full_history','file_batch_rollback','file_version_compare','project_recovery_point'
  ]::text[]), false);
$$;
revoke all on function private.capability_is_released(text)
  from public, anon, authenticated, service_role;


select has_function('public','get_my_cross_project_projects',array['text','integer','uuid'],
  'F search RPC has frozen signature');
select has_function('public','get_my_cross_project_access',array['uuid[]'],
  'F Edge access RPC exists');
select has_function('private','phase2_account_capability_failure',array['uuid','text'],
  'F account capability helper exists');
select ok(not has_function_privilege('anon','public.get_my_cross_project_projects(text,integer,uuid)','EXECUTE'),
  'anon cannot enumerate projects');
select ok(not has_function_privilege('anon','public.get_my_cross_project_access(uuid[])','EXECUTE'),
  'anon cannot enumerate access');
select ok(not has_function_privilege('authenticated','private.phase2_account_capability_failure(uuid,text)','EXECUTE'),
  'account helper remains private');
select ok(has_function_privilege('authenticated','public.get_my_cross_project_projects(text,integer,uuid)','EXECUTE'),
  'authenticated can use search RPC');
select ok(not private.capability_is_released('cross_project_overview'),
  'F capability is not prematurely released');

insert into auth.users(id,email)
select ('61000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
       'f2-cross-user-' || n || '@example.test'
from generate_series(1,8) n;

insert into public.projects(id,name,course_name,deadline_at,leader_id,created_by,lifecycle_state)
select ('62000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
       case n when 1 then '统计项目' when 2 then '统计项目'
              when 3 then 'Rocket 🚀' when 4 then '百分号 %_'
              else '仅私有项目 ' || n end,
       case n when 1 then '离散数学' when 2 then '数据库' when 3 then 'Computer Science'
              when 4 then 'SQL_100%' else '课程' end,
       now()+interval '10 days',
       (case when n=1 then '61000000-0000-0000-0000-000000000001'
            else '61000000-0000-0000-0000-000000000002' end)::uuid,
       (case when n=1 then '61000000-0000-0000-0000-000000000001'
            else '61000000-0000-0000-0000-000000000002' end)::uuid,
       'active'
from generate_series(1,8) n;

insert into public.project_members(project_id,user_id,role,member_state,is_observer)
select id,leader_id,'leader','active',false from public.projects
where id::text like '62000000-0000-0000-0000-%';

insert into public.project_members(project_id,user_id,role,member_state,is_observer,departed_at)
values
('62000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000001','admin','active',false,null),
('62000000-0000-0000-0000-000000000003','61000000-0000-0000-0000-000000000001','member','active',false,null),
('62000000-0000-0000-0000-000000000004','61000000-0000-0000-0000-000000000001','observer','active',true,null),
('62000000-0000-0000-0000-000000000005','61000000-0000-0000-0000-000000000001','member','left',false,now()),
('62000000-0000-0000-0000-000000000006','61000000-0000-0000-0000-000000000001','member','removed',false,now()),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000003','member','active',false,null),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000004','member','active',false,null),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000005','observer','active',true,null),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000006','member','active',false,null),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000007','member','active',false,null),
('62000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000008','member','active',false,null);

insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values
('61000000-0000-0000-0000-000000000001','pro','active',now()-interval '1 day',now()+interval '14 days',now(),'61000000-0000-0000-0000-000000000001','test',1),
('61000000-0000-0000-0000-000000000004','pro','active',now()-interval '1 day',now()+interval '14 days',now(),'61000000-0000-0000-0000-000000000001','test',1),
('61000000-0000-0000-0000-000000000005','pro','active',now()-interval '1 day',now()+interval '14 days',now(),'61000000-0000-0000-0000-000000000001','test',1),
('61000000-0000-0000-0000-000000000006','pro','active',now()+interval '1 day',now()+interval '14 days',now(),'61000000-0000-0000-0000-000000000001','test',1),
('61000000-0000-0000-0000-000000000007','pro','cancelled',now()-interval '1 day',now()+interval '14 days',now(),'61000000-0000-0000-0000-000000000001','test',1),
('61000000-0000-0000-0000-000000000008','pro','active',now()-interval '14 days',now()-interval '1 day',now()-interval '14 days','61000000-0000-0000-0000-000000000001','test',1);

create temp table f_checks(label text primary key, result jsonb);
grant all on f_checks to authenticated;

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f_checks values('unreleased',public.get_my_cross_project_projects());
insert into f_checks values('analytics_unreleased',public.get_my_cross_project_access());
reset role;
select is((select result->>'code' from f_checks where label='unreleased'),
  'CAPABILITY_NOT_AVAILABLE','unreleased overview closed to active Account Pro');
select is((select result->>'code' from f_checks where label='analytics_unreleased'),
  'CAPABILITY_NOT_AVAILABLE','unreleased analytics closed to active Account Pro');

-- Only the pgTAP transaction simulates G release; this is rolled back.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path = '' as $$
select p_capability = any(array[
 'file_full_history','file_batch_rollback','file_version_compare',
 'project_recovery_point','cross_project_overview','cross_project_analytics'
]::text[]);
$$;

select is(private.phase2_account_capability_failure(
 '61000000-0000-0000-0000-000000000001','unknown'),
 private.failure(null,'CAPABILITY_NOT_AVAILABLE'),
 'unknown capability remains unavailable');

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f_checks values('page1',public.get_my_cross_project_projects(null,2,null));
insert into f_checks values('search_course',public.get_my_cross_project_projects('  离散数学  ',50,null));
insert into f_checks values('search_percent',public.get_my_cross_project_projects('%',50,null));
insert into f_checks values('search_underscore',public.get_my_cross_project_projects('_',50,null));
insert into f_checks values('search_rocket',public.get_my_cross_project_projects('🚀',50,null));
insert into f_checks values('too_long',public.get_my_cross_project_projects(repeat('中',101),50,null));
insert into f_checks values('bad_limit',public.get_my_cross_project_projects(null,101,null));
insert into f_checks values('injection',public.get_my_cross_project_projects(''' OR 1=1 --',50,null));
insert into f_checks values('access_all',public.get_my_cross_project_access());
insert into f_checks values('access_zero',public.get_my_cross_project_access('{}'::uuid[]));
insert into f_checks values('access_dupe',public.get_my_cross_project_access(array[
 '62000000-0000-0000-0000-000000000001'::uuid,
 '62000000-0000-0000-0000-000000000001'::uuid
]));
insert into f_checks values('access_guess',public.get_my_cross_project_access(array[
 '62000000-0000-0000-0000-000000000001'::uuid,
 '62000000-0000-0000-0000-000000000008'::uuid
]));
reset role;

select is(jsonb_array_length((select result->'projects' from f_checks where label='page1')),2,
 'keyset first page size two');
select ok((select result->>'nextCursor' is not null from f_checks where label='page1'),
 'keyset returns next cursor');
select is(jsonb_array_length((select result->'projects' from f_checks where label='search_course')),1,
 'trimmed Chinese course search');
select is(jsonb_array_length((select result->'projects' from f_checks where label='search_percent')),1,
 'LIKE percent is escaped');
select is(jsonb_array_length((select result->'projects' from f_checks where label='search_underscore')),1,
 'LIKE underscore is escaped');
select is(jsonb_array_length((select result->'projects' from f_checks where label='search_rocket')),1,
 'Unicode project search');
select is((select result->>'code' from f_checks where label='too_long'),'VALIDATION_FAILED',
 '101 Unicode characters rejected');
select is((select result->>'code' from f_checks where label='bad_limit'),'VALIDATION_FAILED',
 'limit over 100 rejected');
select is(jsonb_array_length((select result->'projects' from f_checks where label='injection')),0,
 'SQL injection string treated literally');
select is(jsonb_array_length((select result->'projectIds' from f_checks where label='access_all')),4,
 'only four active project roles are eligible');
select is(jsonb_array_length((select result->'projectIds' from f_checks where label='access_zero')),0,
 'explicit empty project list is valid');
select is(jsonb_array_length((select result->'projectIds' from f_checks where label='access_dupe')),1,
 'duplicates are deduplicated');
select is((select result->>'code' from f_checks where label='access_guess'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','one foreign ID rejects whole selection');

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f_checks values('page2',public.get_my_cross_project_projects(
 null,2,(select (result->>'nextCursor')::uuid from f_checks where label='page1')
));
reset role;
select is(jsonb_array_length((select result->'projects' from f_checks where label='page2')),2,
 'second keyset page has remaining two active projects');
select ok((select result->>'nextCursor' is null from f_checks where label='page2'),
 'last keyset page has null cursor');

-- Simulated account states and member role distinctions.
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f_checks values('free',public.get_my_cross_project_projects());
reset role;
select is((select result->>'code' from f_checks where label='free'),'CAPABILITY_REQUIRES_PRO',
 'Free member of a Pro-source project does not inherit Account Pro');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into f_checks values('observer',public.get_my_cross_project_projects());
reset role;
select is(jsonb_array_length((select result->'projects' from f_checks where label='observer')),1,
 'active Pro observer sees project metadata only');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000006',true);
set local role authenticated;
insert into f_checks values('scheduled',public.get_my_cross_project_projects());
reset role;
select is((select result->>'code' from f_checks where label='scheduled'),'CAPABILITY_REQUIRES_PRO',
 'scheduled Account Pro denied');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000007',true);
set local role authenticated;
insert into f_checks values('cancelled',public.get_my_cross_project_projects());
reset role;
select is((select result->>'code' from f_checks where label='cancelled'),'CAPABILITY_REQUIRES_PRO',
 'cancelled Account Pro denied');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000008',true);
set local role authenticated;
insert into f_checks values('expired',public.get_my_cross_project_projects());
reset role;
select is((select result->>'code' from f_checks where label='expired'),'CAPABILITY_REQUIRES_PRO',
 'expired Account Pro denied');

-- Revocation takes effect at the next query: no cached project list.
update public.project_members
set member_state='removed',departed_at=now()
where project_id='62000000-0000-0000-0000-000000000004'
 and user_id='61000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into f_checks values('after_revoke',public.get_my_cross_project_access(
 array['62000000-0000-0000-0000-000000000004'::uuid]
));
reset role;
select is((select result->>'code' from f_checks where label='after_revoke'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','removed member cannot reuse cached project ID');

select * from finish();
rollback;
