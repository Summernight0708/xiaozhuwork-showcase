-- Align authenticated Storage INSERT with the existing task-upload reservation contract.
-- Accepted task collaborators are authorized upload actors, but the historical
-- Storage policy only admitted primary assignees, creators, and project leaders.
-- This is an additive policy correction: no direct reservation writes, no
-- pending/observer/outsider access, and no change to read/update/delete policies.
drop policy if exists teamup_files_insert_reserved on storage.objects;
create policy teamup_files_insert_reserved
on storage.objects for insert to authenticated
with check (
  bucket_id = 'teamup-files'
  and exists (
    select 1
    from public.file_upload_reservations r
    join public.project_members pm
      on pm.project_id = r.project_id
      and pm.user_id = (select auth.uid())
      and pm.member_state = 'active'
      and pm.role <> 'observer'
    join public.tasks t
      on t.project_id = r.project_id
      and t.id = r.task_id
    where r.object_path = name
      and r.actor_id = (select auth.uid())
      and r.state = 'reserved'
      and r.expires_at > now()
      and (
        t.assignee_id = (select auth.uid())
        or t.created_by = (select auth.uid())
        or pm.role = 'leader'
        or exists (
          select 1
          from public.task_collaborators c
          where c.project_id = r.project_id
            and c.task_id = r.task_id
            and c.user_id = (select auth.uid())
            and c.state = 'accepted'
        )
      )
  )
);
