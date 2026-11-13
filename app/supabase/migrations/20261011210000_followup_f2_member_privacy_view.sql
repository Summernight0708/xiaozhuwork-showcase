-- F2: preserve immutable rows while redacting retired identities at read boundaries.
-- Every browser-visible membership reader moves to a guarded view. Do not grant
-- original snapshot columns directly to authenticated clients.
create view public.project_members_visible with (security_barrier=true)
as
select m.id,m.project_id,
       m.user_id,m.role,m.member_state,m.is_observer,m.joined_at,m.departed_at,
       case when l.state in ('pending','blocked','redacted')
         then '已注销成员'::text else m.display_name_snapshot end as display_name_snapshot,
       m.created_at,m.version
from public.project_members m
left join public.account_lifecycle_requests l on l.user_id=m.user_id
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(m.project_id);
revoke all on public.project_members_visible from public,anon,authenticated,service_role;
grant select on public.project_members_visible to authenticated;

-- Column-privilege enforcement blocks direct REST SELECT of the historical name
-- even if old RLS policies continue granting row visibility.
revoke select on public.project_members from authenticated;
grant select(id,project_id,user_id,role,member_state,is_observer,joined_at,
             departed_at,created_at,version)
on public.project_members to authenticated;
comment on view public.project_members_visible is
 'Project-member reads for active project viewers; member snapshots redacted at presentation time for account lifecycle requests.';

-- A UUID is also an indirect personal identifier. Public report exports have
-- no need to carry deleted members' stable Auth UUIDs.
create or replace function private.f2_mask_report_members(p_items jsonb)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_item jsonb;v_result jsonb:='[]'::jsonb;v_member uuid;v_id text;
begin
  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array' then return p_items; end if;
  for v_item in select value from pg_catalog.jsonb_array_elements(p_items) loop
    v_id:=v_item->>'memberUserId';
    v_member:=null;
    if v_id is not null and v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_member:=v_id::uuid; end if;
    if v_member is not null and exists(
      select 1 from public.account_lifecycle_requests l
      where l.user_id=v_member and l.state in ('pending','blocked','redacted')
    ) then
      v_item:=pg_catalog.jsonb_set(
        pg_catalog.jsonb_set(v_item,'{memberDisplayName}',
          pg_catalog.to_jsonb('已注销成员'::text),true),
        '{memberUserId}','null'::jsonb,true);
    end if;
    v_result:=v_result||pg_catalog.jsonb_build_array(v_item);
  end loop;
  return v_result;
end;
$$;
revoke all on function private.f2_mask_report_members(jsonb)
 from public,anon,authenticated,service_role;

-- Prevent reading the same indirect identity from raw report tables.
revoke select on public.contribution_items from authenticated;
grant select(id,report_id,project_id,task_id,task_weight,share,
 contribution_value,task_title_snapshot,completed_at_snapshot,created_at)
 on public.contribution_items to authenticated;
revoke select on public.contribution_report_member_ledger_entries from authenticated;
grant select(id,report_id,project_id,task_id,entry_type,entry_id,
 task_title_snapshot,task_weight,share,signed_amount,completed_at_snapshot,captured_at)
 on public.contribution_report_member_ledger_entries to authenticated;
