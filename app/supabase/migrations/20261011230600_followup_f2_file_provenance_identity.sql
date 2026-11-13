-- F2: file provenance IDs must not bypass lifecycle privacy masking.
-- Preserve immutable uploaded_by / created_by in trusted SQL facts.
-- Normal project members retain their own metadata, version and object path.
-- An account with pending/blocked/redacted deletion is not reidentified via
-- raw column SELECT or through otherwise-safe project-scoped file views.

create or replace view public.task_files_visible
with(security_barrier=true) as
select t.id,t.project_id,t.task_id,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.created_by and l.state in('pending','blocked','redacted'))
    then '已注销成员文件'::text else t.logical_name end as logical_name,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.created_by and l.state in('pending','blocked','redacted'))
    then null::uuid else t.created_by end as created_by,
  t.current_version_id,t.version,t.created_at,t.updated_at
from public.task_files t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);

create or replace view public.task_file_versions_visible
with(security_barrier=true) as
select t.id,t.file_id,t.project_id,t.task_id,t.reservation_id,
  t.version_number,t.object_path,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.uploaded_by and l.state in('pending','blocked','redacted'))
    then '已注销成员文件'::text else t.original_name end as original_name,
  t.mime_type,t.size_bytes,t.sha256_hex,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.uploaded_by and l.state in('pending','blocked','redacted'))
    then null::uuid else t.uploaded_by end as uploaded_by,
  t.restored_from_version_id,t.created_at
from public.task_file_versions t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and public.is_active_project_member(t.project_id);

create or replace view public.file_upload_reservations_visible
with(security_barrier=true) as
select t.id,t.project_id,t.task_id,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.actor_id and l.state in('pending','blocked','redacted'))
    then null::uuid else t.actor_id end as actor_id,
  t.mode,t.target_file_id,t.target_file_version,t.object_path,
  case when exists(select 1 from public.account_lifecycle_requests l
    where l.user_id=t.actor_id and l.state in('pending','blocked','redacted'))
    then '已注销成员文件'::text else t.original_name end as original_name,
  t.declared_mime_type,t.declared_size_bytes,t.state,t.rejection_code,
  t.expires_at,t.version,t.created_at,t.updated_at,t.reserved_envelope_bytes
from public.file_upload_reservations t
where auth.uid() is not null
  and public.account_lifecycle_access_allowed(auth.uid())
  and exists(select 1 from public.project_members pm
    where pm.project_id=t.project_id
      and pm.user_id=auth.uid() and pm.member_state='active'
      and (pm.role='leader' or t.actor_id=auth.uid()));

-- Column grants, not just RLS, stop direct SELECT of unsanitized actor IDs.
revoke select on public.task_files from authenticated;
grant select(id,project_id,task_id,current_version_id,version,created_at,updated_at)
  on public.task_files to authenticated;
revoke select on public.task_file_versions from authenticated;
grant select(id,file_id,project_id,task_id,reservation_id,version_number,
 object_path,mime_type,size_bytes,sha256_hex,restored_from_version_id,created_at)
  on public.task_file_versions to authenticated;
revoke select on public.file_upload_reservations from authenticated;
grant select(id,project_id,task_id,mode,target_file_id,target_file_version,
 object_path,declared_mime_type,declared_size_bytes,state,rejection_code,
 expires_at,version,created_at,updated_at,reserved_envelope_bytes)
 on public.file_upload_reservations to authenticated;
revoke select on public.project_recovery_point_file_items from authenticated;
grant select(id,recovery_point_id,project_id,task_id,file_id,
 captured_file_version_id,captured_file_version_number,
 captured_file_version_created_at,captured_object_path,captured_mime_type,
 captured_size_bytes,captured_sha256_hex,captured_file_row_version,
 captured_is_final,captured_final_designation_version,captured_at)
 on public.project_recovery_point_file_items to authenticated;

comment on view public.task_file_versions_visible is
 'Membership-scoped file version view; redacts uploading member UUID and original filename during active deletion. Storage content and old signed URLs require separate release review.';
