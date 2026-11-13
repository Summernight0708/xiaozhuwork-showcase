-- Project recovery points for file/formal-artifact version pointers only.
-- Restore is append-only: it creates new task_file_versions that reference
-- prior immutable storage objects via restored_from_version_id.
-- The shared copy-forward Storage constraints are installed by
-- 202610050001_file_history_batch_rollback.sql.

create table public.project_recovery_points (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  label text,
  scope text not null default 'project_file_pointers_v1',
  project_version integer not null,
  version integer not null default 1,
  item_count integer not null default 0,
  restored_at timestamptz,
  restored_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint project_recovery_points_scope check (scope = 'project_file_pointers_v1'),
  constraint project_recovery_points_project_version check (project_version > 0),
  constraint project_recovery_points_version check (version > 0),
  constraint project_recovery_points_item_count check (item_count >= 0),
  constraint project_recovery_points_label_length check (label is null or char_length(label) between 1 and 160)
);

create table public.project_recovery_point_file_items (
  id uuid primary key default gen_random_uuid(),
  recovery_point_id uuid not null references public.project_recovery_points(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid not null,
  file_id uuid not null,
  captured_file_version_id uuid not null,
  captured_file_version_number integer not null,
  captured_file_version_created_at timestamptz not null,
  captured_object_path text not null,
  captured_original_name text not null,
  captured_mime_type text not null,
  captured_size_bytes bigint not null,
  captured_sha256_hex text not null,
  captured_uploaded_by uuid references auth.users(id) on delete set null,
  captured_file_row_version integer not null,
  captured_is_final boolean not null default false,
  captured_final_designation_version integer,
  captured_at timestamptz not null default now(),
  foreign key(project_id,task_id,file_id)
    references public.task_files(project_id,task_id,id) on delete cascade,
  foreign key(file_id,captured_file_version_id)
    references public.task_file_versions(file_id,id) on delete restrict,
  constraint project_recovery_point_file_items_unique unique(recovery_point_id,file_id),
  constraint project_recovery_point_file_items_version_number check (captured_file_version_number > 0),
  constraint project_recovery_point_file_items_file_row_version check (captured_file_row_version > 0),
  constraint project_recovery_point_file_items_final_version check (
    (captured_is_final and captured_final_designation_version is not null and captured_final_designation_version > 0)
    or (not captured_is_final and captured_final_designation_version is null)
  )
);

create table public.project_recovery_point_restore_items (
  id uuid primary key default gen_random_uuid(),
  recovery_point_id uuid not null references public.project_recovery_points(id) on delete cascade,
  restore_request_id uuid not null,
  project_id uuid not null references public.projects(id) on delete cascade,
  file_id uuid not null,
  restored_from_version_id uuid not null,
  restored_file_version_id uuid not null,
  restored_version_number integer not null,
  restored_final_file_version_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key(file_id,restored_from_version_id)
    references public.task_file_versions(file_id,id) on delete restrict,
  foreign key(file_id,restored_file_version_id)
    references public.task_file_versions(file_id,id) on delete restrict,
  constraint project_recovery_point_restore_items_request_unique unique(recovery_point_id,restore_request_id,file_id),
  constraint project_recovery_point_restore_items_version_number check (restored_version_number > 0)
);

create index project_recovery_points_project_idx
  on public.project_recovery_points(project_id,created_at desc);
create index project_recovery_point_file_items_project_idx
  on public.project_recovery_point_file_items(project_id,recovery_point_id);
create index project_recovery_point_restore_items_project_idx
  on public.project_recovery_point_restore_items(project_id,recovery_point_id,created_at desc);

alter table public.project_recovery_points enable row level security;
alter table public.project_recovery_point_file_items enable row level security;
alter table public.project_recovery_point_restore_items enable row level security;

create policy project_recovery_points_select_member
on public.project_recovery_points for select to authenticated
using (public.is_active_project_member(project_id));

create policy project_recovery_point_file_items_select_member
on public.project_recovery_point_file_items for select to authenticated
using (public.is_active_project_member(project_id));

create policy project_recovery_point_restore_items_select_member
on public.project_recovery_point_restore_items for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.project_recovery_points,
  public.project_recovery_point_file_items,
  public.project_recovery_point_restore_items
  from public,anon,authenticated,service_role;
grant select on public.project_recovery_points,
  public.project_recovery_point_file_items,
  public.project_recovery_point_restore_items
  to authenticated;

create function public.cmd_create_project_recovery_point(
  p_project_id uuid,
  p_request_id uuid,
  p_expected_version integer,
  p_label text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_recovery_point public.project_recovery_points%rowtype;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'expectedVersion',p_expected_version,
    'label',p_label,
    'scope','project_file_pointers_v1'
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_create_project_recovery_point',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p
  where p.id=p_project_id
  for update;

  if not private.is_active_leader(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif p_label is not null and char_length(btrim(p_label)) not between 1 and 160 then
    v_result:=private.failure(p_request_id,'VALIDATION_FAILED','label');
  else
    insert into public.project_recovery_points(
      project_id,created_by,label,project_version,version
    ) values(
      p_project_id,v_actor,nullif(btrim(p_label),''),v_project.version,1
    ) returning * into v_recovery_point;

    insert into public.project_recovery_point_file_items(
      recovery_point_id,project_id,task_id,file_id,captured_file_version_id,
      captured_file_version_number,captured_file_version_created_at,
      captured_object_path,captured_original_name,captured_mime_type,
      captured_size_bytes,captured_sha256_hex,captured_uploaded_by,
      captured_file_row_version,captured_is_final,captured_final_designation_version
    )
    select
      v_recovery_point.id,f.project_id,f.task_id,f.id,fv.id,
      fv.version_number,fv.created_at,fv.object_path,fv.original_name,
      fv.mime_type,fv.size_bytes,fv.sha256_hex,fv.uploaded_by,
      f.version,coalesce(d.is_final,false),
      case when coalesce(d.is_final,false) then d.version else null end
    from public.task_files f
    join public.task_file_versions fv
      on fv.id=f.current_version_id
     and fv.file_id=f.id
    left join public.task_file_final_designations d
      on d.file_version_id=fv.id
     and d.file_id=f.id
    where f.project_id=p_project_id;

    update public.project_recovery_points
    set item_count=(
      select count(*)::integer
      from public.project_recovery_point_file_items i
      where i.recovery_point_id=v_recovery_point.id
    )
    where id=v_recovery_point.id
    returning * into v_recovery_point;

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'project_recovery_point_created','project_recovery_point',v_recovery_point.id,
      p_request_id,jsonb_build_object(
        'scope',v_recovery_point.scope,
        'projectVersion',v_project.version,
        'itemCount',v_recovery_point.item_count
      )
    );
    v_result:=jsonb_build_object(
      'ok',true,
      'data',jsonb_build_object(
        'recoveryPointId',v_recovery_point.id,
        'scope',v_recovery_point.scope,
        'itemCount',v_recovery_point.item_count,
        'projectVersion',v_recovery_point.project_version
      ),
      'requestId',p_request_id,
      'replayed',false,
      'aggregateType','project_recovery_point',
      'aggregateId',v_recovery_point.id,
      'aggregateVersion',v_recovery_point.version
    );
    return private.complete_command(
      v_claim.command_id,v_result,'project_recovery_point',
      v_recovery_point.id,v_recovery_point.version
    );
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_restore_project_recovery_point(
  p_project_id uuid,
  p_recovery_point_id uuid,
  p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_hash bytea;
  v_claim record;
  v_replay jsonb;
  v_result jsonb;
  v_project public.projects%rowtype;
  v_recovery_point public.project_recovery_points%rowtype;
  v_item public.project_recovery_point_file_items%rowtype;
  v_file public.task_files%rowtype;
  v_source public.task_file_versions%rowtype;
  v_reservation_id uuid;
  v_restored_version_id uuid;
  v_restored_version_number integer;
  v_restored_count integer:=0;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_recovery_point_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId' else 'recoveryPointId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'recoveryPointId',p_recovery_point_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_restore_project_recovery_point',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_leader(p_project_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project
  from public.projects p
  where p.id=p_project_id
  for update;

  select * into v_recovery_point
  from public.project_recovery_points rp
  where rp.id=p_recovery_point_id
    and rp.project_id=p_project_id
  for update;

  if v_recovery_point.id is null or not private.is_active_leader(p_project_id,v_actor) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_project.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_project.version);
  elsif v_recovery_point.scope<>'project_file_pointers_v1' then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_recovery_point.version);
  end if;
  if v_result is not null then
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  for v_item in
    select *
    from public.project_recovery_point_file_items i
    where i.recovery_point_id=p_recovery_point_id
      and i.project_id=p_project_id
    order by i.task_id,i.file_id
  loop
    select * into v_file
    from public.task_files f
    where f.id=v_item.file_id
      and f.project_id=p_project_id
      and f.task_id=v_item.task_id
    for update;

    select * into v_source
    from public.task_file_versions fv
    where fv.id=v_item.captured_file_version_id
      and fv.file_id=v_item.file_id
      and fv.project_id=p_project_id
      and fv.task_id=v_item.task_id;

    if v_file.id is null or v_source.id is null then
      v_result:=private.failure(
        p_request_id,'INVALID_TRANSITION',null,null,
        jsonb_build_object('reason','captured_file_missing','fileId',v_item.file_id)
      );
      return private.complete_command(v_claim.command_id,v_result);
    end if;

    if v_file.current_version_id=v_item.captured_file_version_id then
      continue;
    end if;

    v_reservation_id:=extensions.gen_random_uuid();
    v_restored_version_id:=extensions.gen_random_uuid();
    v_restored_version_number:=v_file.version+1;

    insert into public.file_upload_reservations(
      id,project_id,task_id,actor_id,mode,target_file_id,target_file_version,
      object_path,original_name,declared_mime_type,declared_size_bytes,
      state,expires_at,version
    ) values(
      v_reservation_id,p_project_id,v_item.task_id,v_actor,'new_version',
      v_item.file_id,v_file.version,v_source.object_path,v_source.original_name,
      v_source.mime_type,v_source.size_bytes,'finalized',now(),2
    );

    insert into public.task_file_versions(
      id,file_id,project_id,task_id,reservation_id,version_number,
      object_path,original_name,mime_type,size_bytes,sha256_hex,
      uploaded_by,restored_from_version_id
    ) values(
      v_restored_version_id,v_item.file_id,p_project_id,v_item.task_id,
      v_reservation_id,v_restored_version_number,v_source.object_path,
      v_source.original_name,v_source.mime_type,v_source.size_bytes,
      v_source.sha256_hex,v_actor,v_source.id
    );

    update public.task_files
    set current_version_id=v_restored_version_id,
        version=version+1,
        updated_at=now()
    where id=v_item.file_id;

    if v_item.captured_is_final then
      insert into public.task_file_final_designations(
        file_version_id,file_id,project_id,task_id,is_final,version,
        marked_by,marked_at,updated_by
      ) values(
        v_restored_version_id,v_item.file_id,p_project_id,v_item.task_id,
        true,1,v_actor,now(),v_actor
      );
    end if;

    insert into public.project_recovery_point_restore_items(
      recovery_point_id,restore_request_id,project_id,file_id,
      restored_from_version_id,restored_file_version_id,restored_version_number,
      restored_final_file_version_id,created_by
    ) values(
      p_recovery_point_id,p_request_id,p_project_id,v_item.file_id,
      v_source.id,v_restored_version_id,v_restored_version_number,
      case when v_item.captured_is_final then v_restored_version_id else null end,
      v_actor
    );
    v_restored_count:=v_restored_count+1;
  end loop;

  update public.projects
  set version=version+1,updated_at=now()
  where id=p_project_id
  returning * into v_project;

  update public.project_recovery_points
  set restored_at=now(),
      restored_by=v_actor,
      version=version+1
  where id=p_recovery_point_id
  returning * into v_recovery_point;

  perform private.emit_event(
    v_claim.command_id,1,p_project_id,v_actor,
    'project_recovery_point_restored','project_recovery_point',p_recovery_point_id,
    p_request_id,jsonb_build_object(
      'scope',v_recovery_point.scope,
      'restoredItemCount',v_restored_count,
      'projectVersion',v_project.version
    )
  );

  v_result:=jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'projectId',p_project_id,
      'recoveryPointId',p_recovery_point_id,
      'restoredItemCount',v_restored_count,
      'projectVersion',v_project.version
    ),
    'requestId',p_request_id,
    'replayed',false,
    'aggregateType','project',
    'aggregateId',p_project_id,
    'aggregateVersion',v_project.version
  );
  return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_project.version);
end;
$$;

revoke all on function public.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  from public,anon,authenticated,service_role;
revoke all on function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_create_project_recovery_point(uuid,uuid,integer,text)
  to authenticated;
grant execute on function public.cmd_restore_project_recovery_point(uuid,uuid,uuid,integer)
  to authenticated;

comment on table public.project_recovery_points is
  'Recovery metadata for project_file_pointers_v1 only. It captures current task_files pointers and final designation state; it is not project-wide time travel.';
comment on table public.project_recovery_point_file_items is
  'Captured logical file current-version pointers plus formal designation facts. Task/member/dependency/review/submission state is intentionally excluded.';
comment on table public.project_recovery_point_restore_items is
  'Append-only record of copy-forward file versions created by recovery restores.';
