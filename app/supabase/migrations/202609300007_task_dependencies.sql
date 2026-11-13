-- Authoritative task dependency management with concurrency-safe DAG enforcement.

create function public.cmd_set_task_dependencies(
  p_project_id uuid,
  p_downstream_task_id uuid,
  p_upstream_task_ids uuid[],
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
  v_task public.tasks%rowtype;
  v_actor_member public.project_members%rowtype;
  v_upstreams uuid[];
  v_existing uuid[];
  v_cycle boolean:=false;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_upstream_task_ids is null then return private.failure(p_request_id,'VALIDATION_FAILED','upstreamTaskIds'); end if;
  if array_position(p_upstream_task_ids,null::uuid) is not null then
    return private.failure(p_request_id,'VALIDATION_FAILED','upstreamTaskIds');
  end if;
  if not exists(select 1 from public.projects p where p.id=p_project_id) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;

  select coalesce(array_agg(distinct upstream_id order by upstream_id),array[]::uuid[])
  into v_upstreams
  from unnest(p_upstream_task_ids) as x(upstream_id);

  v_hash:=private.payload_hash(jsonb_build_object(
    'projectId',p_project_id,'downstreamTaskId',p_downstream_task_id,
    'upstreamTaskIds',to_jsonb(v_upstreams),'expectedVersion',p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor,'cmd_set_task_dependencies',p_request_id,v_hash,null,p_project_id
  );
  v_result:=private.reject_unless_authorized(
    private.is_active_member(p_project_id,v_actor)
      and exists(
        select 1 from public.tasks t
        where t.id=p_downstream_task_id and t.project_id=p_project_id
          and (t.created_by=v_actor or private.is_active_leader(p_project_id,v_actor))
      ),
    p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches
  );
  if v_result is not null then return v_result; end if;
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;

  select * into v_project from public.projects p where p.id=p_project_id for update;
  select * into v_task from public.tasks t
  where t.id=p_downstream_task_id and t.project_id=p_project_id for update;
  select * into v_actor_member from public.project_members pm
  where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active';

  if v_task.id is null
     or v_actor_member.id is null
     or v_actor_member.role='observer'
     or (v_task.created_by is distinct from v_actor and v_actor_member.role<>'leader') then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_task.version<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
  elsif v_project.lifecycle_state<>'active' then
    v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif v_task.status in ('awaiting_review','completed','canceled') then
    v_result:=private.failure(
      p_request_id,'INVALID_TRANSITION',null,v_task.version,
      jsonb_build_object('reason','task_definition_locked','status',v_task.status)
    );
  elsif p_downstream_task_id=any(v_upstreams) then
    v_result:=private.failure(
      p_request_id,'VALIDATION_FAILED','upstreamTaskIds',v_task.version,
      jsonb_build_object('reason','self_dependency')
    );
  elsif exists(
    select 1 from unnest(v_upstreams) u
    where not exists(select 1 from public.tasks t where t.id=u and t.project_id=p_project_id)
  ) then
    v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED','upstreamTaskIds');
  else
    select coalesce(array_agg(d.upstream_task_id order by d.upstream_task_id),array[]::uuid[])
    into v_existing
    from public.task_dependencies d
    where d.project_id=p_project_id and d.downstream_task_id=p_downstream_task_id;

    if v_existing=v_upstreams then
      v_result:=jsonb_build_object(
        'ok',true,'data',jsonb_build_object(
          'taskId',v_task.id,'taskVersion',v_task.version,'changed',false,
          'upstreamTaskIds',to_jsonb(v_upstreams)
        ),'requestId',p_request_id,'replayed',false,'aggregateType','task',
        'aggregateId',v_task.id,'aggregateVersion',v_task.version
      );
      return private.complete_command(v_claim.command_id,v_result,'task',v_task.id,v_task.version);
    end if;

    with recursive graph(upstream_task_id,downstream_task_id) as (
      select d.upstream_task_id,d.downstream_task_id
      from public.task_dependencies d
      where d.project_id=p_project_id and d.downstream_task_id<>p_downstream_task_id
      union all
      select u,p_downstream_task_id from unnest(v_upstreams) u
    ),
    reachable(task_id) as (
      select p_downstream_task_id
      union
      select g.downstream_task_id
      from graph g join reachable r on g.upstream_task_id=r.task_id
    )
    select exists(select 1 from reachable r where r.task_id=any(v_upstreams))
    into v_cycle;

    if v_cycle then
      v_result:=private.failure(
        p_request_id,'INVALID_TRANSITION',null,v_task.version,
        jsonb_build_object('reason','dependency_cycle')
      );
    else
      delete from public.task_dependencies
      where project_id=p_project_id and downstream_task_id=p_downstream_task_id;
      insert into public.task_dependencies(project_id,upstream_task_id,downstream_task_id,created_by)
      select p_project_id,u,p_downstream_task_id,v_actor from unnest(v_upstreams) u;
      update public.tasks set version=version+1,updated_at=now()
      where id=p_downstream_task_id returning * into v_task;
      perform private.emit_event(
        v_claim.command_id,1,p_project_id,v_actor,'task_dependencies_set','task',v_task.id,p_request_id,
        jsonb_build_object('previousUpstreamTaskIds',to_jsonb(v_existing),'upstreamTaskIds',to_jsonb(v_upstreams),'taskVersion',v_task.version)
      );
      v_result:=jsonb_build_object(
        'ok',true,'data',jsonb_build_object(
          'taskId',v_task.id,'taskVersion',v_task.version,'changed',true,
          'upstreamTaskIds',to_jsonb(v_upstreams)
        ),'requestId',p_request_id,'replayed',false,'aggregateType','task',
        'aggregateId',v_task.id,'aggregateVersion',v_task.version
      );
      return private.complete_command(v_claim.command_id,v_result,'task',v_task.id,v_task.version);
    end if;
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

revoke all on function public.cmd_set_task_dependencies(uuid,uuid,uuid[],uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_set_task_dependencies(uuid,uuid,uuid[],uuid,integer)
  to authenticated;
