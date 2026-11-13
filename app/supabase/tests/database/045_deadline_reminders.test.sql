begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
 ('a1100000-0000-0000-0000-000000000001','a-reminder-leader@example.test'),
 ('a1100000-0000-0000-0000-000000000002','a-reminder-primary@example.test'),
 ('a1100000-0000-0000-0000-000000000003','a-reminder-collaborator@example.test'),
 ('a1100000-0000-0000-0000-000000000004','a-reminder-observer@example.test'),
 ('a1100000-0000-0000-0000-000000000005','a-reminder-outsider@example.test');
insert into public.projects(id,name,deadline_at,leader_id,created_by,contribution_mode)
values('a2100000-0000-0000-0000-000000000001','A reminder weighted',
 now()+interval '12 days','a1100000-0000-0000-0000-000000000001',
 'a1100000-0000-0000-0000-000000000001','weighted'),
 ('a2100000-0000-0000-0000-000000000002','A reminder facts',
 now()+interval '12 days','a1100000-0000-0000-0000-000000000001',
 'a1100000-0000-0000-0000-000000000001','facts_only');
insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
 ('a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','leader','active',false),
 ('a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002','member','active',false),
 ('a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003','member','active',false),
 ('a2100000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000004','observer','active',true),
 ('a2100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000001','leader','active',false),
 ('a2100000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','member','active',false);
insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state)
values
 ('a3100000-0000-0000-0000-000000000001','a2100000-0000-0000-0000-000000000001','Due after 23h',
  'a1100000-0000-0000-0000-000000000002',now()+interval '23 hours','in_progress',2,'assigned'),
 ('a3100000-0000-0000-0000-000000000002','a2100000-0000-0000-0000-000000000001','Not due yet',
  'a1100000-0000-0000-0000-000000000002',now()+interval '3 days','in_progress',2,'assigned'),
 ('a3100000-0000-0000-0000-000000000003','a2100000-0000-0000-0000-000000000002','Facts reminder',
  'a1100000-0000-0000-0000-000000000002',now()+interval '23 hours','in_progress',null,'assigned');

select is((select deadline_revision from public.task_reminder_deadlines
 where task_id='a3100000-0000-0000-0000-000000000001'),1,'initial DDL revision');
select is(private.dispatch_due_task_reminders(100,now()),2,'24h reminders sent in weighted and facts_only');
select is(private.dispatch_due_task_reminders(100,now()),0,'worker replay sends nothing twice');
select is((select count(*)::integer from public.notifications
 where notification_type='task_deadline_reminder'
 and entity_id='a3100000-0000-0000-0000-000000000002'),0,'future node never sent early');
select is((select count(*)::integer from public.task_reminder_jobs
 where task_id='a3100000-0000-0000-0000-000000000001'
 and delivered_at is not null and offset_seconds=86400),1,'24h delivery has occurrence ledger');

update public.tasks set deadline_at=now()+interval '110 minutes'
where id='a3100000-0000-0000-0000-000000000001';
select is((select deadline_revision from public.task_reminder_deadlines
 where task_id='a3100000-0000-0000-0000-000000000001'),2,'DDL changed -> revision increments');
select is(private.dispatch_due_task_reminders(100,now()),1,'new 2h node delivered');
select is((select count(*)::integer from public.notifications
 where entity_id='a3100000-0000-0000-0000-000000000001'
 and notification_type='task_deadline_reminder'),2,'old 24h not replayed on new DDL');
select is(private.dispatch_due_task_reminders(100,now()),0,'same revision idempotent');

create temporary table a_command_results(label text primary key,result jsonb);
grant all on a_command_results to authenticated;
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into a_command_results values ('preferences',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[172800,7200],true,'a9100000-0000-0000-0000-000000000001',0));
insert into a_command_results values ('replay',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[172800,7200],true,'a9100000-0000-0000-0000-000000000001',0));
insert into a_command_results values ('different-payload',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[86400,7200],true,'a9100000-0000-0000-0000-000000000001',0));
insert into a_command_results values ('stale',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[86400,7200],false,'a9100000-0000-0000-0000-000000000002',0));
insert into a_command_results values ('invalid',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[7200,7200],true,'a9100000-0000-0000-0000-000000000003',1));
reset role;
select is((select result->>'ok' from a_command_results where label='preferences'),'true','owner saves custom offsets');
select is((select result->>'replayed' from a_command_results where label='replay'),'true','same request replay');
select is((select result->>'code' from a_command_results where label='different-payload'),'IDEMPOTENCY_KEY_REUSED','same request different payload rejected');
select is((select result->>'code' from a_command_results where label='stale'),'STALE_VERSION','stale preference version rejected');
select is((select result->>'code' from a_command_results where label='invalid'),'VALIDATION_FAILED','duplicate node rejected');
select is((select count(*)::integer from public.business_events
 where event_type='task_reminder_preferences_set' and entity_id='a3100000-0000-0000-0000-000000000001'),1,'replays never multiply audits');

update public.tasks set deadline_at=now()+interval '47 hours'
where id='a3100000-0000-0000-0000-000000000001';
select is(private.dispatch_due_task_reminders(100,now()),1,'future custom 48h node rescheduled after extension');
select is(private.dispatch_due_task_reminders(100,now()),0,'custom node idempotent');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into a_command_results values ('off',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[172800,7200],false,'a9100000-0000-0000-0000-000000000004',1));
reset role;
update public.tasks set deadline_at=now()+interval '110 minutes'
where id='a3100000-0000-0000-0000-000000000001';
select is(private.dispatch_due_task_reminders(100,now()),0,'disabled personal reminder stays silent');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into a_command_results values ('outsider-pref',public.cmd_set_task_reminder_preferences(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 array[86400,7200],false,'a9100000-0000-0000-0000-000000000005',0));
insert into a_command_results values ('outsider-nudge',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 'a9100000-0000-0000-0000-000000000006',1));
reset role;
select is((select result->>'code' from a_command_results where label='outsider-pref'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot write preference');
select is((select result->>'code' from a_command_results where label='outsider-nudge'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot nudge');
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into a_command_results values ('observer',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000001',
 'a9100000-0000-0000-0000-000000000007',1));
reset role;
select is((select result->>'code' from a_command_results where label='observer'),'NOT_FOUND_OR_NOT_AUTHORIZED','observer cannot nudge');

insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at)
values('a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a1100000-0000-0000-0000-000000000003','accepted',now());
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into a_command_results values ('leader-nudge',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000008',1));
insert into a_command_results values ('leader-repeat',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000009',1));
reset role;
select is((select result->>'ok' from a_command_results where label='leader-nudge'),'true','leader nudge succeeds');
select is((select result->>'code' from a_command_results where label='leader-repeat'),'RATE_LIMITED','12h cooldown enforced');
select is((select result->'data'->>'recipientCount' from a_command_results where label='leader-nudge'),'2','leader notifies both participants');
select is((select count(*)::integer from public.notifications where
 notification_type='task_nudge' and entity_id='a3100000-0000-0000-0000-000000000002'),2,'nudge notifications retain task links');
select ok(exists(select 1 from public.business_events where event_type='task_nudge_sent'
 and event_data->>'senderId'='a1100000-0000-0000-0000-000000000001'),'nudge audit retains sender');

select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into a_command_results values ('primary-nudge',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000010',1));
reset role;
select is((select result->'data'->>'recipientCount' from a_command_results where label='primary-nudge'),'1','primary only nudges collaborator');

update public.tasks set status='blocked',blocked_reason='waiting' where id='a3100000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into a_command_results values ('blocked-exception',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000011',1));
insert into a_command_results values ('blocked-repeat',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000012',1));
reset role;
select is((select result->>'ok' from a_command_results where label='blocked-exception'),'true','block permits one extra nudge');
select is((select result->>'code' from a_command_results where label='blocked-repeat'),'RATE_LIMITED','block exception cannot spam');
update public.tasks set status='in_progress',blocked_reason=null,
 deadline_at=now()+interval '1 hour' where id='a3100000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','a1100000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into a_command_results values ('urgent-exception',public.cmd_send_task_nudge(
 'a2100000-0000-0000-0000-000000000001','a3100000-0000-0000-0000-000000000002',
 'a9100000-0000-0000-0000-000000000013',1));
reset role;
select is((select result->>'ok' from a_command_results where label='urgent-exception'),'true','under 2h permits one extra nudge');

update public.tasks set status='completed',completed_at=now() where id='a3100000-0000-0000-0000-000000000002';
select is(private.dispatch_due_task_reminders(100,now()),0,'completed task cannot auto-notify');
update public.projects set archived_at=now() where id='a2100000-0000-0000-0000-000000000002';
select is(private.dispatch_due_task_reminders(100,now()),0,'archived project cannot auto-notify');

select lives_ok($$select private.dispatch_due_task_reminders(10,now())$$,'dispatcher supports safe retries');
select is((select count(*)::integer from public.task_nudge_logs
 where task_id='a3100000-0000-0000-0000-000000000002' and sender_id='a1100000-0000-0000-0000-000000000001'),3,'one normal, one block, one urgent nudge');

-- Responsibility changes, dependency blocks, cancellation, and scheduler ACL.
insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state)
values('a3100000-0000-0000-0000-000000000004',
 'a2100000-0000-0000-0000-000000000001','Reassignment',
 'a1100000-0000-0000-0000-000000000002',now()+interval '1 hour','in_progress',2,'assigned');
insert into public.task_reminder_jobs(task_id,project_id,recipient_id,deadline_revision,
 offset_seconds,deadline_at,scheduled_for) values(
 'a3100000-0000-0000-0000-000000000004',
 'a2100000-0000-0000-0000-000000000001',
 'a1100000-0000-0000-0000-000000000002',1,7200,
 now()+interval '1 hour',now()-interval '1 hour');
update public.tasks set assignee_id='a1100000-0000-0000-0000-000000000003',version=version+1
where id='a3100000-0000-0000-0000-000000000004';
select is(private.dispatch_due_task_reminders(100,now()),2,'reassigned task yields two due nodes for new assignee');
select is((select count(*)::integer from public.notifications
 where entity_id='a3100000-0000-0000-0000-000000000004'
 and recipient_id='a1100000-0000-0000-0000-000000000002'),0,'former assignee not notified');
select ok(exists(select 1 from public.task_reminder_jobs
 where task_id='a3100000-0000-0000-0000-000000000004'
 and recipient_id='a1100000-0000-0000-0000-000000000002'
 and invalidated_at is not null),'queued former assignee reminder invalidated');

insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state)
values('a3100000-0000-0000-0000-000000000005',
 'a2100000-0000-0000-0000-000000000001','Blocked downstream',
 'a1100000-0000-0000-0000-000000000002',now()+interval '23 hours','in_progress',2,'assigned'),
 ('a3100000-0000-0000-0000-000000000006',
 'a2100000-0000-0000-0000-000000000001','Upstream incomplete',
 null,now()+interval '4 days','in_progress',2,'claimable');
insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id) values(
 'a2100000-0000-0000-0000-000000000001',
 'a3100000-0000-0000-0000-000000000006',
 'a3100000-0000-0000-0000-000000000005');
select is(private.dispatch_due_task_reminders(100,now()),0,'incomplete upstream suppresses reminder');
update public.tasks set status='completed',completed_at=now() where id='a3100000-0000-0000-0000-000000000006';
select is(private.dispatch_due_task_reminders(100,now()),1,'unblocked dependent reminder delivered');

insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state,
 canceled_at,cancel_reason)
values('a3100000-0000-0000-0000-000000000007',
 'a2100000-0000-0000-0000-000000000001','Cancelled task',
 'a1100000-0000-0000-0000-000000000002',now()+interval '23 hours','canceled',2,'assigned',
 now(),'Not necessary');
select is(private.dispatch_due_task_reminders(100,now()),0,'canceled task never scheduled');

select throws_ok(
 $$insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state)
 values('a3100000-0000-0000-0000-000000000008',
 'a2100000-0000-0000-0000-000000000002','Archived project reminder',
 'a1100000-0000-0000-0000-000000000002',now()+interval '23 hours','in_progress',null,'assigned')$$,
 'P0001','PROJECT_NOT_ACTIVE','archived projects deny new tasks');
select is(private.dispatch_due_task_reminders(100,now()),0,'archived project cannot schedule');

insert into public.tasks(id,project_id,title,assignee_id,deadline_at,status,weight,assignment_state)
values('a3100000-0000-0000-0000-000000000009',
 'a2100000-0000-0000-0000-000000000001','Member removal',
 'a1100000-0000-0000-0000-000000000003',now()+interval '23 hours','in_progress',2,'assigned');
insert into public.task_reminder_jobs(task_id,project_id,recipient_id,deadline_revision,
 offset_seconds,deadline_at,scheduled_for) values(
 'a3100000-0000-0000-0000-000000000009',
 'a2100000-0000-0000-0000-000000000001',
 'a1100000-0000-0000-0000-000000000003',1,86400,
 now()+interval '23 hours',now()-interval '1 hour');
update public.project_members set member_state='removed',departed_at=now()
 where project_id='a2100000-0000-0000-0000-000000000001'
 and user_id='a1100000-0000-0000-0000-000000000003';
select is(private.dispatch_due_task_reminders(100,now()),0,'removed member stale job never delivered');
select ok(exists(select 1 from public.task_reminder_jobs
 where task_id='a3100000-0000-0000-0000-000000000009'
 and invalidated_at is not null),'removed member queued reminder invalidated');
select ok(not has_function_privilege('authenticated','public.dispatch_task_reminders_service(integer)','EXECUTE'),
 'authenticated cannot execute scheduler');
select ok(not has_function_privilege('anon','public.dispatch_task_reminders_service(integer)','EXECUTE'),
 'anon cannot execute scheduler');
select ok(has_function_privilege('service_role','public.dispatch_task_reminders_service(integer)','EXECUTE'),
 'service role can execute scheduler');
select ok(not has_schema_privilege('authenticated','private','USAGE'),
 'private dispatch schema hidden from authenticated clients');

select * from finish();
rollback;