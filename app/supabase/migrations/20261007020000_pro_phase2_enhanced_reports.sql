-- B: read-only Pro enhanced exports; existing contribution report and base export are untouched.
create function public.get_enhanced_project_report_export(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_project_id uuid;
  v_report_state text;
  v_gate jsonb;
  v_snapshot jsonb;
begin
  if v_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;

  if p_report_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'reportId');
  end if;

  -- Business authorization MUST precede the commercial gate. A missing
  -- report, inactive member and external member share one indistinguishable
  -- result (including when the capability remains unpublished).
  select r.project_id, r.state
    into v_project_id, v_report_state
    from public.contribution_reports r
    where r.id = p_report_id;

  if v_project_id is null
     or not private.is_active_member(v_project_id, v_actor) then
    return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_gate := private.project_capability_failure(
    v_project_id, 'enhanced_report', null
  );
  if v_gate is not null then
    return v_gate;
  end if;

  if v_report_state <> 'formal' then
    return private.failure(null, 'REPORT_NOT_READY');
  end if;

  -- Preserve the exact exported V1 snapshot, including original task
  -- weights, shares, provenance fields and immutable report metadata.
  v_snapshot := public.get_project_report_export(p_report_id);
  if v_snapshot is null
     or jsonb_typeof(v_snapshot) <> 'object'
     or v_snapshot ? 'code'
     or v_snapshot->>'reportId' is distinct from p_report_id::text
     or v_snapshot->>'projectId' is distinct from v_project_id::text
     or v_snapshot->>'reportState' is distinct from 'formal'
     or v_snapshot->>'schemaVersion' is distinct from '1' then
    return private.failure(null, 'SERVICE_UNAVAILABLE');
  end if;

  return jsonb_build_object(
    'ok', true,
    'schemaVersion', 1,
    'reportId', p_report_id,
    'projectId', v_project_id,
    'snapshot', v_snapshot
  );
end;
$$;

revoke all on function public.get_enhanced_project_report_export(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_enhanced_project_report_export(uuid)
  to authenticated;

comment on function public.get_enhanced_project_report_export(uuid) is
  'Pro Phase 2 B: end-user authorized, formal-only immutable contribution snapshot; release gated.';
