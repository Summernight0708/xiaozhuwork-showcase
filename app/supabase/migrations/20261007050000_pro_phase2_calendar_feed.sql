-- Pro Phase 2 / E: private, revocable, single-project calendar subscription.
-- Release of external_integrations remains owned by G.
create table public.project_calendar_subscriptions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  issuer_membership_id uuid not null references public.project_members(id),
  issuer_user_id uuid not null references auth.users(id),
  token_hash bytea not null unique,
  created_at timestamptz not null default transaction_timestamp(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  version integer not null default 1 check (version > 0),
  show_titles boolean not null default false,
  request_id uuid not null,
  constraint phase2_calendar_hash_length check (octet_length(token_hash) = 32),
  constraint phase2_calendar_validity check (
    expires_at > created_at and expires_at <= created_at + interval '90 days'
  ),
  constraint phase2_calendar_issuer_request unique(project_id, issuer_user_id, request_id)
);
create index phase2_calendar_project_issuer_idx
  on public.project_calendar_subscriptions(project_id, issuer_user_id, created_at desc);
create index phase2_calendar_unrevoked_idx
  on public.project_calendar_subscriptions(project_id, expires_at)
  where revoked_at is null;
create index phase2_calendar_tasks_due_idx
  on public.tasks(project_id, deadline_at, id)
  where status not in ('completed', 'canceled');

alter table public.project_calendar_subscriptions enable row level security;
revoke all on public.project_calendar_subscriptions from public, anon, authenticated, service_role;

create function public.get_project_calendar_subscriptions(p_project_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_data jsonb;
  v_project_version integer;
begin
  if v_actor is null then
    return private.failure(null, 'UNAUTHENTICATED');
  end if;
  if not private.is_active_leader(p_project_id, v_actor) then
    return private.failure(null, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  select p.version into v_project_version
    from public.projects p where p.id = p_project_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'createdAt', s.created_at, 'expiresAt', s.expires_at,
    'revokedAt', s.revoked_at, 'version', s.version,
    'showTitles', s.show_titles
  ) order by s.created_at desc, s.id desc), '[]'::jsonb)
    into v_data
    from public.project_calendar_subscriptions s
    where s.project_id = p_project_id;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'projectVersion', v_project_version, 'subscriptions', v_data));
end;
$$;
revoke all on function public.get_project_calendar_subscriptions(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_project_calendar_subscriptions(uuid) to authenticated;

create function public.cmd_create_calendar_feed_subscription(
  p_project_id uuid, p_request_id uuid, p_expected_version integer,
  p_show_titles boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_claim record;
  v_hash bytea;
  v_replay jsonb;
  v_project public.projects%rowtype;
  v_membership uuid;
  v_id uuid;
  v_token text;
  v_created timestamptz := transaction_timestamp();
  v_expiry timestamptz;
  v_result jsonb;
  v_failure jsonb;
begin
  if v_actor is null then return private.failure(p_request_id, 'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null, 'VALIDATION_FAILED', 'requestId'); end if;
  if not private.is_active_leader(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id, 'expectedVersion', p_expected_version,
    'showTitles', p_show_titles
  ));
  select * into v_claim from private.claim_command(
    v_actor, 'cmd_create_calendar_feed_subscription', p_request_id, v_hash,
    null, p_project_id
  );
  if not v_claim.payload_matches then
    return private.failure(p_request_id, 'IDEMPOTENCY_KEY_REUSED');
  end if;
  if v_claim.prior_result is not null then
    if not private.is_active_leader(p_project_id, v_actor) then
      return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
    end if;
    return jsonb_set(
      jsonb_set(v_claim.prior_result, '{replayed}', 'true'::jsonb),
      '{data,token}', 'null'::jsonb, true
    );
  end if;
  select * into v_project from public.projects
    where id = p_project_id for update;
  select pm.id into v_membership from public.project_members pm
    where pm.project_id = p_project_id and pm.user_id = v_actor
      and pm.role = 'leader' and pm.member_state = 'active'
    for share;
  if v_membership is null or v_project.id is null or v_project.leader_id is distinct from v_actor then
    v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or p_expected_version <> v_project.version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_project.version);
  elsif v_project.lifecycle_state <> 'active' or v_project.archived_at is not null then
    v_result := private.failure(p_request_id, 'INVALID_TRANSITION');
  elsif p_show_titles is null then
    v_result := private.failure(p_request_id, 'VALIDATION_FAILED', 'showTitles');
  else
    v_failure := private.project_capability_failure(
      p_project_id, 'external_integrations', p_request_id
    );
    if v_failure is not null then
      v_result := v_failure;
    else
      v_token := encode(extensions.gen_random_bytes(32), 'hex');
      v_expiry := v_created + interval '90 days';
      insert into public.project_calendar_subscriptions (
        project_id, issuer_membership_id, issuer_user_id, token_hash,
        created_at, expires_at, show_titles, request_id
      ) values (
        p_project_id, v_membership, v_actor,
        extensions.digest(convert_to(v_token, 'utf8'), 'sha256'),
        v_created, v_expiry, p_show_titles, p_request_id
      ) returning id into v_id;
      update public.projects set version = version + 1, updated_at = now()
        where id = p_project_id returning version into v_project.version;
      perform private.emit_event(
        v_claim.command_id, 1, p_project_id, v_actor,
        'calendar_subscription_created', 'calendar_subscription',
        v_id, p_request_id, jsonb_build_object('showTitles', p_show_titles)
      );
      -- Persist metadata ONLY; the secret exists solely in this invocation.
      v_result := jsonb_build_object(
        'ok', true, 'requestId', p_request_id, 'replayed', false,
        'aggregateType', 'project', 'aggregateId', p_project_id,
        'aggregateVersion', v_project.version,
        'data', jsonb_build_object(
          'id', v_id, 'token', null, 'createdAt', v_created,
          'expiresAt', v_expiry, 'revokedAt', null,
          'version', 1, 'showTitles', p_show_titles
        )
      );
      perform private.complete_command(
        v_claim.command_id, v_result, 'project', p_project_id, v_project.version
      );
      return jsonb_set(v_result, '{data,token}', to_jsonb(v_token), true);
    end if;
  end if;
  return private.complete_command(v_claim.command_id, v_result);
end;
$$;
revoke all on function public.cmd_create_calendar_feed_subscription(uuid,uuid,integer,boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_create_calendar_feed_subscription(uuid,uuid,integer,boolean)
  to authenticated;

create function public.cmd_revoke_calendar_feed_subscription(
  p_project_id uuid, p_subscription_id uuid, p_request_id uuid,
  p_expected_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash bytea;
  v_claim record;
  v_project public.projects%rowtype;
  v_sub public.project_calendar_subscriptions%rowtype;
  v_result jsonb;
begin
  if v_actor is null then return private.failure(p_request_id, 'UNAUTHENTICATED'); end if;
  if p_request_id is null then return private.failure(null, 'VALIDATION_FAILED', 'requestId'); end if;
  if not private.is_active_leader(p_project_id, v_actor) then
    return private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_hash := private.payload_hash(jsonb_build_object(
    'projectId', p_project_id, 'subscriptionId', p_subscription_id,
    'expectedVersion', p_expected_version
  ));
  select * into v_claim from private.claim_command(
    v_actor, 'cmd_revoke_calendar_feed_subscription', p_request_id, v_hash,
    null, p_project_id
  );
  if not v_claim.payload_matches then
    return private.failure(p_request_id, 'IDEMPOTENCY_KEY_REUSED');
  end if;
  if v_claim.prior_result is not null then
    return jsonb_set(v_claim.prior_result, '{replayed}', 'true'::jsonb);
  end if;
  select * into v_project from public.projects
    where id = p_project_id for update;
  select * into v_sub from public.project_calendar_subscriptions s
    where s.id = p_subscription_id and s.project_id = p_project_id for update;
  if v_project.id is null or
    not private.is_active_leader(p_project_id, v_actor) or v_sub.id is null then
    v_result := private.failure(p_request_id, 'NOT_FOUND_OR_NOT_AUTHORIZED');
  elsif p_expected_version is null or v_sub.version <> p_expected_version then
    v_result := private.failure(p_request_id, 'STALE_VERSION', null, v_sub.version);
  elsif v_sub.revoked_at is not null then
    v_result := private.failure(p_request_id, 'INVALID_TRANSITION');
  else
    update public.project_calendar_subscriptions s
      set revoked_at = transaction_timestamp(), version = version + 1
      where s.id = v_sub.id
      returning * into v_sub;
    perform private.emit_event(
      v_claim.command_id, 1, p_project_id, v_actor,
      'calendar_subscription_revoked', 'calendar_subscription',
      v_sub.id, p_request_id, '{}'::jsonb
    );
    v_result := jsonb_build_object(
      'ok', true, 'requestId', p_request_id, 'replayed', false,
      'data', jsonb_build_object('id', v_sub.id, 'version', v_sub.version,
        'revokedAt', v_sub.revoked_at)
    );
  end if;
  return private.complete_command(
    v_claim.command_id, v_result, 'calendar_subscription',
    case when v_result->>'ok' = 'true' then v_sub.id else null end,
    case when v_result->>'ok' = 'true' then v_sub.version else null end
  );
end;
$$;
revoke all on function public.cmd_revoke_calendar_feed_subscription(uuid,uuid,uuid,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.cmd_revoke_calendar_feed_subscription(uuid,uuid,uuid,integer)
  to authenticated;

-- All checks and the scoped task read happen in a single server transaction.
-- The credential-bearing RPC accepts no project id and returns no secret.
create function private.phase2_calendar_feed_payload(p_token text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_sub public.project_calendar_subscriptions%rowtype;
  v_events jsonb;
  v_count integer;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_sub
    from public.project_calendar_subscriptions s
    where s.token_hash = extensions.digest(convert_to(p_token, 'utf8'), 'sha256')
      and s.revoked_at is null
      and s.expires_at > transaction_timestamp()
    for share;
  if v_sub.id is null then return null; end if;
  perform 1 from public.projects p
    where p.id = v_sub.project_id
      and p.leader_id = v_sub.issuer_user_id
      and p.lifecycle_state = 'active' and p.archived_at is null
    for share;
  if not found then return null; end if;
  perform 1 from public.project_members pm
    where pm.id = v_sub.issuer_membership_id
      and pm.project_id = v_sub.project_id
      and pm.user_id = v_sub.issuer_user_id
      and pm.member_state = 'active' and pm.role = 'leader'
    for share;
  if not found then return null; end if;
  if not private.project_has_capability(v_sub.project_id, 'external_integrations') then
    return null;
  end if;
  with due as (
    select
      encode(extensions.digest(convert_to(v_sub.project_id::text || ':' ||
        t.id::text, 'utf8'), 'sha256'), 'hex') as uid,
      t.deadline_at, t.title
    from public.tasks t
    where t.project_id = v_sub.project_id
      and t.status not in ('completed', 'canceled')
      and t.canceled_at is null
      and t.deadline_at > transaction_timestamp()
      and t.deadline_at <= transaction_timestamp() + interval '90 days'
    order by t.deadline_at, t.id
    limit 501
  )
  select count(*)::integer, coalesce(jsonb_agg(jsonb_build_object(
    'uid', uid, 'deadline', deadline_at,
    'title', case when v_sub.show_titles then title else null end
  ) order by deadline_at, uid) filter (where ordinal <= 500), '[]'::jsonb)
    into v_count, v_events
    from (select due.*, row_number() over(order by deadline_at, uid) as ordinal from due) ranked;
  return jsonb_build_object('ok', true, 'events', v_events,
    'showTitles', v_sub.show_titles, 'truncated', v_count > 500);
end;
$$;
revoke all on function private.phase2_calendar_feed_payload(text)
  from public, anon, authenticated, service_role;

-- Public-schema wrapper is callable by the Edge service_role ONLY.
-- Never expose a direct hash lookup or project-id-scoped anonymous query.
create function public.phase2_calendar_feed_lookup(p_token text)
returns jsonb
language sql volatile security definer set search_path = '' as $$
  select private.phase2_calendar_feed_payload(p_token);
$$;
revoke all on function public.phase2_calendar_feed_lookup(text)
  from public, anon, authenticated, service_role;
grant execute on function public.phase2_calendar_feed_lookup(text) to service_role;
