-- G lifecycle authority: forbid old JWT membership reads through all shared
-- SECURITY DEFINER helper functions (not just private.is_active_member).
create or replace function private.is_active_leader(
  p_project_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_active_member(p_project_id,p_user_id) and exists(
   select 1 from public.project_members pm
   where pm.project_id=p_project_id and pm.user_id=p_user_id
     and pm.role='leader' and pm.member_state='active'
 );
$$;

create or replace function private.is_active_non_observer_member(
  p_project_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_active_member(p_project_id,p_user_id) and exists(
   select 1 from public.project_members pm
   where pm.project_id=p_project_id and pm.user_id=p_user_id
     and pm.member_state='active' and pm.role<>'observer'
     and pm.is_observer is false
 );
$$;

create or replace function public.is_active_project_member(target_project_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.is_active_member(target_project_id,(select auth.uid()));
$$;

-- The response used by a pending account should stay accessible so the user
-- can understand and (before Auth revocation) cancel the request. Nothing
-- here enables permanent cleanup or redaction.
