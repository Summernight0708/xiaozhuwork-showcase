begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public','cmd_edit_task',
  array['uuid','uuid','uuid','integer','text','text','timestamp with time zone','smallint','text'],
  'controlled task edit RPC exists'
);

insert into auth.users(id,email) values
 ('b1000000-0000-0000-0000-000000000001','edit-leader@example.test'),
 ('b1000000-0000-0000-0000-000000000002','edit-creator@example.test'),
 ('b1000000-0000-0000-0000-000000000003','edit-admin@example.test'),
 ('b1000000-0000-0000-0000-000000000004','edit-observer@example.test'),
 ('b1000000-0000-0000-0000-000000000005','edit-outsider@example.test');

insert into public.projects(id,name,deadline_at,leader_id,created_by,version,contribution_mode)
values(
 'b2000000-0000-0000-0000-000000000001','Task edit',now()+interval '20 days',
 'b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',1,'weighted'
);
insert into public.project_members(id,project_id,user_id,role,member_state,is_observer,version) values
 ('b3000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','leader','active',false,1),
 ('b3000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','member','active',false,1),
 ('b3000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','admin','active',false,1),
 ('b3000000-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000004','observer','active',true,1);

insert into public.tasks(id,project_id,title,description,created_by,deadline_at,status,weight,assignment_state,version) values
 ('b4000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','Editable','Old','b1000000-0000-0000-0000-000000000002',now()+interval '8 days','not_started',2,'claimable',1),
 ('b4000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000001','Observer authored','Old','b1000000-0000-0000-0000-000000000004',now()+interval '8 days','not_started',2,'claimable',1),
 ('b4000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000001','Review locked','Old','b1000000-0000-0000-0000-000000000002',now()+interval '8 days','awaiting_review',2,'assigned',1),
 ('b4000000-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001','Completed locked','Old','b1000000-0000-0000-0000-000000000002',now()+interval '8 days','completed',2,'assigned',1);

insert into public.tasks(
 id,project_id,title,description,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version
) values(
 'b4000000-0000-0000-0000-000000000005','b2000000-0000-0000-0000-000000000001',
 'Accepted metadata','Old','b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002',
 now()+interval '8 days','in_progress',2,now(),'assigned',1
);

insert into public.tasks(
 id,project_id,title,description,created_by,assignee_id,deadline_at,status,weight,accepted_at,assignment_state,version
) values(
 'b4000000-0000-0000-0000-000000000006','b2000000-0000-0000-0000-000000000001',
 'Overdue accepted','Old','b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002',
 now()-interval '1 day','in_progress',2,now()-interval '2 days','assigned',1
);

create temporary table edit_rpc_results(label text primary key,result jsonb);
grant all on edit_rpc_results to authenticated;

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into edit_rpc_results values('creator-edit',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',1,'Edited title','New description',
 now()+interval '9 days',4::smallint
));
insert into edit_rpc_results values('creator-replay',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',1,'Edited title','New description',
 now()+interval '9 days',4::smallint
));
insert into edit_rpc_results values('creator-reuse',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000001',1,'Different','New description',
 now()+interval '9 days',4::smallint
));
reset role;

select is((select result->>'ok' from edit_rpc_results where label='creator-edit'),'true','task creator edits basic fields');
select is((select version from public.tasks where id='b4000000-0000-0000-0000-000000000001'),2,'task edit advances task version');
select is((select title from public.tasks where id='b4000000-0000-0000-0000-000000000001'),'Edited title','title persisted');
select is((select weight from public.tasks where id='b4000000-0000-0000-0000-000000000001'),4::smallint,'weight persisted before activity');
select is((select result->>'replayed' from edit_rpc_results where label='creator-replay'),'true','task edit replays identical request');
select is((select result->>'code' from edit_rpc_results where label='creator-reuse'),'IDEMPOTENCY_KEY_REUSED','task edit rejects request id reuse');

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into edit_rpc_results values('leader-edit',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000002',2,'Leader correction','New description',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000001'),4::smallint
));
reset role;
select is((select result->>'ok' from edit_rpc_results where label='leader-edit'),'true','leader may edit any project task');

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
set local role authenticated;
insert into edit_rpc_results values('admin-not-owner',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000003',3,'Admin takeover','New description',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000001'),4::smallint
));
reset role;
select is((select result->>'code' from edit_rpc_results where label='admin-not-owner'),'NOT_FOUND_OR_NOT_AUTHORIZED','admin does not inherit leader-wide task editing');

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
set local role authenticated;
insert into edit_rpc_results values('observer-edit',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000002',
 'b9000000-0000-0000-0000-000000000004',1,'Observer write','Old',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000002'),2::smallint
));
reset role;
select is((select result->>'code' from edit_rpc_results where label='observer-edit'),'NOT_AUTHORIZED','observer remains read-only even when task creator');

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000005',true);
set local role authenticated;
insert into edit_rpc_results values('outsider-edit',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000005',3,'Outsider','New description',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000001'),4::smallint
));
reset role;
select is((select result->>'code' from edit_rpc_results where label='outsider-edit'),'NOT_FOUND_OR_NOT_AUTHORIZED','outsider gets indistinguishable denial');

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into edit_rpc_results values('stale-edit',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',
 'b9000000-0000-0000-0000-000000000006',2,'Stale','New description',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000001'),4::smallint
));
insert into edit_rpc_results values('accepted-metadata',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000005',
 'b9000000-0000-0000-0000-000000000007',1,'Accepted renamed','Updated metadata',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000005'),2::smallint
));
insert into edit_rpc_results values('overdue-metadata',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000006',
 'b9000000-0000-0000-0000-000000000012',1,'Overdue corrected','Metadata correction',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000006'),2::smallint
));
insert into edit_rpc_results values('accepted-deadline',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000005',
 'b9000000-0000-0000-0000-000000000008',2,'Accepted renamed','Updated metadata',
 now()+interval '10 days',2::smallint
));
insert into edit_rpc_results values('accepted-weight',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000005',
 'b9000000-0000-0000-0000-000000000009',2,'Accepted renamed','Updated metadata',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000005'),5::smallint
));
insert into edit_rpc_results values('review-locked',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000003',
 'b9000000-0000-0000-0000-000000000010',1,'No','Old',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000003'),2::smallint
));
insert into edit_rpc_results values('completed-locked',public.cmd_edit_task(
 'b2000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
 'b9000000-0000-0000-0000-000000000011',1,'No','Old',
 (select deadline_at from public.tasks where id='b4000000-0000-0000-0000-000000000004'),2::smallint
));
reset role;

select is((select result->>'code' from edit_rpc_results where label='stale-edit'),'STALE_VERSION','stale task edit is rejected');
select is((select result->>'currentVersion' from edit_rpc_results where label='stale-edit'),'3','stale edit returns current task version');
select is((select result->>'ok' from edit_rpc_results where label='accepted-metadata'),'true','accepted task still allows title and description corrections');
select is((select result->>'ok' from edit_rpc_results where label='overdue-metadata'),'true','overdue accepted task allows metadata correction when its existing deadline is unchanged');
select is((select result->>'code' from edit_rpc_results where label='accepted-deadline'),'CONFIRMATION_REQUIRED','accepted task deadline requires dedicated confirmation flow');
select is((select result->>'field' from edit_rpc_results where label='accepted-deadline'),'deadlineAt','deadline confirmation points to deadline field');
select is((select result->>'code' from edit_rpc_results where label='accepted-weight'),'CONFIRMATION_REQUIRED','weight freezes after task activity');
select is((select result->>'field' from edit_rpc_results where label='accepted-weight'),'weight','weight confirmation points to weight field');
select is((select result->>'code' from edit_rpc_results where label='review-locked'),'INVALID_TRANSITION','task in review cannot be definition-edited');
select is((select result->>'code' from edit_rpc_results where label='completed-locked'),'INVALID_TRANSITION','completed task definition is immutable');
select is((select count(*)::integer from public.business_events where event_type='task_edited' and project_id='b2000000-0000-0000-0000-000000000001'),4,'successful state-changing edits are audited');

select * from finish();
rollback;
