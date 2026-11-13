-- G: C withdrawal signing denial + narrow service-only quarantine queue.
-- A definer predicate avoids the private C policy's inaccessible helper during
-- Storage SELECT while still requiring the caller's active project membership.
create function public.teamup_visible_file_version_object(p_path text)
returns boolean stable language sql security definer set search_path='' as $$
  select exists(
    select 1 from public.task_file_versions v
    where v.object_path=p_path
      and public.is_active_project_member(v.project_id)
      and not exists(
        select 1 from public.file_version_withdrawals w where w.file_version_id=v.id
      )
  );
$$;
revoke all on function public.teamup_visible_file_version_object(text)
 from public,anon,authenticated,service_role;
grant execute on function public.teamup_visible_file_version_object(text)
 to authenticated;

-- Storage move is executed by Edge service role before C marks withdrawn.
alter policy teamup_files_select_finalized on storage.objects
using (
  bucket_id = 'teamup-files' and public.teamup_visible_file_version_object(name)
);

create function public.list_pending_file_withdrawals_service(
  p_batch_limit integer default 20
) returns table(
  withdrawal_id uuid,
  project_id uuid,
  original_path text,
  quarantine_path text
)
language plpgsql security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
  end if;
  if p_batch_limit is null or p_batch_limit<1 or p_batch_limit>100 then
    raise exception using errcode='22023',message='INVALID_BATCH_LIMIT';
  end if;
  return query select w.id,w.project_id,w.original_path,w.quarantine_path
   from public.file_version_withdrawals w
   where w.state='pending_quarantine'
   order by w.requested_at,w.id
   limit p_batch_limit;
end;
$$;
revoke all on function public.list_pending_file_withdrawals_service(integer)
 from public,anon,authenticated,service_role;
grant execute on function public.list_pending_file_withdrawals_service(integer)
 to service_role;
