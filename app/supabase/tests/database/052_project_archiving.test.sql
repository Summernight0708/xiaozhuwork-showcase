begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email)
select ('b1100000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
       'b-archive-'||i||'@example.test'
from generate_series(1,5) s(i);

insert into public.projects(id,name,deadline_at,leader_id,created_by,version)
values(
  'b2100000-0000-0000-0000-000000000001','Archive pgTAP',
  now()+interval '30 days','b1100000-0000-0000-0000-000000000001',
  'b1100000-0000-0000-0000-000000000001',1
);
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
values
 ('b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','leader','active',false),
 ('b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000002','member','active',false),
 ('b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000003','admin','active',false),
 ('b2100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000004','observer','active',true);

create temporary table b_results(label text primary key, result jsonb);
grant all on b_results to authenticated;
select has_table('public','project_archive_cycles','B archive cycles exist');
select has_table('public','project_archive_retention_extensions','B retention evidence exists');
select has_function('public','cmd_archive_project',
  array['uuid','text','uuid','integer'],'archive RPC exists');
select has_function('public','cmd_restore_project',
  array['uuid','uuid','integer'],'restore RPC exists');
select has_function('public','cmd_extend_project_retention',
  array['uuid','integer','uuid','integer'],'extend RPC exists');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into b_results values('member_denied',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','reason',
 'b3100000-0000-0000-0000-000000000001',1));
reset role;
select is((select result->>'code' from b_results where label='member_denied'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','member cannot archive');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into b_results values('admin_denied',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','reason',
 'b3100000-0000-0000-0000-000000000002',1));
reset role;
select is((select result->>'code' from b_results where label='admin_denied'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','admin cannot archive');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into b_results values('observer_denied',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','reason',
 'b3100000-0000-0000-0000-000000000003',1));
reset role;
select is((select result->>'code' from b_results where label='observer_denied'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','observer cannot archive');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into b_results values('outsider_denied',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','reason',
 'b3100000-0000-0000-0000-000000000004',1));
reset role;
select is((select result->>'code' from b_results where label='outsider_denied'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot archive');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into b_results values('archive',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','课程结束',
 'b3100000-0000-0000-0000-000000000005',1));
insert into b_results values('replay',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','课程结束',
 'b3100000-0000-0000-0000-000000000005',1));
insert into b_results values('mismatched_replay',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','other',
 'b3100000-0000-0000-0000-000000000005',1));
insert into b_results values('stale_archive',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','again',
 'b3100000-0000-0000-0000-000000000006',1));
reset role;

select is((select result->>'ok' from b_results where label='archive'),'true','leader archives');
select is((select result->>'replayed' from b_results where label='replay'),'true','archive replay idempotent');
select is((select result->>'code' from b_results where label='mismatched_replay'),
 'IDEMPOTENCY_KEY_REUSED','changed payload refused');
select is((select result->>'code' from b_results where label='stale_archive'),
 'STALE_VERSION','stale archive refused');
select ok((select archived_at is not null from public.projects where id=
 'b2100000-0000-0000-0000-000000000001'),'archive authority updated');
select is((select lifecycle_state from public.projects where id=
 'b2100000-0000-0000-0000-000000000001'),'active','original lifecycle not overwritten');
select is((select count(*)::integer from public.project_archive_cycles where project_id=
 'b2100000-0000-0000-0000-000000000001'),1,'one cycle after replay');
select ok((select retain_until=archived_at+interval '1 year'
 from public.project_archive_cycles where project_id=
 'b2100000-0000-0000-0000-000000000001'),'retention defaults to one year');
select ok((select recovery_until=retain_until+interval '30 days'
 from public.project_archive_cycles where project_id=
 'b2100000-0000-0000-0000-000000000001'),'recovery window 30 days');
select is((select private.account_active_free_project_count(
 'b1100000-0000-0000-0000-000000000001',transaction_timestamp())),0,
 'archived Free project excluded from quota');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into b_results values('extend',public.cmd_extend_project_retention(
 'b2100000-0000-0000-0000-000000000001',30,
 'b3100000-0000-0000-0000-000000000007',2));
insert into b_results values('extend_replay',public.cmd_extend_project_retention(
 'b2100000-0000-0000-0000-000000000001',30,
 'b3100000-0000-0000-0000-000000000007',2));
insert into b_results values('invalid_extend',public.cmd_extend_project_retention(
 'b2100000-0000-0000-0000-000000000001',366,
 'b3100000-0000-0000-0000-000000000008',3));
reset role;

select is((select result->>'ok' from b_results where label='extend'),'true','retention extension allowed');
select is((select result->>'replayed' from b_results where label='extend_replay'),'true','extension is idempotent');
select is((select result->>'code' from b_results where label='invalid_extend'),
 'VALIDATION_FAILED','range validation');
select is((select count(*)::integer from public.project_archive_retention_extensions
 where project_id='b2100000-0000-0000-0000-000000000001'),1,'extension evidence only once');
select ok((select retain_until=archived_at+interval '1 year 30 days'
 from public.project_archive_cycles where project_id='b2100000-0000-0000-0000-000000000001'),
 'retention extended by 30 days');
select is((select count(*)::integer from public.business_events
 where project_id='b2100000-0000-0000-0000-000000000001'
   and event_type in ('project_archived','project_retention_extended')),2,
 'append-only event once per transition');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into b_results values('restore',public.cmd_restore_project(
 'b2100000-0000-0000-0000-000000000001',
 'b3100000-0000-0000-0000-000000000009',3));
insert into b_results values('restore_replay',public.cmd_restore_project(
 'b2100000-0000-0000-0000-000000000001',
 'b3100000-0000-0000-0000-000000000009',3));
reset role;
select is((select result->>'ok' from b_results where label='restore'),'true','restore within window');
select is((select result->>'replayed' from b_results where label='restore_replay'),'true','restore replay');
select ok((select archived_at is null from public.projects where id=
 'b2100000-0000-0000-0000-000000000001'),'archive flag removed on restore');
select is((select count(*)::integer from public.project_archive_cycles
 where project_id='b2100000-0000-0000-0000-000000000001' and restored_at is not null),
 1,'first generation preserved');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into b_results values('rearchive',public.cmd_archive_project(
 'b2100000-0000-0000-0000-000000000001','再次归档',
 'b3100000-0000-0000-0000-000000000010',4));
reset role;
select is((select result->>'ok' from b_results where label='rearchive'),'true','archive after restore');
select is((select max(generation) from public.project_archive_cycles
 where project_id='b2100000-0000-0000-0000-000000000001'),2,'new generation');
select is((select count(*)::integer from public.project_archive_cycles
 where project_id='b2100000-0000-0000-0000-000000000001'),2,'history preserved');

-- Exhaust Free quota while this project is archived, then attempt restore.
insert into public.projects(id,name,deadline_at,leader_id,created_by)
select ('b2200000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
  'Quota '||i,now()+interval '30 days',
  'b1100000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001'
from generate_series(1,5) s(i);
insert into public.project_members(project_id,user_id,role,member_state)
select p.id,'b1100000-0000-0000-0000-000000000001','leader','active'
from public.projects p where p.id::text like 'b2200000-0000-0000-0000-%';
select is((select private.account_active_free_project_count(
 'b1100000-0000-0000-0000-000000000001',transaction_timestamp())),5,
 'five active Free projects');

select set_config('request.jwt.claim.sub','b1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into b_results values('quota_restore_denied',public.cmd_restore_project(
 'b2100000-0000-0000-0000-000000000001',
 'b3100000-0000-0000-0000-000000000011',5));
reset role;
select is((select result->>'code' from b_results where label='quota_restore_denied'),
 'ACTIVE_FREE_PROJECT_LIMIT_REACHED','restore cannot exceed Free limit');
select ok((select archived_at is not null from public.projects where id=
 'b2100000-0000-0000-0000-000000000001'),'denied restore remains archived');

select * from finish();
rollback;
