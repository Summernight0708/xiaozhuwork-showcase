-- G: fail-closed Auth token -> business command authority after a request.
-- This barrier sits below all existing SECURITY DEFINER commands that claim
-- an idempotent command and preserves the F cancellation recovery path.
create function private.g_account_lifecycle_claim_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.command_name not in ('cmd_request_account_deletion','cmd_cancel_account_deletion')
     and exists(
       select 1 from public.account_lifecycle_requests l
       where l.user_id=new.actor_id and l.state <> 'canceled'
     ) then
    raise exception using errcode='42501',message='ACCOUNT_ACCESS_DISABLED';
  end if;
  return new;
end;
$$;
revoke all on function private.g_account_lifecycle_claim_guard()
 from public,anon,authenticated,service_role;
create trigger g_account_lifecycle_claim_guard
before insert on public.command_requests
for each row execute function private.g_account_lifecycle_claim_guard();

-- Legacy SECURITY DEFINER readers often delegate to this membership helper.
create or replace function private.is_active_member(p_project_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select not exists(
    select 1 from public.account_lifecycle_requests l
    where l.user_id=p_user_id and l.state<>'canceled'
  ) and exists(
    select 1 from public.project_members pm
    where pm.project_id=p_project_id and pm.user_id=p_user_id
      and pm.member_state='active'
  );
$$;

-- Protect the Storage version signing predicate from old valid JWTs.
create or replace function public.teamup_visible_file_version_object(p_path text)
returns boolean stable language sql security definer set search_path='' as $$
  select public.account_lifecycle_access_allowed(auth.uid()) and exists(
    select 1 from public.task_file_versions v
    where v.object_path=p_path
      and public.is_active_project_member(v.project_id)
      and not exists(
        select 1 from public.file_version_withdrawals w
        where w.file_version_id=v.id
      )
  );
$$;
