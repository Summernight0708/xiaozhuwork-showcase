-- C1 commercial validation: freeze account Pro grant-source semantics.
--
-- This migration intentionally performs a one-time normalization of legacy
-- grant_source values before installing the new constraints. The immutable
-- account entitlement audit trigger is disabled only for that normalization
-- and is explicitly re-enabled before the migration can complete.
--
-- Production application remains gated by the WP-INTEGRATION pre-migration
-- checksum-verified database backup and row-count evidence.

update public.account_entitlements
set grant_source = 'legacy_unknown'
where grant_source not in ('test','gift','commercial','other');

alter table public.account_entitlement_audit
  disable trigger account_entitlement_audit_immutable;

update public.account_entitlement_audit
set grant_source = 'legacy_unknown'
where grant_source not in ('test','gift','commercial','other');

alter table public.account_entitlement_audit
  enable trigger account_entitlement_audit_immutable;

alter table public.account_entitlements
  add constraint account_entitlements_grant_source_v1
  check (grant_source in ('test','gift','commercial','other','legacy_unknown'));

alter table public.account_entitlement_audit
  add constraint account_entitlement_audit_grant_source_v1
  check (grant_source in ('test','gift','commercial','other','legacy_unknown'));

CREATE OR REPLACE FUNCTION public.cmd_set_account_entitlement_service(p_user_id uuid, p_request_id uuid, p_plan text, p_status text, p_starts_at timestamp with time zone, p_expires_at timestamp with time zone, p_expected_version integer, p_granted_by uuid, p_grant_source text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_at timestamptz := transaction_timestamp();
  v_hash bytea;
  v_existing_cmd private.account_entitlement_service_commands%rowtype;
  v_before public.account_entitlements%rowtype;
  v_after public.account_entitlements%rowtype;
  v_current_version integer := 0;
  v_new_starts_at timestamptz;
  v_new_expires_at timestamptz;
  v_old_active boolean := false;
  v_new_active boolean := false;
  v_project_id uuid;
  v_before_project record;
  v_other_active_source boolean;
  v_action text;
  v_result jsonb;
begin
  if p_request_id is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','requestId');
  end if;
  if p_user_id is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','userId','requestId',p_request_id);
  end if;
  if p_plan <> 'pro' then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','plan','requestId',p_request_id);
  end if;
  if p_status not in ('active','cancelled') then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','status','requestId',p_request_id);
  end if;
  if p_starts_at is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','startsAt','requestId',p_request_id);
  end if;
  if p_expires_at is null or p_expires_at <= p_starts_at then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','expiresAt','requestId',p_request_id);
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','expectedVersion','requestId',p_request_id);
  end if;
  if p_grant_source is null
     or btrim(p_grant_source) not in ('test','gift','commercial','other') then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','grantSource','requestId',p_request_id);
  end if;
  if p_note is not null and char_length(p_note) > 2000 then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED','field','note','requestId',p_request_id);
  end if;

  v_hash := private.payload_hash(jsonb_build_object(
    'userId',p_user_id,
    'plan',p_plan,
    'status',p_status,
    'startsAt',p_starts_at,
    'expiresAt',p_expires_at,
    'expectedVersion',p_expected_version,
    'grantedBy',p_granted_by,
    'grantSource',btrim(p_grant_source),
    'note',p_note
  ));

  insert into private.account_entitlement_service_commands(request_id,payload_hash,result)
  values(p_request_id,v_hash,null)
  on conflict (request_id) do nothing;

  select *
  into v_existing_cmd
  from private.account_entitlement_service_commands c
  where c.request_id = p_request_id
  for update;

  if v_existing_cmd.payload_hash <> v_hash then
    return jsonb_build_object(
      'ok',false,'code','IDEMPOTENCY_KEY_REUSED',
      'requestId',p_request_id,'replayed',false
    );
  end if;
  if v_existing_cmd.result is not null then
    return jsonb_set(v_existing_cmd.result,'{replayed}','true'::jsonb,true);
  end if;

  perform 1
  from public.profiles p
  where p.id = p_user_id
  for update;

  if not found then
    v_result := jsonb_build_object(
      'ok',false,'code','NOT_FOUND_OR_NOT_AUTHORIZED',
      'requestId',p_request_id,'replayed',false
    );
    update private.account_entitlement_service_commands
    set result = v_result
    where request_id = p_request_id;
    return v_result;
  end if;

  select *
  into v_before
  from public.account_entitlements e
  where e.user_id = p_user_id
  for update;

  if found then
    v_current_version := v_before.version;
  else
    v_current_version := 0;
  end if;

  if p_expected_version <> v_current_version then
    v_result := jsonb_build_object(
      'ok',false,'code','STALE_VERSION',
      'requestId',p_request_id,'replayed',false,
      'currentVersion',v_current_version
    );
    update private.account_entitlement_service_commands
    set result = v_result
    where request_id = p_request_id;
    return v_result;
  end if;

  if p_status = 'cancelled' and v_current_version = 0 then
    v_result := jsonb_build_object(
      'ok',false,'code','INVALID_TRANSITION',
      'requestId',p_request_id,'replayed',false
    );
    update private.account_entitlement_service_commands
    set result = v_result
    where request_id = p_request_id;
    return v_result;
  end if;

  v_new_starts_at := case
    when p_status = 'cancelled' and p_starts_at >= v_at
      then v_at - interval '1 microsecond'
    else p_starts_at
  end;
  v_new_expires_at := case
    when p_status = 'cancelled' then v_at
    else p_expires_at
  end;

  if v_current_version > 0 then
    v_old_active :=
      v_before.plan = 'pro'
      and v_before.status = 'active'
      and v_before.starts_at <= v_at
      and v_at < v_before.expires_at;
  end if;

  v_new_active :=
    p_status = 'active'
    and p_starts_at <= v_at
    and v_at < p_expires_at;

  for v_project_id in
    select pm.project_id
    from public.project_members pm
    where pm.user_id = p_user_id
      and pm.member_state = 'active'
      and pm.role in ('leader','admin','member')
    order by pm.project_id
  loop
    perform 1
    from public.projects p
    where p.id = v_project_id
    for update;

    select *
    into v_before_project
    from private.resolve_project_entitlement(v_project_id, v_at);

    if v_before_project.state = 'grace'
       and v_before_project.grace_expires_at is not null then
      insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version,updated_at)
      values(
        v_project_id,
        v_before_project.grace_expires_at - interval '3 days',
        v_before_project.grace_expires_at,
        'account_expired',
        1,
        v_at
      )
      on conflict (project_id) do update
        set started_at = excluded.started_at,
            expires_at = excluded.expires_at,
            reason = excluded.reason,
            version = public.project_pro_grace.version + 1,
            updated_at = excluded.updated_at
        where public.project_pro_grace.expires_at < excluded.expires_at;
    end if;

    if v_old_active and not v_new_active then
      select exists (
        select 1
        from public.project_members pm
        where pm.project_id = v_project_id
          and pm.user_id is not null
          and pm.user_id <> p_user_id
          and pm.member_state = 'active'
          and pm.role in ('leader','admin','member')
          and private.is_account_pro(pm.user_id, v_at)
      )
      into v_other_active_source;

      if not v_other_active_source
         and not private.has_project_level_pro_grant(v_project_id, v_at) then
        insert into public.project_pro_grace(project_id,started_at,expires_at,reason,version,updated_at)
        values(
          v_project_id,
          v_at,
          v_at + interval '3 days',
          case when p_status='cancelled' then 'account_cancelled' else 'account_expired' end,
          1,
          v_at
        )
        on conflict (project_id) do update
          set started_at = excluded.started_at,
              expires_at = excluded.expires_at,
              reason = excluded.reason,
              version = public.project_pro_grace.version + 1,
              updated_at = excluded.updated_at;
      end if;
    end if;
  end loop;

  if v_current_version = 0 then
    insert into public.account_entitlements(
      user_id,plan,status,starts_at,expires_at,granted_at,granted_by,
      grant_source,note,version,created_at,updated_at
    ) values (
      p_user_id,p_plan,p_status,v_new_starts_at,v_new_expires_at,v_at,p_granted_by,
      btrim(p_grant_source),p_note,1,v_at,v_at
    )
    returning * into v_after;
    v_action := 'granted';
  else
    update public.account_entitlements
    set plan = p_plan,
        status = p_status,
        starts_at = v_new_starts_at,
        expires_at = v_new_expires_at,
        granted_at = v_at,
        granted_by = p_granted_by,
        grant_source = btrim(p_grant_source),
        note = p_note,
        version = version + 1,
        updated_at = v_at
    where user_id = p_user_id
    returning * into v_after;

    v_action := case
      when p_status = 'cancelled' then 'cancelled'
      when v_before.status = 'cancelled' and p_status = 'active' then 'granted'
      else 'updated'
    end;
  end if;

  insert into public.account_entitlement_audit(
    user_id,request_id,action,plan,status,starts_at,expires_at,
    granted_at,granted_by,grant_source,note,entitlement_version,created_at
  ) values (
    v_after.user_id,p_request_id,v_action,v_after.plan,v_after.status,
    v_after.starts_at,v_after.expires_at,v_after.granted_at,v_after.granted_by,
    v_after.grant_source,v_after.note,v_after.version,v_at
  );

  v_result := jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'userId',v_after.user_id,
      'plan',v_after.plan,
      'status',v_after.status,
      'startsAt',v_after.starts_at,
      'expiresAt',v_after.expires_at,
      'version',v_after.version
    ),
    'requestId',p_request_id,
    'replayed',false
  );

  update private.account_entitlement_service_commands
  set result = v_result
  where request_id = p_request_id;

  return v_result;
end;
$function$;

revoke all on function public.cmd_set_account_entitlement_service(
  uuid,uuid,text,text,timestamptz,timestamptz,integer,uuid,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.cmd_set_account_entitlement_service(
  uuid,uuid,text,text,timestamptz,timestamptz,integer,uuid,text,text
) to service_role;
