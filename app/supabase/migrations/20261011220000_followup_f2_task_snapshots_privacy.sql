-- F2: Privacy-safe read surfaces for identity-bearing task, invite and handoff snapshots.
-- Preserve base-table evidence; prevent browser bypass of masked columns.

create view public.project_join_requests_visible with(security_barrier=true) as
select t.id,
       t.invitation_id,
       t.project_id,
       t.user_id,
       t.state,
       t.version,
       t.reviewed_by,
       t.reviewed_at,
       t.created_at,
       t.updated_at,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.user_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.display_name_snapshot end as display_name_snapshot
from public.project_join_requests t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and (t.user_id=auth.uid() or exists(select 1 from public.project_members m where m.project_id=t.project_id and m.user_id=auth.uid() and m.role='leader' and m.member_state='active'));
revoke all on public.project_join_requests_visible from public,anon,authenticated,service_role;
grant select on public.project_join_requests_visible to authenticated;
revoke select on public.project_join_requests from authenticated;
grant select(id,invitation_id,project_id,user_id,state,version,reviewed_by,reviewed_at,created_at,updated_at)
 on public.project_join_requests to authenticated;
comment on view public.project_join_requests_visible is 'Authorization-scoped historical collaboration read with per-member identity masking.';

create view public.task_collaborators_visible with(security_barrier=true) as
select t.id,
       t.project_id,
       t.task_id,
       t.user_id,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.user_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.user_name_snapshot end as user_name_snapshot,
       t.state,
       t.invited_by,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.invited_by and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.invited_by_name_snapshot end as invited_by_name_snapshot,
       t.responded_at,
       t.removed_at,
       t.version,
       t.created_at,
       t.updated_at
from public.task_collaborators t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);
revoke all on public.task_collaborators_visible from public,anon,authenticated,service_role;
grant select on public.task_collaborators_visible to authenticated;
revoke select on public.task_collaborators from authenticated;
grant select(id,project_id,task_id,user_id,state,invited_by,responded_at,removed_at,version,created_at,updated_at)
 on public.task_collaborators to authenticated;
comment on view public.task_collaborators_visible is 'Authorization-scoped historical collaboration read with per-member identity masking.';

create view public.task_primary_handoffs_visible with(security_barrier=true) as
select t.id,
       t.project_id,
       t.task_id,
       t.from_user_id,
       t.to_user_id,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.from_user_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.from_user_name_snapshot end as from_user_name_snapshot,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.to_user_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.to_user_name_snapshot end as to_user_name_snapshot,
       t.state,
       t.created_by,
       t.responded_at,
       t.canceled_at,
       t.version,
       t.created_at,
       t.updated_at
from public.task_primary_handoffs t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);
revoke all on public.task_primary_handoffs_visible from public,anon,authenticated,service_role;
grant select on public.task_primary_handoffs_visible to authenticated;
revoke select on public.task_primary_handoffs from authenticated;
grant select(id,project_id,task_id,from_user_id,to_user_id,state,created_by,responded_at,canceled_at,version,created_at,updated_at)
 on public.task_primary_handoffs to authenticated;
comment on view public.task_primary_handoffs_visible is 'Authorization-scoped historical collaboration read with per-member identity masking.';

create view public.task_change_proposals_visible with(security_barrier=true) as
select t.id,
       t.project_id,
       t.task_id,
       t.proposed_by,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.proposed_by and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.proposer_name_snapshot end as proposer_name_snapshot,
       t.state,
       t.old_deadline_at,
       t.new_deadline_at,
       t.old_weight,
       t.new_weight,
       t.base_task_version,
       t.required_confirmer_id,
       case when exists(select 1 from public.account_lifecycle_requests d where d.user_id=t.required_confirmer_id and d.state in ('pending','blocked','redacted')) then '已注销成员'::text else t.required_confirmer_name_snapshot end as required_confirmer_name_snapshot,
       t.decided_at,
       t.decided_by,
       t.decision_reason,
       t.version,
       t.created_at,
       t.updated_at,
       t.old_required_submission_file_type,
       t.new_required_submission_file_type
from public.task_change_proposals t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);
revoke all on public.task_change_proposals_visible from public,anon,authenticated,service_role;
grant select on public.task_change_proposals_visible to authenticated;
revoke select on public.task_change_proposals from authenticated;
grant select(id,project_id,task_id,proposed_by,state,old_deadline_at,new_deadline_at,old_weight,new_weight,base_task_version,required_confirmer_id,decided_at,decided_by,decision_reason,version,created_at,updated_at,old_required_submission_file_type,new_required_submission_file_type)
 on public.task_change_proposals to authenticated;
comment on view public.task_change_proposals_visible is 'Authorization-scoped historical collaboration read with per-member identity masking.';
