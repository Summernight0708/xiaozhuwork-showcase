-- F2: preserve Storage authorization after revoking direct reservation actor PII.
-- A storage.objects RLS policy previously SELECTed file_upload_reservations
-- as authenticated. F2 forbids that raw actor_id SELECT; restore the EXACT
-- role + assignment + reservation predicate behind a no-PII SECURITY DEFINER
-- boolean helper, not by granting back broad table privileges.

create function public.teamup_storage_reserved_upload_allowed(p_object_path text)
returns boolean
language sql stable security definer set search_path=''
as $$
  select auth.uid() is not null
    and public.account_lifecycle_access_allowed(auth.uid())
    and exists (
      select 1
      from public.file_upload_reservations r
      join public.project_members pm
        on pm.project_id=r.project_id and pm.user_id=auth.uid()
        and pm.member_state='active' and pm.role<>'observer'
      join public.tasks t on t.project_id=r.project_id and t.id=r.task_id
      where r.object_path=p_object_path
        and r.actor_id=auth.uid()
        and r.state='reserved'
        and r.expires_at>transaction_timestamp()
        and (
          t.assignee_id=auth.uid() or t.created_by=auth.uid()
          or pm.role='leader'
          or exists(
            select 1 from public.task_collaborators c
            where c.project_id=r.project_id and c.task_id=r.task_id
              and c.user_id=auth.uid() and c.state='accepted'
          )
        )
    );
$$;
revoke all on function public.teamup_storage_reserved_upload_allowed(text)
 from public,anon,authenticated,service_role;
grant execute on function public.teamup_storage_reserved_upload_allowed(text)
 to authenticated;

alter policy teamup_files_insert_reserved on storage.objects
 with check (
   bucket_id='teamup-files'
   and public.teamup_storage_reserved_upload_allowed(name)
 );

-- The other INSERT policy teamup_files_reject_archived_upload remains
-- unchanged and still requires an active unarchived reservation. Neither
-- helper exposes identity fields nor permits users to SELECT original rows.
comment on function public.teamup_storage_reserved_upload_allowed(text) is
 'Server-evaluated original Storage reservation+responsibility predicate. Boolean only, no PII, project membership and lifecycle enforced.';
