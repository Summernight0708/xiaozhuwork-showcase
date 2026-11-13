-- G: bounded service-only drain for C->E authoritative source events.
create table private.followup_g_penalty_dispatch_faults (
  source_event_id bigint primary key references public.business_events(id),
  last_error text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
revoke all on private.followup_g_penalty_dispatch_faults from public,anon,authenticated,service_role;

create function public.dispatch_contribution_penalty_events_service(
 p_batch_limit integer default 100
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_event record;
 v_result jsonb;
 v_processed integer:=0;
 v_assessed integer:=0;
 v_skipped integer:=0;
 v_quarantined integer:=0;
begin
 if auth.role() is distinct from 'service_role' then
  raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 if p_batch_limit is null or p_batch_limit < 1 or p_batch_limit > 100 then
  raise exception using errcode='22023',message='INVALID_BATCH_LIMIT';
 end if;
 for v_event in
  select e.id from public.business_events e
  where e.event_type in ('task_first_submitted_late','task_responsibility_abandoned')
    and not exists(select 1 from public.penalty_event_consumptions c where c.source_event_id=e.id)
    and not exists(select 1 from private.followup_g_penalty_dispatch_faults f where f.source_event_id=e.id)
  order by e.id
  limit p_batch_limit
  for update of e skip locked
 loop
  v_result:=public.process_contribution_penalty_event_service(v_event.id);
  v_processed:=v_processed+1;
  if v_result->>'ok'='true' then
   if v_result->>'disposition'='assessed' then
    v_assessed:=v_assessed+1;
   elsif v_result->>'disposition'='skipped' then
    v_skipped:=v_skipped+1;
   end if;
  else
   insert into private.followup_g_penalty_dispatch_faults(source_event_id,last_error)
   values(v_event.id,coalesce(v_result->>'code','UNKNOWN_RESULT'))
   on conflict(source_event_id) do update
   set last_error=excluded.last_error,last_seen_at=transaction_timestamp();
   v_quarantined:=v_quarantined+1;
  end if;
 end loop;
 return jsonb_build_object('ok',true,'processed',v_processed,
   'assessed',v_assessed,'skipped',v_skipped,'quarantined',v_quarantined);
end;
$$;
revoke all on function public.dispatch_contribution_penalty_events_service(integer)
  from public,anon,authenticated,service_role;
grant execute on function public.dispatch_contribution_penalty_events_service(integer) to service_role;
