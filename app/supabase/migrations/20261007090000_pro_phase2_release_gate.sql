-- G Stage 1: publish only the independently verified large-file capability.
-- The frozen Phase 2 contract forbids automatic bulk activation. Every later
-- capability requires a new forward-only G migration after its own rollout
-- approval and hosted validation.
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
      'file_large_upload'
    ]::text[]),
    false
  );
$$;

revoke all on function private.capability_is_released(text)
from public, anon, authenticated, service_role;

comment on function private.capability_is_released(text)
is 'G-owned staged release registry. Stage 1 publishes file_large_upload only; unknown and unreleased codes fail closed.';
