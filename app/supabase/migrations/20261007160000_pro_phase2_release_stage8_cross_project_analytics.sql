-- G Stage 8: publish cross_project_analytics only.
-- Fail closed unless all prior staged releases are already in place.
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
    and private.capability_is_released('advanced_permissions')
    and private.capability_is_released('project_analytics')
    and private.capability_is_released('external_integrations')
    and private.capability_is_released('cross_project_overview')
  ) then
    raise exception 'PHASE2_RELEASE_PRECONDITION_FAILED: Stage 8 prior capability set is incomplete';
  end if;

  if private.capability_is_released('cross_project_analytics') then
    raise exception 'PHASE2_RELEASE_PRECONDITION_FAILED: Stage 8 capability already released';
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
      'advanced_permissions',
      'project_analytics',
      'external_integrations',
      'cross_project_overview',
      'cross_project_analytics'
    ]::text[]),
    false
  );
$$;

revoke all on function private.capability_is_released(text)
from public, anon, authenticated, service_role;

comment on function private.capability_is_released(text)
is 'G-owned staged release registry. Stage 8 publishes cross_project_analytics; unknown codes fail closed.';
