-- G: keep service_role away from private schema while retaining exactly-once E consumption.
-- Only the public service-only dispatcher can invoke the private E worker.
create function public.process_contribution_penalty_event_service(
  p_source_event_id bigint
) returns jsonb
language plpgsql security definer set search_path=''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
  end if;

  if p_source_event_id is null then
    return jsonb_build_object('ok',false,'code','SOURCE_NOT_FOUND');
  end if;

  return private.process_contribution_penalty_event(p_source_event_id);
end;
$$;

revoke all on function public.process_contribution_penalty_event_service(bigint)
  from public, anon, authenticated;
grant execute on function public.process_contribution_penalty_event_service(bigint)
  to service_role;

-- The E branch temporarily exposed the whole schema for its worker.
-- Remove that broad grant once the narrowly-scoped public entry point exists.
revoke execute on function private.process_contribution_penalty_event(bigint)
  from service_role;
revoke usage on schema private from service_role;
