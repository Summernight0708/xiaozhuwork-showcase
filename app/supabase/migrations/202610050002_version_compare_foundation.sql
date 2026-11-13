create function private.is_text_like_task_file_mime(p_mime text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_mime, '')) in (
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/json',
    'application/xml',
    'text/xml',
    'text/css',
    'text/javascript',
    'application/javascript',
    'text/typescript',
    'application/typescript'
  );
$$;

create function private.task_file_version_metadata_json(
  p_version public.task_file_versions,
  p_file public.task_files
) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'fileVersionId', p_version.id,
    'fileId', p_version.file_id,
    'taskId', p_version.task_id,
    'logicalName', p_file.logical_name,
    'versionNumber', p_version.version_number,
    'originalName', p_version.original_name,
    'mimeType', p_version.mime_type,
    'sizeBytes', p_version.size_bytes,
    'sha256Hex', p_version.sha256_hex,
    'uploadedBy', p_version.uploaded_by,
    'createdAt', p_version.created_at,
    'restoredFromVersionId', p_version.restored_from_version_id
  );
$$;

create function private.task_file_version_metadata_diff_json(
  p_base public.task_file_versions,
  p_target public.task_file_versions,
  p_base_file public.task_files,
  p_target_file public.task_files
) returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'logicalName', jsonb_build_object(
      'changed', p_base_file.logical_name is distinct from p_target_file.logical_name,
      'base', p_base_file.logical_name,
      'target', p_target_file.logical_name
    ),
    'originalName', jsonb_build_object(
      'changed', p_base.original_name is distinct from p_target.original_name,
      'base', p_base.original_name,
      'target', p_target.original_name
    ),
    'sizeBytes', jsonb_build_object(
      'changed', p_base.size_bytes is distinct from p_target.size_bytes,
      'base', p_base.size_bytes,
      'target', p_target.size_bytes,
      'delta', p_target.size_bytes - p_base.size_bytes
    ),
    'mimeType', jsonb_build_object(
      'changed', p_base.mime_type is distinct from p_target.mime_type,
      'base', p_base.mime_type,
      'target', p_target.mime_type
    ),
    'kind', jsonb_build_object(
      'changed',
        private.task_submission_file_type_from_mime(p_base.mime_type)
        is distinct from private.task_submission_file_type_from_mime(p_target.mime_type),
      'base', private.task_submission_file_type_from_mime(p_base.mime_type),
      'target', private.task_submission_file_type_from_mime(p_target.mime_type)
    ),
    'uploadedBy', jsonb_build_object(
      'changed', p_base.uploaded_by is distinct from p_target.uploaded_by,
      'base', p_base.uploaded_by,
      'target', p_target.uploaded_by
    ),
    'createdAt', jsonb_build_object(
      'changed', p_base.created_at is distinct from p_target.created_at,
      'base', p_base.created_at,
      'target', p_target.created_at
    ),
    'sha256Hex', jsonb_build_object(
      'changed', p_base.sha256_hex is distinct from p_target.sha256_hex,
      'base', p_base.sha256_hex,
      'target', p_target.sha256_hex
    )
  );
$$;

create function public.cmd_compare_task_file_versions(
  p_project_id uuid,
  p_base_file_version_id uuid,
  p_target_file_version_id uuid,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_base public.task_file_versions%rowtype;
  v_target public.task_file_versions%rowtype;
  v_base_file public.task_files%rowtype;
  v_target_file public.task_files%rowtype;
  v_base_text_like boolean;
  v_target_text_like boolean;
  v_content_status text;
  v_content_reason text;
begin
  if v_actor is null then
    return private.failure(p_request_id, 'UNAUTHENTICATED');
  end if;
  if p_request_id is null then
    return private.failure(null, 'VALIDATION_FAILED', 'requestId');
  end if;
  if p_project_id is null
     or p_base_file_version_id is null
     or p_target_file_version_id is null then
    return private.failure(
      p_request_id,
      'VALIDATION_FAILED',
      case
        when p_project_id is null then 'projectId'
        when p_base_file_version_id is null then 'baseFileVersionId'
        else 'targetFileVersionId'
      end
    );
  end if;
  if not exists (select 1 from public.projects p where p.id = p_project_id) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id,
    'baseFileVersionId', p_base_file_version_id,
    'targetFileVersionId', p_target_file_version_id
  ));
  select * into v_claim
  from private.claim_command(
    v_actor,
    'cmd_compare_task_file_versions',
    p_request_id,
    v_hash,
    null,
    p_project_id
  );

  v_result := private.reject_unless_authorized(
    private.is_active_member(p_project_id, v_actor),
    p_request_id,
    v_claim.command_id,
    v_claim.prior_result,
    v_claim.payload_matches
  );
  if v_result is not null then
    return v_result;
  end if;
  v_replay := private.replay_or_reuse(
    p_request_id,
    v_claim.prior_result,
    v_claim.payload_matches
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_base
  from public.task_file_versions fv
  where fv.id = p_base_file_version_id
    and fv.project_id = p_project_id;

  select * into v_target
  from public.task_file_versions fv
  where fv.id = p_target_file_version_id
    and fv.project_id = p_project_id;

  if v_base.id is null or v_target.id is null then
    v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif v_base.file_id is distinct from v_target.file_id then
    v_result := private.failure(
      p_request_id,
      'VALIDATION_FAILED',
      null,
      null,
      jsonb_build_object('reason', 'different_logical_file')
    );
  else
    select * into v_base_file
    from public.task_files f
    where f.id = v_base.file_id
      and f.project_id = p_project_id
      and f.task_id = v_base.task_id;

    select * into v_target_file
    from public.task_files f
    where f.id = v_target.file_id
      and f.project_id = p_project_id
      and f.task_id = v_target.task_id;

    if v_base_file.id is null or v_target_file.id is null then
      v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
    else
      v_base_text_like := private.is_text_like_task_file_mime(v_base.mime_type);
      v_target_text_like := private.is_text_like_task_file_mime(v_target.mime_type);

      if v_base_text_like and v_target_text_like then
        v_content_status := 'degraded';
        v_content_reason := 'storage_content_requires_edge_orchestration';
      else
        v_content_status := 'unsupported';
        v_content_reason := 'binary_or_office_content_not_supported';
      end if;

      perform private.emit_event(
        v_claim.command_id,
        1,
        p_project_id,
        v_actor,
        'task_file_versions_compared',
        'task_file',
        v_base.file_id,
        p_request_id,
        jsonb_build_object(
          'fileId', v_base.file_id,
          'baseFileVersionId', v_base.id,
          'targetFileVersionId', v_target.id,
          'contentStatus', v_content_status
        )
      );

      v_result := jsonb_build_object(
        'ok', true,
        'data', jsonb_build_object(
          'projectId', p_project_id,
          'fileId', v_base.file_id,
          'taskId', v_base.task_id,
          'sameLogicalFile', true,
          'overallStatus',
            case when v_content_status = 'degraded' then 'degraded' else 'unsupported' end,
          'base', private.task_file_version_metadata_json(v_base, v_base_file),
          'target', private.task_file_version_metadata_json(v_target, v_target_file),
          'metadataComparison', jsonb_build_object(
            'status', 'supported',
            'diff', private.task_file_version_metadata_diff_json(
              v_base,
              v_target,
              v_base_file,
              v_target_file
            )
          ),
          'contentComparison', jsonb_build_object(
            'status', v_content_status,
            'reason', v_content_reason,
            'supportedContentTypes', jsonb_build_array(
              'text/plain',
              'text/markdown',
              'text/csv',
              'application/json',
              'application/xml',
              'text/xml',
              'text/css',
              'text/javascript',
              'application/javascript',
              'text/typescript',
              'application/typescript'
            ),
            'requires', case
              when v_content_status = 'degraded' then 'edge_orchestration'
              else null
            end
          )
        ),
        'requestId', p_request_id,
        'replayed', false,
        'aggregateType', 'task_file',
        'aggregateId', v_base.file_id,
        'aggregateVersion', v_target_file.version
      );
      return private.complete_command(
        v_claim.command_id,
        v_result,
        'task_file',
        v_base.file_id,
        v_target_file.version
      );
    end if;
  end if;

  return private.complete_command(v_claim.command_id, v_result);
end;
$$;

revoke all on function private.is_text_like_task_file_mime(text)
  from public, anon, authenticated, service_role;
revoke all on function private.task_file_version_metadata_json(
  public.task_file_versions,
  public.task_files
) from public, anon, authenticated, service_role;
revoke all on function private.task_file_version_metadata_diff_json(
  public.task_file_versions,
  public.task_file_versions,
  public.task_files,
  public.task_files
) from public, anon, authenticated, service_role;

revoke all on function public.cmd_compare_task_file_versions(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_compare_task_file_versions(uuid, uuid, uuid, uuid)
  to authenticated;

comment on function public.cmd_compare_task_file_versions(uuid, uuid, uuid, uuid) is
  'Command-style version compare foundation. It authorizes active project membership, requires both versions to belong to the same project and logical task file, returns metadata diff without exposing Storage object keys, and reports text content diff as degraded until Edge orchestration can read private Storage content.';
