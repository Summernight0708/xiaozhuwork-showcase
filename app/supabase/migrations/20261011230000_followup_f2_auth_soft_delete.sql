-- F2: opt-in, non-cascading Auth soft-delete reconciliation.
-- No SQL function deletes auth.users, business history or Storage objects.
-- This stage is NOT the full historical data-erasure or legal-retention gate.
alter table public.account_lifecycle_requests
  add column auth_soft_deleted_at timestamptz;

create function public.lifecycle_list_soft_delete_candidates_service(
  p_batch_limit integer default 10
) returns table(user_id uuid,generation integer)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
  end if;
  if p_batch_limit is null or p_batch_limit not between 1 and 25 then
    raise exception using errcode='22023',message='INVALID_BATCH_LIMIT';
  end if;
  return query select r.user_id,r.generation from public.account_lifecycle_requests r
   where r.state='blocked'
     and r.auth_revoked_at is not null
     and r.auth_soft_deleted_at is null
     and r.cancel_until<=transaction_timestamp()
   order by r.cancel_until,r.user_id limit p_batch_limit;
end;
$$;
revoke all on function public.lifecycle_list_soft_delete_candidates_service(integer)
 from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_list_soft_delete_candidates_service(integer)
 to service_role;

-- Idempotent identity-local scrubbing of editable profile fields. Preserve
-- the stable ID and all project/history foreign keys. Immutable snapshots
-- are masked by dedicated presentation views and field privileges.
create function public.lifecycle_prepare_soft_delete_service(
  p_user uuid,p_generation integer
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_case public.account_lifecycle_requests%rowtype;
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
     or v_case.state<>'blocked'
     or v_case.auth_revoked_at is null
     or v_case.cancel_until>transaction_timestamp() then
    return jsonb_build_object('ok',false,'code','SOFT_DELETE_NOT_DUE');
  end if;
  if v_case.auth_soft_deleted_at is not null then
    return jsonb_build_object('ok',true,'replayed',true,'prepared',true);
  end if;
  update public.profiles
   set display_name='已注销成员',real_name=null,student_number=null,
       updated_at=transaction_timestamp()
   where id=p_user;
  insert into private.account_lifecycle_audit(user_id,generation,action,details)
   select p_user,p_generation,'soft_delete_prepared',
     jsonb_build_object('profileScrubbed',true)
   where not exists(
     select 1 from private.account_lifecycle_audit a
     where a.user_id=p_user and a.generation=p_generation
       and a.action='soft_delete_prepared');
  return jsonb_build_object('ok',true,'prepared',true,'irreversibleDeletes',0);
end;
$$;
revoke all on function public.lifecycle_prepare_soft_delete_service(uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_prepare_soft_delete_service(uuid,integer)
 to service_role;

-- The external GoTrue Admin soft-delete must have occurred first. Verify
-- deleted_at and that Auth PII and identities are absent before checkpoint.
create function public.lifecycle_finalize_soft_delete_service(
  p_user uuid,p_generation integer
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_case public.account_lifecycle_requests%rowtype;
  v_deleted_at timestamptz;
  v_email text;v_phone text;
  v_identity_count integer;
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
    return jsonb_build_object('ok',false,'code','SOFT_DELETE_NOT_DUE');
  end if;
  if v_case.auth_soft_deleted_at is not null then
    return jsonb_build_object('ok',true,'replayed',true,'authSoftDeleted',true);
  end if;
  select deleted_at,email,phone into v_deleted_at,v_email,v_phone
   from auth.users where id=p_user for update;
  select count(*) into v_identity_count from auth.identities where user_id=p_user;
  if v_deleted_at is null or v_email is not null or v_phone is not null
     or v_identity_count<>0 then
    return jsonb_build_object('ok',false,'code','AUTH_SOFT_DELETE_NOT_VERIFIED');
  end if;
  if exists(select 1 from public.profiles p where p.id=p_user and
    (p.display_name is distinct from '已注销成员'
       or p.real_name is not null or p.student_number is not null)) then
    return jsonb_build_object('ok',false,'code','PROFILE_REDACTION_NOT_VERIFIED');
  end if;
  update public.account_lifecycle_requests
   set auth_soft_deleted_at=transaction_timestamp(),updated_at=transaction_timestamp()
   where user_id=p_user and generation=p_generation;
  insert into private.account_lifecycle_audit(user_id,generation,action,details)
   values(p_user,p_generation,'auth_soft_deleted',
    jsonb_build_object('authDeletedAt',v_deleted_at,'identities',v_identity_count));
  return jsonb_build_object('ok',true,'authSoftDeleted',true,
    'identityRowsRemoved',v_identity_count,'irreversibleDeletes',0,
    'redactionAllowed',false);
end;
$$;
revoke all on function public.lifecycle_finalize_soft_delete_service(uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_finalize_soft_delete_service(uuid,integer)
 to service_role;

comment on function public.lifecycle_finalize_soft_delete_service(uuid,integer) is
 'Attests GoTrue soft deletion after strict generation and Auth/profile checks; does not mark full historical redaction or delete shared data.';
