begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column('public','project_members','version','memberships are versioned');
select has_function('public','cmd_update_project_member_role',array['uuid','uuid','text','uuid','integer'],'role update RPC exists');
select has_function('public','cmd_remove_project_member',array['uuid','uuid','uuid','integer'],'member removal RPC exists');
select has_function('public','cmd_transfer_project_leadership',array['uuid','uuid','uuid','integer'],'leadership transfer RPC exists');
select has_function('public','cmd_leave_project',array['uuid','uuid','integer'],'voluntary leave RPC exists');
select ok(not has_table_privilege('authenticated','public.project_members','UPDATE'),'browser cannot directly update memberships');

insert into auth.users(id,email) values
 ('91000000-0000-0000-0000-000000000001','member-leader@example.test'),
 ('91000000-0000-0000-0000-000000000002','member-admin@example.test'),
 ('91000000-0000-0000-0000-000000000003','member-worker@example.test'),
 ('91000000-0000-0000-0000-000000000004','member-observer@example.test'),
 ('91000000-0000-0000-0000-000000000005','member-outsider@example.test'),
 ('91000000-0000-0000-0000-000000000006','member-responsible@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values('92000000-0000-0000-0000-000000000001','Member commands',now()+interval '14 days',
 '91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001',1);

insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','leader','active',false,1),
 ('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002','member','active',false,1),
 ('93000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003','member','active',false,1),
 ('93000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000004','member','active',false,1),
 ('93000000-0000-0000-0000-000000000005','92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000006','member','active',false,1);

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version)
values
 ('94000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','Rehome on removal',
  '91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003',now()+interval '5 days',
  'in_progress',3,now(),'assigned',1),
 ('94000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001','Handoff before leaving',
  '91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000006',now()+interval '5 days',
  'in_progress',3,now(),'assigned',1);

create temporary table member_rpc_results(label text primary key,result jsonb);
grant all on member_rpc_results to authenticated;

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into member_rpc_results values('promote-admin',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002','admin',
 '95000000-0000-0000-0000-000000000001',1));
insert into member_rpc_results values('promote-admin-replay',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002','admin',
 '95000000-0000-0000-0000-000000000001',1));
insert into member_rpc_results values('promote-admin-reuse',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002','observer',
 '95000000-0000-0000-0000-000000000001',1));
reset role;

select is((select result->>'ok' from member_rpc_results where label='promote-admin'),'true','leader may appoint admin');
select is((select role from public.project_members where id='93000000-0000-0000-0000-000000000002'),'admin','admin role is authoritative');
select is((select version from public.project_members where id='93000000-0000-0000-0000-000000000002'),2,'role update advances membership version');
select is((select version from public.projects where id='92000000-0000-0000-0000-000000000001'),2,'role update advances project version');
select is((select result->>'replayed' from member_rpc_results where label='promote-admin-replay'),'true','identical member command replays');
select is((select result->>'code' from member_rpc_results where label='promote-admin-reuse'),'IDEMPOTENCY_KEY_REUSED','member command rejects request id reuse');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into member_rpc_results values('admin-observer',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','observer',
 '95000000-0000-0000-0000-000000000002',1));
insert into member_rpc_results values('admin-cannot-appoint',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','admin',
 '95000000-0000-0000-0000-000000000003',2));
insert into member_rpc_results values('admin-remove-worker',public.cmd_remove_project_member(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000003',
 '95000000-0000-0000-0000-000000000004',1));
reset role;

select is((select result->>'ok' from member_rpc_results where label='admin-observer'),'true','admin may switch member to observer');
select is((select role from public.project_members where id='93000000-0000-0000-0000-000000000004'),'observer','observer is a formal role');
select ok((select is_observer from public.project_members where id='93000000-0000-0000-0000-000000000004'),'legacy observer mirror remains consistent');
select is((select result->>'code' from member_rpc_results where label='admin-cannot-appoint'),'NOT_FOUND_OR_NOT_AUTHORIZED','admin cannot appoint another admin');
select is((select result->>'ok' from member_rpc_results where label='admin-remove-worker'),'true','admin may remove ordinary member');
select is((select member_state from public.project_members where id='93000000-0000-0000-0000-000000000003'),'removed','removed membership keeps historical row');
select ok((select departed_at is not null from public.project_members where id='93000000-0000-0000-0000-000000000003'),'removed membership records departure time');
select is((select assignee_id from public.tasks where id='94000000-0000-0000-0000-000000000001'),null::uuid,'removal releases active assignment');
select is((select assignment_state from public.tasks where id='94000000-0000-0000-0000-000000000001'),'claimable','released task returns to claim pool');
select is((select status from public.tasks where id='94000000-0000-0000-0000-000000000001'),'not_started','released task returns to a claimable status');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into member_rpc_results values('observer-write',public.cmd_create_task(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000005',4,
 'Observer must not write',null,now()+interval '2 days',1::smallint,'claimable',null));
reset role;
select is((select result->>'code' from member_rpc_results where label='observer-write'),'NOT_AUTHORIZED','observer cannot create tasks via RPC');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into member_rpc_results values('outsider-role',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','member',
 '95000000-0000-0000-0000-000000000006',2));
reset role;
select is((select result->>'code' from member_rpc_results where label='outsider-role'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot manage roles');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into member_rpc_results values('stale-role',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','member',
 '95000000-0000-0000-0000-000000000007',1));
insert into member_rpc_results values('remove-leader',public.cmd_remove_project_member(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',
 '95000000-0000-0000-0000-000000000008',1));
insert into member_rpc_results values('transfer',public.cmd_transfer_project_leadership(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002',
 '95000000-0000-0000-0000-000000000009',4));
reset role;

select is((select result->>'code' from member_rpc_results where label='stale-role'),'STALE_VERSION','stale membership role change is rejected');
select is((select result->>'currentVersion' from member_rpc_results where label='stale-role'),'2','stale response returns current membership version');
select is((select result->>'code' from member_rpc_results where label='remove-leader'),'INVALID_TRANSITION','normal removal cannot remove the active leader');
select is((select result->>'ok' from member_rpc_results where label='transfer'),'true','current leader may transfer leadership');
select is((select leader_id from public.projects where id='92000000-0000-0000-0000-000000000001'),'91000000-0000-0000-0000-000000000002'::uuid,'project leader pointer follows transfer');
select is((select role from public.project_members where id='93000000-0000-0000-0000-000000000001'),'member','outgoing leader drops to least-privilege member');
select is((select role from public.project_members where id='93000000-0000-0000-0000-000000000002'),'leader','successor becomes leader');
select is((select count(*)::integer from public.project_members where project_id='92000000-0000-0000-0000-000000000001' and role='leader' and member_state='active'),1,'project has exactly one active leader');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into member_rpc_results values('old-leader-no-power',public.cmd_update_project_member_role(
 '92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','member',
 '95000000-0000-0000-0000-000000000010',2));
reset role;
select is((select result->>'code' from member_rpc_results where label='old-leader-no-power'),'NOT_FOUND_OR_NOT_AUTHORIZED','former leader immediately loses management authority');


select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into member_rpc_results values('member-leave',public.cmd_leave_project(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000011',2));
insert into member_rpc_results values('member-leave-replay',public.cmd_leave_project(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000011',2));
reset role;
select is((select result->>'ok' from member_rpc_results where label='member-leave'),'true','non-leader may voluntarily leave');
select is((select result->>'replayed' from member_rpc_results where label='member-leave-replay'),'true','leave command replays');
select is((select member_state from public.project_members where id='93000000-0000-0000-0000-000000000001'),'left','voluntary departure is distinguished from removal');
select ok((select departed_at is not null from public.project_members where id='93000000-0000-0000-0000-000000000001'),'voluntary departure records departed_at');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into member_rpc_results values('leader-cannot-leave',public.cmd_leave_project(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000012',3));
reset role;
select is((select result->>'code' from member_rpc_results where label='leader-cannot-leave'),'INVALID_TRANSITION','leader must transfer leadership before leaving');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000006',true);
set local role authenticated;
insert into member_rpc_results values('responsible-cannot-leave',public.cmd_leave_project(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000014',1));
reset role;
select is((select result->>'code' from member_rpc_results where label='responsible-cannot-leave'),'INVALID_TRANSITION','member with active responsibility must hand off before leaving');
select is((select member_state from public.project_members where id='93000000-0000-0000-0000-000000000005'),'active','failed leave keeps membership active');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into member_rpc_results values('observer-leave',public.cmd_leave_project(
 '92000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000013',2));
reset role;
select is((select result->>'ok' from member_rpc_results where label='observer-leave'),'true','observer may voluntarily leave despite read-only business permissions');
select is((select member_state from public.project_members where id='93000000-0000-0000-0000-000000000004'),'left','observer departure is persisted as left');
select ok((select count(*)>=4 from public.business_events where project_id='92000000-0000-0000-0000-000000000001' and event_type in ('project_member_role_changed','project_member_removed','project_member_left','project_leadership_transferred','task_assignment_released')),'member changes are auditable');

select * from finish();
rollback;
