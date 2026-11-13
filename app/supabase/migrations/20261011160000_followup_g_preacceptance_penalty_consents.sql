-- G: explicit *pre-acceptance* share consent and opt-in policy gating.
-- No retrospective penalties or inferred 100% allocations.
create table public.project_penalty_policy_consents (
 project_id uuid not null references public.projects(id) on delete cascade,
 member_user_id uuid not null references auth.users(id) on delete restrict,
 policy_version integer not null default 1 check(policy_version=1),
 consented_at timestamptz not null default transaction_timestamp(),
 request_id uuid not null unique,
 primary key(project_id,member_user_id,policy_version)
);
create table public.task_expected_share_consents (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 task_id uuid not null,
 member_user_id uuid not null references auth.users(id) on delete restrict,
 expected_share_bps integer not null check(expected_share_bps between 1 and 10000),
 task_version integer not null check(task_version>0),
 weight_snapshot smallint not null check(weight_snapshot between 1 and 5),
 deadline_snapshot timestamptz not null,
 consented_at timestamptz not null default transaction_timestamp(),
 request_id uuid not null unique,
 unique(task_id,member_user_id,task_version),
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade
);
create index g_expected_consents_by_task on public.task_expected_share_consents(task_id,task_version);
alter table public.project_penalty_policy_consents enable row level security;
alter table public.task_expected_share_consents enable row level security;
revoke all on public.project_penalty_policy_consents,public.task_expected_share_consents from public,anon,authenticated,service_role;
grant select on public.project_penalty_policy_consents,public.task_expected_share_consents to authenticated;
create policy g_policy_consent_member_read on public.project_penalty_policy_consents
 for select to authenticated using(public.is_active_project_member(project_id));
create policy g_expected_share_member_read on public.task_expected_share_consents
 for select to authenticated using(public.is_active_project_member(project_id));
create trigger g_archived_write_reject before insert or update or delete on public.project_penalty_policy_consents
 for each row execute function private.followup_reject_archived_project_write();
create trigger g_archived_write_reject before insert or update or delete on public.task_expected_share_consents
 for each row execute function private.followup_reject_archived_project_write();

create function private.g_consent_append_only() returns trigger language plpgsql
 set search_path='' as $$ begin
 raise exception using errcode='55000',message='CONSENT_IMMUTABLE'; end; $$;
revoke all on function private.g_consent_append_only() from public,anon,authenticated,service_role;
create trigger g_project_policy_consent_immutable before update or delete on public.project_penalty_policy_consents
 for each row execute function private.g_consent_append_only();
create trigger g_task_expected_share_consent_immutable before update or delete on public.task_expected_share_consents
 for each row execute function private.g_consent_append_only();

-- Project-wide positive authorization, recorded separately from per-task consent.
create function public.cmd_consent_auto_penalty_policy(
 p_project_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();p public.projects%rowtype;
begin
 if actor is null then return jsonb_build_object('ok',false,'code','UNAUTHENTICATED');end if;
 select * into p from public.projects where id=p_project_id for update;
 if p.id is null or p.archived_at is not null or p.lifecycle_state<>'active'
    or not private.is_active_non_observer_member(p_project_id,actor) then
   return jsonb_build_object('ok',false,'code','NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 if p_expected_version is distinct from p.version or p_request_id is null then
   return jsonb_build_object('ok',false,'code','STALE_VERSION','aggregateVersion',p.version);
 end if;
 insert into public.project_penalty_policy_consents(project_id,member_user_id,request_id)
 values(p_project_id,actor,p_request_id)
 on conflict(project_id,member_user_id,policy_version) do nothing;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('consented',true,'policyVersion',1));
end; $$;
revoke all on function public.cmd_consent_auto_penalty_policy(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.cmd_consent_auto_penalty_policy(uuid,uuid,integer) to authenticated;

-- Leader may enable only after all active non-observer members explicitly agree.
-- Disabling remains possible without fresh consent.
create function public.cmd_set_project_auto_penalty_policy(
 p_project_id uuid,p_enabled boolean,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();p public.projects%rowtype;
begin
 if actor is null then return jsonb_build_object('ok',false,'code','UNAUTHENTICATED');end if;
 select * into p from public.projects where id=p_project_id for update;
 if p.id is null or p.archived_at is not null or p.lifecycle_state<>'active'
    or not private.is_active_leader(p_project_id,actor) then
   return jsonb_build_object('ok',false,'code','NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 if p_expected_version is distinct from p.version or p_request_id is null or p_enabled is null then
   return jsonb_build_object('ok',false,'code','STALE_VERSION','aggregateVersion',p.version);
 end if;
 if p_enabled and exists(
   select 1 from public.project_members m where m.project_id=p_project_id
     and m.member_state='active' and m.user_id is not null
     and not m.is_observer and m.role<>'observer'
     and not exists(select 1 from public.project_penalty_policy_consents c
      where c.project_id=p_project_id and c.member_user_id=m.user_id
        and c.policy_version=1 and c.consented_at<=transaction_timestamp())
 ) then return jsonb_build_object('ok',false,'code','CONSENT_REQUIRED');end if;
 if p.auto_penalty_enabled is distinct from p_enabled then
  update public.projects set auto_penalty_enabled=p_enabled,version=version+1,updated_at=now()
    where id=p_project_id returning * into p;
 end if;
 return jsonb_build_object('ok',true,'aggregateVersion',p.version,
  'data',jsonb_build_object('enabled',p.auto_penalty_enabled));
end; $$;
revoke all on function public.cmd_set_project_auto_penalty_policy(uuid,boolean,uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.cmd_set_project_auto_penalty_policy(uuid,boolean,uuid,integer) to authenticated;

-- A responsible member must explicitly consent to the exact share and task
-- terms BEFORE accepting the assignment; never backfill a past acceptance.
create function public.cmd_consent_task_expected_share(
 p_project_id uuid,p_task_id uuid,p_share_bps integer,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();p public.projects%rowtype;t public.tasks%rowtype;
begin
 if actor is null then return jsonb_build_object('ok',false,'code','UNAUTHENTICATED');end if;
 select * into p from public.projects where id=p_project_id for share;
 select * into t from public.tasks where id=p_task_id and project_id=p_project_id for update;
 if p.id is null or t.id is null or p.archived_at is not null or p.lifecycle_state<>'active'
  or not private.is_active_non_observer_member(p_project_id,actor) then
   return jsonb_build_object('ok',false,'code','NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 if p_expected_version is distinct from t.version or p_request_id is null
    or p_share_bps is null or p_share_bps not between 1 and 10000 then
    return jsonb_build_object('ok',false,'code','STALE_VERSION','aggregateVersion',t.version);
 end if;
 if t.accepted_at is not null or t.status in ('completed','canceled','awaiting_review')
   or t.weight not between 1 and 5 then
   return jsonb_build_object('ok',false,'code','CONSENT_MUST_PRECEDE_ACCEPTANCE');
 end if;
 if not (
    t.assignee_id=actor
    or exists(select 1 from public.task_assignment_offers o
      where o.task_id=t.id and o.project_id=p_project_id
        and o.target_user_id=actor and o.state='pending')
    or exists(select 1 from public.task_collaborators c
      where c.task_id=t.id and c.project_id=p_project_id
        and c.user_id=actor and c.state in ('pending','accepted'))
 ) then return jsonb_build_object('ok',false,'code','NOT_TASK_PARTICIPANT');end if;
 if exists(select 1 from public.task_expected_share_consents c
  where c.task_id=t.id and c.member_user_id=actor and c.task_version=t.version
   and (c.expected_share_bps is distinct from p_share_bps
     or c.weight_snapshot is distinct from t.weight
     or c.deadline_snapshot is distinct from t.deadline_at))
 then return jsonb_build_object('ok',false,'code','CONSENT_ALREADY_RECORDED'); end if;
 insert into public.task_expected_share_consents(project_id,task_id,member_user_id,
   expected_share_bps,task_version,weight_snapshot,deadline_snapshot,request_id)
 values(p_project_id,p_task_id,actor,p_share_bps,t.version,t.weight,t.deadline_at,p_request_id)
 on conflict(task_id,member_user_id,task_version) do nothing;
 return jsonb_build_object('ok',true,'data',jsonb_build_object(
   'expectedShareBps',p_share_bps,'taskVersion',t.version,'explicit',true));
end; $$;
revoke all on function public.cmd_consent_task_expected_share(uuid,uuid,integer,uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.cmd_consent_task_expected_share(uuid,uuid,integer,uuid,integer)
 to authenticated;

-- Stamping occurs during the actual acceptance transaction. The row is
-- generated by C's authoritative task acceptance trigger, not by a client.
create function private.g_stamp_preacceptance_expected_share()
returns trigger language plpgsql security definer set search_path='' as $$
declare t public.tasks%rowtype; p public.projects%rowtype;
  version_before integer;
  expected integer;
  member_count integer;
  total_bps integer;
  matching integer;
begin
 if new.accepted_at is null or new.responsible_user_id is null then return new;end if;
 select * into t from public.tasks where id=new.task_id and project_id=new.project_id;
 select * into p from public.projects where id=new.project_id;
 if t.id is null or not p.auto_penalty_enabled or p.contribution_mode<>'weighted'
   or new.blocked_exempt or t.weight not between 1 and 5 then return new;end if;
 -- New active members must also consent to v1 before subsequent epochs
 -- can be penalty-eligible. Existing epochs are not retroactively upgraded.
 if exists(
   select 1 from public.project_members m
   where m.project_id=new.project_id and m.member_state='active'
     and not m.is_observer and m.role<>'observer' and m.user_id is not null
     and not exists (
       select 1 from public.project_penalty_policy_consents c
       where c.project_id=new.project_id and c.member_user_id=m.user_id
         and c.policy_version=1 and c.consented_at<=new.accepted_at
     )
 ) then return new;end if;
 version_before:=t.version-1; -- Acceptance-time membership: primary plus collaborators who already
 -- accepted when the primary responsibility begins.
 with participants as (
   select t.assignee_id as user_id
   union select c.user_id from public.task_collaborators c
   where c.project_id=t.project_id and c.task_id=t.id
     and c.state='accepted' and c.user_id is not null
 ), consented as (
   select c.member_user_id,c.expected_share_bps
   from public.task_expected_share_consents c
   join participants x on x.user_id=c.member_user_id
   where c.task_id=t.id and c.task_version=version_before
     and c.consented_at<=new.accepted_at
     and c.weight_snapshot=t.weight and c.deadline_snapshot=t.deadline_at
 )
 select (select count(*) from participants),
        (select count(*) from consented),
        (select coalesce(sum(expected_share_bps),0) from consented)
 into member_count,matching,total_bps;
 if member_count<1 or matching<>member_count or total_bps<>10000 then return new;end if;
 select c.expected_share_bps into expected
 from public.task_expected_share_consents c
 where c.task_id=t.id and c.member_user_id=new.responsible_user_id
  and c.task_version=version_before and c.consented_at<=new.accepted_at;
 if expected is null then return new;end if;
 update public.task_responsibility_epochs
 set expected_share_bps_snapshot=expected,
     shares_confirmed=true,
     accepted_expected_contribution=round(t.weight::numeric*expected/10000,4)
 where id=new.id;
 return new;
end; $$;
revoke all on function private.g_stamp_preacceptance_expected_share()
 from public,anon,authenticated,service_role;
create trigger g_stamp_preacceptance_expected_share
 after insert on public.task_responsibility_epochs
 for each row execute function private.g_stamp_preacceptance_expected_share();

-- Any later team-membership change invalidates future penalties for the
-- current epoch, even if an event is queued after the change.
create function private.g_invalidate_changed_participants()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_task uuid;
begin
 if tg_op='DELETE' then v_task:=old.task_id;else v_task:=new.task_id;end if;
 if tg_op='INSERT' or tg_op='DELETE'
   or old.state is distinct from new.state
   or old.user_id is distinct from new.user_id then
  update public.task_responsibility_epochs
  set blocked_exempt=true,exemption_reason='participants_changed_after_consent'
  where task_id=v_task and closed_at is null and shares_confirmed;
 end if;
 if tg_op='DELETE' then return old;end if;
 return new;
end; $$;
revoke all on function private.g_invalidate_changed_participants()
 from public,anon,authenticated,service_role;
create trigger g_invalidate_changed_participants
 after insert or update or delete on public.task_collaborators
 for each row execute function private.g_invalidate_changed_participants();

-- An event snapshot must agree with trusted C epoch facts, including
-- consent. Discrepant source data is quarantined, not charged.
create or replace function public.process_contribution_penalty_event_service(p_source_event_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare event_record public.business_events%rowtype;
  source jsonb; epoch public.task_responsibility_epochs%rowtype;
  verified_accepted_at timestamptz; verified_base numeric;
begin if auth.role() is distinct from 'service_role' then
   raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 select * into event_record from public.business_events where id=p_source_event_id;
 if not found then return jsonb_build_object('ok',false,'code','SOURCE_NOT_FOUND');end if;
 if event_record.event_type not in ('task_first_submitted_late','task_responsibility_abandoned') then
   return jsonb_build_object('ok',false,'code','INVALID_SOURCE_EVENT');end if;
 source:=event_record.event_data;
 if coalesce(source->>'responsibilityEpochId','')!~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   return jsonb_build_object('ok',false,'code','UNVERIFIED_SOURCE_EPOCH');end if;
 select * into epoch from public.task_responsibility_epochs
 where id=(source->>'responsibilityEpochId')::uuid
   and project_id=event_record.project_id
   and task_id=event_record.entity_id;
 begin
   verified_accepted_at:=(source->>'acceptedAt')::timestamptz;
   verified_base:=(source->>'acceptedExpectedContribution')::numeric;
 exception when invalid_text_representation or invalid_datetime_format
     or datetime_field_overflow or numeric_value_out_of_range then
   return jsonb_build_object('ok',false,'code','MALFORMED_CONSENT_SNAPSHOT');
 end;
 if epoch.id is null or not epoch.shares_confirmed or epoch.blocked_exempt
  or not epoch.auto_penalty_enabled_snapshot
  or epoch.project_contribution_mode<>'weighted'
  or source->>'responsibleUserId' is distinct from epoch.responsible_user_id::text
  or verified_accepted_at is distinct from epoch.accepted_at
  or source->>'expectedShareBpsSnapshot' is distinct from epoch.expected_share_bps_snapshot::text
  or verified_base is distinct from epoch.accepted_expected_contribution
 then
   return jsonb_build_object('ok',false,'code','UNVERIFIED_CONSENT_SNAPSHOT');
 end if; return private.process_contribution_penalty_event(p_source_event_id);
end; $$;
revoke all on function public.process_contribution_penalty_event_service(bigint)
 from public,anon,authenticated,service_role;
grant execute on function public.process_contribution_penalty_event_service(bigint) to service_role;
