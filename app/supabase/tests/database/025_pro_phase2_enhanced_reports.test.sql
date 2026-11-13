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


-- All fixture data are transaction-local (rolled back) and namespaced to B.
select has_function('public','get_enhanced_project_report_export',
  array['uuid'], 'B read-only enhanced export RPC exists');

insert into auth.users(id,email) values
('b1100000-0000-4000-8000-000000000001','p2b-pro-leader@example.test'),
('b1100000-0000-4000-8000-000000000002','p2b-pro-observer@example.test'),
('b1100000-0000-4000-8000-000000000003','p2b-free-leader@example.test'),
('b1100000-0000-4000-8000-000000000004','p2b-grace-leader@example.test'),
('b1100000-0000-4000-8000-000000000005','p2b-outsider@example.test');

insert into public.projects
(id,name,deadline_at,contribution_mode,leader_id,created_by,version,lifecycle_state,completed_at)
values
('b2100000-0000-4000-8000-000000000001','B Pro report',now()+interval '10 days','weighted','b1100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001',2,'completed',now()-interval '1 hour'),
('b2100000-0000-4000-8000-000000000002','B Free report',now()+interval '10 days','weighted','b1100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000003',2,'completed',now()-interval '1 hour'),
('b2100000-0000-4000-8000-000000000003','B Grace report',now()+interval '10 days','weighted','b1100000-0000-4000-8000-000000000004','b1100000-0000-4000-8000-000000000004',2,'completed',now()-interval '1 hour'),
('b2100000-0000-4000-8000-000000000004','B Draft report',now()+interval '10 days','weighted','b1100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001',2,'contribution_review',null);

insert into public.project_members(project_id,user_id,role,member_state,is_observer)
values
('b2100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','leader','active',false),
('b2100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000002','observer','active',true),
('b2100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000003','leader','active',false),
('b2100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000004','leader','active',false),
('b2100000-0000-4000-8000-000000000004','b1100000-0000-4000-8000-000000000001','leader','active',false);

insert into public.account_entitlements
(user_id,plan,status,starts_at,expires_at,granted_at,granted_by,grant_source,version)
values
('b1100000-0000-4000-8000-000000000001','pro','active',
 now()-interval '1 day',now()+interval '20 days',now(),
 'b1100000-0000-4000-8000-000000000001','test',1);

insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version)
values ('b2100000-0000-4000-8000-000000000003',
 now()-interval '1 day',now()+interval '2 days','account_expired',1);

insert into public.tasks
(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
 assignment_state,accepted_at,first_submitted_at,completed_at,version)
select task_id,project_id, '任务快照 B',actor_id,actor_id,
 now()+interval '3 days','completed',3,'assigned',
 now()-interval '2 days',now()-interval '1 day',now()-interval '1 hour',2
from (values
('b3100000-0000-4000-8000-000000000001'::uuid,'b2100000-0000-4000-8000-000000000001'::uuid,'b1100000-0000-4000-8000-000000000001'::uuid),
('b3100000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000003'),
('b3100000-0000-4000-8000-000000000003','b2100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000004'),
('b3100000-0000-4000-8000-000000000004','b2100000-0000-4000-8000-000000000004','b1100000-0000-4000-8000-000000000001')
) as x(task_id,project_id,actor_id);

insert into public.contribution_reports
(id,project_id,state,contribution_mode,source_project_version,
 eligible_member_count,required_confirmation_count,created_by,formalized_at,version)
values
('b8100000-0000-4000-8000-000000000001','b2100000-0000-4000-8000-000000000001','formal','weighted',2,2,2,'b1100000-0000-4000-8000-000000000001',now()-interval '1 hour',2),
('b8100000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','formal','weighted',2,1,1,'b1100000-0000-4000-8000-000000000003',now()-interval '1 hour',2),
('b8100000-0000-4000-8000-000000000003','b2100000-0000-4000-8000-000000000003','formal','weighted',2,1,1,'b1100000-0000-4000-8000-000000000004',now()-interval '1 hour',2),
('b8100000-0000-4000-8000-000000000004','b2100000-0000-4000-8000-000000000004','draft','weighted',2,1,1,'b1100000-0000-4000-8000-000000000001',null,1);

insert into public.contribution_items
(report_id,project_id,task_id,member_user_id,member_display_name_snapshot,
 task_weight,share,contribution_value,task_title_snapshot,completed_at_snapshot)
select report_id,project_id,task_id,user_id,'小猪作业贡献成员',
 3.0000,1.0000,3.0000,'任务快照 B',now()-interval '1 day'
from (values
('b8100000-0000-4000-8000-000000000001'::uuid,'b2100000-0000-4000-8000-000000000001'::uuid,'b3100000-0000-4000-8000-000000000001'::uuid,'b1100000-0000-4000-8000-000000000001'::uuid),
('b8100000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','b3100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000003'),
('b8100000-0000-4000-8000-000000000003','b2100000-0000-4000-8000-000000000003','b3100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000004'),
('b8100000-0000-4000-8000-000000000004','b2100000-0000-4000-8000-000000000004','b3100000-0000-4000-8000-000000000004','b1100000-0000-4000-8000-000000000001')
) as x(report_id,project_id,task_id,user_id);

insert into public.contribution_confirmations(report_id,project_id,user_id)
values
('b8100000-0000-4000-8000-000000000001','b2100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001'),
('b8100000-0000-4000-8000-000000000001','b2100000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000002'),
('b8100000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','b1100000-0000-4000-8000-000000000003'),
('b8100000-0000-4000-8000-000000000003','b2100000-0000-4000-8000-000000000003','b1100000-0000-4000-8000-000000000004');

create temporary table p2b_results(label text primary key,result jsonb);
grant select, insert, update on p2b_results to authenticated;

select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
insert into p2b_results values('anonymous',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
reset role;
select is((select result->>'code' from p2b_results where label='anonymous'),
  'UNAUTHENTICATED','anonymous cannot read enhanced reports');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000005',true);
set local role authenticated;
insert into p2b_results values('outsider-unreleased',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
insert into p2b_results values('outsider-unknown',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000099'));
reset role;
select is((select result->>'code' from p2b_results where label='outsider-unreleased'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','business authorization precedes unpublished feature status');
select is((select result->>'code' from p2b_results where label='outsider-unknown'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','unknown report not discoverable by outsider');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into p2b_results values('pro-unreleased',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
insert into p2b_results values('pro-draft-unreleased',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000004'));
reset role;
select is((select result->>'code' from p2b_results where label='pro-unreleased'),
 'CAPABILITY_NOT_AVAILABLE','Pro cannot bypass unpublished capability');
select is((select result->>'code' from p2b_results where label='pro-draft-unreleased'),
 'CAPABILITY_NOT_AVAILABLE','unreleased gate precedes report lifecycle');

select ok(not private.capability_is_released('enhanced_report'),
 'production allowlist is still unreleased before transaction-only simulation');
select ok(not private.capability_is_released('fake_b_capability'),
 'unknown B capability remains false');

-- Simulate G release only inside this pgTAP transaction. ROLLBACK below
-- ensures the production allowlist remains frozen and never migrates.
create or replace function private.capability_is_released(p_capability text)
returns boolean language sql immutable security definer set search_path=''
as $$
  select coalesce(p_capability = any(array[
   'file_full_history','file_batch_rollback','file_version_compare',
   'project_recovery_point','enhanced_report'
  ]::text[]), false);
$$;
select ok(private.capability_is_released('enhanced_report'),
 'local fixture models G release without shipping allowlist mutation');
select ok(not private.capability_is_released('fake_b_capability'),
 'unknown capability remains fail closed after simulated release');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into p2b_results values('pro-formal',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
insert into p2b_results values('pro-draft',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000004'));
insert into p2b_results values('pro-null',public.get_enhanced_project_report_export(null));
reset role;
select is((select result->>'ok' from p2b_results where label='pro-formal'),
 'true','Pro member can export formal snapshot after simulated release');
select is((select result->>'code' from p2b_results where label='pro-draft'),
 'REPORT_NOT_READY','draft cannot be enhanced-exported');
select is((select result->>'code' from p2b_results where label='pro-null'),
 'VALIDATION_FAILED','null reportId is rejected after authentication');
select is((select result->>'reportId' from p2b_results where label='pro-formal'),
 'b8100000-0000-4000-8000-000000000001','RPC returns stable reportId');
select is((select result->>'schemaVersion' from p2b_results where label='pro-formal'),
 '1','RPC schema version is 1');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000002',true);
set local role authenticated;
insert into p2b_results values('observer',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
reset role;
select is((select result->>'ok' from p2b_results where label='observer'),
 'true','read-only active observer can export formal report');
select is((select result->'snapshot' from p2b_results where label='observer'),
 (select result->'snapshot' from p2b_results where label='pro-formal'),
 'observer receives the identical immutable authoritative snapshot');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000003',true);
set local role authenticated;
insert into p2b_results values('free',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000002'));
insert into p2b_results values('free-basic',public.get_project_report_export('b8100000-0000-4000-8000-000000000002'));
reset role;
select is((select result->>'code' from p2b_results where label='free'),
 'CAPABILITY_REQUIRES_PRO','Free project is denied newly released enhanced export');
select is((select result->>'reportState' from p2b_results where label='free-basic'),
 'formal','Free project retains unchanged basic formal report access');

select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000004',true);
set local role authenticated;
insert into p2b_results values('grace',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000003'));
reset role;
select is((select result->>'ok' from p2b_results where label='grace'),
 'true','project Grace counts as Pro for released enhanced reports');

update public.project_pro_grace set expires_at=now()-interval '1 second'
where project_id='b2100000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000004',true);
set local role authenticated;
insert into p2b_results values('grace-expired',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000003'));
reset role;
select is((select result->>'code' from p2b_results where label='grace-expired'),
 'CAPABILITY_REQUIRES_PRO','after Grace expiration enhanced access closes');

update public.project_members set member_state='left'
where project_id='b2100000-0000-4000-8000-000000000001'
  and user_id='b1100000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000002',true);
set local role authenticated;
insert into p2b_results values('observer-revoked',public.get_enhanced_project_report_export('b8100000-0000-4000-8000-000000000001'));
reset role;
select is((select result->>'code' from p2b_results where label='observer-revoked'),
 'NOT_FOUND_OR_NOT_AUTHORIZED','observer access revocation wins over Pro');
select set_config('request.jwt.claim.sub','b1100000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into p2b_results values('pro-basic',public.get_project_report_export('b8100000-0000-4000-8000-000000000001'));
reset role;
select is((select result->'snapshot' from p2b_results where label='pro-formal'),
  (select result from p2b_results where label='pro-basic'),
  'enhanced data equals existing authoritative v1 snapshot exactly');

select * from finish();
rollback;
