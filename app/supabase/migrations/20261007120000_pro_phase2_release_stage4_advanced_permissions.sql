-- G Stage 4: publish advanced_permissions only.
-- Fail closed unless the previous staged release is exactly in place.
do $$
begin
  if not (
    private.capability_is_released('file_full_history')
    and private.capability_is_released('file_batch_rollback')
    and private.capability_is_released('file_version_compare')
    and private.capability_is_released('project_recovery_point')
    and private.capability_is_released('file_large_upload')
    and private.capability_is_released('project_storage_quota')
    and private.capability_is_released('enhanced_report')
  ) then
    raise exception 'PHASE2_RELEASE_PRECONDITION_FAILED: Stage 4 prior capability set is incomplete';
  end if;

  if (
    private.capability_is_released('advanced_permissions')
    or private.capability_is_released('project_analytics')
    or private.capability_is_released('external_integrations')
    or private.capability_is_released('cross_project_overview')
    or private.capability_is_released('cross_project_analytics')
  ) then
    raise exception 'PHASE2_RELEASE_PRECONDITION_FAILED: Stage 4 current/future capability already released';
  end if;
end;
$$;

create or replace function private.capability_is_released(
  p_capability text
) returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    p_capability = any(array[
      'file_full_history',
      'file_batch_rollback',
      'file_version_compare',
      'project_recovery_point',
      'file_large_upload',
      'project_storage_quota',
      'enhanced_report',
      'advanced_permissions'
    ]::text[]),
    false
  );
$$;

revoke all on function private.capability_is_released(text)
from public, anon, authenticated, service_role;

comment on function private.capability_is_released(text)
is 'G-owned staged release registry. Stage 4 publishes advanced_permissions; unknown and unreleased codes fail closed.';
