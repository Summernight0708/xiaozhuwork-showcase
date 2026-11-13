-- D6 first-version in-app notifications.
-- Reuses the foundation notifications table and derives trusted notifications
-- transactionally from append-only business events.

alter table public.notifications
  alter column project_id drop not null,
  add column title text,
  add column source_event_id bigint references public.business_events (id) on delete cascade;

update public.notifications
set title = case
  when notification_type is null or btrim(notification_type) = '' then '通知'
  else notification_type
end
where title is null;

alter table public.notifications
  alter column title set not null,
  add constraint notifications_title_length check (char_length(title) between 1 and 120);

create unique index notifications_source_recipient_type_idx
  on public.notifications (source_event_id, recipient_id, notification_type)
  where source_event_id is not null;

drop policy if exists notifications_select_recipient on public.notifications;
drop policy if exists notifications_mark_read on public.notifications;

create policy notifications_select_recipient
on public.notifications for select to authenticated
using (
  recipient_id = (select auth.uid())
  and (
    project_id is null
    or public.is_active_project_member(project_id)
  )
);

revoke update on public.notifications from authenticated;

create or replace function private.create_notification(
  p_source_event_id bigint,
  p_project_id uuid,
  p_recipient_id uuid,
  p_notification_type text,
  p_title text,
  p_message text,
  p_entity_type text default null,
  p_entity_id uuid default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient_id is null then
    return;
  end if;

  insert into public.notifications(
    project_id,
    recipient_id,
    notification_type,
    title,
    entity_type,
    entity_id,
    message,
    source_event_id
  ) values (
    p_project_id,
    p_recipient_id,
    p_notification_type,
    p_title,
    p_entity_type,
    p_entity_id,
    p_message,
    p_source_event_id
  )
  on conflict (source_event_id, recipient_id, notification_type)
    where source_event_id is not null
  do nothing;
end;
$$;

create or replace function private.notify_from_business_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_project_id uuid;
  v_task_id uuid;
  v_downstream record;
begin
  if new.event_type = 'task_created'
     and new.event_data->>'assignmentMode' = 'direct' then
    select o.target_user_id into v_recipient
    from public.task_assignment_offers o
    where o.project_id = new.project_id
      and o.task_id = new.entity_id
      and o.state = 'pending'
    order by o.created_at desc, o.id
    limit 1;

    perform private.create_notification(
      new.id,new.project_id,v_recipient,'task_assignment','新任务指派',
      '你收到了一项待确认的任务指派。','task',new.entity_id
    );

  elsif new.event_type = 'task_submitted_for_review' then
    v_task_id := nullif(new.event_data->>'taskId','')::uuid;
    select t.created_by into v_recipient
    from public.tasks t
    where t.id = v_task_id and t.project_id = new.project_id;

    if v_recipient is distinct from new.actor_id then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'task_review_submitted','任务已提交验收',
        '一个与你直接相关的任务已提交验收。','task_review_round',new.entity_id
      );
    end if;

    for v_downstream in
      select distinct t.assignee_id as recipient_id
      from public.task_dependencies d
      join public.tasks t
        on t.project_id = d.project_id
       and t.id = d.downstream_task_id
      where d.project_id = new.project_id
        and d.upstream_task_id = v_task_id
        and t.assignee_id is not null
    loop
      if v_downstream.recipient_id is distinct from new.actor_id
         and v_downstream.recipient_id is distinct from v_recipient then
        perform private.create_notification(
          new.id,new.project_id,v_downstream.recipient_id,'task_review_submitted','上游任务已提交验收',
          '与你负责的下游任务直接相关的上游任务已提交验收。','task_review_round',new.entity_id
        );
      end if;
    end loop;

  elsif new.event_type in (
    'task_submission_rejected',
    'task_submission_changes_requested',
    'task_submission_approved'
  ) then
    v_task_id := nullif(new.event_data->>'taskId','')::uuid;
    select t.assignee_id into v_recipient
    from public.tasks t
    where t.id = v_task_id and t.project_id = new.project_id;

    if new.event_type = 'task_submission_approved' then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'task_review_approved','任务验收通过',
        '你负责的任务验收已通过。','task_review_round',new.entity_id
      );
    else
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'task_review_rejected','任务被打回',
        '你负责的任务需要修改，请进入验收上下文查看。','task_review_round',new.entity_id
      );
    end if;

  elsif new.event_type = 'project_join_requested' then
    select p.leader_id into v_recipient
    from public.projects p
    where p.id = new.project_id;

    perform private.create_notification(
      new.id,new.project_id,v_recipient,'project_join_pending','新的加入申请',
      '项目收到一条待处理的加入申请。','project_join_request',new.entity_id
    );

  elsif new.event_type in ('project_join_request_approved','project_join_request_rejected') then
    select j.user_id into v_recipient
    from public.project_join_requests j
    where j.id = new.entity_id;

    if new.event_type = 'project_join_request_approved' then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'project_join_approved','加入申请已通过',
        '你的项目加入申请已通过。','project_join_request',new.entity_id
      );
    else
      perform private.create_notification(
        new.id,null,v_recipient,'project_join_rejected','加入申请未通过',
        '你的一条项目加入申请未通过。',null,null
      );
    end if;

  elsif new.event_type = 'project_join_request_canceled' then
    select j.user_id into v_recipient
    from public.project_join_requests j
    where j.id = new.entity_id;

    perform private.create_notification(
      new.id,null,v_recipient,'project_join_canceled','加入申请已失效',
      '你的一条待处理项目加入申请已失效。',null,null
    );

  elsif new.event_type = 'project_member_joined' then
    select p.leader_id into v_recipient
    from public.projects p
    where p.id = new.project_id;

    if v_recipient is distinct from new.actor_id then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'project_member_joined','新成员加入项目',
        '一名新成员已加入你的项目。','project_member',new.entity_id
      );
    end if;

  elsif new.event_type = 'project_member_role_changed' then
    select pm.user_id into v_recipient
    from public.project_members pm
    where pm.id = new.entity_id;

    if v_recipient is distinct from new.actor_id then
      perform private.create_notification(
        new.id,new.project_id,v_recipient,'project_member_role_changed','项目角色已变更',
        '你在项目中的角色已发生变更。','project_member',new.entity_id
      );
    end if;

  elsif new.event_type = 'project_member_removed' then
    select pm.user_id into v_recipient
    from public.project_members pm
    where pm.id = new.entity_id;

    perform private.create_notification(
      new.id,null,v_recipient,'project_member_removed','项目成员身份已变更',
      '你已被移出一个项目。',null,null
    );
  end if;

  return new;
end;
$$;

drop trigger if exists business_event_creates_notification on public.business_events;
create trigger business_event_creates_notification
after insert on public.business_events
for each row execute function private.notify_from_business_event();

create or replace function public.get_unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)
  from public.notifications n
  where n.recipient_id = (select auth.uid())
    and n.read_at is null
    and (
      n.project_id is null
      or public.is_active_project_member(n.project_id)
    );
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.notifications n
  set read_at = coalesce(n.read_at, now())
  where n.id = p_notification_id
    and n.recipient_id = auth.uid()
    and (
      n.project_id is null
      or public.is_active_project_member(n.project_id)
    );

  return found;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count bigint;
begin
  if auth.uid() is null then
    return 0;
  end if;

  update public.notifications n
  set read_at = now()
  where n.recipient_id = auth.uid()
    and n.read_at is null
    and (
      n.project_id is null
      or public.is_active_project_member(n.project_id)
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.resolve_notification_target(p_notification_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_notification public.notifications%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;

  select * into v_notification
  from public.notifications n
  where n.id = p_notification_id
    and n.recipient_id = auth.uid()
    and n.project_id is not null
    and public.is_active_project_member(n.project_id);

  if not found then
    return null;
  end if;

  if v_notification.entity_type = 'task'
     and exists(
       select 1 from public.tasks t
       where t.id = v_notification.entity_id
         and t.project_id = v_notification.project_id
     ) then
    return jsonb_build_object(
      'routeName','task-detail',
      'projectId',v_notification.project_id,
      'entityId',v_notification.entity_id
    );
  end if;

  if v_notification.entity_type = 'task_review_round'
     and exists(
       select 1 from public.task_review_rounds rr
       where rr.id = v_notification.entity_id
         and rr.project_id = v_notification.project_id
     ) then
    return jsonb_build_object(
      'routeName','review-detail',
      'projectId',v_notification.project_id,
      'entityId',v_notification.entity_id
    );
  end if;

  if v_notification.entity_type = 'project_join_request'
     and exists(
       select 1 from public.project_join_requests j
       where j.id = v_notification.entity_id
         and j.project_id = v_notification.project_id
     ) then
    return jsonb_build_object(
      'routeName','project-invitations',
      'projectId',v_notification.project_id
    );
  end if;

  if v_notification.entity_type in ('project_member','project')
     or v_notification.entity_type is null then
    return jsonb_build_object(
      'routeName','project-overview',
      'projectId',v_notification.project_id
    );
  end if;

  return null;
end;
$$;

revoke all on function private.create_notification(bigint,uuid,uuid,text,text,text,text,uuid) from public, anon, authenticated, service_role;
revoke all on function private.notify_from_business_event() from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count() from public, anon, authenticated, service_role;
revoke all on function public.mark_notification_read(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mark_all_notifications_read() from public, anon, authenticated, service_role;
revoke all on function public.resolve_notification_target(uuid) from public, anon, authenticated, service_role;

grant execute on function public.get_unread_notification_count() to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
grant execute on function public.resolve_notification_target(uuid) to authenticated;

comment on table public.notifications is
  'Recipient-scoped in-app notifications derived transactionally from trusted business events. Project-linked rows disappear from visibility as soon as project membership is revoked.';
comment on column public.notifications.source_event_id is
  'Authoritative business event identity used for notification idempotency and transactional traceability.';
