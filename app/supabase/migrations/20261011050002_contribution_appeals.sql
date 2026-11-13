
-- Appeals do not rewind task responsibility; votes append and original penalty stays immutable.
create table public.contribution_penalty_appeals (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 penalty_id uuid not null,
 round integer not null check(round>0),
 appellant_user_id uuid references auth.users(id) on delete set null,
 reason text not null check(char_length(btrim(reason)) between 1 and 2000),
 status text not null default 'pending' check(status in ('pending','resolved')),
 version integer not null default 1 check(version>0),
 opened_at timestamptz not null default now(),
 resolved_at timestamptz,
 resolution jsonb,
 unique(penalty_id,round),
 unique(project_id,id),
 foreign key(project_id,penalty_id) references public.contribution_penalties(project_id,id),
 check ((status='resolved')=(resolved_at is not null))
);
create unique index e_one_pending_penalty_appeal on public.contribution_penalty_appeals(penalty_id) where status='pending';
create table public.contribution_appeal_votes (
 id uuid primary key default gen_random_uuid(),
 appeal_id uuid not null references public.contribution_penalty_appeals(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 voter_id uuid references auth.users(id) on delete set null,
 resolution jsonb not null,
 created_at timestamptz not null default now(),
 unique(appeal_id,voter_id)
);
create table public.contribution_penalty_adjustments (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete cascade,
 penalty_id uuid not null,
 appeal_id uuid not null references public.contribution_penalty_appeals(id),
 member_user_id uuid references auth.users(id) on delete set null,
 signed_delta numeric(12,4) not null check(signed_delta>=0),
 previous_amount numeric(12,4) not null,
 resulting_amount numeric(12,4) not null,
 created_at timestamptz not null default now(),
 foreign key(project_id,penalty_id) references public.contribution_penalties(project_id,id),
 unique(appeal_id)
);
create trigger e_votes_immutable before update or delete on public.contribution_appeal_votes
 for each row execute function private.followup_e_immutable();
create trigger e_adjustments_immutable before update or delete on public.contribution_penalty_adjustments
 for each row execute function private.followup_e_immutable();
alter table public.contribution_penalty_appeals enable row level security;
alter table public.contribution_appeal_votes enable row level security;
alter table public.contribution_penalty_adjustments enable row level security;
create policy e_appeals_read on public.contribution_penalty_appeals for select to authenticated
 using(public.is_active_project_member(project_id));
create policy e_votes_read on public.contribution_appeal_votes for select to authenticated
 using(public.is_active_project_member(project_id) and
   (voter_id=auth.uid() or exists(select 1 from public.contribution_penalty_appeals a
     where a.id=appeal_id and a.status='resolved')));
create policy e_adjustments_read on public.contribution_penalty_adjustments for select to authenticated
 using(public.is_active_project_member(project_id));
revoke all on public.contribution_penalty_appeals,public.contribution_appeal_votes,
 public.contribution_penalty_adjustments from public,anon,authenticated;
grant select on public.contribution_penalty_appeals,public.contribution_appeal_votes,
 public.contribution_penalty_adjustments to authenticated;

create function public.cmd_appeal_contribution_penalty(
 p_project_id uuid,p_penalty_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); claim record; result jsonb; proj public.projects%rowtype;
 pen public.contribution_penalties%rowtype; appeal_id uuid; next_round integer;
begin
 if actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_project_id is null or p_penalty_id is null or p_request_id is null then
  return private.failure(p_request_id,'VALIDATION_FAILED','ids'); end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into claim from private.claim_command(actor,'cmd_appeal_contribution_penalty',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'penaltyId',p_penalty_id,
   'reason',p_reason,'expectedVersion',p_expected_version)),null,p_project_id);
 result:=private.replay_or_reuse(p_request_id,claim.prior_result,claim.payload_matches);
 if result is not null then return result; end if;
 select * into proj from public.projects where id=p_project_id for update;
 select * into pen from public.contribution_penalties where id=p_penalty_id and project_id=p_project_id for update;
 if pen.id is null or pen.member_user_id is distinct from actor or not exists(
  select 1 from public.project_members m where m.project_id=p_project_id and m.user_id=actor
  and m.member_state='active' and not m.is_observer and m.role<>'observer') then
  result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif proj.archived_at is not null or proj.lifecycle_state<>'active' then
  result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif p_expected_version is distinct from 1 then
  result:=private.failure(p_request_id,'STALE_VERSION',null,1);
 elsif p_reason is null or char_length(btrim(p_reason)) not between 1 and 2000 then
  result:=private.failure(p_request_id,'VALIDATION_FAILED','reason');
 elsif exists(select 1 from public.contribution_penalty_appeals a where a.penalty_id=p_penalty_id
   and a.status='pending') then
  result:=private.failure(p_request_id,'INVALID_TRANSITION');
 else
  select coalesce(max(round),0)+1 into next_round from public.contribution_penalty_appeals
   where penalty_id=p_penalty_id;
  insert into public.contribution_penalty_appeals(project_id,penalty_id,round,appellant_user_id,reason)
   values(p_project_id,p_penalty_id,next_round,actor,btrim(p_reason)) returning id into appeal_id;
  perform private.emit_event(claim.command_id,1,p_project_id,actor,
   'contribution_penalty_appealed','contribution_penalty',p_penalty_id,p_request_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,
    'occurrenceKey',format('penalty:%s:appeal:%s:opened',p_penalty_id,next_round),
    'occurredAt',transaction_timestamp(),'aggregateVersion',1,'responsibleUserId',actor,
    'appealId',appeal_id,'penaltyId',p_penalty_id));
  result:=jsonb_build_object('ok',true,'requestId',p_request_id,'replayed',false,
   'aggregateType','contribution_penalty_appeal','aggregateId',appeal_id,'aggregateVersion',1,
   'data',jsonb_build_object('appealId',appeal_id,'state','pending','round',next_round));
 end if;
 return private.complete_command(claim.command_id,result,'contribution_penalty_appeal',appeal_id,1);
end; $$;

-- Every eligible non-affected member casts one confidential ballot. Identical
-- ballots must exceed half of the eligible voters for any resolution to pass.
create function public.cmd_resolve_contribution_appeal(
 p_project_id uuid,p_appeal_id uuid,p_resolution jsonb,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); claim record; result jsonb; proj public.projects%rowtype;
 app public.contribution_penalty_appeals%rowtype; pen public.contribution_penalties%rowtype;
 decision text; target numeric(12,4); original_current numeric(12,4);
 eligible integer; approvals integer; passed boolean:=false; delta numeric(12,4);
 at_time timestamptz:=transaction_timestamp();
begin
 if actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_project_id is null or p_appeal_id is null or p_request_id is null then
  return private.failure(p_request_id,'VALIDATION_FAILED','ids'); end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into claim from private.claim_command(actor,'cmd_resolve_contribution_appeal',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'appealId',p_appeal_id,
   'resolution',p_resolution,'expectedVersion',p_expected_version)),null,p_project_id);
 result:=private.replay_or_reuse(p_request_id,claim.prior_result,claim.payload_matches);
 if result is not null then return result; end if;
 select * into proj from public.projects where id=p_project_id for update;
 select * into app from public.contribution_penalty_appeals where id=p_appeal_id and project_id=p_project_id;
 if app.id is not null then
  select * into pen from public.contribution_penalties
   where id=app.penalty_id and project_id=p_project_id for update;
  select * into app from public.contribution_penalty_appeals where id=p_appeal_id for update;
 end if;
 if app.id is null or pen.id is null or pen.member_user_id=actor
   or not exists(select 1 from public.project_members m where m.project_id=p_project_id
    and m.user_id=actor and m.member_state='active' and not m.is_observer and m.role<>'observer') then
  result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif proj.archived_at is not null or proj.lifecycle_state<>'active' then
  result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif p_expected_version is distinct from app.version then
  result:=private.failure(p_request_id,'STALE_VERSION',null,app.version);
 elsif app.status<>'pending' or exists(select 1 from public.contribution_appeal_votes v
   where v.appeal_id=p_appeal_id and v.voter_id=actor) then
  result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif p_resolution is null or jsonb_typeof(p_resolution)<>'object'
   or coalesce(p_resolution->>'decision','') not in ('maintain','reduce','revoke') then
  result:=private.failure(p_request_id,'VALIDATION_FAILED','resolution');
 else
  select (pen.amount+coalesce(sum(a.signed_delta),0))::numeric(12,4)
    into original_current from public.contribution_penalty_adjustments a
    where a.penalty_id=pen.id;
  -- SUM on zero rows is null, but pen.amount+coalesce(...) remains non-null.
  decision:=p_resolution->>'decision';
  if decision='maintain' then
   target:=original_current;
  elsif decision='revoke' then
   target:=0;
  elsif coalesce(p_resolution->>'targetAmount','') !~ '^-?[0-9]{1,7}(\.[0-9]{1,4})?$' then
   result:=private.failure(p_request_id,'VALIDATION_FAILED','targetAmount');
  else
   target:=(p_resolution->>'targetAmount')::numeric(12,4);
  end if;
  if result is null and (target<original_current or target>0
    or (decision='reduce' and target=original_current)) then
   result:=private.failure(p_request_id,'VALIDATION_FAILED','targetAmount');
  end if;
  if result is null then
   -- Canonical vote payload ignores caller's arbitrary additional JSON keys.
   insert into public.contribution_appeal_votes(appeal_id,project_id,voter_id,resolution)
    values(p_appeal_id,p_project_id,actor,jsonb_build_object('decision',decision,'targetAmount',target::text));
   select count(*) into eligible from public.project_members m where m.project_id=p_project_id
    and m.member_state='active' and not m.is_observer and m.role<>'observer'
    and m.user_id is not null and m.user_id is distinct from pen.member_user_id;
   select count(*) into approvals from public.contribution_appeal_votes v
    where v.appeal_id=p_appeal_id
      and v.resolution=jsonb_build_object('decision',decision,'targetAmount',target::text)
      and exists(select 1 from public.project_members m where m.project_id=p_project_id
       and m.user_id=v.voter_id and m.member_state='active' and not m.is_observer
       and m.role<>'observer' and m.user_id is distinct from pen.member_user_id);
   passed:=approvals>eligible/2;
   update public.contribution_penalty_appeals set version=version+1,
    status=case when passed then 'resolved' else 'pending' end,
    resolved_at=case when passed then at_time else null end,
    resolution=case when passed then jsonb_build_object('decision',decision,'targetAmount',target::text) else null end
    where id=p_appeal_id returning * into app;
   if passed then
    delta:=round(target-original_current,4);
    insert into public.contribution_penalty_adjustments(project_id,penalty_id,appeal_id,
      member_user_id,signed_delta,previous_amount,resulting_amount)
    values(p_project_id,pen.id,p_appeal_id,pen.member_user_id,delta,original_current,target);
    perform private.emit_event(claim.command_id,1,p_project_id,actor,
     'contribution_penalty_adjusted','contribution_penalty',pen.id,p_request_id,
     jsonb_build_object('schemaVersion',1,'policyVersion',1,
      'occurrenceKey',format('penalty:%s:appeal:%s:adjusted',pen.id,app.round),
      'occurredAt',at_time,'aggregateVersion',app.version,'responsibleUserId',pen.member_user_id,
      'appealId',app.id,'delta',delta,'targetAmount',target,'decision',decision));
   end if;
   result:=jsonb_build_object('ok',true,'requestId',p_request_id,'replayed',false,
     'aggregateType','contribution_penalty_appeal','aggregateId',app.id,'aggregateVersion',app.version,
     'data',jsonb_build_object('state',app.status,'approvals',approvals,
        'eligibleVoters',eligible,'passed',passed));
  end if;
 end if;
 return private.complete_command(claim.command_id,result,'contribution_penalty_appeal',p_appeal_id,app.version);
end; $$;

create view public.project_contribution_ledger_entries with(security_invoker=true) as
 select l.project_id,l.task_id,l.member_user_id,'task_share'::text as entry_type,l.id as entry_id,
  l.amount::numeric(12,4) as signed_amount
 from public.task_authoritative_contributions l where l.amount is not null
 union all
 select p.project_id,p.task_id,p.member_user_id,'penalty',p.id,p.amount
 from public.contribution_penalties p
 union all
 select a.project_id,p.task_id,a.member_user_id,'adjustment',a.id,a.signed_delta
 from public.contribution_penalty_adjustments a join public.contribution_penalties p on p.id=a.penalty_id;
create view public.project_contribution_balances with(security_invoker=true) as
 select project_id,member_user_id,sum(signed_amount)::numeric(12,4) as amount
 from public.project_contribution_ledger_entries group by project_id,member_user_id;
revoke all on public.project_contribution_ledger_entries,public.project_contribution_balances from public,anon;
grant select on public.project_contribution_ledger_entries,public.project_contribution_balances to authenticated;
revoke all on function public.cmd_appeal_contribution_penalty(uuid,uuid,text,uuid,integer),
 public.cmd_resolve_contribution_appeal(uuid,uuid,jsonb,uuid,integer)
 from public,anon,service_role;
grant execute on function public.cmd_appeal_contribution_penalty(uuid,uuid,text,uuid,integer),
 public.cmd_resolve_contribution_appeal(uuid,uuid,jsonb,uuid,integer) to authenticated;
