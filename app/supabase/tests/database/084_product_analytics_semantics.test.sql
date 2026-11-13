begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'private',
  'analytics_event_actor_eligibility',
  'event-time analytics actor eligibility snapshot exists'
);
select has_function(
  'private',
  'analytics_is_effective_event_v1',
  array['text'],
  'v1 effective-event classifier exists'
);

with expected(event_type,included) as (
  values
    ('account_deletion_canceled',false),
    ('account_deletion_requested',false),
    ('calendar_subscription_created',false),
    ('calendar_subscription_revoked',false),
    ('contribution_penalty_adjusted',false),
    ('contribution_penalty_appealed',false),
    ('contribution_penalty_assessed',false),
    ('contribution_report_confirmed',false),
    ('contribution_report_created',false),
    ('contribution_report_formalized',false),
    ('contribution_shares_confirmed',false),
    ('contribution_shares_proposed',false),
    ('contribution_shares_rejected',false),
    ('external_evidence_created',false),
    ('external_evidence_removed',false),
    ('external_evidence_updated',false),
    ('file_version_withdrawn',false),
    ('project_archived',false),
    ('project_completed',false),
    ('project_contribution_review_started',false),
    ('project_created',false),
    ('project_invitation_created',false),
    ('project_invitation_renewed',false),
    ('project_invitation_revoked',false),
    ('project_join_request_approved',false),
    ('project_join_request_canceled',false),
    ('project_join_request_rejected',false),
    ('project_join_requested',false),
    ('project_leadership_transferred',false),
    ('project_member_joined',true),
    ('project_member_left',false),
    ('project_member_removed',false),
    ('project_member_role_changed',false),
    ('project_permission_delegation_granted',false),
    ('project_permission_delegation_revoked',false),
    ('project_recovery_point_created',false),
    ('project_recovery_point_restored',false),
    ('project_restored',false),
    ('project_retention_extended',false),
    ('project_settings_updated',false),
    ('task_artifact_binding_created',false),
    ('task_artifact_binding_strength_set',false),
    ('task_artifact_binding_update_available',false),
    ('task_artifact_binding_version_switched',false),
    ('task_assignment_accepted',true),
    ('task_assignment_rejected',false),
    ('task_assignment_released',false),
    ('task_canceled',false),
    ('task_change_approved',false),
    ('task_change_proposed',false),
    ('task_change_rejected',false),
    ('task_claimed',true),
    ('task_collaborator_accepted',true),
    ('task_collaborator_invited',false),
    ('task_collaborator_left',false),
    ('task_collaborator_rejected',false),
    ('task_collaborator_removed',false),
    ('task_created',true),
    ('task_deadline_reminder',false),
    ('task_dependencies_set',false),
    ('task_edited',false),
    ('task_empty_deleted',false),
    ('task_file_upload_finalized',false),
    ('task_file_upload_rejected',false),
    ('task_file_upload_reserved',false),
    ('task_file_version_final_marked',true),
    ('task_file_version_final_unmarked',false),
    ('task_file_version_rolled_back',false),
    ('task_file_versions_compared',false),
    ('task_first_submitted_late',false),
    ('task_help_requested',false),
    ('task_help_resolved',false),
    ('task_nudge_sent',false),
    ('task_primary_handoff_accepted',false),
    ('task_primary_handoff_canceled',false),
    ('task_primary_handoff_rejected',false),
    ('task_primary_handoff_requested',false),
    ('task_primary_unassigned',false),
    ('task_progress_updated',false),
    ('task_reminder_preferences_set',false),
    ('task_responsibility_abandoned',false),
    ('task_review_correction_opened',false),
    ('task_submission_approved',true),
    ('task_submission_changes_requested',true),
    ('task_submission_rejected',true),
    ('task_submitted_for_review',true),
    ('task_submitted_without_review',true),
    ('upstream_rework_approved',true),
    ('upstream_rework_rejected',false),
    ('upstream_rework_requested',true)
)
select is(
  private.analytics_is_effective_event_v1(event_type),
  included,
  'v1 event map: ' || event_type
)
from expected
order by event_type;

select is(
  private.analytics_is_effective_event_v1('future_unlisted_event'),
  false,
  'unknown future events are excluded by default'
);

insert into auth.users(id,email) values
 ('a8400000-0000-0000-0000-000000000001','analytics-leader@example.test'),
 ('a8400000-0000-0000-0000-000000000002','analytics-active@example.test'),
 ('a8400000-0000-0000-0000-000000000003','analytics-observer@example.test');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by
) values(
 'a8400000-0000-0000-0000-000000000010',
 'Analytics Task 1 fixture',
 now()+interval '30 days',
 'a8400000-0000-0000-0000-000000000001',
 'a8400000-0000-0000-0000-000000000001'
);

insert into public.project_members(project_id,user_id,role,member_state,is_observer) values
 ('a8400000-0000-0000-0000-000000000010','a8400000-0000-0000-0000-000000000001','leader','active',false),
 ('a8400000-0000-0000-0000-000000000010','a8400000-0000-0000-0000-000000000002','member','active',false),
 ('a8400000-0000-0000-0000-000000000010','a8400000-0000-0000-0000-000000000003','observer','active',true);

with included(event_type) as (
 values
    ('project_member_joined'),
    ('task_assignment_accepted'),
    ('task_claimed'),
    ('task_collaborator_accepted'),
    ('task_created'),
    ('task_file_version_final_marked'),
    ('task_submission_approved'),
    ('task_submission_changes_requested'),
    ('task_submission_rejected'),
    ('task_submitted_for_review'),
    ('task_submitted_without_review'),
    ('upstream_rework_approved'),
    ('upstream_rework_requested')
)
insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data
)
select
 'a8400000-0000-0000-0000-000000000010'::uuid,
 'a8400000-0000-0000-0000-000000000002'::uuid,
 event_type,
 'analytics_test',
 jsonb_build_object('analyticsCase','active','eventType',event_type)
from included;

with included(event_type) as (
 values
    ('project_member_joined'),
    ('task_assignment_accepted'),
    ('task_claimed'),
    ('task_collaborator_accepted'),
    ('task_created'),
    ('task_file_version_final_marked'),
    ('task_submission_approved'),
    ('task_submission_changes_requested'),
    ('task_submission_rejected'),
    ('task_submitted_for_review'),
    ('task_submitted_without_review'),
    ('upstream_rework_approved'),
    ('upstream_rework_requested')
)
insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data
)
select
 'a8400000-0000-0000-0000-000000000010'::uuid,
 'a8400000-0000-0000-0000-000000000003'::uuid,
 event_type,
 'analytics_test',
 jsonb_build_object('analyticsCase','observer','eventType',event_type)
from included;

with included(event_type) as (
 values
    ('project_member_joined'),
    ('task_assignment_accepted'),
    ('task_claimed'),
    ('task_collaborator_accepted'),
    ('task_created'),
    ('task_file_version_final_marked'),
    ('task_submission_approved'),
    ('task_submission_changes_requested'),
    ('task_submission_rejected'),
    ('task_submitted_for_review'),
    ('task_submitted_without_review'),
    ('upstream_rework_approved'),
    ('upstream_rework_requested')
)
insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data
)
select
 'a8400000-0000-0000-0000-000000000010'::uuid,
 null,
 event_type,
 'analytics_test',
 jsonb_build_object('analyticsCase','null_actor','eventType',event_type)
from included;

select is(
 a.actor_was_eligible,
 true,
 'active member eligible: ' || e.event_type
)
from public.business_events e
join private.analytics_event_actor_eligibility a
 on a.business_event_id=e.id
where e.event_data->>'analyticsCase'='active'
order by e.event_type;

select is(
 a.actor_was_eligible,
 false,
 'observer excluded: ' || e.event_type
)
from public.business_events e
join private.analytics_event_actor_eligibility a
 on a.business_event_id=e.id
where e.event_data->>'analyticsCase'='observer'
order by e.event_type;

select is(
 a.actor_was_eligible,
 false,
 'null actor excluded: ' || e.event_type
)
from public.business_events e
join private.analytics_event_actor_eligibility a
 on a.business_event_id=e.id
where e.event_data->>'analyticsCase'='null_actor'
order by e.event_type;

select is(
 (
   select count(*)::bigint
   from private.analytics_event_actor_eligibility a
   join public.business_events e on e.id=a.business_event_id
   where e.event_data->>'analyticsCase'='active'
     and a.actor_was_eligible
 ),
 13::bigint,
 'all thirteen active-member included events were snapshotted eligible'
);

update public.project_members
set role='observer', is_observer=true
where project_id='a8400000-0000-0000-0000-000000000010'
  and user_id='a8400000-0000-0000-0000-000000000002';

select is(
 (
   select count(*)::bigint
   from private.analytics_event_actor_eligibility a
   join public.business_events e on e.id=a.business_event_id
   where e.event_data->>'analyticsCase'='active'
     and a.actor_was_eligible
 ),
 13::bigint,
 'later observer mutation does not rewrite captured eligibility'
);

insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data
) values
 ('a8400000-0000-0000-0000-000000000010',null,'task_deadline_reminder','analytics_test','{"analyticsCase":"excluded_deadline"}'),
 ('a8400000-0000-0000-0000-000000000010','a8400000-0000-0000-0000-000000000002','task_artifact_binding_update_available','analytics_test','{"analyticsCase":"excluded_derived"}');

select is(
 (
   select count(*)::bigint
   from private.analytics_event_actor_eligibility a
   join public.business_events e on e.id=a.business_event_id
   where e.event_data->>'analyticsCase' in ('excluded_deadline','excluded_derived')
 ),
 0::bigint,
 'excluded events never create eligibility snapshots'
);

update public.project_members
set role='member', is_observer=false
where project_id='a8400000-0000-0000-0000-000000000010'
  and user_id='a8400000-0000-0000-0000-000000000002';

alter table public.business_events disable trigger business_event_snapshots_analytics_actor_v1;
insert into public.business_events(
 project_id,actor_id,event_type,entity_type,event_data
) values(
 'a8400000-0000-0000-0000-000000000010',
 'a8400000-0000-0000-0000-000000000002',
 'task_created',
 'analytics_test',
 '{"analyticsCase":"precoverage"}'
);
alter table public.business_events enable trigger business_event_snapshots_analytics_actor_v1;

update public.project_members
set role='observer', is_observer=true
where project_id='a8400000-0000-0000-0000-000000000010'
  and user_id='a8400000-0000-0000-0000-000000000002';

select is(
 (
   select count(*)::bigint
   from private.analytics_event_actor_eligibility a
   join public.business_events e on e.id=a.business_event_id
   where e.event_data->>'analyticsCase'='precoverage'
 ),
 0::bigint,
 'pre-coverage event is not guessed eligible from later membership state'
);

select is(
 (
   select count(*)::bigint
   from pg_constraint c
   join pg_attribute a
     on a.attrelid=c.conrelid
    and a.attnum=any(c.conkey)
   where c.contype='f'
     and c.conrelid='private.analytics_event_actor_eligibility'::regclass
     and a.attname='actor_user_id'
 ),
 0::bigint,
 'actor_user_id deliberately has no auth.users foreign key'
);


-- Task 2 semantic contracts: Activation, First Value, lifecycle, and WACP.
select has_function(
  'private','analytics_project_facts_v1',
  array['uuid','timestamp with time zone'],
  'project facts v1 exists'
);
select has_function(
  'private','analytics_user_activated_v1',
  array['uuid'],
  'user activation v1 exists'
);
select function_privs_are(
  'private','analytics_user_activated_v1',array['uuid'],
  'authenticated',array[]::text[],
  'browser clients cannot execute user activation semantics directly'
);
select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname='analytics_user_activated_v1'
      and pg_get_function_identity_arguments(p.oid)='p_user_id uuid'
  ),
  'user activation semantics are SECURITY DEFINER for explicit auth.users access'
);
select has_function(
  'private','analytics_wacp_v1',
  array['date'],
  'WACP v1 exists'
);
select has_function(
  'private','analytics_overview_v1',
  array['timestamp with time zone','timestamp with time zone','timestamp with time zone'],
  'overview v1 exists'
);

insert into auth.users(id,email,created_at) values
 ('a8410000-0000-0000-0000-000000000001','analytics-v1-a@example.test','2026-10-01 00:00:00+00'),
 ('a8410000-0000-0000-0000-000000000002','analytics-v1-b@example.test','2026-09-01 00:00:00+00'),
 ('a8410000-0000-0000-0000-000000000003','analytics-v1-c@example.test','2026-09-01 00:00:00+00'),
 ('a8410000-0000-0000-0000-000000000004','analytics-boundary@example.test','2026-10-01 00:00:00+00'),
 ('a8410000-0000-0000-0000-000000000005','analytics-partner@example.test','2026-09-01 00:00:00+00'),
 ('a8410000-0000-0000-0000-000000000006','analytics-late@example.test','2026-10-01 00:00:00+00');

insert into public.projects(
 id,name,deadline_at,leader_id,created_by,lifecycle_state,completed_at,archived_at
) values
 ('a8411000-0000-0000-0000-000000000100','Activation basic','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000200','User activation exact','2027-01-01','a8410000-0000-0000-0000-000000000004','a8410000-0000-0000-0000-000000000004','active',null,null),
 ('a8411000-0000-0000-0000-000000000201','User activation late','2027-01-01','a8410000-0000-0000-0000-000000000006','a8410000-0000-0000-0000-000000000006','active',null,null),
 ('a8411000-0000-0000-0000-000000000300','Lifecycle setup','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000301','Lifecycle quiet boundary','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000302','Lifecycle stalled boundary','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000303','Lifecycle collaborating','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000304','Lifecycle completed','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','completed','2026-10-19 00:00:00+00',null),
 ('a8411000-0000-0000-0000-000000000305','Lifecycle archived wins','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','completed','2026-10-17 00:00:00+00','2026-10-18 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000400','Reviewed first value','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000401','Reviewed mismatch','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000402','No review first value','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000403','No review mismatch','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000500','WACP positive','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null),
 ('a8411000-0000-0000-0000-000000000501','WACP one actor','2027-01-01','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000001','active',null,null);

insert into public.project_members(project_id,user_id,role,member_state,is_observer)
select p.id,u.user_id,u.role,'active',false
from (
 values
 ('a8411000-0000-0000-0000-000000000100'::uuid,'a8410000-0000-0000-0000-000000000001'::uuid,'leader'),
 ('a8411000-0000-0000-0000-000000000100'::uuid,'a8410000-0000-0000-0000-000000000002'::uuid,'member'),
 ('a8411000-0000-0000-0000-000000000200'::uuid,'a8410000-0000-0000-0000-000000000004'::uuid,'leader'),
 ('a8411000-0000-0000-0000-000000000200'::uuid,'a8410000-0000-0000-0000-000000000005'::uuid,'member'),
 ('a8411000-0000-0000-0000-000000000201'::uuid,'a8410000-0000-0000-0000-000000000006'::uuid,'leader'),
 ('a8411000-0000-0000-0000-000000000201'::uuid,'a8410000-0000-0000-0000-000000000005'::uuid,'member')
) as u(project_id,user_id,role)
join public.projects p on p.id=u.project_id;

insert into public.project_members(project_id,user_id,role,member_state,is_observer)
select p.id,
       case when x.n=1 then 'a8410000-0000-0000-0000-000000000001'::uuid
            else 'a8410000-0000-0000-0000-000000000002'::uuid end,
       case when x.n=1 then 'leader' else 'member' end,
       'active',false
from public.projects p
cross join (values (1),(2)) as x(n)
where p.id::text ~ '^a8411000-0000-0000-0000-000000000(30[0-3]|40[0-3]|50[0-1])$';

insert into public.business_events(project_id,actor_id,event_type,entity_type,event_data,created_at) values
 ('a8411000-0000-0000-0000-000000000100','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{"case":"activation-a1"}','2026-10-02 10:00:00+00'),
 ('a8411000-0000-0000-0000-000000000100','a8410000-0000-0000-0000-000000000001','task_claimed','analytics_test','{"case":"activation-a1-duplicate"}','2026-10-02 11:00:00+00'),
 ('a8411000-0000-0000-0000-000000000100','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{"case":"activation-a2"}','2026-10-02 12:00:00+00'),
 ('a8411000-0000-0000-0000-000000000200','a8410000-0000-0000-0000-000000000004','task_created','analytics_test','{"case":"user-exact-self"}','2026-10-01 01:00:00+00'),
 ('a8411000-0000-0000-0000-000000000200','a8410000-0000-0000-0000-000000000005','task_created','analytics_test','{"case":"user-exact-partner"}','2026-10-08 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000201','a8410000-0000-0000-0000-000000000005','task_created','analytics_test','{"case":"user-late-partner"}','2026-10-01 01:00:00+00'),
 ('a8411000-0000-0000-0000-000000000201','a8410000-0000-0000-0000-000000000006','task_created','analytics_test','{"case":"user-late-self"}','2026-10-08 00:00:01+00');

-- Rolling lifecycle fixtures evaluated at exactly 2026-10-20T00:00Z.
insert into public.business_events(project_id,actor_id,event_type,entity_type,event_data,created_at) values
 ('a8411000-0000-0000-0000-000000000301','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-10-12 23:59:00+00'),
 ('a8411000-0000-0000-0000-000000000301','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{}','2026-10-13 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000302','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-10-05 23:59:00+00'),
 ('a8411000-0000-0000-0000-000000000302','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{}','2026-10-06 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000303','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-10-12 23:59:00+00'),
 ('a8411000-0000-0000-0000-000000000303','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{}','2026-10-13 00:00:01+00');

insert into public.tasks(
 id,project_id,title,deadline_at,status,requires_review,completed_at,created_by,assignee_id
) values
 ('a8412000-0000-0000-0000-000000000400','a8411000-0000-0000-0000-000000000400','Reviewed valid','2026-12-01','completed',true,'2026-10-10 10:00:00+00','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000002'),
 ('a8412000-0000-0000-0000-000000000401','a8411000-0000-0000-0000-000000000401','Reviewed mismatch','2026-12-01','in_progress',true,null,'a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000002'),
 ('a8412000-0000-0000-0000-000000000402','a8411000-0000-0000-0000-000000000402','No review valid','2026-12-01','completed',false,'2026-10-11 10:00:00+00','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000002'),
 ('a8412000-0000-0000-0000-000000000403','a8411000-0000-0000-0000-000000000403','No review mismatch','2026-12-01','completed',true,'2026-10-12 10:00:00+00','a8410000-0000-0000-0000-000000000001','a8410000-0000-0000-0000-000000000002');

insert into public.business_events(project_id,actor_id,event_type,entity_type,event_data,created_at) values
 ('a8411000-0000-0000-0000-000000000400','a8410000-0000-0000-0000-000000000001','task_submission_approved','task_review_round','{"taskId":"a8412000-0000-0000-0000-000000000400"}','2026-10-10 10:00:00+00'),
 ('a8411000-0000-0000-0000-000000000401','a8410000-0000-0000-0000-000000000001','task_submission_approved','task_review_round','{"taskId":"a8412000-0000-0000-0000-000000000401"}','2026-10-10 11:00:00+00'),
 ('a8411000-0000-0000-0000-000000000402','a8410000-0000-0000-0000-000000000002','task_submitted_without_review','task_review_round','{"taskId":"a8412000-0000-0000-0000-000000000402"}','2026-10-11 10:00:00+00'),
 ('a8411000-0000-0000-0000-000000000403','a8410000-0000-0000-0000-000000000002','task_submitted_without_review','task_review_round','{"taskId":"a8412000-0000-0000-0000-000000000403"}','2026-10-12 10:00:00+00');

-- WACP week: Shanghai Monday 2026-11-02 00:00 == 2026-11-01 16:00Z.
insert into public.business_events(project_id,actor_id,event_type,entity_type,event_data,created_at) values
 ('a8411000-0000-0000-0000-000000000500','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-11-02 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000500','a8410000-0000-0000-0000-000000000001','task_claimed','analytics_test','{}','2026-11-02 01:00:00+00'),
 ('a8411000-0000-0000-0000-000000000500','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{}','2026-11-03 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000501','a8410000-0000-0000-0000-000000000001','task_created','analytics_test','{}','2026-11-02 00:00:00+00'),
 ('a8411000-0000-0000-0000-000000000501','a8410000-0000-0000-0000-000000000002','task_created','analytics_test','{}','2026-11-08 16:00:00+00');

select is(
 (private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000100','2026-10-20 00:00:00+00')->>'activatedAt')::timestamptz,
 '2026-10-02 12:00:00+00'::timestamptz,
 'project activation waits for the second distinct eligible actor'
);
select is(
 (private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000100','2026-10-20 00:00:00+00')->>'lastCollaborationAt')::timestamptz,
 '2026-10-02 12:00:00+00'::timestamptz,
 'duplicate events from one actor do not alter distinct-actor activation'
);

select ok(
 private.analytics_user_activated_v1('a8410000-0000-0000-0000-000000000004'),
 'user activation includes exactly 168 hours'
);
select ok(
 not private.analytics_user_activated_v1('a8410000-0000-0000-0000-000000000006'),
 'user activation excludes 168 hours plus one second'
);

select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000300','2026-10-20 00:00:00+00')->>'lifecycle',
 'setup',
 'project with no collaboration remains setup'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000303','2026-10-20 00:00:00+00')->>'lifecycle',
 'collaborating',
 'less than 168 hours inactive remains collaborating'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000301','2026-10-20 00:00:00+00')->>'lifecycle',
 'quiet',
 'exactly 168 hours inactive enters quiet'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000302','2026-10-20 00:00:00+00')->>'lifecycle',
 'stalled',
 'exactly 336 hours inactive enters stalled'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000304','2026-10-20 00:00:00+00')->>'lifecycle',
 'completed',
 'business completion overrides setup'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000305','2026-10-20 00:00:00+00')->>'lifecycle',
 'archived',
 'archive terminal state has precedence over completion'
);

select is(
 (private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000400','2026-10-20 00:00:00+00')->>'firstValueAt')::timestamptz,
 '2026-10-10 10:00:00+00'::timestamptz,
 'reviewed First Value requires approval plus completed task'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000401','2026-10-20 00:00:00+00')->>'firstValueAt',
 null,
 'approval event without completed business state is not First Value'
);
select is(
 (private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000402','2026-10-20 00:00:00+00')->>'firstValueAt')::timestamptz,
 '2026-10-11 10:00:00+00'::timestamptz,
 'no-review First Value requires atomic completed submission'
);
select is(
 private.analytics_project_facts_v1('a8411000-0000-0000-0000-000000000403','2026-10-20 00:00:00+00')->>'firstValueAt',
 null,
 'no-review event cannot complete a requires-review task'
);

select is(
 private.analytics_wacp_v1('2026-11-02'::date),
 1,
 'WACP deduplicates actors and excludes the next-week boundary'
);
select * from finish();
rollback;