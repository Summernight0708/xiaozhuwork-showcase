begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select ok(
 has_function_privilege('authenticated','public.get_project_contribution_report(uuid)','EXECUTE'),
 'authorized member may call privacy-safe project report'
);
select ok(
 not has_function_privilege('authenticated','public.get_project_contribution_report_f2_unmasked(uuid)','EXECUTE'),
 'raw project report is inaccessible to authenticated clients'
);
select ok(
 not has_function_privilege('anon','public.get_project_contribution_report_f2_unmasked(uuid)','EXECUTE'),
 'raw report inaccessible to anonymous clients'
);
insert into auth.users(id,email) values
 ('f9100000-0000-0000-0000-000000000001','f2-project-pending@example.test'),
 ('f9100000-0000-0000-0000-000000000002','f2-project-canceled@example.test'),
 ('f9100000-0000-0000-0000-000000000003','f2-project-leader@example.test'),
 ('f9100000-0000-0000-0000-000000000004','f2-project-outsider@example.test');
insert into public.account_lifecycle_requests(
 user_id,state,generation,version,requested_at,cancel_until,canceled_at
) values
 ('f9100000-0000-0000-0000-000000000001','pending',1,1,now()-interval '1 day',now()+interval '29 days',null),
 ('f9100000-0000-0000-0000-000000000002','canceled',1,2,now()-interval '2 days',now()+interval '28 days',now()-interval '1 day');
insert into public.projects(id,name,deadline_at,created_by,leader_id,contribution_mode)
 values('f9200000-0000-0000-0000-000000000001','F2 legacy report',
 now()+interval '10 days',
 'f9100000-0000-0000-0000-000000000003',
 'f9100000-0000-0000-0000-000000000003','weighted');
insert into public.project_members(
 project_id,user_id,role,member_state,is_observer
) values
 ('f9200000-0000-0000-0000-000000000001','f9100000-0000-0000-0000-000000000003','leader','active',false),
 ('f9200000-0000-0000-0000-000000000001','f9100000-0000-0000-0000-000000000001','member','active',false),
 ('f9200000-0000-0000-0000-000000000001','f9100000-0000-0000-0000-000000000002','member','active',false);
insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,
 status,weight,accepted_at,completed_at,assignment_state,version
) values
 ('f9300000-0000-0000-0000-000000000001',
 'f9200000-0000-0000-0000-000000000001','First historical task',
 'f9100000-0000-0000-0000-000000000003',
 'f9100000-0000-0000-0000-000000000003',
 now()+interval '4 days','completed',4,now()-interval '3 days',
 now()-interval '1 day','assigned',1),
 ('f9300000-0000-0000-0000-000000000002',
 'f9200000-0000-0000-0000-000000000001','Second historical task',
 'f9100000-0000-0000-0000-000000000003',
 'f9100000-0000-0000-0000-000000000003',
 now()+interval '4 days','completed',3,now()-interval '3 days',
 now()-interval '1 day','assigned',1);
insert into public.contribution_reports(
 id,project_id,state,contribution_mode,
 source_project_version,eligible_member_count,required_confirmation_count,created_by
) values ('f9400000-0000-0000-0000-000000000001',
 'f9200000-0000-0000-0000-000000000001','draft','weighted',1,3,2,
 'f9100000-0000-0000-0000-000000000003');
insert into public.contribution_items(
 report_id,project_id,task_id,member_user_id,
 member_display_name_snapshot,task_weight,share,contribution_value,
 task_title_snapshot,completed_at_snapshot
) values
 ('f9400000-0000-0000-0000-000000000001',
 'f9200000-0000-0000-0000-000000000001',
 'f9300000-0000-0000-0000-000000000001',
 'f9100000-0000-0000-0000-000000000001',
 'Sensitive Deleted Person',4,1,4,'First historical task',now()-interval '1 day'),
 ('f9400000-0000-0000-0000-000000000001',
 'f9200000-0000-0000-0000-000000000001',
 'f9300000-0000-0000-0000-000000000002',
 'f9100000-0000-0000-0000-000000000002',
 'Unchanged Canceled Person',3,1,3,'Second historical task',now()-interval '1 day');
create temp table f2_project_report_read(payload jsonb);
grant insert,select on f2_project_report_read to authenticated;
select set_config('request.jwt.claim.sub','f9100000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into f2_project_report_read
 select public.get_project_contribution_report('f9200000-0000-0000-0000-000000000001');
reset role;
select is((select payload->'items'->0->'memberUserId' from f2_project_report_read),'null'::jsonb,
 'pending member UUID removed in authorized live report');
select is((select payload->'items'->0->>'memberDisplayName' from f2_project_report_read),
 '已注销成员','pending member is given non-identifying label');
select is((select payload->'items'->0->>'contributionValue' from f2_project_report_read),
 '4.0000','signed numeric contribution unchanged');
select is((select payload->'items'->1->>'memberUserId' from f2_project_report_read),
 'f9100000-0000-0000-0000-000000000002',
 'canceled request member UUID unchanged');
select is((select payload->'items'->1->>'contributionValue' from f2_project_report_read),
 '3.0000','unaffected numeric contribution unchanged');
select is((select member_display_name_snapshot from public.contribution_items
 where task_id='f9300000-0000-0000-0000-000000000001'),
 'Sensitive Deleted Person','immutable member history preserved');
create temp table f2_outsider_report(payload jsonb);
grant insert,select on f2_outsider_report to authenticated;
select set_config('request.jwt.claim.sub','f9100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into f2_outsider_report select public.get_project_contribution_report('f9200000-0000-0000-0000-000000000001');
reset role;
select is((select payload->>'code' from f2_outsider_report),
 'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot call live report');
select * from finish();
rollback;
