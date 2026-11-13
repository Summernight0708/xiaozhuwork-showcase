-- Workstream C: independently owned append-only authority facts.
create table public.task_responsibility_epochs (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 task_id uuid not null,
 responsible_user_id uuid references auth.users(id) on delete set null,
 accepted_at timestamptz not null,
 effective_start_at timestamptz,
 effective_deadline_at timestamptz not null,
 free_abandon_until timestamptz,
 deadline_revision integer not null,
 blocked_exempt boolean not null,
 exemption_reason text,
 weight_snapshot smallint,
 expected_share_bps_snapshot integer,
 shares_confirmed boolean not null default false,
 accepted_expected_contribution numeric(12,4),
 project_contribution_mode text not null,
 auto_penalty_enabled_snapshot boolean not null,
 trigger_source text not null,
 closed_at timestamptz,
 closure_reason text,
 created_at timestamptz not null default now(),
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade,
 constraint c_epoch_share check(expected_share_bps_snapshot between 1 and 10000 or expected_share_bps_snapshot is null),
 constraint c_epoch_window check(free_abandon_until is null or
   (effective_start_at is not null and effective_start_at<=free_abandon_until and free_abandon_until<=effective_deadline_at)),
 constraint c_epoch_closed check((closed_at is null and closure_reason is null) or (closed_at is not null and closure_reason is not null))
);
create unique index c_epoch_one_open on public.task_responsibility_epochs(task_id) where closed_at is null;

create table public.task_first_submission_facts (
 task_id uuid primary key,
 project_id uuid not null,
 responsibility_epoch_id uuid references public.task_responsibility_epochs(id),
 first_submitted_at timestamptz not null,
 deadline_snapshot timestamptz not null,
 effective_start_snapshot timestamptz,
 responsible_user_id uuid references auth.users(id) on delete set null,
 blocked_exempt boolean not null,
 eligible_late boolean not null,
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade
);

create table public.file_version_withdrawals (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null,
 task_id uuid not null,
 file_id uuid not null,
 file_version_id uuid not null unique,
 original_path text not null,
 original_path_sha256 text not null,
 quarantine_path text not null unique,
 reason text not null,
 requested_by uuid references auth.users(id) on delete set null,
 requested_at timestamptz not null default now(),
 revoked_at timestamptz,
 state text not null default 'pending_quarantine',
 version integer not null default 1,
 request_command_id uuid not null references public.command_requests(id),
 request_id uuid not null,
 foreign key(project_id,task_id,file_version_id) references public.task_file_versions(project_id,task_id,id),
 constraint c_withdrawal_state check(state in ('pending_quarantine','withdrawn')),
 constraint c_withdrawal_completion check((state='pending_quarantine' and revoked_at is null) or(state='withdrawn' and revoked_at is not null)),
 constraint c_withdrawal_reason check(char_length(btrim(reason)) between 1 and 2000)
);
create index c_withdrawal_project on public.file_version_withdrawals(project_id,task_id);
create unique index c_event_occurrence_unique on public.business_events((event_data->>'occurrenceKey'))
 where event_type in ('task_canceled','task_responsibility_abandoned','task_first_submitted_late','file_version_withdrawn')
 and event_data ? 'occurrenceKey';

alter table public.task_responsibility_epochs enable row level security;
alter table public.task_first_submission_facts enable row level security;
alter table public.file_version_withdrawals enable row level security;
revoke all on public.task_responsibility_epochs,public.task_first_submission_facts,public.file_version_withdrawals from public,anon,authenticated,service_role;
grant select on public.task_responsibility_epochs,public.task_first_submission_facts to authenticated;
grant select(id,project_id,task_id,file_id,file_version_id,reason,requested_by,requested_at,revoked_at,state,version)
 on public.file_version_withdrawals to authenticated;
create policy c_epoch_read on public.task_responsibility_epochs for select to authenticated
 using(private.is_active_member(project_id,(select auth.uid())));
create policy c_first_read on public.task_first_submission_facts for select to authenticated
 using(private.is_active_member(project_id,(select auth.uid())));
create policy c_withdraw_read on public.file_version_withdrawals for select to authenticated
 using(private.is_active_member(project_id,(select auth.uid())));

-- Call from existing authoritative acceptance/handoff transaction after task write (G only).
create function private.followup_open_responsibility_epoch(
 p_project_id uuid,p_task_id uuid,p_user_id uuid,p_accepted_at timestamptz,p_source text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 t public.tasks%rowtype;
 p public.projects%rowtype;
 v_unfinished boolean;
 v_last timestamptz;
 v_start timestamptz;
 v_free timestamptz;
 v_id uuid;
begin
 select * into t from public.tasks where project_id=p_project_id and id=p_task_id;
 select * into p from public.projects where id=p_project_id;
 if t.id is null or t.assignee_id is distinct from p_user_id or t.accepted_at is distinct from p_accepted_at then
  raise exception 'C epoch requires the accepted current primary assignment';
 end if;
 select bool_or(u.status<>'completed'),max(u.completed_at) into v_unfinished,v_last
 from public.task_dependencies d join public.tasks u on u.id=d.upstream_task_id
 where d.project_id=p_project_id and d.downstream_task_id=p_task_id;
 v_unfinished:=coalesce(v_unfinished,false);
 if not v_unfinished then
  v_start:=greatest(p_accepted_at,coalesce(v_last,p_accepted_at));
  if t.deadline_at>v_start then
   v_free:=v_start + (floor(extract(epoch from(t.deadline_at-v_start))::numeric*0.10)::bigint*interval '1 second');
  end if;
 end if;
 -- Repeated hook invocation for the same accepted revision is idempotent.
 select id into v_id from public.task_responsibility_epochs
 where task_id=p_task_id and closed_at is null
 and responsible_user_id is not distinct from p_user_id
 and accepted_at=p_accepted_at and deadline_revision=t.version
 and effective_start_at is not distinct from v_start
 and effective_deadline_at=t.deadline_at
 and blocked_exempt=(v_unfinished or v_free is null);
 if v_id is not null then return v_id; end if;
 update public.task_responsibility_epochs set closed_at=now(),closure_reason='superseded'
 where task_id=p_task_id and closed_at is null;
 insert into public.task_responsibility_epochs(project_id,task_id,responsible_user_id,accepted_at,
 effective_start_at,effective_deadline_at,free_abandon_until,deadline_revision,blocked_exempt,
 exemption_reason,weight_snapshot,project_contribution_mode,auto_penalty_enabled_snapshot,trigger_source)
 values(p_project_id,p_task_id,p_user_id,p_accepted_at,v_start,t.deadline_at,v_free,t.version,
 v_unfinished or v_free is null,case when v_unfinished then 'upstream_incomplete'
 when v_free is null then 'invalid_interval' end,t.weight,p.contribution_mode,p.auto_penalty_enabled,p_source)
 returning id into v_id;
 return v_id;
end;
$$;

-- Call only on NULL -> non-NULL first_submitted_at in the existing submit RPC.
-- G emits task_submitted_for_review event_seq=1, then this helper emits seq=2.
create function private.followup_record_first_submission(
 p_project_id uuid,p_task_id uuid,p_actor_id uuid,p_command_id uuid,
 p_request_id uuid,p_submitted_at timestamptz,p_aggregate_version integer
) returns void language plpgsql security definer set search_path='' as $$
declare
 t public.tasks%rowtype;
 e public.task_responsibility_epochs%rowtype;
 v_late boolean;
 v_inserted boolean;
begin
 select * into t from public.tasks where project_id=p_project_id and id=p_task_id;
 if t.id is null or t.first_submitted_at is distinct from p_submitted_at
 or t.version<>p_aggregate_version or t.status<>'awaiting_review' then
  raise exception 'C first submission snapshot mismatch';
 end if;
 select * into e from public.task_responsibility_epochs where project_id=p_project_id
 and task_id=p_task_id and responsible_user_id=t.assignee_id and closed_at is null;
 v_late:=coalesce(e.id is not null and not e.blocked_exempt and e.effective_start_at is not null
 and e.effective_deadline_at>e.effective_start_at and p_submitted_at>e.effective_deadline_at,false);
 insert into public.task_first_submission_facts(task_id,project_id,responsibility_epoch_id,
 first_submitted_at,deadline_snapshot,effective_start_snapshot,responsible_user_id,blocked_exempt,eligible_late)
 values(p_task_id,p_project_id,e.id,p_submitted_at,coalesce(e.effective_deadline_at,t.deadline_at),
 e.effective_start_at,t.assignee_id,coalesce(e.blocked_exempt,true),v_late)
 on conflict(task_id) do nothing returning true into v_inserted;
 if coalesce(v_inserted,false) and v_late then
  perform private.emit_event(p_command_id,2,p_project_id,p_actor_id,'task_first_submitted_late','task',
   p_task_id,p_request_id,jsonb_build_object(
   'schemaVersion',1,'policyVersion',1,'occurrenceKey','task:'||p_task_id||':first_late',
   'occurredAt',p_submitted_at,'aggregateVersion',p_aggregate_version,
   'taskId',p_task_id,'responsibleUserId',e.responsible_user_id,
   'responsibilityEpochId',e.id,'acceptedAt',e.accepted_at,'effectiveStartAt',e.effective_start_at,
   'effectiveDeadlineAt',e.effective_deadline_at,'freeAbandonUntil',e.free_abandon_until,
   'firstSubmittedAt',p_submitted_at,'blockedExempt',e.blocked_exempt,
   'exemptionReason',e.exemption_reason,'weightSnapshot',e.weight_snapshot,
   'expectedShareBpsSnapshot',e.expected_share_bps_snapshot,
   'acceptedExpectedContribution',e.accepted_expected_contribution::text,
   'projectContributionMode',e.project_contribution_mode,
   'autoPenaltyEnabledSnapshot',e.auto_penalty_enabled_snapshot,'triggerSource','first_submission'));
 end if;
end;
$$;

-- Management cancellation preserves all business facts and must not emit a penalty.
create function public.cmd_cancel_task(
 p_project_id uuid,p_task_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid:=auth.uid(); c record; replay jsonb; r jsonb;
 t public.tasks%rowtype; p public.projects%rowtype;
 reason text:=btrim(coalesce(p_reason,'')); prior_status text;
begin
 if a is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null or p_project_id is null or p_task_id is null
 or length(reason) not between 1 and 2000 then return private.failure(p_request_id,'VALIDATION_FAILED'); end if;
 if not exists(select 1 from public.projects where id=p_project_id)
 then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into c from private.claim_command(a,'cmd_cancel_task',p_request_id,
 private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,
 'reason',reason,'expectedVersion',p_expected_version)),null,p_project_id);
 replay:=private.replay_or_reuse(p_request_id,c.prior_result,c.payload_matches);
 if replay is not null then return replay; end if;
 r:=private.reject_unless_authorized(private.is_active_non_observer_member(p_project_id,a) and
 exists(select 1 from public.tasks tt where tt.project_id=p_project_id and tt.id=p_task_id and
 (private.is_active_leader(p_project_id,a) or tt.created_by=a)),
 p_request_id,c.command_id,c.prior_result,c.payload_matches);
 if r is not null then return r; end if;
 select * into p from public.projects where id=p_project_id for update;
 select * into t from public.tasks where id=p_task_id and project_id=p_project_id for update;
 if p.archived_at is not null or p.lifecycle_state<>'active' then
  r:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif t.id is null then r:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif t.version is distinct from p_expected_version then
  r:=private.failure(p_request_id,'STALE_VERSION',null,t.version);
 elsif t.status in ('canceled','completed','awaiting_review') then
  r:=private.failure(p_request_id,'INVALID_TRANSITION');
 else
  prior_status:=t.status;
  update public.tasks set status='canceled',cancel_reason=reason,canceled_at=now(),
  blocked_reason=null,version=version+1,updated_at=now() where id=p_task_id returning * into t;
  update public.task_responsibility_epochs set closed_at=now(),closure_reason='manager_cancel'
   where task_id=p_task_id and closed_at is null;
  perform private.emit_event(c.command_id,1,p_project_id,a,'task_canceled','task',p_task_id,p_request_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,
   'occurrenceKey','task:'||p_task_id||':cancel','occurredAt',t.canceled_at,
   'aggregateVersion',t.version,'taskId',p_task_id,'responsibleUserId',t.assignee_id,
   'cancelReason',reason,'canceledBy',a,'previousStatus',prior_status,'triggerSource','manager_cancel'));
  r:=jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',p_task_id,'status','canceled'),
   'requestId',p_request_id,'replayed',false,'aggregateType','task','aggregateId',p_task_id,'aggregateVersion',t.version);
  return private.complete_command(c.command_id,r,'task',p_task_id,t.version);
 end if;
 return private.complete_command(c.command_id,r);
end;
$$;

-- Only the accepted current primary may voluntarily abandon this responsibility epoch.
create function public.cmd_abandon_task_responsibility(
 p_project_id uuid,p_task_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid:=auth.uid(); c record; replay jsonb; r jsonb;
 t public.tasks%rowtype; p public.projects%rowtype; e public.task_responsibility_epochs%rowtype;
 reason text:=btrim(coalesce(p_reason,'')); at_time timestamptz; late boolean;
begin
 if a is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null or p_project_id is null or p_task_id is null
 or length(reason) not between 1 and 2000 then return private.failure(p_request_id,'VALIDATION_FAILED'); end if;
 if not exists(select 1 from public.projects where id=p_project_id)
 then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into c from private.claim_command(a,'cmd_abandon_task_responsibility',p_request_id,
 private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,
 'reason',reason,'expectedVersion',p_expected_version)),null,p_project_id);
 replay:=private.replay_or_reuse(p_request_id,c.prior_result,c.payload_matches);
 if replay is not null then return replay; end if;
 r:=private.reject_unless_authorized(private.is_active_non_observer_member(p_project_id,a) and
 exists(select 1 from public.tasks tt where tt.project_id=p_project_id and tt.id=p_task_id
 and tt.assignee_id=a and tt.accepted_at is not null and tt.assignment_state='assigned'),
 p_request_id,c.command_id,c.prior_result,c.payload_matches);
 if r is not null then return r; end if;
 select * into p from public.projects where id=p_project_id for update;
 select * into t from public.tasks where project_id=p_project_id and id=p_task_id for update;
 select * into e from public.task_responsibility_epochs where task_id=p_task_id
 and project_id=p_project_id and responsible_user_id=a and closed_at is null for update;
 if p.archived_at is not null or p.lifecycle_state<>'active' then
  r:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif t.version is distinct from p_expected_version then
  r:=private.failure(p_request_id,'STALE_VERSION',null,t.version);
 elsif t.status not in ('not_started','in_progress','blocked') or t.first_submitted_at is not null
 or exists(select 1 from public.task_review_rounds where task_id=p_task_id) then
  r:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif e.id is null then
  r:=private.failure(p_request_id,'INVALID_TRANSITION',null,t.version,
    jsonb_build_object('reason','epoch_missing_requires_g_hook'));
 else
  at_time:=now();
  late:=not e.blocked_exempt and e.free_abandon_until is not null
    and e.effective_start_at is not null and e.effective_deadline_at>e.effective_start_at
    and at_time>e.free_abandon_until;
  update public.task_responsibility_epochs set closed_at=at_time,closure_reason='abandoned' where id=e.id;
  update public.tasks set assignee_id=null,accepted_at=null,assignment_state='claimable',
   is_direct_assignment=false,status='not_started',progress_text=null,blocked_reason=null,
   version=version+1,updated_at=now() where id=p_task_id returning * into t;
  perform private.emit_event(c.command_id,1,p_project_id,a,
   'task_responsibility_abandoned','task',p_task_id,p_request_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,
   'occurrenceKey','responsibility:'||e.id||':abandon','occurredAt',at_time,
   'aggregateVersion',t.version,'taskId',p_task_id,'responsibleUserId',a,
   'responsibilityEpochId',e.id,'acceptedAt',e.accepted_at,
   'effectiveStartAt',e.effective_start_at,'effectiveDeadlineAt',e.effective_deadline_at,
   'freeAbandonUntil',e.free_abandon_until,'firstSubmittedAt',null,
   'blockedExempt',e.blocked_exempt,'exemptionReason',e.exemption_reason,
   'weightSnapshot',e.weight_snapshot,'expectedShareBpsSnapshot',e.expected_share_bps_snapshot,
   'acceptedExpectedContribution',e.accepted_expected_contribution::text,
   'projectContributionMode',e.project_contribution_mode,
   'autoPenaltyEnabledSnapshot',e.auto_penalty_enabled_snapshot,
   'penaltyCandidate',late,'abandonReason',reason,'triggerSource','self_abandon'));
  r:=jsonb_build_object('ok',true,
   'data',jsonb_build_object('taskId',p_task_id,'responsibilityEpochId',e.id,
    'freeWindow',not late,'assignmentState','claimable'),
   'requestId',p_request_id,'replayed',false,'aggregateType','task',
   'aggregateId',p_task_id,'aggregateVersion',t.version);
  return private.complete_command(c.command_id,r,'task',p_task_id,t.version);
 end if;
 return private.complete_command(c.command_id,r);
end;
$$;

-- Deny deletion when any task-dependent rows or business activity exist.
create function public.cmd_delete_empty_task(
 p_project_id uuid,p_task_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid:=auth.uid(); c record; replay jsonb; r jsonb; t public.tasks%rowtype; p public.projects%rowtype;
begin
 if a is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null or p_project_id is null or p_task_id is null
 then return private.failure(p_request_id,'VALIDATION_FAILED'); end if;
 if not exists(select 1 from public.projects where id=p_project_id)
 then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into c from private.claim_command(a,'cmd_delete_empty_task',p_request_id,
 private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,'expectedVersion',p_expected_version)),
 null,p_project_id);
 replay:=private.replay_or_reuse(p_request_id,c.prior_result,c.payload_matches);
 if replay is not null then return replay; end if;
 r:=private.reject_unless_authorized(private.is_active_non_observer_member(p_project_id,a) and
 exists(select 1 from public.tasks tt where tt.project_id=p_project_id and tt.id=p_task_id
 and (private.is_active_leader(p_project_id,a) or tt.created_by=a)),
 p_request_id,c.command_id,c.prior_result,c.payload_matches);
 if r is not null then return r; end if;
 select * into p from public.projects where id=p_project_id for update;
 select * into t from public.tasks where project_id=p_project_id and id=p_task_id for update;
 if p.archived_at is not null or p.lifecycle_state<>'active' then
  r:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif t.version is distinct from p_expected_version then
  r:=private.failure(p_request_id,'STALE_VERSION',null,t.version);
 elsif t.version<>1 or t.status<>'not_started' or t.assignee_id is not null
 or t.accepted_at is not null or t.first_submitted_at is not null
 or t.progress_text is not null or t.canceled_at is not null
 or exists(select 1 from public.task_dependencies d where d.upstream_task_id=p_task_id or d.downstream_task_id=p_task_id)
 or exists(select 1 from public.task_files where task_id=p_task_id)
 or exists(select 1 from public.file_upload_reservations where task_id=p_task_id)
 or exists(select 1 from public.task_review_rounds where task_id=p_task_id)
 or exists(select 1 from public.task_collaborators where task_id=p_task_id)
 or exists(select 1 from public.task_assignment_offers where task_id=p_task_id)
 or exists(select 1 from public.task_primary_handoffs where task_id=p_task_id)
 or exists(select 1 from public.task_change_proposals where task_id=p_task_id)
 or exists(select 1 from public.task_artifact_bindings where downstream_task_id=p_task_id or upstream_task_id=p_task_id)
 or exists(select 1 from public.task_responsibility_epochs where task_id=p_task_id)
 or exists(select 1 from public.notifications where project_id=p_project_id and entity_id=p_task_id)
 or exists(select 1 from public.business_events where project_id=p_project_id
 and event_type<>'task_created' and (entity_id=p_task_id or event_data->>'taskId'=p_task_id::text))
 then r:=private.failure(p_request_id,'INVALID_TRANSITION',null,t.version,
 jsonb_build_object('reason','task_has_business_history'));
 else
  delete from public.tasks where id=p_task_id;
  perform private.emit_event(c.command_id,1,p_project_id,a,'task_empty_deleted','task',
   p_task_id,p_request_id,jsonb_build_object('schemaVersion',1,'policyVersion',1,
   'occurrenceKey','task:'||p_task_id||':empty_delete',
   'occurredAt',now(),'aggregateVersion',t.version,'responsibleUserId',null,'taskId',p_task_id));
  r:=jsonb_build_object('ok',true,'data',jsonb_build_object('taskId',p_task_id,'deleted',true),
   'requestId',p_request_id,'replayed',false,'aggregateType','task',
   'aggregateId',p_task_id,'aggregateVersion',t.version);
  return private.complete_command(c.command_id,r,'task',p_task_id,t.version);
 end if;
 return private.complete_command(c.command_id,r);
end;
$$;

-- Phase 1 creates a deny-listed, pending intent. It does NOT claim successful revocation.
-- G must immediately block new signing, then move the original Storage object.
create function public.cmd_withdraw_file_version(
 p_project_id uuid,p_file_version_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid:=auth.uid(); c record; replay jsonb; r jsonb;
 p public.projects%rowtype; fv public.task_file_versions%rowtype;
 f public.task_files%rowtype; w public.file_version_withdrawals%rowtype;
 reason text:=btrim(coalesce(p_reason,''));
begin
 if a is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null or p_project_id is null or p_file_version_id is null
 or length(reason) not between 1 and 2000 then return private.failure(p_request_id,'VALIDATION_FAILED'); end if;
 if not exists(select 1 from public.projects where id=p_project_id)
 then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into c from private.claim_command(a,'cmd_withdraw_file_version',p_request_id,
 private.payload_hash(jsonb_build_object('projectId',p_project_id,'fileVersionId',p_file_version_id,
 'reason',reason,'expectedVersion',p_expected_version)),null,p_project_id);
 replay:=private.replay_or_reuse(p_request_id,c.prior_result,c.payload_matches);
 if replay is not null then return replay; end if;
 r:=private.reject_unless_authorized(private.is_active_non_observer_member(p_project_id,a) and
 exists(select 1 from public.task_file_versions v where v.id=p_file_version_id
 and v.project_id=p_project_id and (v.uploaded_by=a or private.is_active_leader(p_project_id,a))),
 p_request_id,c.command_id,c.prior_result,c.payload_matches);
 if r is not null then return r; end if;
 select * into p from public.projects where id=p_project_id for update;
 select * into fv from public.task_file_versions where id=p_file_version_id and project_id=p_project_id;
 -- Respect shared lock order: project -> task -> logical file -> withdrawal.
 perform 1 from public.tasks where id=fv.task_id and project_id=p_project_id for update;
 select * into f from public.task_files where id=fv.file_id for update;
 if p.archived_at is not null or p.lifecycle_state<>'active' then
  r:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif fv.id is null or f.id is null then r:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif f.version is distinct from p_expected_version then
  r:=private.failure(p_request_id,'STALE_VERSION',null,f.version);
 elsif exists(select 1 from public.file_version_withdrawals where file_version_id=p_file_version_id) then
  r:=private.failure(p_request_id,'INVALID_TRANSITION',null,f.version,
   jsonb_build_object('reason','withdrawal_already_requested'));
 else
  insert into public.file_version_withdrawals(project_id,task_id,file_id,file_version_id,
  original_path,original_path_sha256,quarantine_path,reason,requested_by,request_command_id,request_id)
  values(p_project_id,fv.task_id,fv.file_id,fv.id,fv.object_path,
   encode(extensions.digest(convert_to(fv.object_path,'utf8'),'sha256'),'hex'),
   'quarantine/withdrawal/'||gen_random_uuid()::text,reason,a,c.command_id,p_request_id)
  returning * into w;
  r:=jsonb_build_object('ok',true,'data',jsonb_build_object('withdrawalId',w.id,
   'fileVersionId',p_file_version_id,'state','pending_quarantine','revoked',false),
   'requestId',p_request_id,'replayed',false,'aggregateType','file_version_withdrawal',
   'aggregateId',w.id,'aggregateVersion',w.version);
  return private.complete_command(c.command_id,r,'file_version_withdrawal',w.id,w.version);
 end if;
 return private.complete_command(c.command_id,r);
end;
$$;

-- Phase 2: only service_role can attest the actual Storage move.
-- No trusted boolean flag: DB verifies original absence and quarantine presence.
create function public.cmd_complete_file_version_withdrawal_service(
 p_withdrawal_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.file_version_withdrawals%rowtype;
begin
 if auth.role() is distinct from 'service_role' then
  return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 select * into w from public.file_version_withdrawals where id=p_withdrawal_id for update;
 if not found then return private.failure(null,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 if w.state='withdrawn' then
  return jsonb_build_object('ok',true,'replayed',true,'state','withdrawn','withdrawalId',w.id);
 end if;
 if exists(select 1 from storage.objects where bucket_id='teamup-files' and name=w.original_path)
 or not exists(select 1 from storage.objects where bucket_id='teamup-files' and name=w.quarantine_path) then
  return private.failure(null,'INVALID_TRANSITION',null,null,
   jsonb_build_object('reason','storage_quarantine_not_verified'));
 end if;
 update public.file_version_withdrawals set state='withdrawn',revoked_at=now(),version=version+1
 where id=w.id returning * into w;
 perform private.emit_event(w.request_command_id,1,w.project_id,w.requested_by,
  'file_version_withdrawn','task_file_version',w.file_version_id,w.request_id,
  jsonb_build_object('schemaVersion',1,'policyVersion',1,
  'occurrenceKey','file_version:'||w.file_version_id||':withdrawn',
  'occurredAt',w.revoked_at,'aggregateVersion',w.version,
  'responsibleUserId',null,'fileId',w.file_id,'fileVersionId',w.file_version_id,
  'originalObjectPathHash',w.original_path_sha256,'withdrawnBy',w.requested_by,
  'withdrawalReason',w.reason,'triggerSource','storage_quarantine_verified'));
 return jsonb_build_object('ok',true,'replayed',false,'state','withdrawn','withdrawalId',w.id);
end;
$$;

revoke all on function private.followup_open_responsibility_epoch(uuid,uuid,uuid,timestamptz,text) from public,anon,authenticated,service_role;
revoke all on function private.followup_record_first_submission(uuid,uuid,uuid,uuid,uuid,timestamptz,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_cancel_task(uuid,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_abandon_task_responsibility(uuid,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_delete_empty_task(uuid,uuid,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_withdraw_file_version(uuid,uuid,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.cmd_complete_file_version_withdrawal_service(uuid) from public,anon,authenticated,service_role;
grant execute on function public.cmd_cancel_task(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_abandon_task_responsibility(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_delete_empty_task(uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_withdraw_file_version(uuid,uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_complete_file_version_withdrawal_service(uuid) to service_role;
