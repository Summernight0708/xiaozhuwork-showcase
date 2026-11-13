
-- C produces authoritative source events. E never invents responsibility epochs or task facts.
create table public.penalty_event_consumptions (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 source_event_id bigint not null references public.business_events(id),
 member_key text not null,
 kind text not null check(kind in ('late','abandon')),
 disposition text not null check(disposition in ('assessed','skipped')),
 reason text,
 created_at timestamptz not null default now(),
 unique(source_event_id,member_key,kind)
);
create table public.contribution_penalties (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 task_id uuid not null references public.tasks(id),
 source_event_id bigint not null references public.business_events(id),
 member_user_id uuid references auth.users(id) on delete set null,
 member_key text not null,
 kind text not null check(kind in ('late','abandon')),
 source_occurrence_key text not null,
 responsibility_epoch_id uuid not null,
 policy_version integer not null,
 base_amount numeric(12,4) not null check(base_amount>=0),
 rate numeric(6,4) not null check(rate between 0 and 1.5),
 amount numeric(12,4) not null check(amount<=0),
 duration_seconds bigint not null check(duration_seconds>0),
 delay_seconds bigint not null check(delay_seconds>0),
 event_snapshot jsonb not null,
 assessed_at timestamptz not null default now(),
 unique(source_event_id,member_key,kind),
 unique(project_id,source_occurrence_key,member_key,kind),
 unique(project_id,id)
);
create trigger e_penalty_immutable before update or delete on public.contribution_penalties
 for each row execute function private.followup_e_immutable();
create trigger e_consumption_immutable before update or delete on public.penalty_event_consumptions
 for each row execute function private.followup_e_immutable();
alter table public.penalty_event_consumptions enable row level security;
alter table public.contribution_penalties enable row level security;
create policy e_consumptions_read on public.penalty_event_consumptions for select to authenticated
 using(public.is_active_project_member(project_id));
create policy e_penalties_read on public.contribution_penalties for select to authenticated
 using(public.is_active_project_member(project_id));
revoke all on public.penalty_event_consumptions,public.contribution_penalties from public,anon,authenticated;
grant select on public.penalty_event_consumptions,public.contribution_penalties to authenticated;

create function private.process_contribution_penalty_event(p_source_event_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 e public.business_events%rowtype; p public.projects%rowtype; t public.tasks%rowtype;
 d jsonb; responsible uuid; epoch uuid; member_key text; kind text; occurrence text;
 start_at timestamptz; due_at timestamptz; occurred_at timestamptz; free_until timestamptz;
 duration_seconds bigint; elapsed_seconds bigint; share_bps integer; weight numeric;
 base numeric(12,4); rate numeric(6,4); amount numeric(12,4); pen_id uuid;
 disposition text:='skipped'; why text; worker_claim record; event_request_id uuid;
begin
 if auth.role() is distinct from 'service_role' then
  raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED'; end if;
 select * into e from public.business_events where id=p_source_event_id;
 if e.id is null then return jsonb_build_object('ok',false,'code','SOURCE_NOT_FOUND'); end if;
 if e.event_type not in ('task_first_submitted_late','task_responsibility_abandoned') then
  return jsonb_build_object('ok',false,'code','INVALID_SOURCE_EVENT'); end if;
 d:=e.event_data;
 kind:=case when e.event_type='task_first_submitted_late' then 'late' else 'abandon' end;
 if coalesce(d->>'responsibleUserId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  return jsonb_build_object('ok',false,'code','INVALID_SOURCE_SNAPSHOT'); end if;
 responsible:=(d->>'responsibleUserId')::uuid;
 member_key:=responsible::text;
 select * into p from public.projects where id=e.project_id for update;
 select * into t from public.tasks where id=e.entity_id and project_id=e.project_id for update;
 if p.id is null or t.id is null or d->>'taskId' is distinct from t.id::text then
  return jsonb_build_object('ok',false,'code','INVALID_SOURCE_SCOPE'); end if;
 if exists(select 1 from public.penalty_event_consumptions c where c.source_event_id=e.id
   and c.member_key=responsible::text and c.kind=(case when e.event_type='task_first_submitted_late' then 'late' else 'abandon' end)) then
  return jsonb_build_object('ok',true,'replayed',true,'sourceEventId',e.id); end if;
 why:=null;
 if d->>'schemaVersion' is distinct from '1' or d->>'policyVersion' is distinct from '1'
   or coalesce(d->>'occurrenceKey','')=''
   or coalesce(d->>'responsibilityEpochId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or (kind='abandon' and (e.actor_id is distinct from responsible
     or d->>'occurrenceKey' is distinct from 'responsibility:'||(d->>'responsibilityEpochId')||':abandon'))
   or (kind='late' and d->>'occurrenceKey' is distinct from 'task:'||t.id::text||':first_late')
 then why:='invalid_event_envelope';
 elsif d->>'blockedExempt' is distinct from 'false'
   or d->>'autoPenaltyEnabledSnapshot' is distinct from 'true'
   or d->>'projectContributionMode' is distinct from 'weighted'
   or p.archived_at is not null then why:='policy_exempt';
 elsif d->>'expectedShareBpsSnapshot' is null or d->>'acceptedExpectedContribution' is null
   or d->>'weightSnapshot' is null or d->>'acceptedAt' is null
   or d->>'effectiveStartAt' is null or d->>'effectiveDeadlineAt' is null
   or d->>'occurredAt' is null then why:='missing_confirmed_snapshot';
 else
  begin
   epoch:=(d->>'responsibilityEpochId')::uuid;
   share_bps:=(d->>'expectedShareBpsSnapshot')::integer;
   weight:=(d->>'weightSnapshot')::numeric;
   base:=(d->>'acceptedExpectedContribution')::numeric(12,4);
   start_at:=(d->>'effectiveStartAt')::timestamptz;
   due_at:=(d->>'effectiveDeadlineAt')::timestamptz;
   occurred_at:=(d->>'occurredAt')::timestamptz;
   free_until:=start_at + floor(extract(epoch from(due_at-start_at)) /10) * interval '1 second';
   duration_seconds:=floor(extract(epoch from (due_at-start_at)))::bigint;
   if kind='late' then
    if d->>'firstSubmittedAt' is null then why:='missing_first_submission';
    elsif (d->>'firstSubmittedAt')::timestamptz is distinct from occurred_at then
      why:='timestamp_mismatch'; end if;
    elapsed_seconds:=floor(extract(epoch from(occurred_at-due_at)))::bigint;
   else
    if d->>'freeAbandonUntil' is null or (d->>'freeAbandonUntil')::timestamptz <> free_until then
      why:='free_window_mismatch'; end if;
    elapsed_seconds:=floor(extract(epoch from(occurred_at-free_until)))::bigint;
   end if;
   if duration_seconds<=0 or occurred_at<=start_at or (d->>'acceptedAt')::timestamptz>start_at
    or share_bps not between 0 and 10000 or weight not between 1 and 5
    or base<0 or abs(base-round(weight*share_bps/10000,4))>0.0001 then
    why:='invalid_responsibility_interval_or_amount'; end if;
   if elapsed_seconds<=0 then why:='within_free_window'; end if;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
    or numeric_value_out_of_range or division_by_zero then
   why:='invalid_numeric_or_time_snapshot';
  end;
 end if;
 if why is null and exists(select 1 from public.contribution_penalties previous
   where previous.project_id=e.project_id and previous.source_occurrence_key=d->>'occurrenceKey'
     and previous.member_key=responsible::text
     and previous.kind=(case when e.event_type='task_first_submitted_late' then 'late' else 'abandon' end)) then
  why:='duplicate_occurrence';
 end if;
 if why is null then
  if elapsed_seconds*10<=duration_seconds then
   rate:=case when kind='late' then 0.10 else 0.25 end;
  elsif elapsed_seconds*10<=duration_seconds*3 then
   rate:=case when kind='late' then 0.25 else 0.50 end;
  elsif elapsed_seconds*10<=duration_seconds*6 then
   rate:=case when kind='late' then 0.50 else 0.75 end;
  elsif elapsed_seconds<=duration_seconds then
   rate:=case when kind='late' then 0.75 else 1.00 end;
  else rate:=case when kind='late' then 1.00 else 1.50 end;
  end if;
  amount:=-round(base*rate,4);
  insert into public.contribution_penalties(project_id,task_id,source_event_id,member_user_id,
    member_key,kind,source_occurrence_key,responsibility_epoch_id,policy_version,
    base_amount,rate,amount,duration_seconds,delay_seconds,event_snapshot)
  values(e.project_id,t.id,e.id,responsible,member_key,kind,d->>'occurrenceKey',epoch,1,
    base,rate,amount,duration_seconds,elapsed_seconds,d) returning id into pen_id;
  disposition:='assessed';
 end if;
 insert into public.penalty_event_consumptions(project_id,source_event_id,member_key,kind,disposition,reason)
 values(e.project_id,e.id,member_key,kind,disposition,why);
 if disposition='assessed' then
  -- Deterministic per-source-event key; different event_seq values never reuse it.
  event_request_id:=md5('teamup:penalty:' || e.id::text)::uuid;
  select * into worker_claim from private.claim_command(
    coalesce(e.actor_id,responsible),'process_contribution_penalty_event',event_request_id,
    private.payload_hash(jsonb_build_object('sourceEventId',e.id)),null,e.project_id);
  perform private.emit_event(worker_claim.command_id,1,e.project_id,responsible,
    'contribution_penalty_assessed','contribution_penalty',pen_id,event_request_id,
    jsonb_build_object('schemaVersion',1,'policyVersion',1,'occurrenceKey',
     format('penalty:%s:%s:assessed',e.id,member_key),'occurredAt',transaction_timestamp(),
     'aggregateVersion',1,'responsibleUserId',responsible,'sourceEventId',e.id,
     'penaltyId',pen_id,'amount',amount));
  perform private.complete_command(worker_claim.command_id,jsonb_build_object('ok',true,'penaltyId',pen_id),
    'contribution_penalty',pen_id,1);
 end if;
 return jsonb_build_object('ok',true,'replayed',false,'disposition',disposition,
   'reason',why,'penaltyId',pen_id);
end; $$;
revoke all on function private.process_contribution_penalty_event(bigint) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.process_contribution_penalty_event(bigint) to service_role;
