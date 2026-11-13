begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email)
select ('d1100000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
       'p1-quota-' || i || '@example.test'
from generate_series(1,90) s(i);
update public.profiles
set display_name='P1 User',real_name='P1 Real',student_number='P1'
where id::text like 'd1100000-0000-0000-0000-%';

create temporary table p1_results(label text primary key,result jsonb);
grant all on p1_results to authenticated;

select has_function(
  'private','resolve_project_entitlement_with_prospective_member',
  array['uuid','uuid','text','timestamp with time zone'],
  'prospective project entitlement helper exists'
);
select has_function(
  'private','project_member_limit_for_prospective_member',
  array['uuid','uuid','text','timestamp with time zone'],
  'prospective member limit helper exists'
);

-- Free account: fifth Free project succeeds; sixth is blocked with a stable code.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('d2100000-0000-0000-0001-'||lpad(i::text,12,'0'))::uuid,
       'P1 free quota '||i,now()+interval '20 days',
       'd1100000-0000-0000-0000-000000000001',
       'd1100000-0000-0000-0000-000000000001'
from generate_series(1,4) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select id,'d1100000-0000-0000-0000-000000000001','leader','active'
from public.projects where created_by='d1100000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into p1_results values(
  'free-fifth',
  public.cmd_create_project(
    'd4100000-0000-0000-0000-000000000001',0,'P1 fifth Free',
    now()+interval '20 days',null,null,null,null,null,null
  )
);
insert into p1_results values(
  'free-sixth',
  public.cmd_create_project(
    'd4100000-0000-0000-0000-000000000002',0,'P1 sixth Free',
    now()+interval '20 days',null,null,null,null,null,null
  )
);
reset role;

select is((select result->>'ok' from p1_results where label='free-fifth'),'true','fifth active Free project is allowed');
select is((select result->>'code' from p1_results where label='free-sixth'),'ACTIVE_FREE_PROJECT_LIMIT_REACHED','sixth active Free project uses stable quota code');
select is((select (result->'details'->>'limit')::integer from p1_results where label='free-sixth'),5,'account quota reports limit five');
select is((select (result->'details'->>'current')::integer from p1_results where label='free-sixth'),5,'account quota reports current Free-project count');

-- Active Pro account can create beyond five because its new leader project is prospective Pro.
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'd1100000-0000-0000-0000-000000000002','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'd1100000-0000-0000-0000-000000000001','test',1
);
insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('d2100000-0000-0000-0002-'||lpad(i::text,12,'0'))::uuid,
       'P1 pro existing '||i,now()+interval '20 days',
       'd1100000-0000-0000-0000-000000000002',
       'd1100000-0000-0000-0000-000000000002'
from generate_series(1,6) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select id,'d1100000-0000-0000-0000-000000000002','leader','active'
from public.projects where created_by='d1100000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into p1_results values(
  'pro-unlimited',
  public.cmd_create_project(
    'd4100000-0000-0000-0000-000000000003',0,'P1 Pro extra',
    now()+interval '20 days',null,null,null,null,null,null
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='pro-unlimited'),'true','active Pro account can create beyond five');

-- Pro and Grace projects do not count toward a Free account's five-project quota.
insert into public.projects(id,name,deadline_at,leader_id,created_by) values
('d2100000-0000-0000-0003-000000000001','P1 count free 1',now()+interval '20 days','d1100000-0000-0000-0000-000000000003','d1100000-0000-0000-0000-000000000003'),
('d2100000-0000-0000-0003-000000000002','P1 count free 2',now()+interval '20 days','d1100000-0000-0000-0000-000000000003','d1100000-0000-0000-0000-000000000003'),
('d2100000-0000-0000-0003-000000000003','P1 count free 3',now()+interval '20 days','d1100000-0000-0000-0000-000000000003','d1100000-0000-0000-0000-000000000003'),
('d2100000-0000-0000-0003-000000000004','P1 count pro',now()+interval '20 days','d1100000-0000-0000-0000-000000000004','d1100000-0000-0000-0000-000000000004'),
('d2100000-0000-0000-0003-000000000005','P1 count grace',now()+interval '20 days','d1100000-0000-0000-0000-000000000005','d1100000-0000-0000-0000-000000000005');
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
('d2100000-0000-0000-0003-000000000001','d1100000-0000-0000-0000-000000000003','leader','active',false),
('d2100000-0000-0000-0003-000000000002','d1100000-0000-0000-0000-000000000003','leader','active',false),
('d2100000-0000-0000-0003-000000000003','d1100000-0000-0000-0000-000000000003','leader','active',false),
('d2100000-0000-0000-0003-000000000004','d1100000-0000-0000-0000-000000000004','leader','active',false),
('d2100000-0000-0000-0003-000000000004','d1100000-0000-0000-0000-000000000003','observer','active',true),
('d2100000-0000-0000-0003-000000000005','d1100000-0000-0000-0000-000000000005','leader','active',false),
('d2100000-0000-0000-0003-000000000005','d1100000-0000-0000-0000-000000000003','observer','active',true);
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values (
  'd1100000-0000-0000-0000-000000000004','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'd1100000-0000-0000-0000-000000000001','test',1
);
insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values('d2100000-0000-0000-0003-000000000005',now(),now()+interval '3 days','account_expired',1);
select is(
  private.account_active_free_project_count('d1100000-0000-0000-0000-000000000003',transaction_timestamp()),
  3,
  'Pro and Grace projects do not count toward Free-account project quota'
);

-- Free member cap and prospective Pro member admission.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
values('d2100000-0000-0000-0004-000000000001','P1 prospective direct',now()+interval '20 days','d1100000-0000-0000-0000-000000000010','d1100000-0000-0000-0000-000000000010');
insert into public.project_members(project_id,user_id,role,member_state)
select 'd2100000-0000-0000-0004-000000000001',
       ('d1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       case when i=10 then 'leader' else 'member' end,'active'
from generate_series(10,17) s(i);
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values
('d1100000-0000-0000-0000-000000000020','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1),
('d1100000-0000-0000-0000-000000000021','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1);
select is(
  private.project_member_limit_for_prospective_member(
    'd2100000-0000-0000-0004-000000000001',
    'd1100000-0000-0000-0000-000000000021','member',transaction_timestamp()
  ),
  20,
  'prospective active Pro member raises Free project member limit to twenty'
);
select is(
  private.project_member_limit_for_prospective_member(
    'd2100000-0000-0000-0004-000000000001',
    'd1100000-0000-0000-0000-000000000021','observer',transaction_timestamp()
  ),
  8,
  'prospective Pro observer does not raise member limit'
);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values(
  'd3100000-0000-0000-0000-000000000001',
  'd2100000-0000-0000-0004-000000000001',
  'd1100000-0000-0000-0000-000000000010',
  extensions.digest(convert_to('p1-prospective-direct','utf8'),'sha256'),
  'direct',now()+interval '7 days'
);
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000020',true);
set local role authenticated;
insert into p1_results values(
  'prospective-direct',
  public.cmd_join_project_via_invite(
    'p1-prospective-direct','d4100000-0000-0000-0000-000000000010',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='prospective-direct'),'true','ninth active Pro member can join a currently Free eight-member project');
select is(
  (select state from private.resolve_project_entitlement('d2100000-0000-0000-0004-000000000001',transaction_timestamp())),
  'active',
  'prospective Pro member makes project active Pro after join'
);
select is(
  (select count(*)::integer from public.project_members where project_id='d2100000-0000-0000-0004-000000000001' and member_state='active' and user_id is not null),
  9,
  'prospective join creates the ninth member'
);

-- A Free ninth member is rejected with the stable member quota code.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
values('d2100000-0000-0000-0004-000000000002','P1 free member cap',now()+interval '20 days','d1100000-0000-0000-0000-000000000010','d1100000-0000-0000-0000-000000000010');
insert into public.project_members(project_id,user_id,role,member_state)
select 'd2100000-0000-0000-0004-000000000002',
       ('d1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       case when i=10 then 'leader' else 'member' end,'active'
from generate_series(10,17) s(i);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values(
  'd3100000-0000-0000-0000-000000000002',
  'd2100000-0000-0000-0004-000000000002',
  'd1100000-0000-0000-0000-000000000010',
  extensions.digest(convert_to('p1-free-ninth','utf8'),'sha256'),
  'direct',now()+interval '7 days'
);
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000018',true);
set local role authenticated;
insert into p1_results values(
  'free-ninth',
  public.cmd_join_project_via_invite('p1-free-ninth','d4100000-0000-0000-0000-000000000011',1)
);
reset role;
select is((select result->>'code' from p1_results where label='free-ninth'),'PROJECT_MEMBER_LIMIT_REACHED','Free ninth member is rejected with stable code');
select is((select (result->'details'->>'limit')::integer from p1_results where label='free-ninth'),8,'Free member quota reports limit eight');
select is((select (result->'details'->>'current')::integer from p1_results where label='free-ninth'),8,'Free member quota reports current eight');

-- Approval path uses the same prospective semantics.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
values('d2100000-0000-0000-0004-000000000003','P1 prospective approval',now()+interval '20 days','d1100000-0000-0000-0000-000000000030','d1100000-0000-0000-0000-000000000030');
insert into public.project_members(project_id,user_id,role,member_state)
select 'd2100000-0000-0000-0004-000000000003',
       ('d1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       case when i=30 then 'leader' else 'member' end,'active'
from generate_series(30,37) s(i);
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values(
  'd1100000-0000-0000-0000-000000000038','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'd1100000-0000-0000-0000-000000000001','test',1
);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values(
  'd3100000-0000-0000-0000-000000000003',
  'd2100000-0000-0000-0004-000000000003',
  'd1100000-0000-0000-0000-000000000030',
  extensions.digest(convert_to('p1-prospective-approval','utf8'),'sha256'),
  'approval',now()+interval '7 days'
);
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000038',true);
set local role authenticated;
insert into p1_results values(
  'approval-request',
  public.cmd_join_project_via_invite(
    'p1-prospective-approval','d4100000-0000-0000-0000-000000000012',0
  )
);
reset role;
select (result->'data'->>'joinRequestId')::uuid as p1_join_request_id
from p1_results where label='approval-request' \gset
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000030',true);
set local role authenticated;
insert into p1_results values(
  'approval-prospective',
  public.cmd_review_project_join_request(
    'd2100000-0000-0000-0004-000000000003',:'p1_join_request_id','approve',
    'd4100000-0000-0000-0000-000000000013',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='approval-prospective'),'true','approval path allows ninth prospective Pro member');

-- Active Pro and Grace projects use the twenty-member cap.
insert into public.projects(id,name,deadline_at,leader_id,created_by) values
('d2100000-0000-0000-0005-000000000001','P1 Pro member cap',now()+interval '20 days','d1100000-0000-0000-0000-000000000040','d1100000-0000-0000-0000-000000000040'),
('d2100000-0000-0000-0005-000000000002','P1 Grace member cap',now()+interval '20 days','d1100000-0000-0000-0000-000000000041','d1100000-0000-0000-0000-000000000041');
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values(
  'd1100000-0000-0000-0000-000000000040','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'd1100000-0000-0000-0000-000000000001','test',1
);
insert into public.project_members(project_id,user_id,role,member_state)
select 'd2100000-0000-0000-0005-000000000001',
       ('d1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       case when i=40 then 'leader' else 'member' end,'active'
from generate_series(40,59) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select 'd2100000-0000-0000-0005-000000000002',
       ('d1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       case when i=41 then 'leader' else 'member' end,'active'
from generate_series(41,60) s(i);
insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values('d2100000-0000-0000-0005-000000000002',now(),now()+interval '3 days','account_expired',1);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at) values
('d3100000-0000-0000-0000-000000000004','d2100000-0000-0000-0005-000000000001','d1100000-0000-0000-0000-000000000040',extensions.digest(convert_to('p1-pro-21','utf8'),'sha256'),'direct',now()+interval '7 days'),
('d3100000-0000-0000-0000-000000000005','d2100000-0000-0000-0005-000000000002','d1100000-0000-0000-0000-000000000041',extensions.digest(convert_to('p1-grace-21','utf8'),'sha256'),'direct',now()+interval '7 days');
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000061',true);
set local role authenticated;
insert into p1_results values('pro-member-21',public.cmd_join_project_via_invite('p1-pro-21','d4100000-0000-0000-0000-000000000014',1));
reset role;
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000062',true);
set local role authenticated;
insert into p1_results values('grace-member-21',public.cmd_join_project_via_invite('p1-grace-21','d4100000-0000-0000-0000-000000000015',1));
reset role;
select is((select result->>'code' from p1_results where label='pro-member-21'),'PROJECT_MEMBER_LIMIT_REACHED','active Pro project rejects twenty-first member');
select is((select (result->'details'->>'limit')::integer from p1_results where label='pro-member-21'),20,'active Pro member limit is twenty');
select is((select result->>'code' from p1_results where label='grace-member-21'),'PROJECT_MEMBER_LIMIT_REACHED','Grace project rejects twenty-first member');
select is((select result->'details'->>'effectiveState' from p1_results where label='grace-member-21'),'grace','Grace member quota reports grace state');

-- A Free account at five Free projects may still join a Pro/Grace project without consuming quota.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('d2100000-0000-0000-0006-'||lpad(i::text,12,'0'))::uuid,
       'P1 join quota base '||i,now()+interval '20 days',
       'd1100000-0000-0000-0000-000000000063',
       'd1100000-0000-0000-0000-000000000063'
from generate_series(1,5) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select id,'d1100000-0000-0000-0000-000000000063','leader','active'
from public.projects where created_by='d1100000-0000-0000-0000-000000000063';
insert into public.projects(id,name,deadline_at,leader_id,created_by)
values(
  'd2100000-0000-0000-0006-000000000099','P1 join Pro target',
  now()+interval '20 days',
  'd1100000-0000-0000-0000-000000000040',
  'd1100000-0000-0000-0000-000000000040'
);
insert into public.project_members(project_id,user_id,role,member_state)
values(
  'd2100000-0000-0000-0006-000000000099',
  'd1100000-0000-0000-0000-000000000040',
  'leader','active'
);
insert into public.project_invitations(id,project_id,created_by,token_hash,mode,expires_at)
values(
  'd3100000-0000-0000-0000-000000000006',
  'd2100000-0000-0000-0006-000000000099',
  'd1100000-0000-0000-0000-000000000040',
  extensions.digest(convert_to('p1-join-pro-no-free-quota','utf8'),'sha256'),
  'direct',now()+interval '7 days'
);
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000063',true);
set local role authenticated;
insert into p1_results values(
  'join-pro-no-free-quota',
  public.cmd_join_project_via_invite(
    'p1-join-pro-no-free-quota','d4100000-0000-0000-0000-000000000016',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='join-pro-no-free-quota'),'true','Free account at five Free projects can join an active Pro project');

-- Concurrent-task limits: Free 20, Pro/Grace 100.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
('d2100000-0000-0000-0007-000000000001','P1 Free tasks',now()+interval '20 days','d1100000-0000-0000-0000-000000000064','d1100000-0000-0000-0000-000000000064',1),
('d2100000-0000-0000-0007-000000000002','P1 Pro tasks',now()+interval '20 days','d1100000-0000-0000-0000-000000000065','d1100000-0000-0000-0000-000000000065',1),
('d2100000-0000-0000-0007-000000000003','P1 Grace tasks',now()+interval '20 days','d1100000-0000-0000-0000-000000000066','d1100000-0000-0000-0000-000000000066',1),
('d2100000-0000-0000-0007-000000000004','P1 overcap tasks',now()+interval '20 days','d1100000-0000-0000-0000-000000000067','d1100000-0000-0000-0000-000000000067',1);
insert into public.project_members(project_id,user_id,role,member_state) values
('d2100000-0000-0000-0007-000000000001','d1100000-0000-0000-0000-000000000064','leader','active'),
('d2100000-0000-0000-0007-000000000002','d1100000-0000-0000-0000-000000000065','leader','active'),
('d2100000-0000-0000-0007-000000000003','d1100000-0000-0000-0000-000000000066','leader','active'),
('d2100000-0000-0000-0007-000000000004','d1100000-0000-0000-0000-000000000067','leader','active');
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values(
  'd1100000-0000-0000-0000-000000000065','pro','active',
  now()-interval '1 day',now()+interval '30 days',now(),
  'd1100000-0000-0000-0000-000000000001','test',1
);
insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values('d2100000-0000-0000-0007-000000000003',now(),now()+interval '3 days','account_expired',1);
insert into public.tasks(project_id,title,created_by,deadline_at,status,weight)
select 'd2100000-0000-0000-0007-000000000001','Free task '||i,'d1100000-0000-0000-0000-000000000064',now()+interval '5 days','not_started',1
from generate_series(1,20) s(i);
insert into public.tasks(project_id,title,created_by,deadline_at,status,weight)
select 'd2100000-0000-0000-0007-000000000002','Pro task '||i,'d1100000-0000-0000-0000-000000000065',now()+interval '5 days','not_started',1
from generate_series(1,99) s(i);
insert into public.tasks(project_id,title,created_by,deadline_at,status,weight)
select 'd2100000-0000-0000-0007-000000000003','Grace task '||i,'d1100000-0000-0000-0000-000000000066',now()+interval '5 days','not_started',1
from generate_series(1,99) s(i);
insert into public.tasks(project_id,title,created_by,deadline_at,status,weight)
select 'd2100000-0000-0000-0007-000000000004','Overcap task '||i,'d1100000-0000-0000-0000-000000000067',now()+interval '5 days','not_started',1
from generate_series(1,50) s(i);

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000064',true);
set local role authenticated;
insert into p1_results values(
  'free-task-21',
  public.cmd_create_task(
    'd2100000-0000-0000-0007-000000000001','d4100000-0000-0000-0000-000000000020',
    1,'Free task 21',null,now()+interval '5 days',1::smallint,'claimable',null
  )
);
reset role;
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000065',true);
set local role authenticated;
insert into p1_results values(
  'pro-task-100',
  public.cmd_create_task(
    'd2100000-0000-0000-0007-000000000002','d4100000-0000-0000-0000-000000000021',
    1,'Pro task 100',null,now()+interval '5 days',1::smallint,'claimable',null
  )
);
insert into p1_results values(
  'pro-task-101',
  public.cmd_create_task(
    'd2100000-0000-0000-0007-000000000002','d4100000-0000-0000-0000-000000000022',
    2,'Pro task 101',null,now()+interval '5 days',1::smallint,'claimable',null
  )
);
reset role;
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000066',true);
set local role authenticated;
insert into p1_results values(
  'grace-task-100',
  public.cmd_create_task(
    'd2100000-0000-0000-0007-000000000003','d4100000-0000-0000-0000-000000000023',
    1,'Grace task 100',null,now()+interval '5 days',1::smallint,'claimable',null
  )
);
reset role;
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000067',true);
set local role authenticated;
insert into p1_results values(
  'overcap-task-add',
  public.cmd_create_task(
    'd2100000-0000-0000-0007-000000000004','d4100000-0000-0000-0000-000000000024',
    1,'Overcap add',null,now()+interval '5 days',1::smallint,'claimable',null
  )
);
reset role;

select is((select result->>'code' from p1_results where label='free-task-21'),'CONCURRENT_TASK_LIMIT_REACHED','Free project rejects twenty-first concurrent task');
select is((select (result->'details'->>'limit')::integer from p1_results where label='free-task-21'),20,'Free task quota reports twenty');
select is((select result->>'ok' from p1_results where label='pro-task-100'),'true','active Pro project allows hundredth concurrent task');
select is((select result->>'code' from p1_results where label='pro-task-101'),'CONCURRENT_TASK_LIMIT_REACHED','active Pro project rejects hundred-first concurrent task');
select is((select (result->'details'->>'limit')::integer from p1_results where label='pro-task-101'),100,'Pro task quota reports one hundred');
select is((select result->>'ok' from p1_results where label='grace-task-100'),'true','Grace project allows hundredth concurrent task');
select is((select result->>'code' from p1_results where label='overcap-task-add'),'CONCURRENT_TASK_LIMIT_REACHED','passively over-cap Free project is preserved but cannot expand');
select is((select (result->'details'->>'current')::integer from p1_results where label='overcap-task-add'),50,'over-cap task error reports preserved current count');

-- Passive account downgrade/over-cap remains non-destructive and blocks only new Free growth.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('d2100000-0000-0000-0008-'||lpad(i::text,12,'0'))::uuid,
       'P1 passive account '||i,now()+interval '20 days',
       'd1100000-0000-0000-0000-000000000068',
       'd1100000-0000-0000-0000-000000000068'
from generate_series(1,6) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select id,'d1100000-0000-0000-0000-000000000068','leader','active'
from public.projects where created_by='d1100000-0000-0000-0000-000000000068';
select is(private.account_active_free_project_count('d1100000-0000-0000-0000-000000000068',transaction_timestamp()),6,'passive downgrade may leave six active Free projects intact');
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000068',true);
set local role authenticated;
insert into p1_results values(
  'passive-account-add',
  public.cmd_create_project(
    'd4100000-0000-0000-0000-000000000025',0,'P1 passive seventh',
    now()+interval '20 days',null,null,null,null,null,null
  )
);
reset role;
select is((select result->>'code' from p1_results where label='passive-account-add'),'ACTIVE_FREE_PROJECT_LIMIT_REACHED','over-cap Free account cannot expand further');
select is((select count(*)::integer from public.project_members where user_id='d1100000-0000-0000-0000-000000000068' and member_state='active'),6,'over-cap account membership is not destructively changed');

-- Membership source-loss through real commands produces stable grace reasons.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
('d2100000-0000-0000-0009-000000000001','P1 grace observer',now()+interval '20 days','d1100000-0000-0000-0000-000000000069','d1100000-0000-0000-0000-000000000069',1),
('d2100000-0000-0000-0009-000000000002','P1 grace leave',now()+interval '20 days','d1100000-0000-0000-0000-000000000071','d1100000-0000-0000-0000-000000000071',1),
('d2100000-0000-0000-0009-000000000003','P1 grace remove',now()+interval '20 days','d1100000-0000-0000-0000-000000000073','d1100000-0000-0000-0000-000000000073',1),
('d2100000-0000-0000-0009-000000000004','P1 grace multi',now()+interval '20 days','d1100000-0000-0000-0000-000000000075','d1100000-0000-0000-0000-000000000075',1);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
('d5100000-0000-0000-0000-000000000001','d2100000-0000-0000-0009-000000000001','d1100000-0000-0000-0000-000000000069','leader','active',false,1),
('d5100000-0000-0000-0000-000000000002','d2100000-0000-0000-0009-000000000001','d1100000-0000-0000-0000-000000000070','member','active',false,1),
('d5100000-0000-0000-0000-000000000003','d2100000-0000-0000-0009-000000000001','d1100000-0000-0000-0000-000000000080','member','active',false,1),
('d5100000-0000-0000-0000-000000000004','d2100000-0000-0000-0009-000000000002','d1100000-0000-0000-0000-000000000071','leader','active',false,1),
('d5100000-0000-0000-0000-000000000005','d2100000-0000-0000-0009-000000000002','d1100000-0000-0000-0000-000000000072','member','active',false,1),
('d5100000-0000-0000-0000-000000000006','d2100000-0000-0000-0009-000000000003','d1100000-0000-0000-0000-000000000073','leader','active',false,1),
('d5100000-0000-0000-0000-000000000007','d2100000-0000-0000-0009-000000000003','d1100000-0000-0000-0000-000000000074','member','active',false,1),
('d5100000-0000-0000-0000-000000000008','d2100000-0000-0000-0009-000000000004','d1100000-0000-0000-0000-000000000075','leader','active',false,1),
('d5100000-0000-0000-0000-000000000009','d2100000-0000-0000-0009-000000000004','d1100000-0000-0000-0000-000000000076','member','active',false,1),
('d5100000-0000-0000-0000-000000000010','d2100000-0000-0000-0009-000000000004','d1100000-0000-0000-0000-000000000077','member','active',false,1);
insert into public.account_entitlements(
  user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version
) values
('d1100000-0000-0000-0000-000000000070','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1),
('d1100000-0000-0000-0000-000000000072','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1),
('d1100000-0000-0000-0000-000000000074','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1),
('d1100000-0000-0000-0000-000000000076','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1),
('d1100000-0000-0000-0000-000000000077','pro','active',now()-interval '1 day',now()+interval '30 days',now(),'d1100000-0000-0000-0000-000000000001','test',1);

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000069',true);
set local role authenticated;
insert into p1_results values(
  'grace-observer',
  public.cmd_update_project_member_role(
    'd2100000-0000-0000-0009-000000000001','d5100000-0000-0000-0000-000000000002',
    'observer','d4100000-0000-0000-0000-000000000030',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='grace-observer'),'true','last Pro member can become observer');
select is((select reason from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000001'),'member_became_observer','observer transition records stable grace reason');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000072',true);
set local role authenticated;
insert into p1_results values(
  'grace-leave',
  public.cmd_leave_project(
    'd2100000-0000-0000-0009-000000000002','d4100000-0000-0000-0000-000000000031',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='grace-leave'),'true','last Pro member can leave');
select is((select reason from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000002'),'member_left','leave records stable grace reason');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000073',true);
set local role authenticated;
insert into p1_results values(
  'grace-remove',
  public.cmd_remove_project_member(
    'd2100000-0000-0000-0009-000000000003','d5100000-0000-0000-0000-000000000007',
    'd4100000-0000-0000-0000-000000000032',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='grace-remove'),'true','last Pro member can be removed');
select is((select reason from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000003'),'member_removed','removal records stable grace reason');

select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000075',true);
set local role authenticated;
insert into p1_results values(
  'grace-multi-remove',
  public.cmd_remove_project_member(
    'd2100000-0000-0000-0009-000000000004','d5100000-0000-0000-0000-000000000009',
    'd4100000-0000-0000-0000-000000000033',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='grace-multi-remove'),'true','one of multiple Pro sources can be removed');
select is((select count(*)::integer from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000004'),0,'remaining qualifying Pro source prevents grace');

-- Existing grace is not refreshed by unrelated non-Pro role mutation; a restored Pro source is active and can later start a fresh grace.
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000069',true);
set local role authenticated;
insert into p1_results values(
  'grace-nonpro-observer',
  public.cmd_update_project_member_role(
    'd2100000-0000-0000-0009-000000000001','d5100000-0000-0000-0000-000000000003',
    'observer','d4100000-0000-0000-0000-000000000034',1
  )
);
insert into p1_results values(
  'grace-restore-pro',
  public.cmd_update_project_member_role(
    'd2100000-0000-0000-0009-000000000001','d5100000-0000-0000-0000-000000000002',
    'member','d4100000-0000-0000-0000-000000000035',2
  )
);
reset role;
select is((select version from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000001'),1,'non-Pro membership mutation does not refresh existing grace');
select is((select state from private.resolve_project_entitlement('d2100000-0000-0000-0009-000000000001',transaction_timestamp())),'active','restored Pro source immediately restores active Pro');
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000069',true);
set local role authenticated;
insert into p1_results values(
  'grace-fresh-loss',
  public.cmd_update_project_member_role(
    'd2100000-0000-0000-0009-000000000001','d5100000-0000-0000-0000-000000000002',
    'observer','d4100000-0000-0000-0000-000000000036',3
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='grace-fresh-loss'),'true','restored Pro source can be lost again');
select is((select version from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000001'),2,'fresh source loss creates a new grace version');
select ok((select expires_at >= transaction_timestamp()+interval '2 days 23 hours' from public.project_pro_grace where project_id='d2100000-0000-0000-0009-000000000001'),'fresh source loss receives a full new grace window');

-- Over-cap members may reduce without destructive enforcement.
insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('d2100000-0000-0000-0010-000000000001','P1 overcap members',now()+interval '20 days','d1100000-0000-0000-0000-000000000078','d1100000-0000-0000-0000-000000000078',1);
insert into public.project_members(id,project_id,user_id,role,member_state,version)
select ('d5100000-0000-0000-0010-'||lpad(i::text,12,'0'))::uuid,
       'd2100000-0000-0000-0010-000000000001',
       ('d1100000-0000-0000-0000-'||lpad((i+77)::text,12,'0'))::uuid,
       case when i=1 then 'leader' else 'member' end,'active',1
from generate_series(1,13) s(i);
-- Add two more users reusing existing non-Pro identities to make fifteen.
insert into public.project_members(id,project_id,user_id,role,member_state,version) values
('d5100000-0000-0000-0010-000000000014','d2100000-0000-0000-0010-000000000001','d1100000-0000-0000-0000-000000000005','member','active',1),
('d5100000-0000-0000-0010-000000000015','d2100000-0000-0000-0010-000000000001','d1100000-0000-0000-0000-000000000006','member','active',1);
select set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000078',true);
set local role authenticated;
insert into p1_results values(
  'overcap-member-remove',
  public.cmd_remove_project_member(
    'd2100000-0000-0000-0010-000000000001','d5100000-0000-0000-0010-000000000015',
    'd4100000-0000-0000-0000-000000000040',1
  )
);
reset role;
select is((select result->>'ok' from p1_results where label='overcap-member-remove'),'true','over-cap Free project may reduce member count');
select is((select count(*)::integer from public.project_members where project_id='d2100000-0000-0000-0010-000000000001' and member_state='active' and user_id is not null),14,'over-cap member removal reduces fifteen to fourteen');

select * from finish();
rollback;
