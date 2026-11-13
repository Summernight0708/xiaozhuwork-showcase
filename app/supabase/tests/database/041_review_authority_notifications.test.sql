begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('e1000000-0000-0000-0000-000000000001','review-leader@example.test'),
 ('e1000000-0000-0000-0000-000000000002','review-downstream@example.test'),
 ('e1000000-0000-0000-0000-000000000003','review-creator@example.test'),
 ('e1000000-0000-0000-0000-000000000004','review-assignee@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,lifecycle_state,version)
 values('e2000000-0000-0000-0000-000000000001','review rights regression',
 now()+interval '30 days','e1000000-0000-0000-0000-000000000001',
 'e1000000-0000-0000-0000-000000000001','active',1);
insert into public.project_members(project_id,user_id,role,member_state,is_observer,display_name_snapshot) values
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','leader','active',false,'Leader'),
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','member','active',false,'Downstream'),
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000003','member','active',false,'Creator'),
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000004','member','active',false,'Assignee');

insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version) values
 ('e3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','upstream',
  'e1000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000004',now()+interval '5 days','awaiting_review',1,now(),'assigned',1),
 ('e3000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','downstream',
  'e1000000-0000-0000-0000-000000000003','e1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',1,now(),'assigned',1),
 ('e3000000-0000-0000-0000-000000000003','e2000000-0000-0000-0000-000000000001','leader self owned',
  'e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',now()+interval '5 days','awaiting_review',1,now(),'assigned',1);
insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id)
 values('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002');

insert into public.task_review_rounds(id,project_id,task_id,round_number,submitted_file_version_id,submitted_by,submission_text_snapshot) values
 ('e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',1,null,'e1000000-0000-0000-0000-000000000004','ready'),
 ('e4000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003',1,null,'e1000000-0000-0000-0000-000000000001','ready');

select ok((select delegation_required and delegated_reviewer_id is not null from public.task_review_rounds
 where id='e4000000-0000-0000-0000-000000000002'), 'self-assigned leader uses a randomly selected independent member');
select ok((select delegated_reviewer_id <> 'e1000000-0000-0000-0000-000000000001' from public.task_review_rounds
 where id='e4000000-0000-0000-0000-000000000002'), 'leader never self reviews');

insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,event_data) values
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000004','task_submitted_for_review','task_review_round','e4000000-0000-0000-0000-000000000001',
  '{"taskId":"e3000000-0000-0000-0000-000000000001"}'::jsonb),
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','task_submitted_for_review','task_review_round','e4000000-0000-0000-0000-000000000002',
  '{"taskId":"e3000000-0000-0000-0000-000000000003"}'::jsonb);

select is((select count(*)::integer from public.notifications where recipient_id='e1000000-0000-0000-0000-000000000001'
 and entity_id='e4000000-0000-0000-0000-000000000001' and notification_type='task_review_submitted'),1,
 'leader receives optional action notice only once');
select is((select count(*)::integer from public.notifications where recipient_id='e1000000-0000-0000-0000-000000000003'
 and entity_id='e4000000-0000-0000-0000-000000000001' and notification_type='task_review_submitted'),1,
 'creator receives required review notice exactly once');
select is((select count(*)::integer from public.notifications where recipient_id='e1000000-0000-0000-0000-000000000002'
 and entity_id='e4000000-0000-0000-0000-000000000001' and notification_type='task_review_submitted'),1,
 'downstream owner receives upstream review notice exactly once');
select is((select count(*)::integer from public.notifications where entity_id='e4000000-0000-0000-0000-000000000002'
 and recipient_id=(select delegated_reviewer_id from public.task_review_rounds where id='e4000000-0000-0000-0000-000000000002')
 and notification_type='task_review_submitted'),1, 'randomly delegated reviewer gets one actionable notice');
select is((select count(*)::integer from public.notifications where entity_id='e4000000-0000-0000-0000-000000000002'
 and recipient_id='e1000000-0000-0000-0000-000000000001'),0,'self submitter does not receive own review assignment');

create temporary table permission_outcomes(label text primary key,result jsonb);
grant all on permission_outcomes to authenticated;
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into permission_outcomes values ('downstream-approve',public.cmd_review_task_submission(
 'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',
 'e4000000-0000-0000-0000-000000000001','approve',null,
 'e5000000-0000-0000-0000-000000000001',1));
reset role;
-- A downgraded observer cannot reject using stale downstream assignment facts.
update public.project_members set role='observer',is_observer=true
where project_id='e2000000-0000-0000-0000-000000000001'
  and user_id='e1000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into permission_outcomes values ('observer-downstream-reject',public.cmd_review_task_submission(
 'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',
 'e4000000-0000-0000-0000-000000000001','request_changes','Unauthorized observer',
 'e5000000-0000-0000-0000-000000000003',1));
reset role;
update public.project_members set role='member',is_observer=false
where project_id='e2000000-0000-0000-0000-000000000001'
  and user_id='e1000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','e1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into permission_outcomes values ('downstream-reject',public.cmd_review_task_submission(
 'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',
 'e4000000-0000-0000-0000-000000000001','request_changes','Please revise upstream',
 'e5000000-0000-0000-0000-000000000002',1));
reset role;
select ok((select result->>'ok' from permission_outcomes where label='downstream-approve')='false',
 'downstream assignee cannot approve upstream');
select is((select result->>'ok' from permission_outcomes where label='observer-downstream-reject'),'false',
 'downgraded observer cannot reject using stale downstream assignment');
select is((select result->>'ok' from permission_outcomes where label='downstream-reject'),'true',
 'direct downstream assignee can send upstream back for changes');
select is((select status from public.tasks where id='e3000000-0000-0000-0000-000000000001'),'in_progress',
 'upstream reject restores in-progress task status');
select is((select state from public.task_review_rounds where id='e4000000-0000-0000-0000-000000000001'),'rejected',
 'upstream reject persists processed review round');

select * from finish();
rollback;
