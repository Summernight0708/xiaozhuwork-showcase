begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public','cmd_set_task_dependencies',
  array['uuid','uuid','uuid[]','uuid','integer'],
  'authoritative dependency set RPC exists'
);

insert into auth.users(id,email) values
 ('d1000000-0000-0000-0000-000000000001','dep-leader@example.test'),
 ('d1000000-0000-0000-0000-000000000002','dep-creator@example.test'),
 ('d1000000-0000-0000-0000-000000000003','dep-member@example.test'),
 ('d1000000-0000-0000-0000-000000000004','dep-observer@example.test'),
 ('d1000000-0000-0000-0000-000000000005','dep-removed@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values
 ('d2000000-0000-0000-0000-000000000001','Dependencies',now()+interval '30 days','d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',1),
 ('d2000000-0000-0000-0000-000000000002','Other project',now()+interval '30 days','d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',1);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','leader','active',false,1),
 ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002','member','active',false,1),
 ('d3000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000003','member','active',false,1),
 ('d3000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000004','observer','active',true,1),
 ('d3000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000005','member','removed',false,1),
 ('d3000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000001','leader','active',false,1);

insert into public.tasks(id,project_id,title,created_by,deadline_at,status,assignment_state,version,completed_at) values
 ('d4000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','A','d1000000-0000-0000-0000-000000000002',now()+interval '10 days','in_progress','assigned',1,null),
 ('d4000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','B','d1000000-0000-0000-0000-000000000002',now()+interval '11 days','in_progress','assigned',1,null),
 ('d4000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','C','d1000000-0000-0000-0000-000000000002',now()+interval '12 days','in_progress','assigned',1,null),
 ('d4000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','Done','d1000000-0000-0000-0000-000000000002',now()+interval '9 days','completed','assigned',1,now()),
 ('d4000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000002','Other','d1000000-0000-0000-0000-000000000001',now()+interval '10 days','in_progress','assigned',1,null);

create temporary table dep_results(label text primary key,result jsonb);
grant all on dep_results to authenticated;

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dep_results values('a-to-b',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 array['d4000000-0000-0000-0000-000000000001'::uuid],
 'd9000000-0000-0000-0000-000000000001',1));
reset role;

select is((select result->>'ok' from dep_results where label='a-to-b'),'true','A -> B succeeds');
select is((select count(*)::integer from public.task_dependencies where downstream_task_id='d4000000-0000-0000-0000-000000000002'),1,'one upstream edge stored');
select ok(exists(
 select 1 from public.task_dependencies d join public.tasks u on u.id=d.upstream_task_id
 where d.downstream_task_id='d4000000-0000-0000-0000-000000000002' and u.status<>'completed'
),'unfinished upstream derives B as blocked');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dep_results values('multi-to-c',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 array['d4000000-0000-0000-0000-000000000001'::uuid,'d4000000-0000-0000-0000-000000000004'::uuid,'d4000000-0000-0000-0000-000000000001'::uuid],
 'd9000000-0000-0000-0000-000000000002',1));
reset role;
select is((select count(*)::integer from public.task_dependencies where downstream_task_id='d4000000-0000-0000-0000-000000000003'),2,'duplicate upstream ids are idempotently deduplicated');
select ok(exists(
 select 1 from public.task_dependencies d join public.tasks u on u.id=d.upstream_task_id
 where d.downstream_task_id='d4000000-0000-0000-0000-000000000003' and u.status<>'completed'
),'partial upstream completion keeps C blocked');
update public.tasks set status='completed',completed_at=now() where id='d4000000-0000-0000-0000-000000000001';
select ok(not exists(
 select 1 from public.task_dependencies d join public.tasks u on u.id=d.upstream_task_id
 where d.downstream_task_id='d4000000-0000-0000-0000-000000000003' and u.status<>'completed'
),'all upstream completed automatically unblocks C without copied blocked fact');
update public.tasks set status='in_progress',completed_at=null where id='d4000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dep_results values('self',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 array['d4000000-0000-0000-0000-000000000001'::uuid],
 'd9000000-0000-0000-0000-000000000003',1));
insert into dep_results values('cross-project',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 array['d4000000-0000-0000-0000-000000000005'::uuid],
 'd9000000-0000-0000-0000-000000000004',1));
insert into dep_results values('cycle-two',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 array['d4000000-0000-0000-0000-000000000002'::uuid],
 'd9000000-0000-0000-0000-000000000005',1));
reset role;
select is((select result->>'code' from dep_results where label='self'),'VALIDATION_FAILED','self dependency rejected');
select is((select result->>'code' from dep_results where label='cross-project'),'NOT_FOUND_OR_NOT_AUTHORIZED','cross-project dependency rejected');
select is((select result->>'code' from dep_results where label='cycle-two'),'INVALID_TRANSITION','two-node cycle rejected');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into dep_results values('b-to-c-only',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 array['d4000000-0000-0000-0000-000000000002'::uuid],
 'd9000000-0000-0000-0000-000000000006',2));
insert into dep_results values('cycle-three',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 array['d4000000-0000-0000-0000-000000000003'::uuid],
 'd9000000-0000-0000-0000-000000000007',1));
reset role;
select is((select result->>'code' from dep_results where label='cycle-three'),'INVALID_TRANSITION','multi-node cycle rejected');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into dep_results values('unauthorized-member',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 array[]::uuid[],'d9000000-0000-0000-0000-000000000008',2));
reset role;
select is((select result->>'code' from dep_results where label='unauthorized-member'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-creator member cannot write dependencies');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into dep_results values('observer',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 array[]::uuid[],'d9000000-0000-0000-0000-000000000009',2));
reset role;
select is((select result->>'code' from dep_results where label='observer'),'NOT_AUTHORIZED','observer cannot write dependencies');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into dep_results values('removed',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 array[]::uuid[],'d9000000-0000-0000-0000-000000000010',2));
reset role;
select is((select result->>'code' from dep_results where label='removed'),'NOT_FOUND_OR_NOT_AUTHORIZED','removed member cannot write dependencies');

set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
select throws_ok(
 $$insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id) values(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000004','d4000000-0000-0000-0000-000000000001')$$,
 '42501',
 null,
 'authenticated browser cannot directly write dependency facts'
);
reset role;

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into dep_results values('leader-delete',public.cmd_set_task_dependencies(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 array[]::uuid[],'d9000000-0000-0000-0000-000000000011',2));
reset role;
select is((select result->>'ok' from dep_results where label='leader-delete'),'true','leader can delete dependency by replacing upstream set');
select is((select count(*)::integer from public.task_dependencies where downstream_task_id='d4000000-0000-0000-0000-000000000002'),0,'dependency deletion persisted');
select cmp_ok((select count(*) from public.business_events where event_type='task_dependencies_set' and project_id='d2000000-0000-0000-0000-000000000001'),'>=',3::bigint,'dependency writes are audited');

select * from finish();
rollback;
