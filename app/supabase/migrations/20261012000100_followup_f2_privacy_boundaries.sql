-- Additive F2 boundaries. Original shared evidence is never rewritten.
-- Comparison is a command with cached JSON. Mask AFTER the authorized
-- implementation returns so pre-request cached responses cannot leak names.
alter function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
 rename to cmd_compare_task_file_versions_f2_internal;
revoke all on function public.cmd_compare_task_file_versions_f2_internal(uuid,uuid,uuid,uuid)
 from public,anon,authenticated,service_role;
create function public.cmd_compare_task_file_versions(
 p_project_id uuid,p_base_file_version_id uuid,p_target_file_version_id uuid,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_side text; v_key text;
begin
 v_result:=private.f2_mask_file_payload(public.cmd_compare_task_file_versions_f2_internal(
   p_project_id,p_base_file_version_id,p_target_file_version_id,p_request_id));
 if v_result->>'ok'='true' then
   foreach v_side in array array['base','target'] loop
     foreach v_key in array array['logicalName','originalName','uploadedBy'] loop
       if v_result#>array['data',v_side,v_key] is not null then
         v_result:=jsonb_set(v_result,array['data','metadataComparison','diff',v_key,v_side],
           v_result#>array['data',v_side,v_key],false);
       end if;
     end loop;
   end loop;
 end if;
 return v_result;
end;
$$;
revoke all on function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.cmd_compare_task_file_versions(uuid,uuid,uuid,uuid) to authenticated;

-- Unstructured audit payloads have no browser consumer; numeric facts remain
-- readable under their existing RLS. Do not pretend arbitrary JSON is anonymous.
revoke select on public.business_events from public,anon,authenticated;
grant select(id,project_id,actor_id,event_type,entity_type,entity_id,request_id,
 created_at,command_request_id,event_seq) on public.business_events to authenticated;
revoke select(event_data) on public.business_events from public,anon,authenticated;
revoke select on public.contribution_penalties from public,anon,authenticated;
grant select(id,project_id,task_id,source_event_id,member_user_id,member_key,kind,
 source_occurrence_key,responsibility_epoch_id,policy_version,base_amount,rate,
 amount,duration_seconds,delay_seconds,assessed_at)
 on public.contribution_penalties to authenticated;
revoke select(event_snapshot) on public.contribution_penalties from public,anon,authenticated;

-- Check Auth truth as well as lifecycle truth, including canceled cases. This
-- does not demand session claims from service jobs or historical business RPCs.
create or replace function public.account_lifecycle_access_allowed(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_user is not null
   and (p_user=auth.uid() or auth.role()='service_role')
   and exists(select 1 from auth.users u where u.id=p_user
     and u.deleted_at is null
     and (u.banned_until is null or u.banned_until<=transaction_timestamp()))
   and not exists(select 1 from public.account_lifecycle_requests l
     where l.user_id=p_user and l.state<>'canceled');
$$;

create or replace function private.is_active_member(p_project_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u where u.id=p_user_id
   and u.deleted_at is null and (u.banned_until is null or u.banned_until<=transaction_timestamp()))
 and not exists(select 1 from public.account_lifecycle_requests l where l.user_id=p_user_id and l.state<>'canceled')
 and exists(select 1 from public.project_members m where m.project_id=p_project_id
   and m.user_id=p_user_id and m.member_state='active');
$$;

-- Sensitive request/cancel operations require a currently existing GoTrue
-- session owned by this subject. A signed legacy JWT without session_id, or
-- one whose session has been revoked, cannot reverse the lifecycle fence.
create function private.f2_lifecycle_session_valid()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s join auth.users u on u.id=s.user_id
   where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid()
     and (s.not_after is null or s.not_after>transaction_timestamp())
     and u.deleted_at is null
     and (u.banned_until is null or u.banned_until<=transaction_timestamp()));
$$;
revoke all on function private.f2_lifecycle_session_valid() from public,anon,authenticated,service_role;

alter function public.cmd_request_account_deletion(uuid,integer)
 rename to cmd_request_account_deletion_f2_internal;
alter function public.cmd_cancel_account_deletion(uuid,integer)
 rename to cmd_cancel_account_deletion_f2_internal;
revoke all on function public.cmd_request_account_deletion_f2_internal(uuid,integer),
 public.cmd_cancel_account_deletion_f2_internal(uuid,integer)
 from public,anon,authenticated,service_role;
create function public.cmd_request_account_deletion(p_request_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.f2_lifecycle_session_valid() then
   return private.failure(p_request_id,'REAUTHENTICATION_REQUIRED');
 end if;
 return public.cmd_request_account_deletion_f2_internal(p_request_id,p_expected_version);
end;
$$;
create function public.cmd_cancel_account_deletion(p_request_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.f2_lifecycle_session_valid() then
   return private.failure(p_request_id,'REAUTHENTICATION_REQUIRED');
 end if;
 return public.cmd_cancel_account_deletion_f2_internal(p_request_id,p_expected_version);
end;
$$;
revoke all on function public.cmd_request_account_deletion(uuid,integer),
 public.cmd_cancel_account_deletion(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.cmd_request_account_deletion(uuid,integer),
 public.cmd_cancel_account_deletion(uuid,integer) to authenticated;

-- The original insertion guard also runs before ON CONFLICT replay. Retain
-- that protection and reject banned/deleted Auth subjects for business writes.
create or replace function private.g_account_lifecycle_claim_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.command_name not in ('cmd_request_account_deletion','cmd_cancel_account_deletion')
   and (exists(select 1 from public.account_lifecycle_requests l
       where l.user_id=new.actor_id and l.state<>'canceled')
     or exists(select 1 from auth.users u where u.id=new.actor_id
       and (u.deleted_at is not null or u.banned_until>transaction_timestamp()))) then
   raise exception using errcode='42501',message='ACCOUNT_ACCESS_DISABLED';
 end if;
 return new;
end;
$$;

-- Supplement every existing public table's RLS, including tables added after
-- Projectless notifications bypass the membership predicate; fence their
-- SECURITY DEFINER operations explicitly as well as direct table reads.
create or replace function public.get_unread_notification_count()
returns bigint language sql stable security definer set search_path='' as $$
 select count(*) from public.notifications n
 where public.account_lifecycle_access_allowed(auth.uid())
   and n.recipient_id=auth.uid() and n.read_at is null
   and (n.project_id is null or public.is_active_project_member(n.project_id));
$$;
create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.account_lifecycle_access_allowed(auth.uid()) then return false; end if;
 update public.notifications n set read_at=coalesce(n.read_at,now())
 where n.id=p_notification_id and n.recipient_id=auth.uid()
   and (n.project_id is null or public.is_active_project_member(n.project_id));
 return found;
end;
$$;
create or replace function public.mark_all_notifications_read()
returns bigint language plpgsql security definer set search_path='' as $$
declare v_count bigint;
begin
 if not public.account_lifecycle_access_allowed(auth.uid()) then return 0; end if;
 update public.notifications n set read_at=now()
 where n.recipient_id=auth.uid() and n.read_at is null
   and (n.project_id is null or public.is_active_project_member(n.project_id));
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

-- Supplement every existing public table's RLS, including tables added after
-- the initial F migration. This is restrictive, never an access grant.
do $$
declare r record;
begin
 for r in select c.oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind in ('r','p') and c.relrowsecurity
     and not exists(select 1 from pg_policy p where p.polrelid=c.oid
       and p.polname='account_deletion_access_fence')
 loop
   execute format('create policy account_deletion_access_fence on public.%I as restrictive for all to authenticated using (public.account_lifecycle_access_allowed((select auth.uid()))) with check (public.account_lifecycle_access_allowed((select auth.uid())))',r.relname);
 end loop;
end;
$$;
