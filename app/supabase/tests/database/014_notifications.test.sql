begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column('public','notifications','title','notifications have a concise title');
select has_column('public','notifications','source_event_id','notifications retain their authoritative business-event source');
select has_function('public','mark_notification_read',array['uuid'],'recipient can mark one notification read through a controlled RPC');
select has_function('public','mark_all_notifications_read',array[]::text[],'recipient can mark all visible notifications read');
select has_function('public','get_unread_notification_count',array[]::text[],'recipient can read an authoritative unread count');
select has_function('public','resolve_notification_target',array['uuid'],'recipient can resolve a safe current target');

select ok(not has_table_privilege('authenticated','public.notifications','INSERT'),'browser cannot directly insert business notifications');
select ok(not has_table_privilege('authenticated','public.notifications','UPDATE'),'browser cannot directly update notification rows');

insert into auth.users(id,email) values
 ('f1000000-0000-0000-0000-000000000001','notification-leader@example.test'),
 ('f1000000-0000-0000-0000-000000000002','notification-member@example.test'),
 ('f1000000-0000-0000-0000-000000000003','notification-outsider@example.test'),
 ('f1000000-0000-0000-0000-000000000004','notification-applicant@example.test');

insert into public.projects(id,name,deadline_at,contribution_mode,leader_id,created_by,version)
values(
 'f2000000-0000-0000-0000-000000000001','Notification project',now()+interval '20 days','weighted',
 'f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001',1
);
insert into public.project_members(project_id,user_id,role,member_state,display_name_snapshot) values
 ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','leader','active','Leader'),
 ('f2000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','member','active','Member');

create temporary table notification_results(label text primary key,result jsonb);
grant all on notification_results to authenticated;

-- Direct assignment produces exactly one notification for the target and replays without spam.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into notification_results values('direct-task',public.cmd_create_task(
 'f2000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000001',1,
 'Assigned task',null,now()+interval '5 days',3::smallint,'direct','f1000000-0000-0000-0000-000000000002'
));
insert into notification_results values('direct-task-replay',public.cmd_create_task(
 'f2000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000001',1,
 'Assigned task',null,now()+interval '5 days',3::smallint,'direct','f1000000-0000-0000-0000-000000000002'
));
reset role;

select is(
 (select count(*)::integer from public.notifications where recipient_id='f1000000-0000-0000-0000-000000000002' and notification_type='task_assignment'),
 1,
 'direct assignment notifies only once across request replay'
);
select is(
 (select count(*)::integer from public.notifications where recipient_id='f1000000-0000-0000-0000-000000000001' and notification_type='task_assignment'),
 0,
 'assignment creator is not broadcast a redundant assignment notification'
);

-- Approval-mode join request alerts only the leader; the eventual decision alerts the applicant.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into notification_results values('approval-invite',public.cmd_create_project_invite(
 'f2000000-0000-0000-0000-000000000001','f9000000-0000-0000-0000-000000000002',2,'approval',7,1
));
reset role;
select result->'data'->>'token' as notification_invite_token from notification_results where label='approval-invite' \gset

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into notification_results values('join-request',public.cmd_join_project_via_invite(
 :'notification_invite_token','f9000000-0000-0000-0000-000000000003',0
));
reset role;
select (result->'data'->>'joinRequestId')::uuid as notification_join_request_id from notification_results where label='join-request' \gset

select is(
 (select count(*)::integer from public.notifications where recipient_id='f1000000-0000-0000-0000-000000000001' and notification_type='project_join_pending'),
 1,
 'pending join request notifies the project leader'
);
select is(
 (select count(*)::integer from public.notifications where recipient_id='f1000000-0000-0000-0000-000000000002' and notification_type='project_join_pending'),
 0,
 'pending join request is not broadcast to ordinary members'
);

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into notification_results values('approve-join',public.cmd_review_project_join_request(
 'f2000000-0000-0000-0000-000000000001',:'notification_join_request_id','approve',
 'f9000000-0000-0000-0000-000000000004',1
));
reset role;

select is(
 (select count(*)::integer from public.notifications where recipient_id='f1000000-0000-0000-0000-000000000004' and notification_type='project_join_approved'),
 1,
 'approved applicant receives a join-result notification'
);

-- Recipient RLS, unread count, mark-read ownership, and safe target resolution.
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(public.get_unread_notification_count(),1::bigint,'recipient sees own unread count');
select (select id::text from public.notifications where notification_type='task_assignment' limit 1) as member_notification_id \gset
select ok(public.mark_notification_read(:'member_notification_id'::uuid),'recipient can mark own notification read');
select is(public.get_unread_notification_count(),0::bigint,'mark read updates unread count');
select ok((public.resolve_notification_target(:'member_notification_id'::uuid)->>'routeName')='task-detail','task notification resolves to task detail');
reset role;

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select is((select count(*)::integer from public.notifications),0,'non-recipient cannot read another users notifications');
select is(public.resolve_notification_target(:'member_notification_id'::uuid),null::jsonb,'non-recipient cannot resolve another users target');
select ok(not public.mark_notification_read(:'member_notification_id'::uuid),'non-recipient cannot mark another users notification read');
reset role;


-- Submission, rejection, and approval are emitted by the real review commands.
insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
 is_direct_assignment,accepted_at,assignment_state,version
) values(
 'f3000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001',
 'Review notification task','f1000000-0000-0000-0000-000000000001',
 'f1000000-0000-0000-0000-000000000002',now()+interval '5 days','in_progress',3,
 false,now(),'assigned',1
);
insert into public.tasks(
 id,project_id,title,created_by,assignee_id,deadline_at,status,weight,
 is_direct_assignment,accepted_at,assignment_state,version
) values(
 'f3000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000001',
 'Downstream reviewer task','f1000000-0000-0000-0000-000000000001',
 'f1000000-0000-0000-0000-000000000004',now()+interval '8 days','in_progress',2,
 false,now(),'assigned',1
);
insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
values(
 'f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000002',
 'f3000000-0000-0000-0000-000000000003',
 'f1000000-0000-0000-0000-000000000001'
);
insert into public.file_upload_reservations(
 id,project_id,task_id,actor_id,mode,object_path,original_name,
 declared_mime_type,declared_size_bytes,state,expires_at,version
) values(
 'f4000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000002',
 'new_file','pending/f2000000/review-notification.pdf','review-notification.pdf',
 'application/pdf',100,'finalized',now()+interval '1 hour',2
);
insert into public.task_files(id,project_id,task_id,logical_name,created_by,version)
values(
 'f5000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001',
 'f3000000-0000-0000-0000-000000000002','review-notification.pdf',
 'f1000000-0000-0000-0000-000000000002',1
);
insert into public.task_file_versions(
 id,file_id,project_id,task_id,reservation_id,version_number,object_path,
 original_name,mime_type,size_bytes,sha256_hex,uploaded_by
) values(
 'f6000000-0000-0000-0000-000000000002','f5000000-0000-0000-0000-000000000002',
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002',
 'f4000000-0000-0000-0000-000000000002',1,'pending/f2000000/review-notification.pdf',
 'review-notification.pdf','application/pdf',100,repeat('b',64),
 'f1000000-0000-0000-0000-000000000002'
);
update public.task_files
set current_version_id='f6000000-0000-0000-0000-000000000002'
where id='f5000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into notification_results values('review-submit',public.cmd_submit_task_for_review(
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002',
 null,array['f6000000-0000-0000-0000-000000000002']::uuid[],'f9000000-0000-0000-0000-000000000005',1
));
reset role;
select (result->'data'->>'reviewRoundId')::uuid as notification_round_one_id
from notification_results where label='review-submit' \gset

select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000001'
    and notification_type='task_review_submitted'
    and entity_id=:'notification_round_one_id'::uuid),
 1,
 'submission notifies the task creator who can review it'
);
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000002'
    and notification_type='task_review_submitted'),
 0,
 'submission is not echoed back to the assignee'
);
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000004'
    and notification_type='task_review_submitted'
    and entity_id=:'notification_round_one_id'::uuid),
 1,
 'submission notifies the primary assignee of a direct downstream task'
);

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into notification_results values('review-reject',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002',
 :'notification_round_one_id','reject','Needs revision',
 'f9000000-0000-0000-0000-000000000006',1
));
reset role;
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000002'
    and notification_type='task_review_rejected'
    and entity_id=:'notification_round_one_id'::uuid),
 1,
 'rejection notifies the task assignee'
);

select version::text as review_task_version
from public.tasks where id='f3000000-0000-0000-0000-000000000002' \gset
select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into notification_results values('review-resubmit',public.cmd_submit_task_for_review(
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002',
 null,array['f6000000-0000-0000-0000-000000000002']::uuid[],'f9000000-0000-0000-0000-000000000007',
 :review_task_version::integer
));
reset role;
select (result->'data'->>'reviewRoundId')::uuid as notification_round_two_id
from notification_results where label='review-resubmit' \gset

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into notification_results values('review-approve',public.cmd_review_task_submission(
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002',
 :'notification_round_two_id','approve',null,
 'f9000000-0000-0000-0000-000000000008',1
));
reset role;
select is(
 (select count(*)::integer from public.notifications
  where recipient_id='f1000000-0000-0000-0000-000000000002'
    and notification_type='task_review_approved'
    and entity_id=:'notification_round_two_id'::uuid),
 1,
 'approval notifies the task assignee'
);


-- If the notification side effect fails, the business command must not half-succeed.
create or replace function pg_temp.reject_assignment_notification()
returns trigger
language plpgsql
as $$
begin
  if new.notification_type = 'task_assignment' then
    raise exception using errcode = 'P0001', message = 'injected notification failure';
  end if;
  return new;
end;
$$;

create trigger notifications_force_failure
before insert on public.notifications
for each row execute function pg_temp.reject_assignment_notification();

select version::text as notification_project_version
from public.projects
where id='f2000000-0000-0000-0000-000000000001' \gset

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok(
  format(
    'select public.cmd_create_task(%L,%L,%s,%L,null,now()+interval ''5 days'',3::smallint,%L,%L)',
    'f2000000-0000-0000-0000-000000000001',
    'f9000000-0000-0000-0000-000000000009',
    :'notification_project_version',
    'Atomic notification failure',
    'direct',
    'f1000000-0000-0000-0000-000000000004'
  ),
  'P0001',
  'injected notification failure',
  'notification failure aborts the business command'
);
reset role;

drop trigger notifications_force_failure on public.notifications;

select is(
  (select count(*)::integer from public.tasks where title='Atomic notification failure'),
  0,
  'notification failure rolls back the task mutation'
);
select is(
  (select count(*)::integer from public.command_requests where request_id='f9000000-0000-0000-0000-000000000009'),
  0,
  'notification failure rolls back the command ledger claim'
);
select is(
  (select count(*)::integer from public.business_events where request_id='f9000000-0000-0000-0000-000000000009'),
  0,
  'notification failure leaves no business event'
);
select is(
  (select count(*)::integer from public.notifications where message like '%Atomic notification failure%'),
  0,
  'notification failure leaves no notification residue'
);

-- Once membership is revoked, old project-linked notifications and their target stop being visible.
update public.project_members
set member_state='removed',departed_at=now()
where project_id='f2000000-0000-0000-0000-000000000001'
  and user_id='f1000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','f1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::integer from public.notifications),0,'revoked member cannot read old project-linked notifications');
select is(public.resolve_notification_target(:'member_notification_id'::uuid),null::jsonb,'revoked member cannot resolve an old target');
reset role;

-- The notification side effect is transactional with its source event.
savepoint notification_atomicity;
insert into public.business_events(
 project_id,actor_id,event_type,entity_type,entity_id,event_data,created_at
) values(
 'f2000000-0000-0000-0000-000000000001',
 'f1000000-0000-0000-0000-000000000001',
 'project_member_role_changed','project_member',
 (select id from public.project_members where project_id='f2000000-0000-0000-0000-000000000001' and user_id='f1000000-0000-0000-0000-000000000002'),
 jsonb_build_object('oldRole','member','newRole','admin'),now()
);
select max(id)::text as atomic_event_id
from public.business_events
where event_type='project_member_role_changed'
  and actor_id='f1000000-0000-0000-0000-000000000001' \gset
select is((select count(*)::integer from public.notifications where source_event_id=:'atomic_event_id'::bigint),1,'business event creates notification in the same transaction');
rollback to savepoint notification_atomicity;
select is((select count(*)::integer from public.notifications where source_event_id=:'atomic_event_id'::bigint),0,'rolling back source event also rolls back notification');

select * from finish();
rollback;
