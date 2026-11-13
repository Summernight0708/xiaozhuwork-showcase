-- G: fail-closed archived-project write barrier across legacy RPCs, tables and uploads.
-- Enforced below SECURITY DEFINER commands, so older commands cannot silently mutate archived projects.
create function private.followup_reject_archived_project_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_old_project_id uuid;
  v_new_project_id uuid;
  v_archived timestamptz;
begin
  if tg_op <> 'INSERT' then
    v_old_project_id := old.project_id;
  end if;
  if tg_op <> 'DELETE' then
    v_new_project_id := new.project_id;
  end if;
  if v_old_project_id is not null then
    select p.archived_at into v_archived
      from public.projects p where p.id=v_old_project_id for share;
    if v_archived is not null then
      raise exception using errcode='P0001', message='PROJECT_NOT_ACTIVE';
    end if;
  end if;
  if v_new_project_id is not null and v_new_project_id is distinct from v_old_project_id then
    select p.archived_at into v_archived
      from public.projects p where p.id=v_new_project_id for share;
    if v_archived is not null then
      raise exception using errcode='P0001', message='PROJECT_NOT_ACTIVE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.followup_reject_archived_project_write() from public,anon,authenticated,service_role;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'tasks','task_dependencies','task_assignment_offers','task_change_proposals',
    'task_collaborators','task_primary_handoffs','task_help_requests','upstream_rework_requests',
    'task_review_rounds','task_review_round_files',
    'task_files','task_file_versions','task_file_final_designations','file_upload_reservations',
    'file_version_withdrawals','task_artifact_bindings','task_artifact_binding_history',
    'project_members','project_invitations','project_join_requests','project_permission_delegations',
    'project_calendar_subscriptions','project_recovery_points',
    'project_recovery_point_file_items','project_recovery_point_restore_items',
    'contribution_reports','contribution_items','contribution_confirmations',
    'task_external_evidence','task_external_evidence_revisions',
    'task_share_proposals','task_share_allocations','task_contribution_ledger',
    'contribution_penalty_appeals','contribution_appeal_votes',
    'contribution_penalty_adjustments','contribution_penalties','penalty_event_consumptions',
    'task_nudge_logs','task_reminder_jobs','task_reminder_deadlines','task_reminder_preferences',
    'task_responsibility_epochs','task_first_submission_facts'
  ] loop
    execute format('create trigger g_archived_write_reject
       before insert or update or delete on public.%I
       for each row execute function private.followup_reject_archived_project_write()',v_table);
  end loop;
end;
$$;

-- Legacy settings RPCs update projects directly, without touching a child table.
-- The archive command and restore command themselves must still be allowed.
create function private.followup_reject_archived_project_update()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.archived_at is not null and new.archived_at is not null
     and (to_jsonb(new) - 'version' - 'updated_at') is distinct from
         (to_jsonb(old) - 'version' - 'updated_at') then
    raise exception using errcode='P0001',message='PROJECT_NOT_ACTIVE';
  end if;
  return new;
end;
$$;
revoke all on function private.followup_reject_archived_project_update() from public,anon,authenticated,service_role;
create trigger g_archived_project_update_reject
before update on public.projects
for each row execute function private.followup_reject_archived_project_update();

-- Restrictive Storage policies are evaluated under authenticated RLS,
-- so a narrowly scoped definer predicate checks the reservation/project.
create function public.teamup_active_upload_reservation(p_object_path text)
returns boolean stable language sql security definer set search_path='' as $$
  select exists(
    select 1 from public.file_upload_reservations r
    join public.projects p on p.id=r.project_id
    where r.object_path=p_object_path and r.actor_id=(select auth.uid())
      and r.state='reserved' and r.expires_at>transaction_timestamp()
      and p.archived_at is null and p.lifecycle_state='active'
  );
$$;
revoke all on function public.teamup_active_upload_reservation(text) from public,anon,authenticated,service_role;
grant execute on function public.teamup_active_upload_reservation(text) to authenticated;
create policy teamup_files_reject_archived_upload
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'teamup-files' or
  public.teamup_active_upload_reservation(name)
);
