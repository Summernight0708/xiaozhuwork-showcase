create schema if not exists private;

create table private.ops_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default transaction_timestamp(),
  created_by uuid not null
);

create table private.ops_admin_audit (
  id bigint generated always as identity primary key,
  operator_user_id uuid not null,
  target_user_id uuid not null,
  action text not null check (action in ('enabled','disabled')),
  request_id uuid not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default transaction_timestamp()
);

create table private.ops_access_audit (
  id bigint generated always as identity primary key,
  operator_user_id uuid not null,
  target_user_id uuid not null,
  action text not null
    check (action = 'account_support_view'),
  request_id uuid not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default transaction_timestamp()
);

-- Keep the lifecycle privacy inventory complete when this later migration adds
-- private identity/audit tables. Classification is review-only, never approval.
insert into private.lifecycle_pii_classifications(
  schema_name,
  table_name,
  column_name,
  data_type,
  classification
)
select
  n.nspname,
  c.relname,
  a.attname,
  format_type(a.atttypid,a.atttypmod),
  case
    when format_type(a.atttypid,a.atttypmod)='uuid'
      then 'identity_reference'
    when format_type(a.atttypid,a.atttypmod) in ('json','jsonb')
      then 'unstructured_json'
    when format_type(a.atttypid,a.atttypmod) ~ '^(text|character|citext)'
      then 'free_text'
    else 'structured'
  end
from pg_attribute a
join pg_class c on c.oid=a.attrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='private'
  and c.relname in ('ops_admins','ops_admin_audit','ops_access_audit')
  and c.relkind in ('r','p')
  and a.attnum>0
  and not a.attisdropped
on conflict (schema_name,table_name,column_name) do update
set data_type=excluded.data_type,
    classification=excluded.classification,
    disposition='manual_review_required';


create index ops_access_audit_operator_created_idx
  on private.ops_access_audit(operator_user_id, created_at desc);
create index ops_access_audit_target_created_idx
  on private.ops_access_audit(target_user_id, created_at desc);
create index ops_admin_audit_target_created_idx
  on private.ops_admin_audit(target_user_id, created_at desc);

revoke all on private.ops_admins,
              private.ops_admin_audit,
              private.ops_access_audit
  from PUBLIC, anon, authenticated, service_role;

create function private.reject_ops_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode='55000', message='OPS_AUDIT_IMMUTABLE';
end;
$$;

revoke all on function private.reject_ops_audit_mutation()
  from PUBLIC, anon, authenticated, service_role;

create trigger ops_admin_audit_immutable
before update or delete on private.ops_admin_audit
for each statement execute function private.reject_ops_audit_mutation();

create trigger ops_access_audit_immutable
before update or delete on private.ops_access_audit
for each statement execute function private.reject_ops_audit_mutation();

create function private.ops_admin_enabled(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from private.ops_admins a
    where a.user_id = p_user_id
      and a.enabled
  );
$$;

revoke all on function private.ops_admin_enabled(uuid)
  from PUBLIC, anon, authenticated, service_role;

create function public.ops_assert_access_service(p_operator_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Service-only access is enforced by PostgreSQL EXECUTE grants below.
  -- Current Supabase secret keys map directly to service_role and are not JWTs.
  if p_operator_user_id is null
     or not private.ops_admin_enabled(p_operator_user_id) then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;

  return jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object('userId',p_operator_user_id)
  );
end;
$$;

revoke all on function public.ops_assert_access_service(uuid)
  from PUBLIC, anon, authenticated, service_role;
grant execute on function public.ops_assert_access_service(uuid)
  to service_role;

create function public.ops_get_account_support_summary_service(
  p_operator_user_id uuid,
  p_query text,
  p_request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_query text := btrim(coalesce(p_query,''));
  v_target auth.users%rowtype;
  v_match_count integer := 0;
  v_query_kind text;
  v_account_state text;
  v_entitlement record;
  v_active_projects integer := 0;
  v_historical_projects integer := 0;
  v_recent_activity jsonb := '[]'::jsonb;
begin
  -- The service_role-only EXECUTE grant is the authorization boundary for
  -- both legacy service-role JWTs and newer Supabase secret keys.
  if p_operator_user_id is null
     or not private.ops_admin_enabled(p_operator_user_id) then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;

  if p_request_id is null or char_length(v_query) not between 3 and 320 then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  if v_query ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_query_kind := 'uuid';
    select count(*)::integer into v_match_count
    from auth.users u
    where u.id = v_query::uuid;

    if v_match_count = 1 then
      select * into v_target
      from auth.users u
      where u.id = v_query::uuid;
    end if;
  elsif v_query ~* '^[^[:space:]@%_]+@[^[:space:]@%_]+\.[^[:space:]@%_]+$' then
    v_query_kind := 'email';
    select count(*)::integer into v_match_count
    from auth.users u
    where lower(u.email) = lower(v_query);

    if v_match_count = 1 then
      select * into v_target
      from auth.users u
      where lower(u.email) = lower(v_query);
    end if;
  else
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  if v_match_count = 0 then
    return jsonb_build_object('ok',false,'code','NOT_FOUND');
  elsif v_match_count <> 1 then
    return jsonb_build_object('ok',false,'code','VALIDATION_FAILED');
  end if;

  insert into private.ops_access_audit(
    operator_user_id,target_user_id,action,request_id,metadata
  ) values(
    p_operator_user_id,
    v_target.id,
    'account_support_view',
    p_request_id,
    jsonb_build_object('schemaVersion',1,'queryKind',v_query_kind)
  );

  select coalesce(
    (
      select l.state
      from public.account_lifecycle_requests l
      where l.user_id = v_target.id
    ),
    case when v_target.deleted_at is not null then 'auth_deleted' else 'active' end
  ) into v_account_state;

  select * into v_entitlement
  from private.account_entitlement_state(
    v_target.id,
    transaction_timestamp()
  );

  select count(distinct m.project_id)::integer
  into v_active_projects
  from public.project_members m
  join public.projects p on p.id=m.project_id
  where m.user_id=v_target.id
    and m.member_state='active'
    and p.archived_at is null
    and p.lifecycle_state = 'active';

  select count(distinct m.project_id)::integer
  into v_historical_projects
  from public.project_members m
  where m.user_id=v_target.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('eventType',e.event_type,'at',e.created_at)
      order by e.created_at desc, e.id desc
    ),
    '[]'::jsonb
  )
  into v_recent_activity
  from (
    select b.id,b.event_type,b.created_at
    from public.business_events b
    where b.actor_id=v_target.id
    order by b.created_at desc,b.id desc
    limit 20
  ) e;

  return jsonb_build_object(
    'ok',true,
    'data',jsonb_build_object(
      'schemaVersion',1,
      'userId',v_target.id,
      'email',v_target.email,
      'createdAt',v_target.created_at,
      'lastSignInAt',v_target.last_sign_in_at,
      'accountState',v_account_state,
      'activeProjectCount',v_active_projects,
      'historicalProjectCount',v_historical_projects,
      'plan',v_entitlement.plan,
      'entitlementState',v_entitlement.state,
      'proExpiresAt',
        case when v_entitlement.state='free' then null else v_entitlement.expires_at end,
      'recentActivity',v_recent_activity
    )
  );
end;
$$;

revoke all on function public.ops_get_account_support_summary_service(uuid,text,uuid)
  from PUBLIC, anon, authenticated, service_role;
grant execute on function public.ops_get_account_support_summary_service(uuid,text,uuid)
  to service_role;
