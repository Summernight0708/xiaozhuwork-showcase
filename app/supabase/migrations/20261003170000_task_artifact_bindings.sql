-- Additive light/strong bindings from downstream tasks to immutable formal upstream artifact versions.
-- This deliberately does not modify task_review_rounds or submission schemas.

create table public.task_artifact_bindings (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  downstream_task_id uuid not null,
  upstream_task_id uuid not null,
  logical_file_id uuid not null,
  file_version_id uuid not null,
  strength text not null default 'light',
  version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  foreign key(project_id,downstream_task_id)
    references public.tasks(project_id,id) on delete cascade,
  foreign key(project_id,upstream_task_id)
    references public.tasks(project_id,id) on delete cascade,
  foreign key(project_id,upstream_task_id,logical_file_id)
    references public.task_files(project_id,task_id,id) on delete cascade,
  foreign key(logical_file_id,file_version_id)
    references public.task_file_versions(file_id,id) on delete cascade,
  constraint task_artifact_bindings_strength check (strength in ('light','strong')),
  constraint task_artifact_bindings_version_positive check (version > 0),
  constraint task_artifact_bindings_not_self check (upstream_task_id <> downstream_task_id),
  constraint task_artifact_bindings_downstream_file_unique unique(downstream_task_id,logical_file_id),
  constraint task_artifact_bindings_project_id_id_unique unique(project_id,id)
);

create index task_artifact_bindings_downstream_idx
  on public.task_artifact_bindings(project_id,downstream_task_id,updated_at desc);
create index task_artifact_bindings_upstream_strong_idx
  on public.task_artifact_bindings(project_id,upstream_task_id,logical_file_id)
  where strength='strong';

create table public.task_artifact_binding_history (
  id bigint generated always as identity primary key,
  binding_id uuid not null references public.task_artifact_bindings(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  downstream_task_id uuid not null,
  upstream_task_id uuid not null,
  logical_file_id uuid not null,
  previous_file_version_id uuid references public.task_file_versions(id) on delete set null,
  new_file_version_id uuid references public.task_file_versions(id) on delete set null,
  previous_strength text,
  new_strength text not null,
  change_kind text not null,
  actor_id uuid references auth.users(id) on delete set null,
  request_id uuid,
  created_at timestamptz not null default now(),
  foreign key(project_id,downstream_task_id)
    references public.tasks(project_id,id) on delete cascade,
  foreign key(project_id,upstream_task_id)
    references public.tasks(project_id,id) on delete cascade,
  constraint task_artifact_binding_history_previous_strength
    check (previous_strength is null or previous_strength in ('light','strong')),
  constraint task_artifact_binding_history_new_strength
    check (new_strength in ('light','strong')),
  constraint task_artifact_binding_history_change_kind
    check (change_kind in ('created','strength_changed','version_switched'))
);

create index task_artifact_binding_history_binding_idx
  on public.task_artifact_binding_history(binding_id,id desc);
create index task_artifact_binding_history_downstream_idx
  on public.task_artifact_binding_history(project_id,downstream_task_id,id desc);

create table private.task_artifact_binding_update_notices (
  id bigint generated always as identity primary key,
  binding_id uuid not null references public.task_artifact_bindings(id) on delete cascade,
  available_file_version_id uuid not null references public.task_file_versions(id) on delete cascade,
  source_event_id bigint references public.business_events(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint task_artifact_binding_update_notice_unique
    unique(binding_id,available_file_version_id)
);

alter table public.task_artifact_bindings enable row level security;
alter table public.task_artifact_binding_history enable row level security;

create policy task_artifact_bindings_select_member
on public.task_artifact_bindings for select to authenticated
using (public.is_active_project_member(project_id));

create policy task_artifact_binding_history_select_member
on public.task_artifact_binding_history for select to authenticated
using (public.is_active_project_member(project_id));

revoke all on public.task_artifact_bindings, public.task_artifact_binding_history
  from public,anon,authenticated,service_role;
grant select on public.task_artifact_bindings, public.task_artifact_binding_history
  to authenticated;

create function private.can_manage_task_artifact_binding(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_actor_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_task_participant(
    p_project_id,p_downstream_task_id,p_actor_id
  );
$$;

create function private.is_formal_task_artifact_version(
  p_project_id uuid,
  p_upstream_task_id uuid,
  p_file_version_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.task_file_versions fv
    join public.file_upload_reservations r
      on r.id=fv.reservation_id
     and r.project_id=fv.project_id
     and r.task_id=fv.task_id
    join public.tasks t
      on t.project_id=fv.project_id
     and t.id=fv.task_id
    where fv.id=p_file_version_id
      and fv.project_id=p_project_id
      and fv.task_id=p_upstream_task_id
      and r.state='finalized'
      and t.status='completed'
      and (
        exists(
          select 1
          from public.task_file_final_designations d
          where d.file_version_id=fv.id
            and d.project_id=fv.project_id
            and d.task_id=fv.task_id
            and d.is_final
        )
        or exists(
          select 1
          from public.task_review_rounds rr
          join public.task_review_round_files rf
            on rf.review_round_id=rr.id
           and rf.project_id=rr.project_id
           and rf.task_id=rr.task_id
          where rr.project_id=fv.project_id
            and rr.task_id=fv.task_id
            and rr.state='approved'
            and rf.file_version_id=fv.id
        )
      )
  );
$$;

create function private.emit_artifact_binding_update_if_needed(
  p_binding_id uuid,
  p_actor_id uuid,
  p_source_event_id bigint default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_binding public.task_artifact_bindings%rowtype;
  v_bound public.task_file_versions%rowtype;
  v_latest public.task_file_versions%rowtype;
  v_file public.task_files%rowtype;
  v_notice_id bigint;
begin
  select * into v_binding
  from public.task_artifact_bindings b
  where b.id=p_binding_id;

  if v_binding.id is null or v_binding.strength<>'strong' then
    return;
  end if;

  select * into v_bound
  from public.task_file_versions fv
  where fv.id=v_binding.file_version_id
    and fv.file_id=v_binding.logical_file_id;

  select * into v_latest
  from public.task_file_versions fv
  where fv.file_id=v_binding.logical_file_id
    and fv.project_id=v_binding.project_id
    and fv.task_id=v_binding.upstream_task_id
    and private.is_formal_task_artifact_version(
      v_binding.project_id,v_binding.upstream_task_id,fv.id
    )
  order by fv.version_number desc,fv.created_at desc,fv.id desc
  limit 1;

  if v_bound.id is null
     or v_latest.id is null
     or v_latest.version_number<=v_bound.version_number then
    return;
  end if;

  insert into private.task_artifact_binding_update_notices(
    binding_id,available_file_version_id,source_event_id
  ) values(v_binding.id,v_latest.id,p_source_event_id)
  on conflict(binding_id,available_file_version_id) do nothing
  returning id into v_notice_id;

  if v_notice_id is null then
    return;
  end if;

  select * into v_file
  from public.task_files f
  where f.id=v_binding.logical_file_id
    and f.project_id=v_binding.project_id
    and f.task_id=v_binding.upstream_task_id;

  insert into public.business_events(
    project_id,actor_id,event_type,entity_type,entity_id,request_id,event_data
  ) values(
    v_binding.project_id,
    p_actor_id,
    'task_artifact_binding_update_available',
    'task_artifact_binding',
    v_binding.id,
    null,
    jsonb_build_object(
      'bindingId',v_binding.id,
      'downstreamTaskId',v_binding.downstream_task_id,
      'upstreamTaskId',v_binding.upstream_task_id,
      'fileId',v_binding.logical_file_id,
      'logicalName',v_file.logical_name,
      'boundFileVersionId',v_bound.id,
      'newFileVersionId',v_latest.id,
      'fromVersionNumber',v_bound.version_number,
      'toVersionNumber',v_latest.version_number
    )
  );
end;
$$;

create function private.emit_artifact_updates_from_business_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_binding record;
begin
  if new.event_type not in ('task_file_version_final_marked','task_submission_approved') then
    return new;
  end if;

  begin
    v_task_id:=nullif(new.event_data->>'taskId','')::uuid;
  exception when invalid_text_representation then
    return new;
  end;

  if v_task_id is null then
    return new;
  end if;

  for v_binding in
    select b.id
    from public.task_artifact_bindings b
    where b.project_id=new.project_id
      and b.upstream_task_id=v_task_id
      and b.strength='strong'
  loop
    perform private.emit_artifact_binding_update_if_needed(
      v_binding.id,new.actor_id,new.id
    );
  end loop;

  return new;
end;
$$;

create trigger business_event_emits_artifact_binding_updates
after insert on public.business_events
for each row execute function private.emit_artifact_updates_from_business_event();

create function private.notify_from_artifact_binding_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_downstream_task_id uuid;
  v_recipient uuid;
  v_logical_name text;
  v_from_version text;
  v_to_version text;
begin
  if new.event_type<>'task_artifact_binding_update_available' then
    return new;
  end if;

  begin
    v_downstream_task_id:=nullif(new.event_data->>'downstreamTaskId','')::uuid;
  exception when invalid_text_representation then
    return new;
  end;

  if v_downstream_task_id is null then
    return new;
  end if;

  select t.assignee_id into v_recipient
  from public.tasks t
  where t.id=v_downstream_task_id
    and t.project_id=new.project_id;

  v_logical_name:=coalesce(nullif(new.event_data->>'logicalName',''),'上游成果');
  v_from_version:=coalesce(nullif(new.event_data->>'fromVersionNumber',''),'?');
  v_to_version:=coalesce(nullif(new.event_data->>'toVersionNumber',''),'?');

  perform private.create_notification(
    new.id,
    new.project_id,
    v_recipient,
    'artifact_binding_update',
    '上游成果已有更新',
    format('你强绑定的上游成果“%s”已从 v%s 更新到 v%s。',v_logical_name,v_from_version,v_to_version),
    'task',
    v_downstream_task_id
  );

  return new;
end;
$$;

create trigger artifact_binding_event_creates_notification
after insert on public.business_events
for each row execute function private.notify_from_artifact_binding_event();

create function public.get_upstream_artifacts(p_downstream_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();
  v_project_id uuid;
  v_can_bind boolean:=false;
  v_artifacts jsonb;
begin
  if v_actor is null or p_downstream_task_id is null then
    return null;
  end if;

  select t.project_id into v_project_id
  from public.tasks t
  where t.id=p_downstream_task_id;

  if v_project_id is null
     or not private.is_active_member(v_project_id,v_actor) then
    return null;
  end if;

  v_can_bind:=private.can_manage_task_artifact_binding(
    v_project_id,p_downstream_task_id,v_actor
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'upstreamTaskId',q.upstream_task_id,
      'upstreamTaskTitle',q.upstream_task_title,
      'fileId',q.file_id,
      'logicalName',q.logical_name,
      'versions',q.versions,
      'latestVersionId',q.latest_version_id,
      'binding',case when q.binding_id is null then null else jsonb_build_object(
        'bindingId',q.binding_id,
        'fileVersionId',q.bound_file_version_id,
        'boundVersionNumber',q.bound_version_number,
        'strength',q.binding_strength,
        'version',q.binding_version
      ) end
    )
    order by q.upstream_task_title,q.logical_name,q.file_id
  ),'[]'::jsonb)
  into v_artifacts
  from (
    select
      d.upstream_task_id,
      u.title as upstream_task_title,
      f.id as file_id,
      f.logical_name,
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'fileVersionId',fv.id,
            'versionNumber',fv.version_number,
            'objectPath',fv.object_path,
            'originalName',fv.original_name,
            'mimeType',fv.mime_type,
            'sizeBytes',fv.size_bytes,
            'createdAt',fv.created_at
          )
          order by fv.version_number,fv.created_at,fv.id
        ),'[]'::jsonb)
        from public.task_file_versions fv
        where fv.file_id=f.id
          and private.is_formal_task_artifact_version(
            v_project_id,d.upstream_task_id,fv.id
          )
      ) as versions,
      (
        select fv.id
        from public.task_file_versions fv
        where fv.file_id=f.id
          and private.is_formal_task_artifact_version(
            v_project_id,d.upstream_task_id,fv.id
          )
        order by fv.version_number desc,fv.created_at desc,fv.id desc
        limit 1
      ) as latest_version_id,
      b.id as binding_id,
      b.file_version_id as bound_file_version_id,
      bv.version_number as bound_version_number,
      b.strength as binding_strength,
      b.version as binding_version
    from public.task_dependencies d
    join public.tasks u
      on u.project_id=d.project_id
     and u.id=d.upstream_task_id
    join public.task_files f
      on f.project_id=d.project_id
     and f.task_id=d.upstream_task_id
    left join public.task_artifact_bindings b
      on b.project_id=d.project_id
     and b.downstream_task_id=d.downstream_task_id
     and b.logical_file_id=f.id
    left join public.task_file_versions bv
      on bv.id=b.file_version_id
     and bv.file_id=b.logical_file_id
    where d.project_id=v_project_id
      and d.downstream_task_id=p_downstream_task_id
      and exists(
        select 1
        from public.task_file_versions formal_version
        where formal_version.file_id=f.id
          and private.is_formal_task_artifact_version(
            v_project_id,d.upstream_task_id,formal_version.id
          )
      )
  ) q;

  return jsonb_build_object(
    'downstreamTaskId',p_downstream_task_id,
    'canBind',v_can_bind,
    'artifacts',v_artifacts
  );
end;
$$;

create function public.cmd_record_task_artifact_use(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_file_version_id uuid,
  p_request_id uuid
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
  v_downstream public.tasks%rowtype;
  v_file_version public.task_file_versions%rowtype;
  v_binding public.task_artifact_bindings%rowtype;
  v_inserted boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_downstream_task_id is null or p_file_version_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId'
           when p_downstream_task_id is null then 'downstreamTaskId'
           else 'fileVersionId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'downstreamTaskId',p_downstream_task_id,
    'fileVersionId',p_file_version_id
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_record_task_artifact_use',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.can_manage_task_artifact_binding(p_project_id,p_downstream_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.projects p where p.id=p_project_id for update;
  select * into v_downstream
  from public.tasks t
  where t.id=p_downstream_task_id and t.project_id=p_project_id
  for update;

  if v_downstream.id is null
     or not private.can_manage_task_artifact_binding(
       p_project_id,p_downstream_task_id,v_actor
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_file_version
  from public.task_file_versions fv
  where fv.id=p_file_version_id
    and fv.project_id=p_project_id
    and exists(
      select 1
      from public.task_dependencies d
      where d.project_id=p_project_id
        and d.downstream_task_id=p_downstream_task_id
        and d.upstream_task_id=fv.task_id
    );

  if v_file_version.id is null
     or not private.is_formal_task_artifact_version(
       p_project_id,v_file_version.task_id,v_file_version.id
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','fileVersionId');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  insert into public.task_artifact_bindings(
    project_id,downstream_task_id,upstream_task_id,logical_file_id,file_version_id,
    strength,version,created_by,updated_by
  ) values(
    p_project_id,p_downstream_task_id,v_file_version.task_id,v_file_version.file_id,
    v_file_version.id,'light',1,v_actor,v_actor
  )
  on conflict(downstream_task_id,logical_file_id) do nothing
  returning * into v_binding;

  if v_binding.id is not null then
    v_inserted:=true;
    insert into public.task_artifact_binding_history(
      binding_id,project_id,downstream_task_id,upstream_task_id,logical_file_id,
      previous_file_version_id,new_file_version_id,previous_strength,new_strength,
      change_kind,actor_id,request_id
    ) values(
      v_binding.id,p_project_id,p_downstream_task_id,v_binding.upstream_task_id,
      v_binding.logical_file_id,null,v_binding.file_version_id,null,'light',
      'created',v_actor,p_request_id
    );

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_artifact_binding_created','task_artifact_binding',v_binding.id,p_request_id,
      jsonb_build_object(
        'downstreamTaskId',p_downstream_task_id,
        'upstreamTaskId',v_binding.upstream_task_id,
        'fileId',v_binding.logical_file_id,
        'fileVersionId',v_binding.file_version_id,
        'strength','light',
        'bindingVersion',v_binding.version
      )
    );
  else
    select * into v_binding
    from public.task_artifact_bindings b
    where b.downstream_task_id=p_downstream_task_id
      and b.logical_file_id=v_file_version.file_id
    for update;
  end if;

  if v_binding.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  v_result:=jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'bindingId',v_binding.id,
      'downstreamTaskId',v_binding.downstream_task_id,
      'fileVersionId',v_binding.file_version_id,
      'strength',v_binding.strength,
      'bindingVersion',v_binding.version,
      'changed',v_inserted
    ),
    'requestId',p_request_id,
    'replayed',false,
    'aggregateType','task_artifact_binding',
    'aggregateId',v_binding.id,
    'aggregateVersion',v_binding.version
  );
  return private.complete_command(
    v_claim.command_id,v_result,'task_artifact_binding',v_binding.id,v_binding.version
  );
end;
$$;

create function public.cmd_set_task_artifact_binding_strength(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_file_version_id uuid,
  p_strength text,
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
  v_downstream public.tasks%rowtype;
  v_file_version public.task_file_versions%rowtype;
  v_binding public.task_artifact_bindings%rowtype;
  v_previous_strength text;
  v_changed boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_downstream_task_id is null or p_file_version_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId'
           when p_downstream_task_id is null then 'downstreamTaskId'
           else 'fileVersionId' end
    );
  end if;
  if p_strength is null or p_strength not in ('light','strong') then
    return private.failure(p_request_id,'VALIDATION_FAILED','strength');
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'downstreamTaskId',p_downstream_task_id,
    'fileVersionId',p_file_version_id,
    'strength',p_strength,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_set_task_artifact_binding_strength',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.can_manage_task_artifact_binding(p_project_id,p_downstream_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.projects p where p.id=p_project_id for update;
  select * into v_downstream
  from public.tasks t
  where t.id=p_downstream_task_id and t.project_id=p_project_id
  for update;

  if v_downstream.id is null
     or not private.can_manage_task_artifact_binding(
       p_project_id,p_downstream_task_id,v_actor
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_file_version
  from public.task_file_versions fv
  where fv.id=p_file_version_id
    and fv.project_id=p_project_id
    and exists(
      select 1
      from public.task_dependencies d
      where d.project_id=p_project_id
        and d.downstream_task_id=p_downstream_task_id
        and d.upstream_task_id=fv.task_id
    );

  if v_file_version.id is null
     or not private.is_formal_task_artifact_version(
       p_project_id,v_file_version.task_id,v_file_version.id
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','fileVersionId');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_binding
  from public.task_artifact_bindings b
  where b.downstream_task_id=p_downstream_task_id
    and b.logical_file_id=v_file_version.file_id
  for update;

  if v_binding.id is null then
    if p_strength<>'strong' then
      v_result:=private.failure(
        p_request_id,'INVALID_TRANSITION',null,0,
        jsonb_build_object('reason','binding_missing')
      );
    elsif coalesce(p_expected_version,-1)<>0 then
      v_result:=private.failure(p_request_id,'STALE_VERSION',null,0);
    else
      insert into public.task_artifact_bindings(
        project_id,downstream_task_id,upstream_task_id,logical_file_id,file_version_id,
        strength,version,created_by,updated_by
      ) values(
        p_project_id,p_downstream_task_id,v_file_version.task_id,v_file_version.file_id,
        v_file_version.id,'strong',1,v_actor,v_actor
      )
      returning * into v_binding;
      v_changed:=true;

      insert into public.task_artifact_binding_history(
        binding_id,project_id,downstream_task_id,upstream_task_id,logical_file_id,
        previous_file_version_id,new_file_version_id,previous_strength,new_strength,
        change_kind,actor_id,request_id
      ) values(
        v_binding.id,p_project_id,p_downstream_task_id,v_binding.upstream_task_id,
        v_binding.logical_file_id,null,v_binding.file_version_id,null,'strong',
        'created',v_actor,p_request_id
      );
    end if;
  elsif v_binding.file_version_id is distinct from p_file_version_id then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_binding.version,
      jsonb_build_object('reason','explicit_switch_required')
    );
  elsif p_expected_version is null or v_binding.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_binding.version);
  elsif v_binding.strength=p_strength then
    v_changed:=false;
  else
    v_previous_strength:=v_binding.strength;
    update public.task_artifact_bindings
    set strength=p_strength,
        version=version+1,
        updated_by=v_actor,
        updated_at=now()
    where id=v_binding.id
    returning * into v_binding;
    v_changed:=true;

    insert into public.task_artifact_binding_history(
      binding_id,project_id,downstream_task_id,upstream_task_id,logical_file_id,
      previous_file_version_id,new_file_version_id,previous_strength,new_strength,
      change_kind,actor_id,request_id
    ) values(
      v_binding.id,p_project_id,p_downstream_task_id,v_binding.upstream_task_id,
      v_binding.logical_file_id,v_binding.file_version_id,v_binding.file_version_id,
      v_previous_strength,v_binding.strength,'strength_changed',v_actor,p_request_id
    );
  end if;

  if v_result is not null then
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  if v_changed then
    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_artifact_binding_strength_set','task_artifact_binding',v_binding.id,p_request_id,
      jsonb_build_object(
        'downstreamTaskId',v_binding.downstream_task_id,
        'upstreamTaskId',v_binding.upstream_task_id,
        'fileId',v_binding.logical_file_id,
        'fileVersionId',v_binding.file_version_id,
        'strength',v_binding.strength,
        'bindingVersion',v_binding.version
      )
    );
  end if;

  if v_binding.strength='strong' then
    perform private.emit_artifact_binding_update_if_needed(v_binding.id,v_actor,null);
  end if;

  v_result:=jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'bindingId',v_binding.id,
      'downstreamTaskId',v_binding.downstream_task_id,
      'fileVersionId',v_binding.file_version_id,
      'strength',v_binding.strength,
      'bindingVersion',v_binding.version,
      'changed',v_changed
    ),
    'requestId',p_request_id,
    'replayed',false,
    'aggregateType','task_artifact_binding',
    'aggregateId',v_binding.id,
    'aggregateVersion',v_binding.version
  );
  return private.complete_command(
    v_claim.command_id,v_result,'task_artifact_binding',v_binding.id,v_binding.version
  );
end;
$$;

create function public.cmd_switch_task_artifact_binding_version(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_file_version_id uuid,
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
  v_downstream public.tasks%rowtype;
  v_file_version public.task_file_versions%rowtype;
  v_binding public.task_artifact_bindings%rowtype;
  v_previous_file_version_id uuid;
  v_changed boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_downstream_task_id is null or p_file_version_id is null then
    return private.failure(
      p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId'
           when p_downstream_task_id is null then 'downstreamTaskId'
           else 'fileVersionId' end
    );
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,
    'downstreamTaskId',p_downstream_task_id,
    'fileVersionId',p_file_version_id,
    'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_switch_task_artifact_binding_version',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.can_manage_task_artifact_binding(p_project_id,p_downstream_task_id,v_actor),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(
    p_request_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_replay is not null then return v_replay; end if;

  perform 1 from public.projects p where p.id=p_project_id for update;
  select * into v_downstream
  from public.tasks t
  where t.id=p_downstream_task_id and t.project_id=p_project_id
  for update;

  if v_downstream.id is null
     or not private.can_manage_task_artifact_binding(
       p_project_id,p_downstream_task_id,v_actor
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_file_version
  from public.task_file_versions fv
  where fv.id=p_file_version_id
    and fv.project_id=p_project_id
    and exists(
      select 1
      from public.task_dependencies d
      where d.project_id=p_project_id
        and d.downstream_task_id=p_downstream_task_id
        and d.upstream_task_id=fv.task_id
    );

  if v_file_version.id is null
     or not private.is_formal_task_artifact_version(
       p_project_id,v_file_version.task_id,v_file_version.id
     ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','fileVersionId');
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  select * into v_binding
  from public.task_artifact_bindings b
  where b.downstream_task_id=p_downstream_task_id
    and b.logical_file_id=v_file_version.file_id
  for update;

  if v_binding.id is null then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_binding.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_binding.version);
  elsif v_binding.file_version_id=p_file_version_id then
    v_changed:=false;
  else
    v_previous_file_version_id:=v_binding.file_version_id;
    update public.task_artifact_bindings
    set upstream_task_id=v_file_version.task_id,
        file_version_id=v_file_version.id,
        version=version+1,
        updated_by=v_actor,
        updated_at=now()
    where id=v_binding.id
    returning * into v_binding;
    v_changed:=true;

    insert into public.task_artifact_binding_history(
      binding_id,project_id,downstream_task_id,upstream_task_id,logical_file_id,
      previous_file_version_id,new_file_version_id,previous_strength,new_strength,
      change_kind,actor_id,request_id
    ) values(
      v_binding.id,p_project_id,p_downstream_task_id,v_binding.upstream_task_id,
      v_binding.logical_file_id,v_previous_file_version_id,v_binding.file_version_id,
      v_binding.strength,v_binding.strength,'version_switched',v_actor,p_request_id
    );

    perform private.emit_event(
      v_claim.command_id,1,p_project_id,v_actor,
      'task_artifact_binding_version_switched','task_artifact_binding',v_binding.id,p_request_id,
      jsonb_build_object(
        'downstreamTaskId',v_binding.downstream_task_id,
        'upstreamTaskId',v_binding.upstream_task_id,
        'fileId',v_binding.logical_file_id,
        'previousFileVersionId',v_previous_file_version_id,
        'fileVersionId',v_binding.file_version_id,
        'strength',v_binding.strength,
        'bindingVersion',v_binding.version
      )
    );
  end if;

  if v_result is not null then
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  if v_binding.strength='strong' then
    perform private.emit_artifact_binding_update_if_needed(v_binding.id,v_actor,null);
  end if;

  v_result:=jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'bindingId',v_binding.id,
      'downstreamTaskId',v_binding.downstream_task_id,
      'fileVersionId',v_binding.file_version_id,
      'strength',v_binding.strength,
      'bindingVersion',v_binding.version,
      'changed',v_changed
    ),
    'requestId',p_request_id,
    'replayed',false,
    'aggregateType','task_artifact_binding',
    'aggregateId',v_binding.id,
    'aggregateVersion',v_binding.version
  );
  return private.complete_command(
    v_claim.command_id,v_result,'task_artifact_binding',v_binding.id,v_binding.version
  );
end;
$$;

revoke all on function public.get_upstream_artifacts(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.cmd_record_task_artifact_use(uuid,uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.cmd_set_task_artifact_binding_strength(uuid,uuid,uuid,text,uuid,integer)
  from public,anon,authenticated,service_role;
revoke all on function public.cmd_switch_task_artifact_binding_version(uuid,uuid,uuid,uuid,integer)
  from public,anon,authenticated,service_role;

grant execute on function public.get_upstream_artifacts(uuid) to authenticated;
grant execute on function public.cmd_record_task_artifact_use(uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.cmd_set_task_artifact_binding_strength(uuid,uuid,uuid,text,uuid,integer)
  to authenticated;
grant execute on function public.cmd_switch_task_artifact_binding_version(uuid,uuid,uuid,uuid,integer)
  to authenticated;

revoke all on function private.can_manage_task_artifact_binding(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.is_formal_task_artifact_version(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function private.emit_artifact_binding_update_if_needed(uuid,uuid,bigint)
  from public,anon,authenticated,service_role;
revoke all on function private.emit_artifact_updates_from_business_event()
  from public,anon,authenticated,service_role;
revoke all on function private.notify_from_artifact_binding_event()
  from public,anon,authenticated,service_role;

comment on table public.task_artifact_bindings is
  'Current downstream-task binding to one immutable direct-upstream formal artifact version. Versions never auto-advance.';
comment on table public.task_artifact_binding_history is
  'Append-only-by-API history of artifact binding creation, strength changes, and explicit version switches.';
comment on function private.is_formal_task_artifact_version(uuid,uuid,uuid) is
  'Replaceable boundary for deciding which immutable finalized upstream versions belong to the formal task delivery chain.';
