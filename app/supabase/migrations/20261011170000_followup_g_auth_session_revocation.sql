-- G: expired F account: independently verify external Auth ban,
-- invalidate all refresh credentials, then mark revocation checkpoint.
-- This is NOT account deletion or history redaction.
create function public.lifecycle_list_expired_revocation_candidates_service(
  p_batch_limit integer default 10
) returns table(user_id uuid,generation integer)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
  end if;
  if p_batch_limit is null or p_batch_limit not between 1 and 25 then
    raise exception using errcode='22023',message='INVALID_BATCH_LIMIT';
  end if;
  return query
    select r.user_id,r.generation
    from public.account_lifecycle_requests r
    where r.state='pending'
      and r.auth_revoked_at is null
      and r.cancel_until<=transaction_timestamp()
    order by r.cancel_until,r.user_id limit p_batch_limit;
end;
$$;
revoke all on function public.lifecycle_list_expired_revocation_candidates_service(integer)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_list_expired_revocation_candidates_service(integer)
  to service_role;

create function public.lifecycle_finalize_auth_revocation_service(
  p_user uuid,p_generation integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_request public.account_lifecycle_requests%rowtype;
  v_banned_until timestamptz;
  v_tokens integer:=0;
  v_sessions integer:=0;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
  end if;
  if p_user is null or p_generation is null then
    raise exception using errcode='22023',message='INVALID_TARGET';
  end if;
  select * into v_request from public.account_lifecycle_requests
    where user_id=p_user for update;
  if v_request.user_id is null or v_request.generation<>p_generation
      or v_request.state<>'pending'
      or v_request.cancel_until>transaction_timestamp() then
    return jsonb_build_object('ok',false,'code','REVOCATION_NOT_DUE');
  end if;
  if v_request.auth_revoked_at is not null then
    return jsonb_build_object('ok',true,'replayed',true,'revoked',true);
  end if;
  select banned_until into v_banned_until from auth.users
    where id=p_user for update;
  if v_banned_until is null or v_banned_until < transaction_timestamp()+interval '300 days' then
    return jsonb_build_object('ok',false,'code','AUTH_BAN_NOT_VERIFIED');
  end if;

  -- Ban alone is insufficient: GoTrue still permits existing refresh
  -- credentials. Remove only auth sessions/refresh tokens for this exact
  -- account. Previously issued JWTs are separately denied by G's RLS/RPC
  -- lifecycle barriers until expiry.
  delete from auth.refresh_tokens where user_id=p_user::text;
  get diagnostics v_tokens=row_count;
  delete from auth.sessions where user_id=p_user;
  get diagnostics v_sessions=row_count;

  if exists(select 1 from auth.refresh_tokens where user_id=p_user::text)
      or exists(select 1 from auth.sessions where user_id=p_user) then
    raise exception using errcode='55000',message='AUTH_SESSION_REVOKE_NOT_CONFIRMED';
  end if;
  if not private.record_account_auth_revocation(p_user,p_generation) then
    raise exception using errcode='55000',message='AUTH_GENERATION_CHANGED';
  end if;
  insert into private.account_lifecycle_audit(
    user_id,generation,action,details
  ) values (
    p_user,p_generation,'auth_sessions_revoked',
    jsonb_build_object('sessions',v_sessions,'refreshTokens',v_tokens)
  );
  return jsonb_build_object(
    'ok',true,'revoked',true,'replayed',false,
    'sessionsRevoked',v_sessions,'refreshTokensRevoked',v_tokens,
    'irreversibleDeletes',0
  );
end;
$$;
revoke all on function public.lifecycle_finalize_auth_revocation_service(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_finalize_auth_revocation_service(uuid,integer)
  to service_role;
