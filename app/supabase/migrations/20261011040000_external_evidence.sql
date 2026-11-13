-- D only. Metadata links, never fetched, stored in Storage, or treated as file versions.
-- Deliberately reject ALL IP literals, ports other than 443, and encoded authorities.
create function private.external_evidence_url_host(p_url text)
returns text language plpgsql immutable set search_path = '' as $$
declare
  v_parts text[];
  v_host text;
  v_label text;
begin
  if p_url is null or char_length(p_url) > 2048
     or p_url collate "C" ~ '[^!-~]'
     or p_url ~ '[\\<>"`{}|^]'
     or p_url ~* '%(0[0-9a-f]|1[0-9a-f]|7f|5c|25)'
     or regexp_replace(p_url, '%[0-9a-fA-F]{2}', '', 'g') like '%\%%' escape '\' then
    return null;
  end if;
  v_parts := regexp_match(p_url, '^https://([A-Za-z0-9.-]+)(:443)?([/?#].*)?$');
  if v_parts is null then return null; end if;
  v_host := lower(v_parts[1]);
  if char_length(v_host) > 253 or position('.' in v_host) = 0
     or v_host !~ '\.[a-z]{2,63}$'
     or v_host ~ '(^|\.)(localhost|localdomain|local|internal|intranet|lan|home|corp|test|invalid|onion|arpa)$' then
    return null;
  end if;
  foreach v_label in array string_to_array(v_host, '.') loop
    if v_label !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' then return null; end if;
  end loop;
  return v_host;
end;
$$;

create table public.task_external_evidence (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  task_id uuid not null,
  https_url text not null,
  host text not null,
  description text not null,
  submitted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  version integer not null default 1 check (version > 0),
  unique (project_id, task_id, id),
  foreign key (project_id, task_id) references public.tasks(project_id, id),
  constraint external_evidence_url_valid check (
    private.external_evidence_url_host(https_url) is not null
    and host = private.external_evidence_url_host(https_url)
  ),
  constraint external_evidence_description_length check (char_length(btrim(description)) <= 2000),
  constraint external_evidence_revocation check (revoked_at is not null or revoked_by is null)
);
create index external_evidence_task_idx
  on public.task_external_evidence(project_id, task_id, created_at, id);
create index external_evidence_submitter_idx on public.task_external_evidence(submitted_by)
  where submitted_by is not null;
create index external_evidence_revoker_idx on public.task_external_evidence(revoked_by)
  where revoked_by is not null;

-- Pre-change metadata only. No external content snapshots or rollback claim.
create table public.task_external_evidence_revisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id),
  task_id uuid not null,
  evidence_id uuid not null,
  version integer not null check (version > 0),
  https_url text not null,
  host text not null,
  description text not null,
  submitted_by uuid references auth.users(id) on delete set null,
  evidence_created_at timestamptz not null,
  evidence_updated_at timestamptz not null,
  action text not null check (action in ('updated', 'removed')),
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  request_id uuid not null,
  -- Not an FK to command_requests: deleting an account must not delete/block this history.
  command_request_id uuid not null,
  occurrence_key text not null unique,
  unique (evidence_id, version),
  foreign key (project_id, task_id, evidence_id)
    references public.task_external_evidence(project_id, task_id, id)
);
create index external_evidence_revision_project_idx
  on public.task_external_evidence_revisions(project_id, task_id, evidence_id, version);
create index external_evidence_revision_submitter_idx
  on public.task_external_evidence_revisions(submitted_by) where submitted_by is not null;
create index external_evidence_revision_actor_idx
  on public.task_external_evidence_revisions(changed_by) where changed_by is not null;

create function private.external_evidence_revision_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Same narrow identity-nulling exception as existing audit; no metadata rewrite.
  if tg_op = 'UPDATE'
     and (new.submitted_by is not distinct from old.submitted_by or new.submitted_by is null)
     and (new.changed_by is not distinct from old.changed_by or new.changed_by is null)
     and (to_jsonb(new) - array['submitted_by','changed_by']) =
         (to_jsonb(old) - array['submitted_by','changed_by']) then
    return new;
  end if;
  raise exception using errcode='55000', message='External evidence revisions are immutable';
end;
$$;
create trigger external_evidence_revisions_immutable
before update or delete on public.task_external_evidence_revisions
for each row execute function private.external_evidence_revision_immutable();

alter table public.task_external_evidence enable row level security;
alter table public.task_external_evidence_revisions enable row level security;
create policy external_evidence_read on public.task_external_evidence
for select to authenticated using (public.is_active_project_member(project_id));
create policy external_evidence_revision_read on public.task_external_evidence_revisions
for select to authenticated using (public.is_active_project_member(project_id));
revoke all on public.task_external_evidence, public.task_external_evidence_revisions
  from public, anon, authenticated, service_role;
grant select on public.task_external_evidence, public.task_external_evidence_revisions to authenticated;

-- Only D event types participate. Historical audit and its immutable trigger are unchanged.
create unique index external_evidence_event_occurrence_idx
  on public.business_events(project_id, (event_data->>'occurrenceKey'))
  where event_type in ('external_evidence_created','external_evidence_updated','external_evidence_removed');

create function private.external_evidence_can_write(
  p_project_id uuid, p_task_id uuid, p_actor_id uuid, p_submitter uuid, p_create boolean
) returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_eligible_task_collaborator_member(p_project_id,p_actor_id)
    and private.is_current_task_file_actor(p_project_id,p_task_id,p_actor_id)
    and (p_create or coalesce(p_submitter=p_actor_id,false) or exists (
      select 1 from public.tasks t where t.project_id=p_project_id and t.id=p_task_id
        and (t.created_by=p_actor_id or t.assignee_id=p_actor_id
             or private.is_active_leader(p_project_id,p_actor_id))
    ));
$$;

-- One D-specific implementation, using the existing kernel; no alternate request/event store.
create function private.external_evidence_command(
  p_action text, p_project_id uuid, p_entity_id uuid, p_https_url text,
  p_description text, p_request_id uuid, p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_evidence public.task_external_evidence%rowtype;
  v_task_id uuid;
  v_claim record;
  v_result jsonb;
  v_host text;
  v_url text;
  v_key text;
  v_now timestamptz;
  v_version integer;
  v_command text := 'cmd_' || p_action || '_external_evidence';
  v_event text;
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
  if p_project_id is null or p_entity_id is null then
    return private.failure(p_request_id,'VALIDATION_FAILED',
      case when p_project_id is null then 'projectId'
           when p_action='create' then 'taskId' else 'evidenceId' end);
  end if;
  if p_action not in ('create','update','remove') then
    return private.failure(p_request_id,'VALIDATION_FAILED','action');
  end if;

  -- Unlocked authorization preflight avoids request claims for missing targets.
  select * into v_project from public.projects where id=p_project_id;
  if not found or not private.is_eligible_task_collaborator_member(p_project_id,v_actor) then
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  if p_action='create' then
    v_task_id := p_entity_id;
  else
    -- Discovery is not a lock; never take evidence before task.
    select task_id into v_task_id from public.task_external_evidence
      where project_id=p_project_id and id=p_entity_id;
  end if;
  select * into v_task from public.tasks
    where project_id=p_project_id and id=v_task_id;
  if not found then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  if p_action <> 'create' then
    select * into v_evidence from public.task_external_evidence
      where project_id=p_project_id and task_id=v_task_id and id=p_entity_id;
    if not found then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
  end if;
  if private.external_evidence_can_write(
    p_project_id,v_task_id,v_actor,v_evidence.submitted_by,p_action='create'
  ) is not true then return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;

  select * into v_claim from private.claim_command(
    v_actor,v_command,p_request_id,private.payload_hash(jsonb_build_object(
      'projectId',p_project_id,'entityId',p_entity_id,'httpsUrl',p_https_url,
      'description',p_description,'expectedVersion',p_expected_version
    )),null,p_project_id
  );
  -- F0 order: command claim -> project -> task -> evidence.
  -- Unlocked preflight avoids enumeration; authoritative state is rechecked
  -- under locks before any replay or mutation.
  select * into v_project from public.projects where id=p_project_id for no key update;
  if not found or not private.is_eligible_task_collaborator_member(p_project_id,v_actor) then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    if v_claim.prior_result is not null then return v_result; end if;
    return private.complete_command(v_claim.command_id,v_result);
  end if;
  select * into v_task from public.tasks
    where project_id=p_project_id and id=v_task_id for update;
  if not found then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    if v_claim.prior_result is not null then return v_result; end if;
    return private.complete_command(v_claim.command_id,v_result);
  end if;
  if p_action <> 'create' then
    select * into v_evidence from public.task_external_evidence
      where project_id=p_project_id and task_id=v_task_id and id=p_entity_id for update;
    if not found then
      v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
      if v_claim.prior_result is not null then return v_result; end if;
      return private.complete_command(v_claim.command_id,v_result);
    end if;
  end if;
  if private.external_evidence_can_write(
    p_project_id,v_task_id,v_actor,v_evidence.submitted_by,p_action='create'
  ) is not true then
    v_result := private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
    if v_claim.prior_result is not null then return v_result; end if;
    return private.complete_command(v_claim.command_id,v_result);
  end if;

  v_result := private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_result is not null then return v_result; end if;

  v_version := case when p_action='create' then v_task.version else v_evidence.version end;
  v_host := private.external_evidence_url_host(p_https_url);
  if v_project.archived_at is not null or v_project.lifecycle_state <> 'active' then
    v_result := private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_project.version);
  elsif p_expected_version is distinct from v_version then
    v_result := private.failure(p_request_id,'STALE_VERSION',null,v_version);
  elsif v_evidence.revoked_at is not null then
    v_result := private.failure(p_request_id,'EVIDENCE_WITHDRAWN',null,v_version);
  elsif v_task.status in ('awaiting_review','completed','canceled') then
    v_result := private.failure(p_request_id,'INVALID_TRANSITION',null,v_task.version);
  elsif p_action <> 'remove' and v_host is null then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','httpsUrl');
  elsif p_action <> 'remove' and char_length(btrim(coalesce(p_description,''))) > 2000 then
    v_result := private.failure(p_request_id,'VALIDATION_FAILED','description');
  else
    v_now := clock_timestamp();
    if p_action <> 'remove' then
      v_url := p_https_url; -- preserve the validated original URL; normalize host separately
    end if;
    if p_action='create' then
      insert into public.task_external_evidence(project_id,task_id,https_url,host,description,submitted_by,created_at,updated_at)
        values(p_project_id,v_task_id,v_url,v_host,btrim(coalesce(p_description,'')),v_actor,v_now,v_now)
        returning * into v_evidence;
      -- Create fences the task aggregate and advances it, so concurrent creates cannot share a stale version.
      update public.tasks set version=version+1,updated_at=v_now
        where id=v_task_id returning * into v_task;
      v_event := 'external_evidence_created';
      v_key := 'external_evidence:' || v_evidence.id || ':version:1:created';
    else
      v_event := case when p_action='update' then 'external_evidence_updated' else 'external_evidence_removed' end;
      v_key := 'external_evidence:' || v_evidence.id || ':version:' || (v_evidence.version+1) ||
        case when p_action='update' then ':updated' else ':removed' end;
      insert into public.task_external_evidence_revisions(
        project_id,task_id,evidence_id,version,https_url,host,description,submitted_by,
        evidence_created_at,evidence_updated_at,action,changed_by,changed_at,request_id,command_request_id,occurrence_key
      ) values (
        p_project_id,v_task_id,v_evidence.id,v_evidence.version,v_evidence.https_url,v_evidence.host,
        v_evidence.description,v_evidence.submitted_by,v_evidence.created_at,v_evidence.updated_at,
        case when p_action='update' then 'updated' else 'removed' end,
        v_actor,v_now,p_request_id,v_claim.command_id,v_key
      );
      update public.task_external_evidence set
        https_url=case when p_action='update' then v_url else https_url end,
        host=case when p_action='update' then v_host else host end,
        description=case when p_action='update' then btrim(coalesce(p_description,'')) else description end,
        revoked_at=case when p_action='remove' then v_now else null end,
        revoked_by=case when p_action='remove' then v_actor else null end,
        version=version+1,updated_at=v_now
      where id=v_evidence.id returning * into v_evidence;
    end if;
    perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,v_event,
      'external_evidence',v_evidence.id,p_request_id,jsonb_build_object(
        'schemaVersion',1,'policyVersion',1,'occurrenceKey',v_key,'occurredAt',v_now,
        'aggregateVersion',v_evidence.version,'responsibleUserId',v_task.assignee_id,
        'taskId',v_task_id,'evidenceId',v_evidence.id,'evidenceVersion',v_evidence.version,
        'host',v_evidence.host,'revokedAt',v_evidence.revoked_at
      ));
    v_result := jsonb_build_object('ok',true,'data',jsonb_build_object(
      'evidenceId',v_evidence.id,'taskId',v_task_id,'taskVersion',v_task.version,
      'evidenceVersion',v_evidence.version,'revokedAt',v_evidence.revoked_at
    ),'requestId',p_request_id,'replayed',false,
      'aggregateType',case when p_action='create' then 'task' else 'external_evidence' end,
      'aggregateId',case when p_action='create' then v_task_id else v_evidence.id end,
      'aggregateVersion',case when p_action='create' then v_task.version else v_evidence.version end);
    return private.complete_command(v_claim.command_id,v_result,v_result->>'aggregateType',
      (v_result->>'aggregateId')::uuid,(v_result->>'aggregateVersion')::integer);
  end if;
  return private.complete_command(v_claim.command_id,v_result);
end;
$$;

create function public.cmd_create_external_evidence(
  p_project_id uuid,p_task_id uuid,p_https_url text,p_description text,p_request_id uuid,p_expected_version integer
) returns jsonb language sql security definer set search_path = '' as $$
  select private.external_evidence_command('create',p_project_id,p_task_id,p_https_url,p_description,p_request_id,p_expected_version);
$$;
create function public.cmd_update_external_evidence(
  p_project_id uuid,p_evidence_id uuid,p_https_url text,p_description text,p_request_id uuid,p_expected_version integer
) returns jsonb language sql security definer set search_path = '' as $$
  select private.external_evidence_command('update',p_project_id,p_evidence_id,p_https_url,p_description,p_request_id,p_expected_version);
$$;
create function public.cmd_remove_external_evidence(
  p_project_id uuid,p_evidence_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language sql security definer set search_path = '' as $$
  select private.external_evidence_command('remove',p_project_id,p_evidence_id,null,null,p_request_id,p_expected_version);
$$;

revoke all on function private.external_evidence_url_host(text),
  private.external_evidence_revision_immutable(),
  private.external_evidence_can_write(uuid,uuid,uuid,uuid,boolean),
  private.external_evidence_command(text,uuid,uuid,text,text,uuid,integer)
  from public, anon, authenticated, service_role;
revoke all on function public.cmd_create_external_evidence(uuid,uuid,text,text,uuid,integer),
  public.cmd_update_external_evidence(uuid,uuid,text,text,uuid,integer),
  public.cmd_remove_external_evidence(uuid,uuid,uuid,integer) from public, anon, authenticated, service_role;
grant execute on function public.cmd_create_external_evidence(uuid,uuid,text,text,uuid,integer),
  public.cmd_update_external_evidence(uuid,uuid,text,text,uuid,integer),
  public.cmd_remove_external_evidence(uuid,uuid,uuid,integer) to authenticated;

comment on table public.task_external_evidence is
  'Private project link metadata. Restrictive task/project FKs preserve history. No network fetch or Storage accounting. Revocation retains metadata.';
comment on table public.task_external_evidence_revisions is
  'Immutable pre-change link metadata, not external document versions. Only identity references may be nulled by trusted account lifecycle processing.';
