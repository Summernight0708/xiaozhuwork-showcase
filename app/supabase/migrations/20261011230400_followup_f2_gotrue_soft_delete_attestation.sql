-- F2: attest real GoTrue soft-delete behavior, not nonexistent NULL fields.
-- Supabase GoTrue obfuscates users.email (base64url SHA-256 length 43) and
-- users.phone (15-char truncation) and retains auth.identities while
-- obfuscating provider_id and clearing identity_data. Keep this guarded
-- behind independent per-user approval, and never perform deletion in SQL.
create or replace function public.lifecycle_finalize_soft_delete_service(
  p_user uuid,p_generation integer
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_case public.account_lifecycle_requests%rowtype;
  v_deleted_at timestamptz;
  v_email text;
  v_phone text;
  v_user_metadata jsonb;
  v_app_metadata jsonb;
  v_password text;
  v_identity_count integer;
  v_identity_unsafe integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
  end if;
  if p_user is null or p_generation is null then
    raise exception using errcode='22023',message='INVALID_TARGET';
  end if;
  select * into v_case from public.account_lifecycle_requests
    where user_id=p_user for update;
  if v_case.user_id is null or v_case.generation<>p_generation
     or v_case.state<>'blocked' or v_case.auth_revoked_at is null
     or v_case.cancel_until>transaction_timestamp() then
    return pg_catalog.jsonb_build_object('ok',false,'code','SOFT_DELETE_NOT_DUE');
  end if;
  if not private.f2_has_soft_delete_release(p_user,p_generation) then
    return pg_catalog.jsonb_build_object(
      'ok',false,'code','INDEPENDENT_PRIVACY_APPROVAL_REQUIRED');
  end if;
  if v_case.auth_soft_deleted_at is not null then
    return pg_catalog.jsonb_build_object(
      'ok',true,'replayed',true,'authSoftDeleted',true);
  end if;
  select u.deleted_at,u.email,u.phone,u.raw_user_meta_data,
    u.raw_app_meta_data,u.encrypted_password
    into v_deleted_at,v_email,v_phone,v_user_metadata,v_app_metadata,v_password
    from auth.users u where u.id=p_user for update;
  select pg_catalog.count(*),
    pg_catalog.count(*) filter(
      where i.provider_id !~ '^[A-Za-z0-9_-]{43}$'
        or i.identity_data is distinct from '{}'::jsonb
        or i.email is not null
    )
    into v_identity_count,v_identity_unsafe
    from auth.identities i where i.user_id=p_user;
  -- GoTrue soft delete does NOT make these columns NULL and does NOT
  -- delete identity rows; it writes deterministic obfuscation hashes.
  -- Protect against false attestations from manually set deleted_at.
  if v_deleted_at is null
      or v_email is null or v_email !~ '^[A-Za-z0-9_-]{43}$'
      or v_phone is null or v_phone !~ '^[A-Za-z0-9_-]{15}$'
      or v_user_metadata is distinct from '{}'::jsonb
      or v_app_metadata is distinct from '{}'::jsonb
      or v_password is not null
      or v_identity_unsafe<>0
      or exists(select 1 from auth.sessions s where s.user_id=p_user)
  then
    return pg_catalog.jsonb_build_object(
      'ok',false,'code','AUTH_SOFT_DELETE_NOT_VERIFIED');
  end if;
  if exists(
    select 1 from public.profiles p
    where p.id=p_user and
      (p.display_name is distinct from '已注销成员'
       or p.real_name is not null or p.student_number is not null)
  ) then
    return pg_catalog.jsonb_build_object(
      'ok',false,'code','PROFILE_REDACTION_NOT_VERIFIED');
  end if;
  update public.account_lifecycle_requests
    set auth_soft_deleted_at=transaction_timestamp(),
      updated_at=transaction_timestamp()
    where user_id=p_user and generation=p_generation;
  insert into private.account_lifecycle_audit(
    user_id,generation,action,details)
    values(p_user,p_generation,'auth_soft_deleted',
      pg_catalog.jsonb_build_object(
        'authDeletedAt',v_deleted_at,
        'identitiesScrubbed',v_identity_count));
  return pg_catalog.jsonb_build_object(
    'ok',true,'authSoftDeleted',true,
    'identityRowsScrubbed',v_identity_count,'irreversibleDeletes',0,
    'redactionAllowed',false);
end;
$$;
revoke all on function public.lifecycle_finalize_soft_delete_service(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_finalize_soft_delete_service(uuid,integer)
  to service_role;
comment on function public.lifecycle_finalize_soft_delete_service(uuid,integer) is
 'Verifies GoTrue soft deletion via hashed email/phone, scrubbed retained identities, cleared metadata/password/session, approval and profile. Does not mark complete historical redaction.';
