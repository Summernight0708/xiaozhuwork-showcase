-- F2: wrap existing authorized file JSON RPCs to eliminate raw name
-- bypasses through SECURITY DEFINER data serialization. Preserve original
-- task membership, version-history entitlement and dependency authorization.
create function private.f2_mask_file_payload(p_input jsonb)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
  v_item jsonb;v_out jsonb;v_pair record;
  v_subject uuid;v_id text;v_key text;
begin
  if p_input is null then return null; end if;
  if jsonb_typeof(p_input)='array' then
    v_out:='[]'::jsonb;
    for v_item in select value from jsonb_array_elements(p_input) loop
      v_out:=v_out||jsonb_build_array(private.f2_mask_file_payload(v_item));
    end loop;
    return v_out;
  end if;
  if jsonb_typeof(p_input)<>'object' then return p_input; end if;
  v_out:='{}'::jsonb;
  for v_pair in select key,value from jsonb_each(p_input) loop
    v_out:=jsonb_set(v_out,array[v_pair.key],
      private.f2_mask_file_payload(v_pair.value),true);
  end loop;
  -- Use actual file/version authority, never a user-submitted uploader id.
  v_id:=v_out->>'fileVersionId';
  if v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select fv.uploaded_by into v_subject from public.task_file_versions fv
      where fv.id=v_id::uuid;
    if v_subject is not null and exists(select 1 from public.account_lifecycle_requests l
      where l.user_id=v_subject and l.state in ('pending','blocked','redacted')) then
      if v_out ? 'originalName' then
        v_out:=jsonb_set(v_out,'{originalName}',to_jsonb('已注销成员文件'::text),true);
      end if;
      if v_out ? 'uploadedBy' then v_out:=jsonb_set(v_out,'{uploadedBy}','null'::jsonb,true); end if;
    end if;
  end if;
  v_id:=v_out->>'fileId';
  if v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select f.created_by into v_subject from public.task_files f where f.id=v_id::uuid;
    if v_subject is not null and exists(select 1 from public.account_lifecycle_requests l
      where l.user_id=v_subject and l.state in ('pending','blocked','redacted')) then
      if v_out ? 'logicalName' then
        v_out:=jsonb_set(v_out,'{logicalName}',to_jsonb('已注销成员文件'::text),true);
      end if;
      if v_out ? 'createdBy' then v_out:=jsonb_set(v_out,'{createdBy}','null'::jsonb,true); end if;
    end if;
  end if;
  return v_out;
end;
$$;
revoke all on function private.f2_mask_file_payload(jsonb)
 from public,anon,authenticated,service_role;

alter function public.get_task_files(uuid) rename to get_task_files_f2_unmasked;
revoke all on function public.get_task_files_f2_unmasked(uuid)
 from public,anon,authenticated,service_role;
create function public.get_task_files(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  return private.f2_mask_file_payload(public.get_task_files_f2_unmasked(p_task_id));
end;
$$;
revoke all on function public.get_task_files(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_task_files(uuid) to authenticated;

alter function public.get_task_file_history(uuid,integer,integer)
 rename to get_task_file_history_f2_unmasked;
revoke all on function public.get_task_file_history_f2_unmasked(uuid,integer,integer)
 from public,anon,authenticated,service_role;
create function public.get_task_file_history(
 p_file_id uuid,p_limit integer default 50,p_before_version integer default null
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  return private.f2_mask_file_payload(
    public.get_task_file_history_f2_unmasked(p_file_id,p_limit,p_before_version));
end;
$$;
revoke all on function public.get_task_file_history(uuid,integer,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.get_task_file_history(uuid,integer,integer)
 to authenticated;

alter function public.get_upstream_artifacts(uuid)
 rename to get_upstream_artifacts_f2_unmasked;
revoke all on function public.get_upstream_artifacts_f2_unmasked(uuid)
 from public,anon,authenticated,service_role;
create function public.get_upstream_artifacts(p_downstream_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  return private.f2_mask_file_payload(
    public.get_upstream_artifacts_f2_unmasked(p_downstream_task_id));
end;
$$;
revoke all on function public.get_upstream_artifacts(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_upstream_artifacts(uuid) to authenticated;
