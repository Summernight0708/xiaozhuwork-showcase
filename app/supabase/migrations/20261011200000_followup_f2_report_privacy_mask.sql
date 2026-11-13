-- F2: Non-destructive account privacy mask for authorized contribution exports.
-- Formal snapshots remain immutable; Auth, JSON, Storage and backups require separate review.
create function private.f2_mask_report_members(p_items jsonb)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_item jsonb;v_result jsonb:='[]'::jsonb;v_member uuid;v_id text;
begin
  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array' then return p_items; end if;
  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    v_id:=v_item->>'memberUserId';
    v_member:=null;
    if v_id is not null and v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_member:=v_id::uuid;
    end if;
    if v_member is not null and exists(
      select 1 from public.account_lifecycle_requests l
      where l.user_id=v_member and l.state in ('pending','blocked','redacted')
    ) then
      v_item:=pg_catalog.jsonb_set(v_item,'{memberDisplayName}',
        pg_catalog.to_jsonb('已注销成员'::text),true);
    end if;
    v_result:=v_result||pg_catalog.jsonb_build_array(v_item);
  end loop;
  return v_result;
end;
$$;
revoke all on function private.f2_mask_report_members(jsonb)
 from public,anon,authenticated,service_role;

-- Rename the final G report implementation; never expose the raw name-bearing
-- SECURITY DEFINER RPC to authenticated users, including via a legacy helper.
alter function public.get_project_report_export(uuid)
 rename to get_project_report_export_f2_unmasked;
revoke all on function public.get_project_report_export_f2_unmasked(uuid)
 from public,anon,authenticated,service_role;
create function public.get_project_report_export(p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  v_result:=public.get_project_report_export_f2_unmasked(p_report_id);
  if v_result is null or pg_catalog.jsonb_typeof(v_result)<>'object'
    or v_result ? 'code' or pg_catalog.jsonb_typeof(v_result->'items')<>'array' then
    return v_result;
  end if;
  return pg_catalog.jsonb_set(v_result,'{items}',
    private.f2_mask_report_members(v_result->'items'),false);
end;
$$;
revoke all on function public.get_project_report_export(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_project_report_export(uuid) to authenticated;
comment on function public.get_project_report_export(uuid) is
 'Basic and enhanced export source: masks pending/blocked member names without modifying signed numeric history. Not complete account erasure.';

-- The two raw contribution snapshot tables expose identifying snapshots via
-- SELECT even when the export RPC is masked. Retain read access to numeric
-- fields but forbid ordinary clients from selecting original member names.
revoke select on public.contribution_items from authenticated;
grant select(
  id,report_id,project_id,task_id,member_user_id,task_weight,share,
  contribution_value,task_title_snapshot,completed_at_snapshot,created_at
) on public.contribution_items to authenticated;

revoke select on public.contribution_report_member_ledger_entries from authenticated;
grant select(
  id,report_id,project_id,task_id,member_user_id,entry_type,entry_id,
  task_title_snapshot,task_weight,share,signed_amount,completed_at_snapshot,captured_at
) on public.contribution_report_member_ledger_entries to authenticated;
