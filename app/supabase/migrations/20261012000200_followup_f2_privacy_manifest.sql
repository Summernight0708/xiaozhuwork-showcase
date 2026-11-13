-- Persistent, NONDESTRUCTIVE privacy review. Counts/metadata only: never copy
-- personal values, file bytes, credentials or signed URLs into this inventory.
create function private.f2_privacy_schema()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'columns',coalesce((select jsonb_agg(jsonb_build_object(
   'schema',n.nspname,'table',c.relname,'column',a.attname,
   'type',format_type(a.atttypid,a.atttypmod)) order by n.nspname,c.relname,a.attnum)
   from pg_attribute a join pg_class c on c.oid=a.attrelid
   join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('auth','public','storage','private') and c.relkind in ('r','p')
     and not (n.nspname='private' and c.relname in ('lifecycle_pii_classifications','lifecycle_privacy_manifests','lifecycle_cleanup_reviews','lifecycle_cleanup_review_attempts'))
     and a.attnum>0 and not a.attisdropped),'[]'::jsonb),
 'foreignKeys',coalesce((select jsonb_agg(jsonb_build_object(
   'table',con.conrelid::regclass::text,'name',con.conname,
   'definition',pg_get_constraintdef(con.oid)) order by con.conrelid::regclass::text,con.conname)
   from pg_constraint con join pg_class c on c.oid=con.conrelid
   join pg_namespace n on n.oid=c.relnamespace
   where con.contype='f' and n.nspname in ('auth','public','storage','private')
     and not (n.nspname='private' and c.relname in ('lifecycle_pii_classifications','lifecycle_privacy_manifests','lifecycle_cleanup_reviews','lifecycle_cleanup_review_attempts'))),'[]'::jsonb));
$$;
revoke all on function private.f2_privacy_schema() from public,anon,authenticated,service_role;

create table private.lifecycle_pii_classifications (
 schema_name text not null, table_name text not null, column_name text not null,
 data_type text not null,
 classification text not null check(classification in
   ('identity_reference','unstructured_json','free_text','structured')),
 disposition text not null default 'manual_review_required'
   check(disposition='manual_review_required'),
 primary key(schema_name,table_name,column_name)
);
-- Classification is a conservative review queue, NEVER an approval of contents.
insert into private.lifecycle_pii_classifications(schema_name,table_name,column_name,data_type,classification)
 select c->>'schema',c->>'table',c->>'column',c->>'type',
 case when c->>'type'='uuid' then 'identity_reference'
      when c->>'type' in ('json','jsonb') then 'unstructured_json'
      when c->>'type' ~ '^(text|character|citext)' then 'free_text'
      else 'structured' end
 from jsonb_array_elements(private.f2_privacy_schema()->'columns') c;

create table private.lifecycle_privacy_manifests (
 id uuid primary key default gen_random_uuid(),
 scan_sequence bigint generated always as identity unique,
 user_id uuid not null, generation integer not null check(generation>0),
 request_id uuid not null unique,
 schema_sha256 text not null check(schema_sha256 ~ '^[0-9a-f]{64}$'),
 manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
 manifest jsonb not null,
 created_at timestamptz not null default transaction_timestamp(),
 unique(id,user_id,generation)
);
create index lifecycle_privacy_manifests_subject on private.lifecycle_privacy_manifests(user_id,generation,created_at desc);

create table private.lifecycle_cleanup_reviews (
 user_id uuid not null, generation integer not null,
 manifest_id uuid not null,
 legal_hold boolean, retain_until timestamptz,
 legal_reviewer_id uuid, security_reviewer_id uuid,
 evidence_sha256 text check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 approved_at timestamptz, expires_at timestamptz, revoked_at timestamptz,
 primary key(user_id,generation),
 foreign key(manifest_id,user_id,generation)
   references private.lifecycle_privacy_manifests(id,user_id,generation),
 check(legal_reviewer_id is null or legal_reviewer_id<>user_id),
 check(security_reviewer_id is null or security_reviewer_id<>user_id),
 check(legal_reviewer_id is null or security_reviewer_id is null or legal_reviewer_id<>security_reviewer_id),
 check(approved_at is null or (retain_until is not null
   and legal_reviewer_id is not null and security_reviewer_id is not null
   and evidence_sha256 is not null and expires_at is not null
   and expires_at>approved_at and expires_at<=approved_at+interval '24 hours'))
);
create table private.lifecycle_cleanup_review_attempts (
 request_id uuid primary key,
 user_id uuid not null, generation integer not null,
 result jsonb not null,
 created_at timestamptz not null default transaction_timestamp()
);
alter table private.lifecycle_pii_classifications enable row level security;
alter table private.lifecycle_privacy_manifests enable row level security;
alter table private.lifecycle_cleanup_reviews enable row level security;
alter table private.lifecycle_cleanup_review_attempts enable row level security;
revoke all on private.lifecycle_pii_classifications,private.lifecycle_privacy_manifests,
 private.lifecycle_cleanup_reviews,private.lifecycle_cleanup_review_attempts
 from public,anon,authenticated,service_role;
revoke all on sequence private.lifecycle_privacy_manifests_scan_sequence_seq from public,anon,authenticated,service_role;

create function public.lifecycle_scan_pii_service(p_user uuid,p_generation integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_case public.account_lifecycle_requests%rowtype;
 v_prior private.lifecycle_privacy_manifests%rowtype;
 v_schema jsonb; v_manifest jsonb; v_fields jsonb:='[]'; v_col record;
 v_tokens text[]; v_hits bigint; v_unknown integer; v_id uuid; v_sha text;
begin
 if auth.role() is distinct from 'service_role' then
   raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 if p_user is null or p_generation is null or p_generation<1 or p_request_id is null then
   raise exception using errcode='22023',message='INVALID_TARGET';
 end if;
 -- Serializes same-subject scans with lifecycle changes; the request lock also
 -- makes cross-subject reuse deterministic without a unique-violation retry.
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,120002));
 select * into v_case from public.account_lifecycle_requests where user_id=p_user for update;
 if not found or v_case.generation<>p_generation or v_case.state='canceled' then
   return jsonb_build_object('ok',false,'code','NO_ACTIVE_GENERATION');
 end if;
 select * into v_prior from private.lifecycle_privacy_manifests where request_id=p_request_id;
 if found then
   if v_prior.user_id<>p_user or v_prior.generation<>p_generation then
     return jsonb_build_object('ok',false,'code','IDEMPOTENCY_KEY_REUSED');
   end if;
   return jsonb_build_object('ok',true,'replayed',true,'manifestId',v_prior.id,
     'manifestSha256',v_prior.manifest_sha256,'redactionAllowed',false,'irreversibleDeletes',0);
 end if;
 v_schema:=private.f2_privacy_schema();
 select count(*) into v_unknown from jsonb_array_elements(v_schema->'columns') c
 where not exists(select 1 from private.lifecycle_pii_classifications k
   where k.schema_name=c->>'schema' and k.table_name=c->>'table'
     and k.column_name=c->>'column' and k.data_type=c->>'type');
 -- Literal substring detection, not regex/replacement. Findings are only
 -- candidates; short/encoded/old identifiers and file contents remain unknown.
 select array_agg(distinct lower(x)) into v_tokens from (
   select p_user::text x union all
   select email from auth.users where id=p_user union all
   select phone from auth.users where id=p_user union all
   select display_name from public.profiles where id=p_user union all
   select real_name from public.profiles where id=p_user union all
   select student_number from public.profiles where id=p_user
 ) t where length(x)>=3;
 for v_col in
   select n.nspname schema_name,c.relname table_name,a.attname column_name,
     format_type(a.atttypid,a.atttypmod) data_type
   from pg_attribute a join pg_class c on c.oid=a.attrelid
   join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('auth','public','storage','private') and c.relkind in ('r','p')
     and not (n.nspname='private' and c.relname in ('lifecycle_pii_classifications','lifecycle_privacy_manifests','lifecycle_cleanup_reviews','lifecycle_cleanup_review_attempts'))
     and a.attnum>0 and not a.attisdropped
     and (a.atttypid in ('uuid'::regtype,'text'::regtype,'varchar'::regtype,
       'bpchar'::regtype,'json'::regtype,'jsonb'::regtype)
       or a.attndims>0)
   order by n.nspname,c.relname,a.attnum
 loop
   execute format('select count(*) from %I.%I r where exists(select 1 from unnest($1::text[]) token where strpos(lower(r.%I::text),token)>0)',
     v_col.schema_name,v_col.table_name,v_col.column_name) into v_hits using v_tokens;
   v_fields:=v_fields||jsonb_build_array(jsonb_build_object(
     'schema',v_col.schema_name,'table',v_col.table_name,'column',v_col.column_name,
     'candidateRows',v_hits,'review','manual_review_required'));
 end loop;
 v_manifest:=jsonb_build_object('schemaVersion',1,'userId',p_user,'generation',p_generation,
   'schema',v_schema,'unclassifiedColumns',v_unknown,'fields',v_fields,
   'externalReview',jsonb_build_object('attachmentContents','unverified',
     'signedUrlsAndCopies','unverified','generatedExports','unverified',
     'backupsAndLogs','unverified','externalLinksAndCaches','unverified'),
   'scanLimitations','Literal current identifiers >=3 chars only; zero hits is not erasure. Encoded, historical, short and indirect identifiers require review.',
   'sharedArtifacts','preserved','redactionAllowed',false,'irreversibleDeletes',0);
 v_sha:=encode(extensions.digest(v_manifest::text,'sha256'),'hex');
 insert into private.lifecycle_privacy_manifests(user_id,generation,request_id,
   schema_sha256,manifest_sha256,manifest) values(p_user,p_generation,p_request_id,
   encode(extensions.digest(v_schema::text,'sha256'),'hex'),v_sha,v_manifest) returning id into v_id;
 insert into private.account_lifecycle_audit(user_id,generation,action,request_id,details)
 values(p_user,p_generation,'privacy_manifest_scanned',p_request_id,
   jsonb_build_object('manifestId',v_id,'manifestSha256',v_sha,'unclassifiedColumns',v_unknown));
 return jsonb_build_object('ok',true,'replayed',false,'manifestId',v_id,
   'manifestSha256',v_sha,'unclassifiedColumns',v_unknown,'redactionAllowed',false,'irreversibleDeletes',0);
end;
$$;
revoke all on function public.lifecycle_scan_pii_service(uuid,integer,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_scan_pii_service(uuid,integer,uuid) to service_role;

-- Service-only retrieval; never make the manifest a browser-visible JSON RPC.
create function public.lifecycle_get_pii_manifest_service(p_manifest_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then
   raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 return (select jsonb_build_object('manifestId',id,'manifestSha256',manifest_sha256,
   'createdAt',created_at,'manifest',manifest) from private.lifecycle_privacy_manifests where id=p_manifest_id);
end;
$$;
revoke all on function public.lifecycle_get_pii_manifest_service(uuid) from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_get_pii_manifest_service(uuid) to service_role;

create function private.f2_cleanup_review_valid(p_user uuid,p_generation integer)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.lifecycle_cleanup_reviews r
   join private.lifecycle_privacy_manifests m on m.id=r.manifest_id
   where r.user_id=p_user and r.generation=p_generation
     and r.legal_hold is false and r.retain_until<=transaction_timestamp()
     and r.approved_at>=m.created_at and r.approved_at<=transaction_timestamp()
     and r.expires_at>transaction_timestamp()
     and m.created_at>=transaction_timestamp()-interval '24 hours'
     and r.revoked_at is null
     and r.legal_reviewer_id is not null and r.security_reviewer_id is not null
     and r.evidence_sha256 is not null
     and m.manifest->>'unclassifiedColumns'='0'
     and m.schema_sha256=encode(extensions.digest(private.f2_privacy_schema()::text,'sha256'),'hex')
     and not exists(select 1 from private.lifecycle_privacy_manifests newer
       where newer.user_id=p_user and newer.generation=p_generation
         and newer.scan_sequence>m.scan_sequence));
$$;
revoke all on function private.f2_cleanup_review_valid(uuid,integer) from public,anon,authenticated,service_role;

-- Existing Auth approval must bind to the reviewed durable manifest, not an
-- arbitrary 64-character string. No migration/worker ever inserts approvals.
create or replace function private.f2_has_soft_delete_release(p_user uuid,p_generation integer)
returns boolean language sql stable security definer set search_path='' as $$
 select private.f2_cleanup_review_valid(p_user,p_generation) and exists(
   select 1 from private.account_soft_delete_release_approvals a
   join private.lifecycle_cleanup_reviews r on r.user_id=a.user_id and r.generation=a.generation
   join private.lifecycle_privacy_manifests m on m.id=r.manifest_id
   where a.user_id=p_user and a.generation=p_generation
     and a.privacy_manifest_sha256=m.manifest_sha256
     and a.legal_reviewer_id=r.legal_reviewer_id and a.security_reviewer_id=r.security_reviewer_id
     and a.legal_hold_cleared and a.exported_artifacts_reviewed
     and a.backups_and_logs_reviewed and a.consent_verified);
$$;

-- A retryable assessment only. Even eligible means manual review, not execute.
create function public.lifecycle_assess_cleanup_service(p_user uuid,p_generation integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_case public.account_lifecycle_requests%rowtype; v_prior private.lifecycle_cleanup_review_attempts%rowtype; v_result jsonb; v_code text;
begin
 if auth.role() is distinct from 'service_role' then
   raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 if p_user is null or p_generation is null or p_generation<1 or p_request_id is null then
   raise exception using errcode='22023',message='INVALID_TARGET';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,120002));
 select * into v_case from public.account_lifecycle_requests where user_id=p_user for update;
 if not found or v_case.generation<>p_generation or v_case.state='canceled' then
   return jsonb_build_object('ok',false,'code','NO_ACTIVE_GENERATION');
 end if;
 select * into v_prior from private.lifecycle_cleanup_review_attempts where request_id=p_request_id;
 if found then
   if v_prior.user_id<>p_user or v_prior.generation<>p_generation then
     return jsonb_build_object('ok',false,'code','IDEMPOTENCY_KEY_REUSED');
   end if;
   return v_prior.result||jsonb_build_object('replayed',true);
 end if;
 v_code:=case
   when v_case.cancel_until>transaction_timestamp() then 'CANCELLATION_WINDOW_OPEN'
   when not private.f2_cleanup_review_valid(p_user,p_generation) then 'LEGAL_RETENTION_MANIFEST_REVIEW_REQUIRED'
   else 'MANUAL_EXECUTION_REVIEW_REQUIRED' end;
 v_result:=jsonb_build_object('ok',true,'code',v_code,'replayed',false,
   'dryRun',true,'executionAllowed',false,'irreversibleDeletes',0);
 insert into private.lifecycle_cleanup_review_attempts(request_id,user_id,generation,result)
 values(p_request_id,p_user,p_generation,v_result);
 insert into private.account_lifecycle_audit(user_id,generation,action,request_id,details)
 values(p_user,p_generation,'cleanup_assessed',p_request_id,v_result);
 return v_result;
end;
$$;
revoke all on function public.lifecycle_assess_cleanup_service(uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_assess_cleanup_service(uuid,integer,uuid) to service_role;

create function public.lifecycle_list_cleanup_candidates_service(p_batch_limit integer default 10)
returns table(user_id uuid,generation integer,review_ready boolean,execution_allowed boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then
   raise exception using errcode='42501',message='SERVICE_ROLE_REQUIRED';
 end if;
 if p_batch_limit is null or p_batch_limit not between 1 and 25 then
   raise exception using errcode='22023',message='INVALID_BATCH_LIMIT';
 end if;
 return query select l.user_id,l.generation,private.f2_cleanup_review_valid(l.user_id,l.generation),false
 from public.account_lifecycle_requests l where l.state in ('pending','blocked')
   and l.cancel_until<=transaction_timestamp()
 order by l.cancel_until,l.user_id limit p_batch_limit;
end;
$$;
revoke all on function public.lifecycle_list_cleanup_candidates_service(integer) from public,anon,authenticated,service_role;
grant execute on function public.lifecycle_list_cleanup_candidates_service(integer) to service_role;
