
-- E independent contribution allocations; never mutate legacy contribution_items.
create table public.task_share_proposals (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  revision integer not null check(revision>0),
  proposed_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check(status in ('pending','confirmed','superseded')),
  weight_snapshot numeric(12,4),
  contribution_mode_snapshot text not null check(contribution_mode_snapshot in ('weighted','facts_only')),
  version integer not null default 1 check(version>0),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unique(task_id,revision), unique(project_id,id),
  check (status<>'confirmed' or confirmed_at is not null)
);
create unique index task_shares_pending_unique on public.task_share_proposals(task_id) where status='pending';
create unique index task_shares_confirmed_unique on public.task_share_proposals(task_id) where status='confirmed';
create table public.task_share_allocations (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.task_share_proposals(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  member_user_id uuid references auth.users(id) on delete set null,
  share_bps integer not null check(share_bps between 0 and 10000),
  amount numeric(12,4),
  unique(proposal_id,member_user_id)
);
create table public.task_share_confirmations (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.task_share_proposals(id) on delete cascade,
  member_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default now(),
  unique(proposal_id,member_user_id)
);
create table public.task_contribution_ledger (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null references public.tasks(id),
  proposal_id uuid not null references public.task_share_proposals(id),
  member_user_id uuid references auth.users(id) on delete set null,
  share_bps integer not null check(share_bps between 0 and 10000),
  amount numeric(12,4),
  weight_snapshot numeric(12,4),
  created_at timestamptz not null default now(),
  unique(proposal_id,member_user_id)
);
create function private.followup_e_immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='55000',message='Immutable contribution history'; end; $$;
create trigger e_share_alloc_immutable before update or delete on public.task_share_allocations
 for each row execute function private.followup_e_immutable();
create trigger e_share_confirm_immutable before update or delete on public.task_share_confirmations
 for each row execute function private.followup_e_immutable();
create trigger e_share_ledger_immutable before update or delete on public.task_contribution_ledger
 for each row execute function private.followup_e_immutable();

alter table public.task_share_proposals enable row level security;
alter table public.task_share_allocations enable row level security;
alter table public.task_share_confirmations enable row level security;
alter table public.task_contribution_ledger enable row level security;
create policy e_proposals_read on public.task_share_proposals for select to authenticated
 using(public.is_active_project_member(project_id));
create policy e_allocations_read on public.task_share_allocations for select to authenticated
 using(public.is_active_project_member(project_id));
create policy e_confirmations_read on public.task_share_confirmations for select to authenticated
 using(exists(select 1 from public.task_share_proposals p where p.id=proposal_id and public.is_active_project_member(p.project_id)));
create policy e_ledger_read on public.task_contribution_ledger for select to authenticated
 using(public.is_active_project_member(project_id));
revoke all on public.task_share_proposals,public.task_share_allocations,public.task_share_confirmations,public.task_contribution_ledger
 from public,anon,authenticated;
grant select on public.task_share_proposals,public.task_share_allocations,public.task_share_confirmations,public.task_contribution_ledger to authenticated;
revoke all on function private.followup_e_immutable() from public,anon,authenticated,service_role;

create function private.e_task_participants(p_project uuid,p_task uuid)
returns table(user_id uuid) stable language sql security definer set search_path='' as $$
 select t.assignee_id from public.tasks t where t.project_id=p_project and t.id=p_task and t.assignee_id is not null
 union
 select c.user_id from public.task_collaborators c
 where c.project_id=p_project and c.task_id=p_task and c.state='accepted' and c.user_id is not null;
$$;
revoke all on function private.e_task_participants(uuid,uuid) from public,anon,authenticated,service_role;

create function public.cmd_propose_task_shares(
 p_project_id uuid,p_task_id uuid,p_allocations jsonb,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); claim record; result jsonb; proj public.projects%rowtype; task public.tasks%rowtype;
 entry jsonb; uid uuid; bps integer; total integer:=0; cnt integer:=0; need integer; proposal uuid;
 rev integer; weight numeric(12,4); missing_units integer; at_time timestamptz:=transaction_timestamp();
begin
 if actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_project_id is null or p_task_id is null or p_request_id is null then
  return private.failure(p_request_id,'VALIDATION_FAILED','ids'); end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into claim from private.claim_command(actor,'cmd_propose_task_shares',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,
  'allocations',p_allocations,'expectedVersion',p_expected_version)),null,p_project_id);
 result:=private.replay_or_reuse(p_request_id,claim.prior_result,claim.payload_matches);
 if result is not null then return result; end if;
 select * into proj from public.projects where id=p_project_id for update;
 select * into task from public.tasks where project_id=p_project_id and id=p_task_id for update;
 if task.id is null or task.assignee_id is distinct from actor or not exists(
   select 1 from public.project_members m where m.project_id=p_project_id and m.user_id=actor
     and m.member_state='active' and not m.is_observer and m.role<>'observer') then
  result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif proj.archived_at is not null or proj.lifecycle_state<>'active' then
  result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif p_expected_version is distinct from task.version then
  result:=private.failure(p_request_id,'STALE_VERSION',null,task.version);
 elsif task.status<>'completed' or (proj.contribution_mode='weighted' and task.weight is null)
   or exists(select 1 from public.contribution_reports r where r.project_id=p_project_id) then
  result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif p_allocations is null or jsonb_typeof(p_allocations)<>'array'
   or jsonb_array_length(p_allocations) not between 1 and 50 then
  result:=private.failure(p_request_id,'VALIDATION_FAILED','allocations');
 else
  select count(*) into need from private.e_task_participants(p_project_id,p_task_id);
  if need<>jsonb_array_length(p_allocations) then
   result:=private.failure(p_request_id,'VALIDATION_FAILED','participants');
  else
   for entry in select value from jsonb_array_elements(p_allocations) loop
    if jsonb_typeof(entry)<>'object'
      or coalesce(entry->>'userId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(entry->'shareBps')<>'number'
      or coalesce(entry->>'shareBps','') !~ '^(0|[1-9][0-9]{0,4})$' then
      return private.complete_command(claim.command_id,private.failure(p_request_id,'VALIDATION_FAILED','allocations'));
    end if;
    uid:=(entry->>'userId')::uuid; bps:=(entry->>'shareBps')::integer;
    if bps>10000 or not exists(select 1 from private.e_task_participants(p_project_id,p_task_id) m where m.user_id=uid)
      or not exists(select 1 from public.project_members m where m.project_id=p_project_id
        and m.user_id=uid and m.member_state='active' and not m.is_observer and m.role<>'observer') then
      return private.complete_command(claim.command_id,private.failure(p_request_id,'VALIDATION_FAILED','participants'));
    end if;
    cnt:=cnt+1; total:=total+bps;
   end loop;
   if total<>10000 or (select count(distinct value->>'userId') from jsonb_array_elements(p_allocations))<>cnt then
    result:=private.failure(p_request_id,'VALIDATION_FAILED','shareBps');
   else
    update public.task_share_proposals set status='superseded',version=version+1
      where task_id=p_task_id and status='pending';
    select coalesce(max(revision),0)+1 into rev from public.task_share_proposals where task_id=p_task_id;
    weight:=case when proj.contribution_mode='weighted' then task.weight::numeric else null end;
    insert into public.task_share_proposals(project_id,task_id,revision,proposed_by,weight_snapshot,contribution_mode_snapshot)
     values(p_project_id,p_task_id,rev,actor,weight,proj.contribution_mode) returning id into proposal;
    -- Residual cents of a star are allocated during INSERT, never by updating immutable rows.
    with raw as (
      select (v.value->>'userId')::uuid as participant_id,
        (v.value->>'shareBps')::integer as bps,
        case when weight is null then null
             else trunc(weight * (v.value->>'shareBps')::integer / 10000, 4) end as truncated_amount
      from jsonb_array_elements(p_allocations) v
    ), ranked as (
      select raw.*, row_number() over(order by participant_id) as ordinal,
        case when weight is null then 0
             else round((weight - sum(truncated_amount) over()) * 10000)::integer
        end as remainder_units
      from raw
    )
    insert into public.task_share_allocations(proposal_id,project_id,member_user_id,share_bps,amount)
    select proposal,p_project_id,r.participant_id,r.bps,
      case when weight is null then null
           else r.truncated_amount + case when r.ordinal <= r.remainder_units then 0.0001 else 0 end
      end
    from ranked r;
    update public.tasks set version=version+1,updated_at=at_time where id=p_task_id returning * into task;
    perform private.emit_event(claim.command_id,1,p_project_id,actor,'contribution_shares_proposed',
      'task',p_task_id,p_request_id,jsonb_build_object('schemaVersion',1,'policyVersion',1,
      'occurrenceKey',format('task:%s:allocation:%s:proposed',p_task_id,rev),
      'occurredAt',at_time,'aggregateVersion',task.version,'responsibleUserId',actor,'proposalId',proposal,'revision',rev));
    result:=jsonb_build_object('ok',true,'requestId',p_request_id,'replayed',false,'aggregateType','task',
      'aggregateId',p_task_id,'aggregateVersion',task.version,
      'data',jsonb_build_object('proposalId',proposal,'revision',rev,'taskVersion',task.version,'state','pending'));
   end if;
  end if;
 end if;
 return private.complete_command(claim.command_id,result,'task',p_task_id,task.version);
end; $$;

create function public.cmd_confirm_task_shares(
 p_project_id uuid,p_proposal_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); claim record; result jsonb; proj public.projects%rowtype; task public.tasks%rowtype;
 prop public.task_share_proposals%rowtype; required_count integer; have_count integer; done boolean;
 at_time timestamptz:=transaction_timestamp();
begin
 if actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_project_id is null or p_proposal_id is null or p_request_id is null then
  return private.failure(p_request_id,'VALIDATION_FAILED','ids'); end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into claim from private.claim_command(actor,'cmd_confirm_task_shares',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,
   'proposalId',p_proposal_id,'expectedVersion',p_expected_version)),null,p_project_id);
 result:=private.replay_or_reuse(p_request_id,claim.prior_result,claim.payload_matches);
 if result is not null then return result; end if;
 select * into proj from public.projects where id=p_project_id for update;
 select * into prop from public.task_share_proposals where id=p_proposal_id and project_id=p_project_id;
 if prop.id is not null then
  select * into task from public.tasks where id=prop.task_id and project_id=p_project_id for update;
  select * into prop from public.task_share_proposals where id=p_proposal_id for update;
 end if;
 if prop.id is null or not exists(select 1 from public.task_share_allocations a
     where a.proposal_id=p_proposal_id and a.member_user_id=actor)
    or not exists(select 1 from public.project_members m where m.project_id=p_project_id
     and m.user_id=actor and m.member_state='active' and not m.is_observer and m.role<>'observer') then
  result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif proj.archived_at is not null or proj.lifecycle_state<>'active' then
  result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif p_expected_version is distinct from prop.version then
  result:=private.failure(p_request_id,'STALE_VERSION',null,prop.version);
 elsif prop.status<>'pending' or task.status<>'completed'
   or exists(select 1 from public.task_share_confirmations c where c.proposal_id=p_proposal_id and c.member_user_id=actor) then
  result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif exists(
  (select user_id from private.e_task_participants(p_project_id,prop.task_id)
     except select member_user_id from public.task_share_allocations where proposal_id=p_proposal_id)
  union all
  (select member_user_id from public.task_share_allocations where proposal_id=p_proposal_id
     except select user_id from private.e_task_participants(p_project_id,prop.task_id))
 ) or exists(select 1 from public.task_share_allocations a left join public.project_members m
   on m.project_id=p_project_id and m.user_id=a.member_user_id
   where a.proposal_id=p_proposal_id and (m.member_state is distinct from 'active' or m.is_observer is distinct from false or m.role='observer')) then
  result:=private.failure(p_request_id,'SHARES_NOT_CONFIRMED',null,prop.version);
 else
  insert into public.task_share_confirmations(proposal_id,member_user_id) values(p_proposal_id,actor);
  update public.task_share_proposals set version=version+1 where id=p_proposal_id returning * into prop;
  select count(*) into required_count from public.task_share_allocations where proposal_id=p_proposal_id;
  select count(*) into have_count from public.task_share_confirmations where proposal_id=p_proposal_id;
  done:=required_count=have_count;
  if done then
   update public.task_share_proposals set status='superseded',version=version+1
    where task_id=prop.task_id and status='confirmed';
   update public.task_share_proposals set status='confirmed',confirmed_at=at_time,version=version+1
    where id=p_proposal_id returning * into prop;
   insert into public.task_contribution_ledger(project_id,task_id,proposal_id,member_user_id,share_bps,amount,weight_snapshot)
    select p_project_id,prop.task_id,a.proposal_id,a.member_user_id,a.share_bps,a.amount,prop.weight_snapshot
    from public.task_share_allocations a where a.proposal_id=p_proposal_id;
  end if;
  perform private.emit_event(claim.command_id,1,p_project_id,actor,'contribution_shares_confirmed','task',
   prop.task_id,p_request_id,jsonb_build_object('schemaVersion',1,'policyVersion',1,
   'occurrenceKey',format('task:%s:allocation:%s:member:%s:confirmed',prop.task_id,prop.revision,actor),
   'occurredAt',at_time,'aggregateVersion',prop.version,'responsibleUserId',actor,'proposalId',p_proposal_id,'complete',done));
  if done then
   perform private.emit_event(claim.command_id,2,p_project_id,actor,'contribution_shares_confirmed','task',
    prop.task_id,p_request_id,jsonb_build_object('schemaVersion',1,'policyVersion',1,
    'occurrenceKey',format('task:%s:allocation:%s:confirmed',prop.task_id,prop.revision),
    'occurredAt',at_time,'aggregateVersion',prop.version,'responsibleUserId',actor,'proposalId',p_proposal_id,'complete',true));
  end if;
  result:=jsonb_build_object('ok',true,'requestId',p_request_id,'replayed',false,
   'aggregateType','task_share_proposal','aggregateId',p_proposal_id,'aggregateVersion',prop.version,
   'data',jsonb_build_object('proposalId',p_proposal_id,'state',prop.status,'confirmedCount',have_count,'requiredCount',required_count));
 end if;
 return private.complete_command(claim.command_id,result,'task_share_proposal',p_proposal_id,prop.version);
end; $$;

create view public.task_authoritative_contributions with(security_invoker=true) as
 select l.* from public.task_contribution_ledger l
 join public.task_share_proposals p on p.id=l.proposal_id and p.status='confirmed';
create view public.project_contribution_share_readiness with(security_invoker=true) as
 select t.project_id,t.id task_id,
 (p.id is not null
   and not exists(select 1 from public.task_share_proposals pending
    where pending.task_id=t.id and pending.status='pending')
   and not exists(select 1 from public.task_share_allocations a
    left join public.project_members m on m.project_id=t.project_id and m.user_id=a.member_user_id
    where a.proposal_id=p.id and (m.member_state is distinct from 'active'
      or m.is_observer is distinct from false or m.role='observer'))
   and (select count(*) from public.task_share_allocations a where a.proposal_id=p.id)=
   (select count(*) from public.task_share_confirmations c where c.proposal_id=p.id)
   and not exists(
    (select t.assignee_id as user_id where t.assignee_id is not null
      union select c.user_id from public.task_collaborators c
        where c.task_id=t.id and c.project_id=t.project_id and c.state='accepted' and c.user_id is not null
      except select member_user_id from public.task_share_allocations where proposal_id=p.id)
    union all
    (select member_user_id from public.task_share_allocations where proposal_id=p.id
      except (select t.assignee_id where t.assignee_id is not null
       union select c.user_id from public.task_collaborators c where c.task_id=t.id
        and c.project_id=t.project_id and c.state='accepted' and c.user_id is not null))
   )) as shares_ready
 from public.tasks t left join public.task_share_proposals p on p.task_id=t.id and p.status='confirmed'
 where t.status='completed';
revoke all on public.task_authoritative_contributions,public.project_contribution_share_readiness from public,anon;
grant select on public.task_authoritative_contributions,public.project_contribution_share_readiness to authenticated;
revoke all on function public.cmd_propose_task_shares(uuid,uuid,jsonb,uuid,integer),
 public.cmd_confirm_task_shares(uuid,uuid,uuid,integer) from public,anon,service_role;
grant execute on function public.cmd_propose_task_shares(uuid,uuid,jsonb,uuid,integer),
 public.cmd_confirm_task_shares(uuid,uuid,uuid,integer) to authenticated;
