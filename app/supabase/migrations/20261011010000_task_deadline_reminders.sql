-- Workstream A: UTC deadline reminders and service-only transactional dispatch.
create table public.task_reminder_deadlines (
 task_id uuid primary key references public.tasks(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 deadline_at timestamptz not null,
 deadline_revision integer not null default 1 check(deadline_revision>0)
);
create function private.sync_task_reminder_deadline()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.task_reminder_deadlines(task_id,project_id,deadline_at)
 values(new.id,new.project_id,new.deadline_at)
 on conflict(task_id) do update set
 deadline_at=excluded.deadline_at,
 deadline_revision=public.task_reminder_deadlines.deadline_revision+1
 where public.task_reminder_deadlines.deadline_at is distinct from excluded.deadline_at;
 return new;
end $$;
create trigger task_deadline_reminder_revision
after insert or update of deadline_at on public.tasks
for each row execute function private.sync_task_reminder_deadline();
insert into public.task_reminder_deadlines(task_id,project_id,deadline_at)
select id,project_id,deadline_at from public.tasks on conflict do nothing;

create function private.valid_task_reminder_offsets(p integer[])
returns boolean language sql immutable set search_path='' as $$
 select p is not null and cardinality(p) between 1 and 6
 and not exists(select 1 from unnest(p) as o(v)
                where v is null or v<300 or v>1209600 or v%60<>0)
 and cardinality(p)=(select count(distinct v) from unnest(p) as o(v))
 and p=(select array_agg(v order by v desc) from unnest(p) as o(v));
$$;
create table public.task_reminder_preferences (
 project_id uuid not null references public.projects(id) on delete cascade,
 task_id uuid not null,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 offsets_seconds integer[] not null default array[86400,7200],
 enabled boolean not null default true,
 version integer not null default 1 check(version>0),
 updated_at timestamptz not null default now(),
 primary key(task_id,recipient_id),
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade,
 constraint reminder_offsets_valid check(private.valid_task_reminder_offsets(offsets_seconds))
);
create table public.task_reminder_jobs (
 task_id uuid not null,
 project_id uuid not null,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 deadline_revision integer not null check(deadline_revision>0),
 offset_seconds integer not null check(offset_seconds between 300 and 1209600),
 scheduled_for timestamptz not null,
 deadline_at timestamptz not null,
 delivered_at timestamptz,
 invalidated_at timestamptz,
 source_event_id bigint references public.business_events(id),
 primary key(task_id,recipient_id,deadline_revision,offset_seconds),
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade,
 constraint reminder_job_single_terminal check(delivered_at is null or invalidated_at is null)
);
create index task_reminder_due_idx on public.task_reminder_jobs(scheduled_for)
 where delivered_at is null and invalidated_at is null;
create unique index task_reminder_once_per_offset_idx
 on public.task_reminder_jobs(task_id,recipient_id,offset_seconds)
 where delivered_at is not null;

create table public.task_nudge_logs (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null,
 task_id uuid not null,
 sender_id uuid not null references auth.users(id) on delete cascade,
 exception_kind text not null check(exception_kind in ('none','blocked','urgent')),
 recipient_count integer not null check(recipient_count>0),
 source_event_id bigint references public.business_events(id),
 sent_at timestamptz not null default now(),
 foreign key(project_id,task_id) references public.tasks(project_id,id) on delete cascade
);
create index task_nudge_cooldown_idx on public.task_nudge_logs(sender_id,task_id,sent_at desc);

alter table public.task_reminder_deadlines enable row level security;
alter table public.task_reminder_preferences enable row level security;
alter table public.task_reminder_jobs enable row level security;
alter table public.task_nudge_logs enable row level security;
create policy self_task_reminder_preferences on public.task_reminder_preferences
 for select to authenticated using(recipient_id=(select auth.uid())
 and public.is_active_project_member(project_id));
create policy own_task_nudges on public.task_nudge_logs
 for select to authenticated using(sender_id=(select auth.uid())
 and public.is_active_project_member(project_id));
revoke all on public.task_reminder_deadlines,public.task_reminder_preferences,
 public.task_reminder_jobs,public.task_nudge_logs from public,anon,authenticated,service_role;
grant select on public.task_reminder_preferences,public.task_nudge_logs to authenticated;

create function public.cmd_set_task_reminder_preferences(
 p_project_id uuid,p_task_id uuid,p_offsets_seconds integer[],p_enabled boolean,
 p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_claim record; v_replay jsonb; v_result jsonb;
 v_project public.projects%rowtype; v_task public.tasks%rowtype;
 v_version integer:=0; v_current public.task_reminder_preferences%rowtype;
begin
 if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
 if not exists(select 1 from public.tasks where id=p_task_id and project_id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into v_claim from private.claim_command(
  v_actor,'cmd_set_task_reminder_preferences',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,
   'offsetsSeconds',p_offsets_seconds,'enabled',p_enabled,'expectedVersion',p_expected_version)),
  null,p_project_id);
 v_result:=private.reject_unless_authorized(
  private.is_task_participant(p_project_id,p_task_id,v_actor),
  p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
 if v_result is not null then
  if v_result->>'code'='NOT_AUTHORIZED' then
   v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
   return private.complete_command(v_claim.command_id,v_result);
  end if;
  return v_result;
 end if;
 v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
 if v_replay is not null then return v_replay; end if;
 select * into v_project from public.projects where id=p_project_id for update;
 select * into v_task from public.tasks where id=p_task_id and project_id=p_project_id for update;
 select * into v_current from public.task_reminder_preferences
  where task_id=p_task_id and recipient_id=v_actor for update;
 if found then v_version:=v_current.version; end if;
 if not private.is_task_participant(p_project_id,p_task_id,v_actor) then
  v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif v_project.archived_at is not null or v_project.lifecycle_state<>'active' then
  v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif v_task.status in ('completed','canceled') then
  v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif p_expected_version is null or p_expected_version<>v_version then
  v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_version);
 elsif p_enabled is null or not private.valid_task_reminder_offsets(p_offsets_seconds) then
  v_result:=private.failure(p_request_id,'VALIDATION_FAILED','offsetsSeconds');
 else
  insert into public.task_reminder_preferences(project_id,task_id,recipient_id,offsets_seconds,enabled)
  values(p_project_id,p_task_id,v_actor,p_offsets_seconds,p_enabled)
  on conflict(task_id,recipient_id) do update set offsets_seconds=excluded.offsets_seconds,
   enabled=excluded.enabled,version=public.task_reminder_preferences.version+1,updated_at=now()
  returning version into v_version;
  perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,
   'task_reminder_preferences_set','task',p_task_id,p_request_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,'taskId',p_task_id,
    'occurrenceKey',format('task:%s:recipient:%s:preferences:%s',p_task_id,v_actor,v_version),
    'occurredAt',transaction_timestamp(),'aggregateVersion',v_version,
    'responsibleUserId',v_actor,'enabled',p_enabled,'offsetsSeconds',p_offsets_seconds));
  v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
    'taskId',p_task_id,'recipientId',v_actor,'offsetsSeconds',p_offsets_seconds,
    'enabled',p_enabled,'preferenceVersion',v_version),
    'requestId',p_request_id,'replayed',false,'aggregateType','task_reminder_preferences',
    'aggregateId',p_task_id,'aggregateVersion',v_version);
  return private.complete_command(v_claim.command_id,v_result,'task_reminder_preferences',p_task_id,v_version);
 end if;
 return private.complete_command(v_claim.command_id,v_result);
end $$;

create function public.cmd_send_task_nudge(
 p_project_id uuid,p_task_id uuid,p_request_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_claim record; v_replay jsonb; v_result jsonb;
 v_project public.projects%rowtype; v_task public.tasks%rowtype;
 v_leader boolean; v_primary boolean; v_kind text:='none'; v_count integer;
 v_now timestamptz:=transaction_timestamp(); v_last timestamptz;
 v_exception_used boolean; v_sender_name text; v_log_id uuid; v_event_id bigint;
 v_recipient record;
begin
 if v_actor is null then return private.failure(p_request_id,'UNAUTHENTICATED'); end if;
 if p_request_id is null then return private.failure(null,'VALIDATION_FAILED','requestId'); end if;
 if not exists(select 1 from public.tasks where id=p_task_id and project_id=p_project_id) then
  return private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED'); end if;
 select * into v_claim from private.claim_command(v_actor,'cmd_send_task_nudge',p_request_id,
  private.payload_hash(jsonb_build_object('projectId',p_project_id,'taskId',p_task_id,
   'expectedVersion',p_expected_version)),null,p_project_id);
 v_leader:=private.is_active_leader(p_project_id,v_actor)
  and private.is_active_non_observer_member(p_project_id,v_actor);
 v_primary:=private.is_task_participant(p_project_id,p_task_id,v_actor)
  and exists(select 1 from public.tasks where id=p_task_id and assignee_id=v_actor);
 v_result:=private.reject_unless_authorized(v_leader or v_primary,
  p_request_id,v_claim.command_id,v_claim.prior_result,v_claim.payload_matches);
 if v_result is not null then
  if v_result->>'code'='NOT_AUTHORIZED' then
   v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
   return private.complete_command(v_claim.command_id,v_result);
  end if;
  return v_result;
 end if;
 v_replay:=private.replay_or_reuse(p_request_id,v_claim.prior_result,v_claim.payload_matches);
 if v_replay is not null then return v_replay; end if;
 select * into v_project from public.projects where id=p_project_id for update;
 select * into v_task from public.tasks where id=p_task_id and project_id=p_project_id for update;
 v_leader:=private.is_active_leader(p_project_id,v_actor)
  and private.is_active_non_observer_member(p_project_id,v_actor);
 v_primary:=private.is_task_participant(p_project_id,p_task_id,v_actor)
  and v_task.assignee_id=v_actor;
 select count(*) into v_count from (
  select v_task.assignee_id as recipient where v_leader
  union select c.user_id from public.task_collaborators c
   where c.project_id=p_project_id and c.task_id=p_task_id and c.state='accepted'
 ) recipients where recipient is not null and recipient<>v_actor
  and private.is_active_non_observer_member(p_project_id,recipient);
 if v_task.status='blocked' or exists(
  select 1 from public.task_dependencies d join public.tasks u
   on u.project_id=d.project_id and u.id=d.upstream_task_id
  where d.project_id=p_project_id and d.downstream_task_id=p_task_id
   and u.status<>'completed'
 ) then v_kind:='blocked';
 elsif v_task.deadline_at>v_now and v_task.deadline_at<v_now+interval '2 hours'
 then v_kind:='urgent'; end if;
 select max(sent_at) into v_last from public.task_nudge_logs
  where task_id=p_task_id and sender_id=v_actor and sent_at>v_now-interval '12 hours';
 select exists(select 1 from public.task_nudge_logs
  where task_id=p_task_id and sender_id=v_actor and exception_kind=v_kind
  and sent_at>v_now-interval '12 hours') into v_exception_used;
 if not(v_leader or v_primary) then
  v_result:=private.failure(p_request_id,'NOT_FOUND_OR_NOT_AUTHORIZED');
 elsif v_project.archived_at is not null or v_project.lifecycle_state<>'active' then
  v_result:=private.failure(p_request_id,'PROJECT_NOT_ACTIVE');
 elsif v_task.status in ('completed','canceled') then
  v_result:=private.failure(p_request_id,'INVALID_TRANSITION');
 elsif p_expected_version is null or v_task.version<>p_expected_version then
  v_result:=private.failure(p_request_id,'STALE_VERSION',null,v_task.version);
 elsif v_count=0 then
  v_result:=private.failure(p_request_id,'INVALID_TRANSITION',null,v_task.version,
   jsonb_build_object('reason','no_eligible_recipients'));
 elsif v_last is not null and (v_kind='none' or v_exception_used) then
  v_result:=private.failure(p_request_id,'RATE_LIMITED',null,v_task.version,
   jsonb_build_object('cooldownSeconds',43200,'exceptionKind',v_kind));
 else
  select coalesce(nullif(p.display_name,''),nullif(pm.display_name_snapshot,''),'组员')
   into v_sender_name from public.project_members pm
   left join public.profiles p on p.id=pm.user_id
   where pm.project_id=p_project_id and pm.user_id=v_actor and pm.member_state='active'
   limit 1;
  insert into public.task_nudge_logs(project_id,task_id,sender_id,exception_kind,recipient_count)
   values(p_project_id,p_task_id,v_actor,v_kind,v_count) returning id into v_log_id;
  perform private.emit_event(v_claim.command_id,1,p_project_id,v_actor,'task_nudge_sent',
   'task',p_task_id,p_request_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,
    'occurrenceKey',format('task:%s:nudge:%s',p_task_id,v_log_id),
    'occurredAt',v_now,'aggregateVersion',v_task.version,
    'responsibleUserId',v_task.assignee_id,'taskId',p_task_id,
    'senderId',v_actor,'senderName',v_sender_name,
    'exceptionKind',v_kind,'recipientCount',v_count,'nudgeId',v_log_id));
  select id into v_event_id from public.business_events
   where command_request_id=v_claim.command_id and event_seq=1;
  update public.task_nudge_logs set source_event_id=v_event_id where id=v_log_id;
  for v_recipient in
   select recipient from (
    select v_task.assignee_id as recipient where v_leader
    union select c.user_id from public.task_collaborators c
     where c.project_id=p_project_id and c.task_id=p_task_id and c.state='accepted'
   ) r where recipient is not null and recipient<>v_actor
    and private.is_active_non_observer_member(p_project_id,recipient)
  loop
   perform private.create_notification(v_event_id,p_project_id,v_recipient.recipient,
    'task_nudge','任务催促',
    left(format('%s 催促你处理任务「%s」。',v_sender_name,v_task.title),1000),
    'task',p_task_id);
  end loop;
  v_result:=jsonb_build_object('ok',true,'data',jsonb_build_object(
   'taskId',p_task_id,'nudgeId',v_log_id,'recipientCount',v_count,
   'exceptionKind',v_kind,'sentAt',v_now),
   'requestId',p_request_id,'replayed',false,'aggregateType','task',
   'aggregateId',p_task_id,'aggregateVersion',v_task.version);
  return private.complete_command(v_claim.command_id,v_result,'task',p_task_id,v_task.version);
 end if;
 return private.complete_command(v_claim.command_id,v_result);
end $$;

create function private.dispatch_due_task_reminders(
 p_batch_limit integer default 100,p_now timestamptz default transaction_timestamp()
) returns integer language plpgsql security definer set search_path='' as $$
declare
 v_job public.task_reminder_jobs%rowtype; v_task public.tasks%rowtype;
 v_project public.projects%rowtype; v_revision public.task_reminder_deadlines%rowtype;
 v_offsets integer[]; v_enabled boolean; v_event bigint; v_sent integer:=0;
 v_now timestamptz:=coalesce(p_now,transaction_timestamp());
begin
 if p_batch_limit is null or p_batch_limit not between 1 and 500 then
  raise exception 'Invalid reminder batch limit' using errcode='22023'; end if;
 -- Candidate projection is repeatable and concurrency-safe. No client scheduling.
 insert into public.task_reminder_jobs(
  task_id,project_id,recipient_id,deadline_revision,offset_seconds,scheduled_for,deadline_at)
 select t.id,t.project_id,participant.user_id,r.deadline_revision,o.seconds,
  r.deadline_at-make_interval(secs=>o.seconds),r.deadline_at
 from public.tasks t
 join public.projects p on p.id=t.project_id
 join public.task_reminder_deadlines r on r.task_id=t.id
 cross join lateral(
  select t.assignee_id as user_id where t.assignee_id is not null
  union select c.user_id from public.task_collaborators c
   where c.project_id=t.project_id and c.task_id=t.id and c.state='accepted'
   and c.user_id is not null
 ) participant
 join public.project_members pm on pm.project_id=t.project_id
  and pm.user_id=participant.user_id and pm.member_state='active'
  and not pm.is_observer and pm.role<>'observer'
 left join public.task_reminder_preferences pref
  on pref.task_id=t.id and pref.recipient_id=participant.user_id
 cross join lateral unnest(coalesce(pref.offsets_seconds,array[86400,7200])) as o(seconds)
 where p.archived_at is null and p.lifecycle_state='active'
  and t.status not in ('completed','canceled','blocked')
  and r.deadline_at=t.deadline_at and r.deadline_at>v_now
  and coalesce(pref.enabled,true)
  and r.deadline_at-make_interval(secs=>o.seconds)<=v_now
  and not exists(select 1 from public.task_dependencies d
   join public.tasks u on u.project_id=d.project_id and u.id=d.upstream_task_id
   where d.project_id=t.project_id and d.downstream_task_id=t.id
    and u.status<>'completed')
  and not exists(select 1 from public.task_reminder_jobs prior
   where prior.task_id=t.id and prior.recipient_id=participant.user_id
    and prior.offset_seconds=o.seconds and prior.delivered_at is not null)
 order by r.deadline_at-make_interval(secs=>o.seconds),t.id,participant.user_id
 limit (p_batch_limit*10) on conflict do nothing;

 for v_job in
  select * from public.task_reminder_jobs
  where delivered_at is null and invalidated_at is null and scheduled_for<=v_now
  order by scheduled_for,task_id,recipient_id,offset_seconds
  limit p_batch_limit for update skip locked
 loop
  select * into v_project from public.projects where id=v_job.project_id for update;
  select * into v_task from public.tasks
   where id=v_job.task_id and project_id=v_job.project_id for update;
  select * into v_revision from public.task_reminder_deadlines
   where task_id=v_job.task_id for update;
  select offsets_seconds,enabled into v_offsets,v_enabled from public.task_reminder_preferences
   where task_id=v_job.task_id and recipient_id=v_job.recipient_id;
  if not found then v_offsets:=array[86400,7200];v_enabled:=true;end if;
  if v_project.id is null or v_task.id is null or v_revision.task_id is null
   or v_project.archived_at is not null or v_project.lifecycle_state<>'active'
   or v_task.status in ('completed','canceled','blocked')
   or v_revision.deadline_revision<>v_job.deadline_revision
   or v_revision.deadline_at<>v_job.deadline_at
   or v_revision.deadline_at<>v_task.deadline_at
   or v_now>=v_revision.deadline_at or v_job.scheduled_for>v_now
   or not coalesce(v_enabled,false) or not(v_job.offset_seconds=any(v_offsets))
   or not private.is_task_participant(v_job.project_id,v_job.task_id,v_job.recipient_id)
   or exists(select 1 from public.task_dependencies d
    join public.tasks u on u.project_id=d.project_id and u.id=d.upstream_task_id
    where d.project_id=v_job.project_id and d.downstream_task_id=v_job.task_id
     and u.status<>'completed')
   or exists(select 1 from public.task_reminder_jobs prior
    where prior.task_id=v_job.task_id and prior.recipient_id=v_job.recipient_id
     and prior.offset_seconds=v_job.offset_seconds and prior.delivered_at is not null)
  then
   update public.task_reminder_jobs set invalidated_at=v_now
    where task_id=v_job.task_id and recipient_id=v_job.recipient_id
     and deadline_revision=v_job.deadline_revision and offset_seconds=v_job.offset_seconds;
   continue;
  end if;
  insert into public.business_events(project_id,actor_id,event_type,entity_type,entity_id,event_data)
  values(v_job.project_id,null,'task_deadline_reminder','task',v_job.task_id,
   jsonb_build_object('schemaVersion',1,'policyVersion',1,
    'occurrenceKey',format('task:%s:recipient:%s:deadline:%s:offset:%s',
     v_job.task_id,v_job.recipient_id,v_job.deadline_revision,v_job.offset_seconds),
    'occurredAt',v_now,'aggregateVersion',v_task.version,
    'responsibleUserId',v_job.recipient_id,'taskId',v_job.task_id,
    'recipientId',v_job.recipient_id,'deadlineRevision',v_job.deadline_revision,
    'deadlineAt',v_job.deadline_at,'offsetSeconds',v_job.offset_seconds))
  returning id into v_event;
  perform private.create_notification(v_event,v_job.project_id,v_job.recipient_id,
   'task_deadline_reminder','任务即将截止',
   left(format('任务「%s」距离截止还有 %s 分钟，请及时处理。',
    v_task.title,(v_job.offset_seconds/60)),1000),'task',v_job.task_id);
  update public.task_reminder_jobs set delivered_at=v_now,source_event_id=v_event
   where task_id=v_job.task_id and recipient_id=v_job.recipient_id
    and deadline_revision=v_job.deadline_revision and offset_seconds=v_job.offset_seconds;
  v_sent:=v_sent+1;
 end loop;
 return v_sent;
end $$;

-- Private schema is not exposed by REST; only the service_role wrapper is callable.
create function public.dispatch_task_reminders_service(p_batch_limit integer default 100)
returns integer language sql volatile security definer set search_path='' as $$
 select private.dispatch_due_task_reminders(p_batch_limit,transaction_timestamp());
$$;
revoke all on function private.sync_task_reminder_deadline() from public,anon,authenticated,service_role;
revoke all on function private.valid_task_reminder_offsets(integer[]) from public,anon,authenticated,service_role;
revoke all on function private.dispatch_due_task_reminders(integer,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.dispatch_task_reminders_service(integer) from public,anon,authenticated;
grant execute on function public.dispatch_task_reminders_service(integer) to service_role;
revoke all on function public.cmd_set_task_reminder_preferences(uuid,uuid,integer[],boolean,uuid,integer) from public,anon,service_role;
grant execute on function public.cmd_set_task_reminder_preferences(uuid,uuid,integer[],boolean,uuid,integer) to authenticated;
revoke all on function public.cmd_send_task_nudge(uuid,uuid,uuid,integer) from public,anon,service_role;
grant execute on function public.cmd_send_task_nudge(uuid,uuid,uuid,integer) to authenticated;