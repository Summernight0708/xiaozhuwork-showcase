-- F-only additive migration. Safe by default: NO Auth user deletion, Storage purge or project hard delete.
-- The release gate in docs/handoff/followup-f-integration-request.md is required.
create table public.account_lifecycle_requests (
  user_id uuid primary key references auth.users(id) on delete restrict,
  state text not null check (state in ('pending','canceled','blocked','redacted')),
  generation integer not null check (generation > 0),
  version integer not null check (version > 0),
  requested_at timestamptz not null,
  cancel_until timestamptz not null,
  canceled_at timestamptz,
  auth_revoked_at timestamptz,
  redacted_at timestamptz,
  updated_at timestamptz not null default transaction_timestamp(),
  constraint lifecycle_window_valid check (cancel_until > requested_at),
  constraint lifecycle_cancel_state check (
    (state='canceled' and canceled_at is not null) or
    (state<>'canceled' and canceled_at is null)
  )
);
create index account_lifecycle_due on public.account_lifecycle_requests (cancel_until)
  where state='pending';

create table private.account_lifecycle_audit (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  generation integer not null,
  action text not null,
  request_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default transaction_timestamp()
);
create unique index account_lifecycle_audit_request
  on private.account_lifecycle_audit(user_id,generation,action,request_id)
  where request_id is not null;

create table public.project_retention_notices (
  project_id uuid not null references public.projects(id) on delete cascade,
  generation integer not null,
  node text not null check (node in ('retention_30d','recovery_started','recovery_7d')),
  created_at timestamptz not null default transaction_timestamp(),
  primary key(project_id,generation,node)
);
create table private.project_purge_queue (
  project_id uuid not null references public.projects(id) on delete cascade,
  generation integer not null,
  cycle_version integer not null,
  recovery_until timestamptz not null,
  state text not null default 'awaiting_release_gate'
    check (state in ('awaiting_release_gate','invalidated','blocked','completed')),
  created_at timestamptz not null default transaction_timestamp(),
  updated_at timestamptz not null default transaction_timestamp(),
  primary key(project_id,generation)
);

alter table public.account_lifecycle_requests enable row level security;
alter table public.project_retention_notices enable row level security;
revoke all on public.account_lifecycle_requests, public.project_retention_notices
  from public,anon,authenticated,service_role;
revoke all on private.account_lifecycle_audit, private.project_purge_queue
  from public,anon,authenticated,service_role;

create function public.account_lifecycle_access_allowed(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user is not null
    and (p_user = auth.uid() or auth.role() = 'service_role')
    and not exists(
    select 1 from public.account_lifecycle_requests l
    where l.user_id=p_user and l.state<>'canceled'
  );
$$;
revoke all on function public.account_lifecycle_access_allowed(uuid) from public,anon,authenticated;
grant execute on function public.account_lifecycle_access_allowed(uuid) to authenticated;

-- Supplement all existing row policies. Does not protect SECURITY DEFINER
-- routines or already-signed Storage URLs; those G gates are mandatory.
do $$
declare v_name text;
begin
  foreach v_name in array array[
    'profiles','projects','project_members','tasks','task_dependencies','business_events',
    'notifications','project_join_requests','task_assignment_offers','task_files',
    'task_file_versions','task_review_rounds','contribution_reports','contribution_items',
    'contribution_confirmations','project_entitlements','account_entitlements',
    'task_collaborators'
  ] loop
    if to_regclass('public.'||v_name) is not null then
      execute format(
        'create policy account_deletion_access_fence on public.%I as restrictive for all to authenticated using (public.account_lifecycle_access_allowed((select auth.uid()))) with check (public.account_lifecycle_access_allowed((select auth.uid())))',
        v_name
      );
    end if;
  end loop;
end;
$$;

create function public.get_account_lifecycle_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := auth.uid(); v_state public.account_lifecycle_requests%rowtype;
begin
  if v_actor is null then return jsonb_build_object('ok',false,'code','UNAUTHENTICATED'); end if;
  select * into v_state from public.account_lifecycle_requests where user_id=v_actor;
  if not found then
    return jsonb_build_object('ok',true,'data',jsonb_build_object('state','active','version',0));
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object(
    'state',v_state.state,'version',v_state.version,'generation',v_state.generation,
    'requestedAt',v_state.requested_at,'cancelUntil',v_state.cancel_until,
    'authRevokedAt',v_state.auth_revoked_at,'redactedAt',v_state.redacted_at));
end;
$$;

create function public.cmd_request_account_deletion(
  p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_claim record;v_replay jsonb;v_result jsonb;
  v_state public.account_lifecycle_requests%rowtype;
  v_id uuid;v_reason text;v_seq integer:=0;
  v_version integer;v_generation integer;
  v_time timestamptz:=transaction_timestamp();
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','requestId'); end if;
  select * into v_claim from private.claim_command(v_actor,
    'cmd_request_account_deletion',p_request_id,
    private.payload_hash(jsonb_build_object('expectedVersion',p_expected_version)),
    v_actor,null);
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  perform 1 from public.profiles where id=v_actor for update;
  if not found then
    return private.complete_command(v_claim.command_id,
      private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'));
  end if;
  -- F0 lock order: claim -> profile -> projects UUID ascending -> child rows.
  for v_id in
    select distinct p.id from public.projects p
    join public.project_members m on m.project_id=p.id
    where m.user_id=v_actor and m.member_state='active' order by p.id
  loop
    perform 1 from public.projects where id=v_id for update;
  end loop;
  select * into v_state from public.account_lifecycle_requests
    where user_id=v_actor for update;
  if p_expected_version is null or coalesce(v_state.version,0)<>p_expected_version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,coalesce(v_state.version,0));
  elsif v_state.state is not null and v_state.state<>'canceled' then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  else
    select case
      when exists(select 1 from public.project_members m
        where m.user_id=v_actor and m.role='leader' and m.member_state='active')
        then '仍为项目组长，需先合法移交'
      when exists(select 1 from public.tasks t
        where t.assignee_id=v_actor and t.status not in ('completed','canceled'))
        then '仍为未完成任务的主负责人'
      when exists(select 1 from public.task_collaborators c
        join public.tasks t on t.id=c.task_id
        where c.user_id=v_actor and c.state in ('pending','accepted')
          and t.status not in ('completed','canceled'))
        then '仍承担未完成的协作者责任'
      when exists(select 1 from public.task_review_rounds r
        join public.tasks t on t.id=r.task_id
        where r.state='pending' and (t.created_by=v_actor or r.reviewed_by=v_actor))
        then '仍有本人待处理的任务验收'
      when exists(select 1 from public.contribution_reports r
        join public.project_members m on m.project_id=r.project_id
        where m.user_id=v_actor and m.member_state='active'
        and r.state='draft'
        and not exists (select 1 from public.contribution_confirmations c
          where c.report_id=r.id and c.user_id=v_actor))
        then '仍有待本人确认的贡献报告'
      else null end into v_reason;
    if v_reason is not null then
      v_result:=private.failure(p_request_id,'ACCOUNT_DELETION_BLOCKED',null,null,
        jsonb_build_object('reason',v_reason));
    else
      v_version:=coalesce(v_state.version,0)+1;
      v_generation:=coalesce(v_state.generation,0)+1;
      insert into public.account_lifecycle_requests(
        user_id,state,generation,version,requested_at,cancel_until,canceled_at,
        auth_revoked_at,redacted_at,updated_at
      ) values(v_actor,'pending',v_generation,v_version,v_time,v_time+interval '30 days',
        null,null,null,v_time)
      on conflict(user_id) do update set state='pending',generation=excluded.generation,
        version=excluded.version,requested_at=excluded.requested_at,
        cancel_until=excluded.cancel_until,canceled_at=null,auth_revoked_at=null,
        redacted_at=null,updated_at=excluded.updated_at;
      insert into private.account_lifecycle_audit(user_id,generation,action,request_id,details)
        values(v_actor,v_generation,'requested',p_request_id,
          jsonb_build_object('cancelUntil',v_time+interval '30 days'));
      for v_id in select distinct m.project_id from public.project_members m
        where m.user_id=v_actor order by m.project_id
      loop
        v_seq:=v_seq+1;
        perform private.emit_event(v_claim.command_id,v_seq,v_id,v_actor,
          'account_deletion_requested','account',v_actor,p_request_id,
          jsonb_build_object('schemaVersion',1,'policyVersion',1,'aggregateVersion',v_version,
            'occurrenceKey','account:'||v_actor||':deletion:'||v_generation,
            'occurredAt',v_time,'responsibleUserId',v_actor));
      end loop;
      v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
        'state','pending','cancelUntil',v_time+interval '30 days',
        'generation',v_generation),
        'requestId',p_request_id,'replayed',false,'aggregateType','account',
        'aggregateId',v_actor,'aggregateVersion',v_version);
    end if;
  end if;
  return private.complete_command(v_claim.command_id,v_result,'account',v_actor,
    case when v_result->>'ok'='true' then v_version else null end);
end;
$$;

create function public.cmd_cancel_account_deletion(
  p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid:=auth.uid();v_claim record;v_replay jsonb;v_result jsonb;
  v_state public.account_lifecycle_requests%rowtype;
  v_id uuid;v_seq integer:=0;v_time timestamptz:=transaction_timestamp();
begin
  if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(p_request_id,'VALIDATION_FAILED','requestId'); end if;
  select * into v_claim from private.claim_command(v_actor,
    'cmd_cancel_account_deletion',p_request_id,
    private.payload_hash(jsonb_build_object('expectedVersion',p_expected_version)),
    v_actor,null);
  v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
  if v_replay is not null then return v_replay; end if;
  perform 1 from public.profiles where id=v_actor for update;
  if not found then return private.complete_command(v_claim.command_id,
    private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED')); end if;
  for v_id in select distinct p.id from public.projects p
    join public.project_members m on m.project_id=p.id
    where m.user_id=v_actor order by p.id
  loop
    perform 1 from public.projects where id=v_id for update;
  end loop;
  select * into v_state from public.account_lifecycle_requests
    where user_id=v_actor for update;
  if not found then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  elsif p_expected_version is distinct from v_state.version then
    v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_state.version);
  elsif v_state.state<>'pending' or v_state.redacted_at is not null then
    v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
  elsif v_time>=v_state.cancel_until then
    v_result:=private.failure(p_request_id,'RETENTION_WINDOW_EXPIRED');
  elsif v_state.auth_revoked_at is not null then
    -- G must provide independent OTP identity recovery + Auth unban before cancellation.
    v_result:=private.failure(p_request_id,'ACCOUNT_DELETION_BLOCKED',null,null,
      jsonb_build_object('reason','先通过受信任的身份恢复流程'));
  else
    update public.account_lifecycle_requests set state='canceled',canceled_at=v_time,
      version=version+1,updated_at=v_time where user_id=v_actor;
    insert into private.account_lifecycle_audit(user_id,generation,action,request_id)
      values(v_actor,v_state.generation,'canceled',p_request_id);
    for v_id in select distinct m.project_id from public.project_members m
      where m.user_id=v_actor order by m.project_id
    loop
      v_seq:=v_seq+1;
      perform private.emit_event(v_claim.command_id,v_seq,v_id,v_actor,
        'account_deletion_canceled','account',v_actor,p_request_id,
        jsonb_build_object('schemaVersion',1,'policyVersion',1,
          'occurrenceKey','account:'||v_actor||':deletion:'||v_state.generation||':cancel',
          'occurredAt',v_time,'aggregateVersion',v_state.version+1,
          'responsibleUserId',v_actor));
    end loop;
    v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object('state','canceled'),
      'requestId',p_request_id,'replayed',false,'aggregateType','account',
      'aggregateId',v_actor,'aggregateVersion',v_state.version+1);
  end if;
  return private.complete_command(v_claim.command_id,v_result,'account',v_actor,
    case when v_result->>'ok'='true' then v_state.version+1 else null end);
end;
$$;

-- Auth is external to the SQL transaction. This protected checkpoint is only
-- for the trusted server that has independently confirmed actual revocation.
create function private.record_account_auth_revocation(p_user uuid,p_generation integer)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role()<>'service_role' then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  update public.account_lifecycle_requests
    set auth_revoked_at=coalesce(auth_revoked_at,transaction_timestamp()),
        updated_at=transaction_timestamp()
    where user_id=p_user and generation=p_generation and state='pending';
  return found;
end;
$$;

create function private.process_account_lifecycle(batch_limit integer, now timestamptz)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row record;v_blocked integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if batch_limit is null or batch_limit not between 1 and 100 or now is null then
    raise exception 'INVALID_BATCH' using errcode='22023';
  end if;
  -- Redaction of immutable contribution snapshots, JSONB, Auth PII and exports
  -- is NOT implemented in the F0 baseline. Fail closed, never claim deletion.
  for v_row in
    select user_id,generation from public.account_lifecycle_requests
    where state='pending' and cancel_until<=now and auth_revoked_at is not null
    order by cancel_until,user_id for update skip locked limit batch_limit
  loop
    update public.account_lifecycle_requests set state='blocked',version=version+1,
      updated_at=transaction_timestamp() where user_id=v_row.user_id;
    insert into private.account_lifecycle_audit(user_id,generation,action,details)
      values(v_row.user_id,v_row.generation,'redaction_blocked',
        jsonb_build_object('reason','history_and_auth_redaction_gate_not_integrated'));
    v_blocked:=v_blocked+1;
  end loop;
  return jsonb_build_object('ok',true,'blockedForRedaction',v_blocked,
    'irreversibleDeletes',0);
end;
$$;

create function private.process_project_retention(batch_limit integer, now timestamptz)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_cycle record;v_current record;v_node text;v_checked integer:=0;
  v_notices integer:=0;v_queued integer:=0;v_msg text;
begin
  if auth.role()<>'service_role' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if batch_limit is null or batch_limit not between 1 and 100 or now is null then
    raise exception 'INVALID_BATCH' using errcode='22023';
  end if;
  if to_regclass('public.project_archive_cycles') is null then
    return jsonb_build_object('ok',false,'code','ARCHIVE_CYCLES_NOT_INTEGRATED');
  end if;
  for v_cycle in execute
    'select project_id,generation,version,archived_at,retain_until,recovery_until,restored_at
     from public.project_archive_cycles where restored_at is null
     order by retain_until,project_id,generation'
  loop
    exit when v_checked>=batch_limit;
    if now<v_cycle.retain_until-interval '30 days' then continue; end if;
    select id,archived_at into v_current from public.projects
      where id=v_cycle.project_id for update skip locked;
    if not found or v_current.archived_at is null
      or v_current.archived_at is distinct from v_cycle.archived_at then
      update private.project_purge_queue set state='invalidated',
        updated_at=transaction_timestamp()
      where project_id=v_cycle.project_id and generation=v_cycle.generation
        and state='awaiting_release_gate';
      continue;
    end if;
    update private.project_purge_queue set state='invalidated',
      updated_at=transaction_timestamp()
    where project_id=v_cycle.project_id and generation=v_cycle.generation
      and (cycle_version<>v_cycle.version or recovery_until<>v_cycle.recovery_until)
      and state='awaiting_release_gate';
    for v_node in select unnest(array['retention_30d','recovery_started','recovery_7d'])
    loop
      if (v_node='retention_30d' and now>=v_cycle.retain_until-interval '30 days'
          and now<v_cycle.retain_until)
        or (v_node='recovery_started' and now>=v_cycle.retain_until
          and now<v_cycle.recovery_until)
        or (v_node='recovery_7d' and now>=v_cycle.recovery_until-interval '7 days'
          and now<v_cycle.recovery_until) then
        insert into public.project_retention_notices(project_id,generation,node)
          values(v_cycle.project_id,v_cycle.generation,v_node) on conflict do nothing;
        if found then
          v_msg:=case v_node when 'retention_30d'
            then '项目归档保留期即将结束，必要时请延长保留。'
            when 'recovery_started'
            then '项目进入仅恢复窗口，请在期限内恢复。'
            else '项目恢复窗口即将结束，请尽快处理。' end;
          insert into public.notifications(project_id,recipient_id,notification_type,
            title,entity_type,entity_id,message)
          select v_cycle.project_id,m.user_id,'project_retention','归档通知','project',
            v_cycle.project_id,v_msg
          from public.project_members m
          where m.project_id=v_cycle.project_id and m.member_state='active'
            and m.user_id is not null
            and public.account_lifecycle_access_allowed(m.user_id);
          v_notices:=v_notices+1;
        end if;
      end if;
    end loop;
    if now>=v_cycle.recovery_until then
      insert into private.project_purge_queue(
        project_id,generation,cycle_version,recovery_until
      ) values(v_cycle.project_id,v_cycle.generation,v_cycle.version,v_cycle.recovery_until)
      on conflict(project_id,generation) do update set state='awaiting_release_gate',
        cycle_version=excluded.cycle_version,recovery_until=excluded.recovery_until,
        updated_at=transaction_timestamp()
      where private.project_purge_queue.state='invalidated';
      if found then v_queued:=v_queued+1; end if;
    end if;
    v_checked:=v_checked+1;
  end loop;
  return jsonb_build_object('ok',true,'cyclesChecked',v_checked,
    'notificationNodesSent',v_notices,'purgeCandidates',v_queued,
    'irreversibleDeletes',0);
end;
$$;

-- Service role records successful external Auth/session revocation using a
-- generation-fenced checkpoint. This does NOT itself perform or fake a ban.
create function public.lifecycle_record_auth_revocation(
  p_user uuid,p_generation integer
) returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  return private.record_account_auth_revocation(p_user,p_generation);
end;
$$;
revoke all on function public.lifecycle_record_auth_revocation(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_record_auth_revocation(uuid,integer) to service_role;

-- Private schema is deliberately NOT exposed in PostgREST. Only service_role
-- may execute this public bridge; anon/authenticated have no EXECUTE permission.
create function public.lifecycle_worker_tick(p_batch_limit integer default 25)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  return jsonb_build_object(
    'account',private.process_account_lifecycle(p_batch_limit,transaction_timestamp()),
    'projects',private.process_project_retention(p_batch_limit,transaction_timestamp()));
end;
$$;

revoke all on function public.get_account_lifecycle_status()
  from public,anon,authenticated,service_role;
grant execute on function public.get_account_lifecycle_status() to authenticated;
revoke all on function public.cmd_request_account_deletion(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_request_account_deletion(uuid,integer) to authenticated;
revoke all on function public.cmd_cancel_account_deletion(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.cmd_cancel_account_deletion(uuid,integer) to authenticated;
revoke all on function public.lifecycle_worker_tick(integer)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_worker_tick(integer) to service_role;
revoke all on function private.record_account_auth_revocation(uuid,integer)
  from public,anon,authenticated,service_role;
revoke all on function private.process_account_lifecycle(integer,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.process_project_retention(integer,timestamptz)
  from public,anon,authenticated,service_role;

comment on table public.account_lifecycle_requests is
  'Account deletion request and 30 day cancel window. State blocked is NOT completion.';
comment on table private.project_purge_queue is
  'Release-gated candidate queue, never an automatic permanent deletion command.';
