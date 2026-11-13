-- Version-level final-file semantics without mutating immutable file-version rows.

create table public.task_file_final_designations (
  file_version_id uuid primary key references public.task_file_versions(id) on delete restrict,
  file_id uuid not null,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  is_final boolean not null default true,
  version integer not null default 1,
  marked_by uuid references auth.users(id) on delete set null,
  marked_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  foreign key(project_id,task_id,file_id)
    references public.task_files(project_id,task_id,id) on delete cascade,
  foreign key(file_id,file_version_id)
    references public.task_file_versions(file_id,id) on delete restrict,
  constraint task_file_final_designations_version check (version > 0),
  constraint task_file_final_designations_mark_state check (
    (is_final and marked_at is not null) or (not is_final and marked_at is null)
  )
);

create index task_file_final_designations_project_idx
  on public.task_file_final_designations(project_id,is_final,file_version_id);
create index task_file_final_designations_task_idx
  on public.task_file_final_designations(task_id,is_final,file_version_id);

alter table public.task_file_final_designations enable row level security;
create policy task_file_final_designations_select_member
on public.task_file_final_designations for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_file_final_designations from public,anon,authenticated,service_role;
grant select on public.task_file_final_designations to authenticated;

create function public.cmd_set_task_file_version_final(
  p_project_id uuid,
  p_file_version_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_is_final boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_file_version public.task_file_versions%rowtype;
  v_task public.tasks%rowtype;
  v_designation public.task_file_final_designations%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'fileVersionId',p_file_version_id,
    'expectedVersion',p_expected_version,'isFinal',p_is_final
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_set_task_file_version_final',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  if not private.is_active_leader(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_file_version
  from public.task_file_versions fv
  where fv.id=p_file_version_id and fv.project_id=p_project_id
  for update;
  if v_file_version.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_task
  from public.tasks t
  where t.id=v_file_version.task_id and t.project_id=p_project_id
  for update;

  select * into v_designation
  from public.task_file_final_designations d
  where d.file_version_id=p_file_version_id
  for update;

  if p_is_final is null then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','isFinal');
  elsif v_project.lifecycle_state='completed'
     or exists(
       select 1 from public.contribution_reports r
       where r.project_id=p_project_id and r.state='formal'
     ) then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,
      case when v_designation.file_version_id is null then 0 else v_designation.version end,
      jsonb_build_object('reason','formal_report_locked')
    );
  elsif v_task.status<>'completed' then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,
      case when v_designation.file_version_id is null then 0 else v_designation.version end,
      jsonb_build_object('reason','task_not_completed')
    );
  elsif v_designation.file_version_id is null and coalesce(p_expected_version,-1)<>0 then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,0);
  elsif v_designation.file_version_id is not null
        and (p_expected_version is null or v_designation.version<>p_expected_version) then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_designation.version);
  elsif v_designation.file_version_id is null and not p_is_final then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,0,jsonb_build_object('reason','not_currently_final')
    );
  elsif v_designation.file_version_id is not null and v_designation.is_final=p_is_final then
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'fileVersionId',v_file_version.id,'fileId',v_file_version.file_id,
        'taskId',v_file_version.task_id,'isFinal',v_designation.is_final,
        'designationVersion',v_designation.version,'changed',false
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','task_file_final_designation',
      'aggregateId',v_file_version.id,'aggregateVersion',v_designation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_file_final_designation',v_file_version.id,v_designation.version
    );
  else
    if v_designation.file_version_id is null then
      insert into public.task_file_final_designations(
        file_version_id,file_id,project_id,task_id,is_final,version,marked_by,marked_at,updated_by
      ) values(
        v_file_version.id,v_file_version.file_id,p_project_id,v_file_version.task_id,true,1,
        v_actor,now(),v_actor
      ) returning * into v_designation;
    else
      update public.task_file_final_designations
      set is_final=p_is_final,
          version=version+1,
          marked_by=case when p_is_final then v_actor else null end,
          marked_at=case when p_is_final then now() else null end,
          updated_by=v_actor,
          updated_at=now()
      where file_version_id=p_file_version_id
      returning * into v_designation;
    end if;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      case when p_is_final then 'task_file_version_final_marked' else 'task_file_version_final_unmarked' end,
      'task_file_version',p_file_version_id,p_request_id,
      jsonb_build_object(
        'fileId',v_file_version.file_id,'taskId',v_file_version.task_id,
        'designationVersion',v_designation.version
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'fileVersionId',v_file_version.id,'fileId',v_file_version.file_id,
        'taskId',v_file_version.task_id,'isFinal',v_designation.is_final,
        'designationVersion',v_designation.version,'changed',true
      ),
      'requestId',p_request_id,'replayed',false,'aggregateType','task_file_final_designation',
      'aggregateId',v_file_version.id,'aggregateVersion',v_designation.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'task_file_final_designation',v_file_version.id,v_designation.version
    );
  end if;

  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_set_task_file_version_final(uuid,uuid,uuid,integer,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_set_task_file_version_final(uuid,uuid,uuid,integer,boolean)
  to authenticated;

comment on table public.task_file_final_designations is
  'Mutable audited designation state for immutable task-file versions. Multiple versions may be final; new uploads never change existing designations.';
