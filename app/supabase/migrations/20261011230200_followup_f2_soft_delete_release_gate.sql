-- F2 independent per-subject privacy release gate.
-- No worker or browser can grant itself a deletion approval. This table has
-- NO execute/write bridge and NO grants to service_role or authenticated.
create table private.account_soft_delete_release_approvals (
  user_id uuid not null,
  generation integer not null check(generation>0),
  privacy_manifest_sha256 text not null check(privacy_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  storage_manifest_sha256 text not null check(storage_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  legal_reviewer_id uuid not null,
  security_reviewer_id uuid not null,
  legal_hold_cleared boolean not null check(legal_hold_cleared),
  exported_artifacts_reviewed boolean not null check(exported_artifacts_reviewed),
  backups_and_logs_reviewed boolean not null check(backups_and_logs_reviewed),
  consent_verified boolean not null check(consent_verified),
  approved_at timestamptz not null default transaction_timestamp(),
  primary key(user_id,generation),
  check(legal_reviewer_id<>security_reviewer_id),
  check(legal_reviewer_id<>user_id and security_reviewer_id<>user_id)
);
revoke all on private.account_soft_delete_release_approvals from public,anon,authenticated,service_role;
comment on table private.account_soft_delete_release_approvals is
 'Independent human legal+security approval, subject/generation-bound; never inserted by Edge worker. Required before irreversible Auth soft deletion.';

create function private.f2_has_soft_delete_release(p_user uuid,p_generation integer)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from private.account_soft_delete_release_approvals a
    where a.user_id=p_user and a.generation=p_generation
      and a.legal_hold_cleared and a.exported_artifacts_reviewed
      and a.backups_and_logs_reviewed and a.consent_verified
  );
$$;
revoke all on function private.f2_has_soft_delete_release(uuid,integer)
  from public,anon,authenticated,service_role;

-- The only candidate function used by the Edge Admin API requires the
-- approval. Avoid creating a second unaudited public candidate interface.
create or replace function public.lifecycle_list_soft_delete_candidates_service(
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
     and private.f2_has_soft_delete_release(r.user_id,r.generation)
   order by r.cancel_until,r.user_id limit p_batch_limit;
end;
$$;
revoke all on function public.lifecycle_list_soft_delete_candidates_service(integer)
 from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_list_soft_delete_candidates_service(integer)
 to service_role;

-- Defense in depth: even a direct service-role request cannot prepare an
-- unapproved target and cannot silently erase their editable profile.
create or replace function public.lifecycle_prepare_soft_delete_service(
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
  if not private.f2_has_soft_delete_release(p_user,p_generation) then
    return jsonb_build_object('ok',false,'code','INDEPENDENT_PRIVACY_APPROVAL_REQUIRED');
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
