-- Formal four-role membership schema and shared guards.

alter table public.project_members drop constraint project_members_role;
update public.project_members set role='observer' where is_observer;
alter table public.project_members
  add column version integer not null default 1,
  add constraint project_members_role check (role in ('leader','admin','member','observer')),
  add constraint project_members_version_positive check (version > 0),
  add constraint project_members_observer_role_consistency check (is_observer = (role='observer'));

create function private.assert_project_leader_integrity()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_project_id uuid;
  v_leader_id uuid;
  v_count integer;
begin
  if tg_table_name='projects' then
    v_project_id:=coalesce(new.id,old.id);
  else
    v_project_id:=coalesce(new.project_id,old.project_id);
  end if;
  select p.leader_id into v_leader_id from public.projects p where p.id=v_project_id;
  if not found then return null; end if;

  select count(*)::integer into v_count
  from public.project_members pm
  where pm.project_id=v_project_id and pm.role='leader' and pm.member_state='active';

  if v_count <> 1 or not exists (
    select 1 from public.project_members pm
    where pm.project_id=v_project_id and pm.role='leader' and pm.member_state='active'
      and pm.user_id is not distinct from v_leader_id
  ) then
    raise exception using errcode='23514', constraint='project_requires_exactly_one_active_leader',
      message='Project must have exactly one active leader matching projects.leader_id';
  end if;
  return null;
end;
$$;

create constraint trigger project_members_leader_integrity
after insert or update or delete on public.project_members
deferrable initially deferred
for each row execute function private.assert_project_leader_integrity();

create constraint trigger projects_leader_integrity
after update on public.projects
deferrable initially deferred
for each row execute function private.assert_project_leader_integrity();

create function private.is_active_project_manager(p_project_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.project_members pm
    where pm.project_id=p_project_id and pm.user_id=p_user_id
      and pm.member_state='active' and pm.role in ('leader','admin')
  );
$$;

-- Every project-scoped command is read-only for observers. Existing RPCs still
-- perform their normal authorization; this adds a server-side backstop so a
-- hidden client button can never become authority.
create or replace function private.claim_command(
  p_actor_id uuid,
  p_command_name text,
  p_request_id uuid,
  p_payload_hash bytea,
  p_account_id uuid default null,
  p_project_id uuid default null
) returns table(command_id uuid, prior_result jsonb, payload_matches boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.command_requests%rowtype;
  v_inserted_count integer:=0;
  v_failure jsonb;
begin
  insert into public.command_requests(account_id,project_id,actor_id,command_name,request_id,payload_hash)
  values(p_account_id,p_project_id,p_actor_id,p_command_name,p_request_id,p_payload_hash)
  on conflict do nothing;
  get diagnostics v_inserted_count = row_count;

  select * into v_row
  from public.command_requests cr
  where cr.actor_id=p_actor_id and cr.command_name=p_command_name and cr.request_id=p_request_id
    and cr.account_id is not distinct from p_account_id
    and cr.project_id is not distinct from p_project_id
  for update;

  if v_row.state='in_progress'
     and v_row.payload_hash=p_payload_hash
     and p_project_id is not null
     and p_command_name <> 'cmd_leave_project'
     and exists(
       select 1 from public.project_members pm
       where pm.project_id=p_project_id and pm.user_id=p_actor_id
         and pm.member_state='active' and pm.role='observer'
     ) then
    v_failure:=private.failure(p_request_id,'NOT_AUTHORIZED',null,null,jsonb_build_object('reason','observer_read_only'));
    update public.command_requests
    set state='completed',result=v_failure,updated_at=now(),completed_at=now()
    where id=v_row.id;
    v_row.state:='completed';
    v_row.result:=v_failure;
  end if;

  command_id:=v_row.id;
  prior_result:=case
    when v_row.state='completed' and v_inserted_count=1 then v_row.result || jsonb_build_object('_firstClaim',true)
    when v_row.state='completed' then v_row.result
    else null
  end;
  payload_matches:=v_row.payload_hash=p_payload_hash;
  return next;
end;
$$;

create or replace function private.replay_or_reuse(
  p_request_id uuid,p_prior_result jsonb,p_payload_matches boolean
) returns jsonb language sql immutable set search_path = '' as $$
  select case
    when not p_payload_matches then private.failure(p_request_id,'IDEMPOTENCY_KEY_REUSED')
    when p_prior_result is not null and p_prior_result @> '{"_firstClaim":true}'::jsonb then p_prior_result - '_firstClaim'
    when p_prior_result is not null then jsonb_set(p_prior_result,'{replayed}','true'::jsonb)
    else null
  end;
$$;

create or replace function private.reject_unless_authorized(
  p_authorized boolean,p_request_id uuid,p_command_id uuid,p_prior_result jsonb,p_payload_matches boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if p_payload_matches is not true then return private.failure(p_request_id,'IDEMPOTENCY_KEY_REUSED'); end if;
  if p_prior_result is not null and p_prior_result @> '{"_firstClaim":true}'::jsonb then
    return p_prior_result - '_firstClaim';
  end if;
  if p_authorized then return null; end if;
  if p_prior_result is not null then
    if p_prior_result->>'ok'='false' then return jsonb_set(p_prior_result,'{replayed}','true'::jsonb); end if;
    return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  end if;
  v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
  return private.complete_command(p_command_id,v_result);
end;
$$;

-- Revoke outstanding upload authority immediately when an actor becomes
-- an observer. Reservations alone are not durable write permission.
create or replace function private.is_current_task_file_actor(
  p_project_id uuid,
  p_task_id uuid,
  p_actor_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.project_members pm
    join public.tasks t
      on t.project_id=pm.project_id
     and t.id=p_task_id
    where pm.project_id=p_project_id
      and pm.user_id=p_actor_id
      and pm.member_state='active'
      and pm.role<>'observer'
      and (
        t.assignee_id=p_actor_id
        or t.created_by=p_actor_id
        or pm.role='leader'
      )
  );
$$;

drop policy if exists file_upload_reservations_select_owner_or_leader
  on public.file_upload_reservations;
create policy file_upload_reservations_select_owner_or_leader
on public.file_upload_reservations for select to authenticated
using (
  exists(
    select 1
    from public.project_members pm
    where pm.project_id=file_upload_reservations.project_id
      and pm.user_id=(select auth.uid())
      and pm.member_state='active'
      and (
        file_upload_reservations.actor_id=(select auth.uid())
        or pm.role='leader'
      )
  )
);

drop policy if exists teamup_files_insert_reserved on storage.objects;
create policy teamup_files_insert_reserved
on storage.objects for insert to authenticated
with check (
  bucket_id='teamup-files'
  and exists(
    select 1
    from public.file_upload_reservations r
    join public.project_members pm
      on pm.project_id=r.project_id
     and pm.user_id=(select auth.uid())
     and pm.member_state='active'
     and pm.role<>'observer'
    join public.tasks t
      on t.project_id=r.project_id
     and t.id=r.task_id
    where r.object_path=name
      and r.actor_id=(select auth.uid())
      and r.state='reserved'
      and r.expires_at>now()
      and (
        t.assignee_id=(select auth.uid())
        or t.created_by=(select auth.uid())
        or pm.role='leader'
      )
  )
);

revoke all on function private.is_current_task_file_actor(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

revoke all on function private.assert_project_leader_integrity() from public,anon,authenticated,service_role;
revoke all on function private.is_active_project_manager(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function private.claim_command(uuid,text,uuid,bytea,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function private.replay_or_reuse(uuid,jsonb,boolean) from public,anon,authenticated,service_role;
revoke all on function private.reject_unless_authorized(boolean,uuid,uuid,jsonb,boolean) from public,anon,authenticated,service_role;

comment on column public.project_members.role is 'Authoritative project role: leader, admin, member, or observer. is_observer remains a constrained compatibility mirror.';
comment on column public.project_members.version is 'Optimistic concurrency version for controlled membership changes.';
