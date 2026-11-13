-- F lifecycle: read-only, service-role-only per-account PII preflight inventory.
-- This intentionally CANNOT anonymize, delete, unlock the redaction gate, or
-- advance any account lifecycle state. It also never returns PII field values.
create or replace function public.lifecycle_pii_preflight_service(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state text;
  v_generation integer;
  v_col record;
  v_count bigint;
  v_identity_hits jsonb := '[]'::jsonb;
  v_risk_fields jsonb := '[]'::jsonb;
  v_scanned integer := 0;
  v_risk_total integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_user is null then
    raise exception 'ACCOUNT_REQUIRED' using errcode = '22023';
  end if;

  select l.state,l.generation into v_state,v_generation
  from public.account_lifecycle_requests l where l.user_id=p_user;
  if not found or v_state = 'canceled' then
    return jsonb_build_object(
      'ok', false, 'code', 'NO_ACTIVE_LIFECYCLE_REQUEST',
      'redactionAllowed', false, 'irreversibleDeletes', 0);
  end if;

  -- Schema driven, not a hand-maintained partial list of user_id columns.
  -- Include all real tables under the three data-bearing schemas, including
  -- new migrations. Never emit row contents or any of the subject's values.
  for v_col in
    select n.nspname as schema_name,c.relname as table_name,a.attname as column_name
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    join pg_catalog.pg_type t on t.oid=a.atttypid
    where n.nspname in ('auth','public','storage')
      and c.relkind in ('r','p')
      and a.attnum > 0 and not a.attisdropped
      and t.typname in ('uuid','text','varchar','bpchar')
      and a.attname ~ '(^user_id$|_user_id$|^owner_id$|^actor_id$|^created_by$|^uploaded_by$|^assignee_id$|^reviewed_by$|^recipient_id$|^invited_by$|^issuer_user_id$|^leader_id$|^proposer_id$|^required_confirmer_id$|^target_user_id$|^responsible_user_id$|^from_user_id$|^to_user_id$|^id$)'
      -- Generic id columns would match every table's PK and are NOT all users.
      and (a.attname <> 'id'
        or (n.nspname='auth' and c.relname='users')
        or (n.nspname='public' and c.relname='profiles'))
    order by n.nspname,c.relname,a.attname
  loop
    execute pg_catalog.format(
      'select count(*)::bigint from %I.%I where %I::text = $1::text',
      v_col.schema_name,v_col.table_name,v_col.column_name
    ) into v_count using p_user;
    v_scanned := v_scanned+1;
    if v_count > 0 then
      v_identity_hits := v_identity_hits || jsonb_build_array(jsonb_build_object(
        'schema',v_col.schema_name,'table',v_col.table_name,
        'column',v_col.column_name,'linkedRows',v_count));
    end if;
  end loop;

  -- These fields may contain indirect identifying data and immutable
  -- contributor snapshots, even if no direct UUID reference is present.
  -- List metadata for manual/legal review; never invent a "safe" decision.
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema',z.schema_name,'table',z.table_name,'column',z.column_name)
    order by z.schema_name,z.table_name,z.column_name),'[]'::jsonb),
    count(*)::integer into v_risk_fields,v_risk_total
  from (
    select n.nspname as schema_name,c.relname as table_name,a.attname as column_name
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid=a.attrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    join pg_catalog.pg_type t on t.oid=a.atttypid
    where n.nspname in ('auth','public','storage')
      and c.relkind in ('r','p')
      and a.attnum > 0 and not a.attisdropped
      and t.typname in ('text','varchar','bpchar','json','jsonb')
      and a.attname ~* '(name|email|phone|student|snapshot|reason|message|payload|metadata|title|description|url|path|content|token|audit|identity|comment)'
  ) z;

  return jsonb_build_object(
    'ok',true,'userId',p_user,'state',v_state,'generation',v_generation,
    'directReferenceColumnsScanned',v_scanned,'directReferenceHits',v_identity_hits,
    'possibleIndirectPiiFields',v_risk_fields,
    'possibleIndirectPiiFieldCount',v_risk_total,
    'unverifiedStorageSignedUrls',true,'unverifiedExportsAndBackups',true,
    'requiresImmutableLedgerPolicyReview',true,
    'requiresExternalLegalRetentionApproval',true,
    'redactionAllowed',false,'irreversibleDeletes',0,
    'disposition','BLOCKED_PENDING_FULL_REDACTION_AND_RETENTION_REVIEW');
end;
$$;
revoke all on function public.lifecycle_pii_preflight_service(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_pii_preflight_service(uuid) to service_role;
comment on function public.lifecycle_pii_preflight_service(uuid) is
  'Read-only, privileged PII schema/ref inventory. NOT a redaction or deletion authorization.';
