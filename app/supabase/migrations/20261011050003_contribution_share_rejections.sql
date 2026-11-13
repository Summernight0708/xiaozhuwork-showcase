-- Explicit rejection of proposed shares: a member never consents by silence.
-- Rejections are immutable evidence; a fresh proposal needs fresh unanimous consent.
create table public.task_share_rejections (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.task_share_proposals(id) on delete cascade,
  member_user_id uuid references auth.users(id) on delete set null,
  reason text not null check(char_length(btrim(reason)) between 1 and 2000),
  rejected_at timestamptz not null default transaction_timestamp(),
  unique(proposal_id,member_user_id)
);
create trigger e_share_rejections_immutable before update or delete on public.task_share_rejections
  for each row execute function private.followup_e_immutable();
alter table public.task_share_rejections enable row level security;
create policy e_share_rejections_read on public.task_share_rejections for select to authenticated
 using(exists(select 1 from public.task_share_proposals p
    where p.id=proposal_id and public.is_active_project_member(p.project_id)));
revoke all on public.task_share_rejections from public,anon,authenticated;
grant select on public.task_share_rejections to authenticated;

create function public.cmd_reject_task_shares(
 p_project_id uuid,p_proposal_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); claim record; result jsonb;
 proj public.projects%rowtype; prop public.task_share_proposals%rowtype; task public.tasks%rowtype;
 rejected_id uuid; at_time timestamptz:=transaction_timestamp();
begin
 if actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_project_id is null or p_proposal_id is null or p_request_id is null then
   return private.failure(p_request_id,'VALIDATION_FAILED','ids'); end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
   return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into claim from private.claim_command(actor,'cmd_reject_task_shares',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'proposalId',p_proposal_id,
    'reason',p_reason,'expectedVersion',p_expected_version)),null,p_project_id);
 result:=private.replay_or_reuse(p_request_id,claim.prior_result,claim.payload_matches);
 if result is not null then return result; end if;

 select * into proj from public.projects where id=p_project_id for update;
 select * into prop from public.task_share_proposals
   where project_id=p_project_id and id=p_proposal_id;
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
 elsif prop.status<>'pending' or task.status<>'completed' then
   result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif p_reason is null or char_length(btrim(p_reason)) not between 1 and 2000 then
   result:=private.failure(p_request_id,'VALIDATION_FAILED','reason');
 else
   insert into public.task_share_rejections(proposal_id,member_user_id,reason)
    values(p_proposal_id,actor,btrim(p_reason)) returning id into rejected_id;
   update public.task_share_proposals set status='superseded',version=version+1
    where id=p_proposal_id returning * into prop;
   perform private.emit_event(claim.command_id,1,p_project_id,actor,
     'contribution_shares_rejected','task',prop.task_id,p_request_id,
     jsonb_build_object('schemaVersion',1,'policyVersion',1,
       'occurrenceKey',format('task:%s:allocation:%s:member:%s:rejected',prop.task_id,prop.revision,actor),
       'occurredAt',at_time,'aggregateVersion',prop.version,'responsibleUserId',actor,
       'proposalId',p_proposal_id,'rejectionId',rejected_id));
   result:=jsonb_build_object('ok',true,'requestId',p_request_id,'replayed',false,
     'aggregateType','task_share_proposal','aggregateId',p_proposal_id,'aggregateVersion',prop.version,
     'data',jsonb_build_object('proposalId',p_proposal_id,'state','superseded',
       'rejectionId',rejected_id,'requiresNewProposal',true));
 end if;
 return private.complete_command(claim.command_id,result,'task_share_proposal',p_proposal_id,prop.version);
end; $$;
revoke all on function public.cmd_reject_task_shares(uuid,uuid,text,uuid,integer) from public,anon,service_role;
grant execute on function public.cmd_reject_task_shares(uuid,uuid,text,uuid,integer) to authenticated;
