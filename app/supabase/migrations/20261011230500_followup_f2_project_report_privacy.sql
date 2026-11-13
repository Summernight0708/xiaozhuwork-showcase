-- F2: close the older project-level contribution-report read boundary.
-- The formal CSV/PDF export was already masked but the project report's
-- memberUserId could still be read directly via this public RPC.
-- Preserve original project authorization, report state and numeric ledger.
alter function public.get_project_contribution_report(uuid)
 rename to get_project_contribution_report_f2_unmasked;
revoke all on function public.get_project_contribution_report_f2_unmasked(uuid)
 from public,anon,authenticated,service_role;

create function public.get_project_contribution_report(p_project_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_payload jsonb;
begin
  v_payload := public.get_project_contribution_report_f2_unmasked(p_project_id);
  if v_payload is null
    or pg_catalog.jsonb_typeof(v_payload) <> 'object'
    or v_payload ? 'code'
    or pg_catalog.jsonb_typeof(v_payload->'items') <> 'array'
  then
    return v_payload;
  end if;
  return pg_catalog.jsonb_set(
    v_payload,'{items}',private.f2_mask_report_members(v_payload->'items'),false
  );
end;
$$;
revoke all on function public.get_project_contribution_report(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_project_contribution_report(uuid)
 to authenticated;
comment on function public.get_project_contribution_report(uuid) is
 'Authorized draft/formal project contribution reader: hides lifecycle-subject user IDs and labels without altering immutable values; full erasure not implied.';
