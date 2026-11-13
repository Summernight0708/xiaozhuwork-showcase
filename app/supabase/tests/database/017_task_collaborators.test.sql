begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_collaborators','task collaborator relation exists');
select has_function(
  'public','cmd_invite_task_collaborator',
  array['uuid','uuid','uuid','uuid','integer'],
  'invite collaborator command exists'
);
select has_function(
  'public','cmd_respond_to_task_collaborator',
  array['uuid','uuid','uuid','text','uuid','integer'],
  'respond collaborator command exists'
);
select has_function(
  'public','cmd_remove_task_collaborator',
  array['uuid','uuid','uuid','uuid','integer'],
  'remove collaborator command exists'
);
select has_function(
  'public','cmd_leave_task_collaboration',
  array['uuid','uuid','uuid','uuid','integer'],
  'leave collaboration command exists'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.task_collaborators'::regclass),
  'collaborator relation enables RLS'
);
select ok(
  has_table_privilege('authenticated','public.task_collaborators_visible','SELECT'),
  'authenticated members may read through privacy-scoped view'
);
select ok(
  not has_table_privilege('authenticated','public.task_collaborators','INSERT')
  and not has_table_privilege('authenticated','public.task_collaborators','UPDATE')
  and not has_table_privilege('authenticated','public.task_collaborators','DELETE'),
  'browser cannot mutate collaborator relation directly'
);

insert into auth.users(id,email) values
 ('d1000000-0000-0000-0000-000000000001','collab-leader@example.test'),
 ('d1000000-0000-0000-0000-000000000002','collab-creator@example.test'),
 ('d1000000-0000-0000-0000-000000000003','collab-primary@example.test'),
 ('d1000000-0000-0000-0000-000000000004','collab-member@example.test'),
 ('d1000000-0000-0000-0000-000000000005','collab-second@example.test'),
 ('d1000000-0000-0000-0000-000000000006','collab-observer@example.test'),
 ('d1000000-0000-0000-0000-000000000007','collab-outsider@example.test');

update public.profiles set display_name='组长' where id='d1000000-0000-0000-0000-000000000001';
update public.profiles set display_name='创建者' where id='d1000000-0000-0000-0000-000000000002';
update public.profiles set display_name='主负责人' where id='d1000000-0000-0000-0000-000000000003';
update public.profiles set display_name='协作者甲' where id='d1000000-0000-0000-0000-000000000004';
update public.profiles set display_name='协作者乙' where id='d1000000-0000-0000-0000-000000000005';

insert into public.projects(
  id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values (
  'd2000000-0000-0000-0000-000000000001','Collaborator project',now()+interval '30 days',
  'd1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',
  1,'weighted','active'
);

insert into public.projects(
  id,name,deadline_at,leader_id,created_by,version,contribution_mode,lifecycle_state
) values (
  'd2000000-0000-0000-0000-000000000002','Other project',now()+interval '30 days',
  'd1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',
  1,'weighted','active'
);

insert into public.project_members(
  id,project_id,user_id,role,member_state,is_observer,version,departed_at
) values
 ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','leader','active',false,1,null),
 ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002','member','active',false,1,null),
 ('d3000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000003','member','active',false,1,null),
 ('d3000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000004','member','active',false,1,null),
 ('d3000000-0000-0000-0000-000000000005','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000005','member','active',false,1,null),
 ('d3000000-0000-0000-0000-000000000006','d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000006','observer','active',true,1,null);

insert into public.project_members(
  id,project_id,user_id,role,member_state,is_observer,version,departed_at
) values (
  'd3000000-0000-0000-0000-000000000007',
  'd2000000-0000-0000-0000-000000000002',
  'd1000000-0000-0000-0000-000000000001',
  'leader','active',false,1,null
);

insert into public.tasks(
  id,project_id,title,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version
) values
 ('d4000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','答辩 PPT','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',3,now()-interval '1 day','assigned',1),
 ('d4000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001','已完成任务','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','completed',2,now()-interval '2 days','assigned',1),
 ('d4000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000002','其他项目任务','d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001',now()+interval '10 days','in_progress',2,now()-interval '1 day','assigned',1),
 ('d4000000-0000-0000-0000-000000000004','d2000000-0000-0000-0000-000000000001','协作与主责冲突任务','d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003',now()+interval '10 days','in_progress',2,now()-interval '1 day','assigned',1);

create temporary table collaborator_results(label text primary key,result jsonb);
grant all on collaborator_results to authenticated;

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into collaborator_results values('invite',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000004','d9000000-0000-0000-0000-000000000001',0
));
insert into collaborator_results values('invite-replay',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000004','d9000000-0000-0000-0000-000000000001',0
));
insert into collaborator_results values('duplicate-pending',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000004','d9000000-0000-0000-0000-000000000002',1
));
insert into collaborator_results values('primary-as-collaborator',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000003','d9000000-0000-0000-0000-000000000003',0
));
insert into collaborator_results values('observer-target',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000006','d9000000-0000-0000-0000-000000000004',0
));
insert into collaborator_results values('outsider-target',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000007','d9000000-0000-0000-0000-000000000005',0
));
insert into collaborator_results values('cross-project-task',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000003',
 'd1000000-0000-0000-0000-000000000005','d9000000-0000-0000-0000-000000000016',0
));
reset role;

select is((select result->>'ok' from collaborator_results where label='invite'),'true','creator invites collaborator');
select is((select result->>'replayed' from collaborator_results where label='invite-replay'),'true','invite request replay is idempotent');
select is((select result->>'code' from collaborator_results where label='duplicate-pending'),'INVALID_TRANSITION','duplicate pending invitation is rejected');
select is((select result->>'code' from collaborator_results where label='primary-as-collaborator'),'INVALID_TRANSITION','primary cannot also be collaborator');
select is((select result->>'code' from collaborator_results where label='observer-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','observer cannot become collaborator');
select is((select result->>'code' from collaborator_results where label='outsider-target'),'NOT_FOUND_OR_NOT_AUTHORIZED','non-member cannot become collaborator');
select is((select result->>'code' from collaborator_results where label='cross-project-task'),'NOT_FOUND_OR_NOT_AUTHORIZED','cross-project task id is rejected');
select is(
 (select state from public.task_collaborators where task_id='d4000000-0000-0000-0000-000000000001' and user_id='d1000000-0000-0000-0000-000000000004'),
 'pending','invitation starts pending'
);
select ok(
 exists(select 1 from public.notifications where recipient_id='d1000000-0000-0000-0000-000000000004' and notification_type='task_collaborator_invited'),
 'invite generates notification'
);

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into collaborator_results values('accept',public.cmd_respond_to_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (select id from public.task_collaborators where task_id='d4000000-0000-0000-0000-000000000001' and user_id='d1000000-0000-0000-0000-000000000004'),
 'accept','d9000000-0000-0000-0000-000000000006',1
));
insert into collaborator_results values('collaborator-progress',public.cmd_update_task_progress(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd9000000-0000-0000-0000-000000000007',1,'in_progress','协作推进中',null
));
insert into collaborator_results values('collaborator-submit',public.cmd_submit_task_for_review(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 null,array['d8000000-0000-0000-0000-000000000001']::uuid[],
 'd9000000-0000-0000-0000-000000000008',2
));
reset role;

select is((select result->>'ok' from collaborator_results where label='accept'),'true','invitee accepts collaboration');
select is((select state from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000004'),'accepted','accepted relation is active');
select is((select result->>'ok' from collaborator_results where label='collaborator-progress'),'true','accepted collaborator updates progress');
select is((select result->>'code' from collaborator_results where label='collaborator-submit'),'NOT_FOUND_OR_NOT_AUTHORIZED','collaborator cannot submit final review');
select ok(
 exists(select 1 from public.notifications where notification_type='task_collaborator_accepted' and recipient_id in ('d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003')),
 'acceptance generates responsibility notification'
);

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into collaborator_results values('remove',public.cmd_remove_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (select id from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000004'),
 'd9000000-0000-0000-0000-000000000009',2
));
reset role;
select is((select result->>'ok' from collaborator_results where label='remove'),'true','leader removes collaborator');
select is((select state from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000004'),'removed','removed relation remains as history');
select ok(
 exists(select 1 from public.notifications where notification_type='task_collaborator_removed' and recipient_id='d1000000-0000-0000-0000-000000000004'),
 'removed collaborator is notified'
);

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into collaborator_results values('removed-progress',public.cmd_update_task_progress(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd9000000-0000-0000-0000-000000000010',2,'in_progress','不应成功',null
));
reset role;
select is((select result->>'code' from collaborator_results where label='removed-progress'),'NOT_FOUND_OR_NOT_AUTHORIZED','removed collaborator loses participant mutation rights');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into collaborator_results values('reinvite',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000004','d9000000-0000-0000-0000-000000000011',0
));
insert into collaborator_results values('invite-second',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 'd1000000-0000-0000-0000-000000000005','d9000000-0000-0000-0000-000000000012',0
));
reset role;
select is((select result->>'ok' from collaborator_results where label='reinvite'),'true','removed collaborator can be explicitly re-invited');
select is(
  (
    select count(*)::bigint
    from public.task_collaborators
    where task_id='d4000000-0000-0000-0000-000000000001'
      and user_id='d1000000-0000-0000-0000-000000000004'
      and state='removed'
  ),
  1::bigint,
  'reinvite preserves removed history row'
);
select is(
  (
    select count(*)::bigint
    from public.task_collaborators
    where task_id='d4000000-0000-0000-0000-000000000001'
      and user_id='d1000000-0000-0000-0000-000000000004'
      and state='pending'
  ),
  1::bigint,
  'reinvite creates a new pending relation'
);

update public.project_members
set member_state='left', departed_at=now(), version=version+1
where project_id='d2000000-0000-0000-0000-000000000001'
  and user_id='d1000000-0000-0000-0000-000000000004';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into collaborator_results values('accept-after-leaving-project',public.cmd_respond_to_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (
   select id
   from public.task_collaborators
   where user_id='d1000000-0000-0000-0000-000000000004'
     and state='pending'
 ),
 'accept','d9000000-0000-0000-0000-000000000017',1
));
reset role;
select is(
 (select result->>'code' from collaborator_results where label='accept-after-leaving-project'),
 'NOT_FOUND_OR_NOT_AUTHORIZED',
 'pending collaborator cannot accept after leaving project'
);

update public.tasks
set status='completed', completed_at=now(), updated_at=now()
where id='d4000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into collaborator_results values('accept-after-completion',public.cmd_respond_to_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (select id from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000005'),
 'accept','d9000000-0000-0000-0000-000000000018',1
));
reset role;
select is(
 (select result->>'code' from collaborator_results where label='accept-after-completion'),
 'INVALID_TRANSITION',
 'pending collaborator cannot accept after task completion'
);

update public.tasks
set status='in_progress', completed_at=null, updated_at=now()
where id='d4000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into collaborator_results values('accept-second',public.cmd_respond_to_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (select id from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000005'),
 'accept','d9000000-0000-0000-0000-000000000013',1
));
insert into collaborator_results values('leave',public.cmd_leave_task_collaboration(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001',
 (select id from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000005'),
 'd9000000-0000-0000-0000-000000000014',2
));
reset role;
select is((select result->>'ok' from collaborator_results where label='leave'),'true','accepted collaborator can leave');
select is((select state from public.task_collaborators where user_id='d1000000-0000-0000-0000-000000000005'),'removed','leave preserves removed history');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into collaborator_results values('invite-completed',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000002',
 'd1000000-0000-0000-0000-000000000005','d9000000-0000-0000-0000-000000000015',0
));
reset role;
select is((select result->>'code' from collaborator_results where label='invite-completed'),'INVALID_TRANSITION','completed task rejects collaborator invitation');

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into collaborator_results values('invite-before-claim',public.cmd_invite_task_collaborator(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000004',
 'd1000000-0000-0000-0000-000000000005','d9000000-0000-0000-0000-000000000019',0
));
reset role;
select is((select result->>'ok' from collaborator_results where label='invite-before-claim'),'true','pending collaborator setup for primary conflict');

update public.tasks
set assignee_id=null, assignment_state='claimable', accepted_at=null, status='not_started'
where id='d4000000-0000-0000-0000-000000000004';

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into collaborator_results values('pending-collaborator-claim',public.cmd_claim_task(
 'd2000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000004',
 'd9000000-0000-0000-0000-000000000020',1
));
reset role;
select is(
 (select result->>'code' from collaborator_results where label='pending-collaborator-claim'),
 'INVALID_TRANSITION',
 'pending collaboration must resolve before explicit primary claim'
);

select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000007',true);
set local role authenticated;
select is(
  (select count(*)::bigint from public.task_collaborators where project_id='d2000000-0000-0000-0000-000000000001'),
  0::bigint,
  'outsider cannot read collaborator relations through RLS'
);
reset role;

select ok(
 not exists(
   select 1
   from public.task_collaborators c
   join public.tasks t on t.project_id=c.project_id and t.id=c.task_id
   where c.state='accepted' and c.user_id=t.assignee_id
 ),
 'accepted collaborator never overlaps primary assignee'
);
select ok(
 exists(select 1 from public.business_events where event_type='task_collaborator_invited'),
 'collaborator lifecycle emits business events'
);

select * from finish();
rollback;
