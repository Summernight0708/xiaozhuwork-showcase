-- B: archive authority. projects.archived_at remains the only active archive bit.
create table public.project_archive_cycles (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id) on delete restrict,
 generation integer not null check(generation>0),
 archived_at timestamptz not null,
 archived_by uuid references auth.users(id) on delete set null,
 archive_reason text not null check(length(btrim(archive_reason)) between 1 and 500),
 archived_project_version integer not null,
 retain_until timestamptz not null,
 recovery_until timestamptz not null,
 restored_at timestamptz,
 restored_by uuid references auth.users(id) on delete set null,
 restored_project_version integer,
 version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),
 unique(project_id,generation),
 check(retain_until>archived_at and recovery_until=retain_until+interval '30 days'),
 check((restored_at is null and restored_by is null and restored_project_version is null)
   or (restored_at is not null and restored_project_version is not null))
);
create unique index project_archive_one_open_cycle on public.project_archive_cycles(project_id)
 where restored_at is null;
create index project_archive_retention_due on public.project_archive_cycles(retain_until)
 where restored_at is null;

-- Immutable per-extension records plus the common append-only business_events.
create table public.project_archive_retention_extensions (
 id uuid primary key default gen_random_uuid(),
 cycle_id uuid not null references public.project_archive_cycles(id) on delete restrict,
 project_id uuid not null references public.projects(id) on delete restrict,
 actor_id uuid references auth.users(id) on delete set null,
 request_id uuid not null,
 additional_days integer not null check(additional_days between 1 and 365),
 previous_retain_until timestamptz not null,
 new_retain_until timestamptz not null,
 project_version integer not null,
 created_at timestamptz not null default now(),
 unique(project_id,actor_id,request_id),
 check(new_retain_until>previous_retain_until)
);
alter table public.project_archive_cycles enable row level security;
alter table public.project_archive_retention_extensions enable row level security;
create policy archive_cycle_read on public.project_archive_cycles for select to authenticated
 using(public.is_active_project_member(project_id));
create policy archive_extension_read on public.project_archive_retention_extensions for select to authenticated
 using(public.is_active_project_member(project_id));
revoke all on public.project_archive_cycles,public.project_archive_retention_extensions from public,anon,authenticated;
grant select on public.project_archive_cycles,public.project_archive_retention_extensions to authenticated;

-- Legacy archive rows are backfilled without touching their lifecycle or data.
insert into public.project_archive_cycles(
 project_id,generation,archived_at,archived_by,archive_reason,
 archived_project_version,retain_until,recovery_until
)
select id,1,archived_at,null,'历史归档状态回填',version,
 archived_at+interval '1 year',(archived_at+interval '1 year')+interval '30 days'
from public.projects where archived_at is not null;

-- All quota-affecting commands acquire sorted profiles before projects.
create function private.lock_archive_profiles(p_project_id uuid) returns uuid[]
language plpgsql security definer set search_path='' as $$
declare v_ids uuid[]; v_id uuid;
begin
 select coalesce(array_agg(distinct user_id order by user_id),'{}'::uuid[]) into v_ids
 from public.project_members
 where project_id=p_project_id and member_state='active' and user_id is not null;
 foreach v_id in array v_ids loop
   perform 1 from public.profiles where id=v_id for update;
 end loop;
 return v_ids;
end; $$;
create function private.archive_profile_set_unchanged(p_project_id uuid,p_ids uuid[])
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select array_agg(distinct user_id order by user_id)
   from public.project_members where project_id=p_project_id
   and member_state='active' and user_id is not null),'{}'::uuid[])=p_ids;
$$;
revoke all on function private.lock_archive_profiles(uuid) from public,anon,authenticated;
revoke all on function private.archive_profile_set_unchanged(uuid,uuid[]) from public,anon,authenticated;

create function public.cmd_archive_project(
 p_project_id uuid,p_reason text,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_at timestamptz:=transaction_timestamp();
 v_hash bytea; v_claim record; v_result jsonb; v_replay jsonb;
 v_p public.projects%rowtype; v_c public.project_archive_cycles%rowtype;
 v_ids uuid[]; v_generation integer; v_reason text:=btrim(coalesce(p_reason,''));
begin
 if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
 if p_project_id is null or not private.is_active_leader(p_project_id,v_actor) then
   return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,
   'reason',p_reason,'expectedVersion',p_expected_version));
 select * into v_claim from private.claim_command(v_actor,'cmd_archive_project',
   p_request_id,v_hash,null,p_project_id);
 v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),
   p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
 if v_result is not null then return v_result; end if;
 v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
 if v_replay is not null then return v_replay; end if;

 v_ids:=private.lock_archive_profiles(p_project_id);
 select * into v_p from public.projects where id=p_project_id for update;
 if not found or v_p.leader_id is distinct from v_actor
    or not private.is_active_leader(p_project_id,v_actor) then
   v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif not private.archive_profile_set_unchanged(p_project_id,v_ids) then
   v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_p.version);
 elsif p_expected_version is null or v_p.version<>p_expected_version then
   v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_p.version);
 elsif v_p.archived_at is not null then
   v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE',null,v_p.version);
 elsif length(v_reason) not between 1 and 500 then
   v_result:=private.failure(p_request_id,'VALIDATION_FAILED','reason');
 else
   select coalesce(max(generation),0)+1 into v_generation
   from public.project_archive_cycles where project_id=p_project_id;
   insert into public.project_archive_cycles(
     project_id,generation,archived_at,archived_by,archive_reason,archived_project_version,
     retain_until,recovery_until
   ) values(p_project_id,v_generation,v_at,v_actor,v_reason,v_p.version+1,
     v_at+interval '1 year',(v_at+interval '1 year')+interval '30 days')
   returning * into v_c;
   update public.projects set archived_at=v_at,version=version+1,updated_at=v_at
     where id=p_project_id;
   perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'project_archived',
     'project',p_project_id,p_request_id,jsonb_build_object(
       'schemaVersion',1,'policyVersion',1,'occurrenceKey',
       format('project:%s:archive:%s:archived',p_project_id,v_generation),
       'occurredAt',v_at,'aggregateVersion',v_p.version+1,'responsibleUserId',null,
       'archiveCycleId',v_c.id,'archiveGeneration',v_generation,'projectVersion',v_p.version+1,
       'reason',v_reason,'retainUntil',v_c.retain_until,'recoveryUntil',v_c.recovery_until
     ));
   v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
     'projectId',p_project_id,'archiveCycleId',v_c.id,'generation',v_generation,
     'archivedAt',v_at,'retainUntil',v_c.retain_until,'recoveryUntil',v_c.recovery_until),
     'requestId',p_request_id,'replayed',false,'aggregateType','project',
     'aggregateId',p_project_id,'aggregateVersion',v_p.version+1);
   return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_p.version+1);
 end if;
 return private.complete_command(v_claim.command_id,v_result);
end; $$;

create function public.cmd_restore_project(
 p_project_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_at timestamptz:=transaction_timestamp();
 v_hash bytea; v_claim record; v_result jsonb; v_replay jsonb;
 v_p public.projects%rowtype; v_c public.project_archive_cycles%rowtype;
 v_ids uuid[]; v_member uuid; v_is_free boolean; v_quota_user uuid;
begin
 if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
 if p_project_id is null or not private.is_active_leader(p_project_id,v_actor) then
   return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,'expectedVersion',p_expected_version));
 select * into v_claim from private.claim_command(v_actor,'cmd_restore_project',
   p_request_id,v_hash,null,p_project_id);
 v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),
   p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
 if v_result is not null then return v_result; end if;
 v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
 if v_replay is not null then return v_replay; end if;

 v_ids:=private.lock_archive_profiles(p_project_id);
 select * into v_p from public.projects where id=p_project_id for update;
 if not found or v_p.leader_id is distinct from v_actor
   or not private.is_active_leader(p_project_id,v_actor) then
   v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif not private.archive_profile_set_unchanged(p_project_id,v_ids) then
   v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_p.version);
 elsif p_expected_version is null or v_p.version<>p_expected_version then
   v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_p.version);
 elsif v_p.archived_at is null then
   v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_p.version);
 else
   select * into v_c from public.project_archive_cycles where project_id=p_project_id
     and restored_at is null for update;
   if not found or v_c.archived_at is distinct from v_p.archived_at then
     v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_p.version);
   elsif v_at>v_c.recovery_until then
     v_result:=private.failure(p_request_id,'RETENTION_WINDOW_EXPIRED',null,v_p.version);
   else
     select exists(select 1 from private.resolve_project_entitlement(p_project_id,v_at)
       where state='free') into v_is_free;
     if v_is_free then
       foreach v_member in array v_ids loop
         if not private.account_can_add_free_project(v_member,v_at) then
           v_quota_user:=v_member; exit;
         end if;
       end loop;
     end if;
     if v_quota_user is not null then
       v_result:=private.failure(p_request_id,'ACTIVE_FREE_PROJECT_LIMIT_REACHED',null,v_p.version,
         jsonb_build_object('limit',5,'reason','restore_member_quota'));
     else
       update public.project_archive_cycles set restored_at=v_at,restored_by=v_actor,
         restored_project_version=v_p.version+1,version=version+1 where id=v_c.id;
       update public.projects set archived_at=null,version=version+1,updated_at=v_at
         where id=p_project_id;
       perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'project_restored',
         'project',p_project_id,p_request_id,jsonb_build_object(
         'schemaVersion',1,'policyVersion',1,'occurrenceKey',
         format('project:%s:archive:%s:restored',p_project_id,v_c.generation),
         'occurredAt',v_at,'aggregateVersion',v_p.version+1,'responsibleUserId',null,
         'archiveCycleId',v_c.id,'archiveGeneration',v_c.generation,'projectVersion',v_p.version+1,
         'retainUntil',v_c.retain_until,'recoveryUntil',v_c.recovery_until));
       v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
         'projectId',p_project_id,'archiveCycleId',v_c.id,'generation',v_c.generation,'restoredAt',v_at),
         'requestId',p_request_id,'replayed',false,'aggregateType','project',
         'aggregateId',p_project_id,'aggregateVersion',v_p.version+1);
       return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_p.version+1);
     end if;
   end if;
 end if;
 return private.complete_command(v_claim.command_id,v_result);
end; $$;

create function public.cmd_extend_project_retention(
 p_project_id uuid,p_additional_days integer,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_at timestamptz:=transaction_timestamp();
 v_hash bytea; v_claim record; v_result jsonb; v_replay jsonb;
 v_p public.projects%rowtype; v_c public.project_archive_cycles%rowtype;
 v_until timestamptz;
begin
 if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
 if p_project_id is null or not private.is_active_leader(p_project_id,v_actor) then
   return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 end if;
 v_hash:=private.payload_hash(jsonb_build_object('projectId',p_project_id,
   'additionalDays',p_additional_days,'expectedVersion',p_expected_version));
 select * into v_claim from private.claim_command(v_actor,'cmd_extend_project_retention',
   p_request_id,v_hash,null,p_project_id);
 v_result:=private.reject_unless_authorized(private.is_active_leader(p_project_id,v_actor),
   p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
 if v_result is not null then return v_result; end if;
 v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
 if v_replay is not null then return v_replay; end if;
 select * into v_p from public.projects where id=p_project_id for update;
 if not found or v_p.leader_id is distinct from v_actor
   or not private.is_active_leader(p_project_id,v_actor) then
   v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif p_expected_version is null or v_p.version<>p_expected_version then
   v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_p.version);
 elsif v_p.archived_at is null then
   v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_p.version);
 elsif p_additional_days is null or p_additional_days not between 1 and 365 then
   v_result:=private.failure(p_request_id,'VALIDATION_FAILED','additionalDays');
 else
   select * into v_c from public.project_archive_cycles where project_id=p_project_id
     and restored_at is null for update;
   if not found or v_c.archived_at is distinct from v_p.archived_at then
     v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_p.version);
   elsif v_at>=v_c.retain_until then
     v_result:=private.failure(p_request_id,'RETENTION_WINDOW_EXPIRED',null,v_p.version);
   else
     v_until:=v_c.retain_until+make_interval(days=>p_additional_days);
     update public.project_archive_cycles set retain_until=v_until,
       recovery_until=v_until+interval '30 days',version=version+1 where id=v_c.id;
     insert into public.project_archive_retention_extensions(
       cycle_id,project_id,actor_id,request_id,additional_days,
       previous_retain_until,new_retain_until,project_version
     ) values(v_c.id,p_project_id,v_actor,p_request_id,p_additional_days,
       v_c.retain_until,v_until,v_p.version+1);
     update public.projects set version=version+1,updated_at=v_at where id=p_project_id;
     perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,
       'project_retention_extended','project',p_project_id,p_request_id,jsonb_build_object(
       'schemaVersion',1,'policyVersion',1,'occurrenceKey',
       format('project:%s:archive:%s:extension:%s',p_project_id,v_c.generation,v_c.version+1),
       'occurredAt',v_at,'aggregateVersion',v_p.version+1,'responsibleUserId',null,
       'archiveCycleId',v_c.id,'archiveGeneration',v_c.generation,'projectVersion',v_p.version+1,
       'additionalDays',p_additional_days,'previousRetainUntil',v_c.retain_until,
       'retainUntil',v_until,'recoveryUntil',v_until+interval '30 days'));
     v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
       'projectId',p_project_id,'archiveCycleId',v_c.id,'generation',v_c.generation,
       'additionalDays',p_additional_days,'retainUntil',v_until,
       'recoveryUntil',v_until+interval '30 days'),
       'requestId',p_request_id,'replayed',false,'aggregateType','project',
       'aggregateId',p_project_id,'aggregateVersion',v_p.version+1);
     return private.complete_command(v_claim.command_id,v_result,'project',p_project_id,v_p.version+1);
   end if;
 end if;
 return private.complete_command(v_claim.command_id,v_result);
end; $$;

revoke all on function public.cmd_archive_project(uuid,text,uuid,integer)
 from public,anon,authenticated;
revoke all on function public.cmd_restore_project(uuid,uuid,integer)
 from public,anon,authenticated;
revoke all on function public.cmd_extend_project_retention(uuid,integer,uuid,integer)
 from public,anon,authenticated;
grant execute on function public.cmd_archive_project(uuid,text,uuid,integer) to authenticated;
grant execute on function public.cmd_restore_project(uuid,uuid,integer) to authenticated;
grant execute on function public.cmd_extend_project_retention(uuid,integer,uuid,integer) to authenticated;
comment on table public.project_archive_cycles is
 'B authority; projects.archived_at is the active flag, and F consumes B retain/recovery dates.';
