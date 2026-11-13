-- TeamUp system announcements: admin-only broadcast into the existing personal inbox.
-- Keeps announcement provenance separate from recipient-specific hide/read state.

create table private.system_announcements (
  id uuid primary key default gen_random_uuid(),
  announcement_key text not null unique
    check (char_length(btrim(announcement_key)) between 1 and 120),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  message text not null check (char_length(btrim(message)) between 1 and 4000),
  route_name text not null default 'notifications'
    check (route_name in ('notifications','help-center','download','upgrade')),
  published_at timestamptz not null default transaction_timestamp(),
  recipient_count integer not null default 0 check (recipient_count >= 0)
);

revoke all on private.system_announcements from public, anon, authenticated, service_role;
-- This migration runs after the F2 privacy manifest foundation. Every new
-- persisted column must be explicitly classified so lifecycle cleanup remains
-- fail-closed without treating expected schema evolution as unknown drift.
insert into private.lifecycle_pii_classifications(
  schema_name,table_name,column_name,data_type,classification
) values
  ('private','system_announcements','id','uuid','structured'),
  ('private','system_announcements','announcement_key','text','free_text'),
  ('private','system_announcements','title','text','free_text'),
  ('private','system_announcements','message','text','free_text'),
  ('private','system_announcements','route_name','text','free_text'),
  ('private','system_announcements','published_at','timestamp with time zone','structured'),
  ('private','system_announcements','recipient_count','integer','structured');


create unique index notifications_system_announcement_recipient_idx
  on public.notifications(recipient_id, entity_id, notification_type)
  where entity_type='system_announcement' and notification_type='system_announcement';

create or replace function private.publish_system_announcement(
  p_announcement_key text,
  p_title text,
  p_message text,
  p_route_name text default 'notifications'
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_announcement private.system_announcements%rowtype;
  v_inserted integer;
  v_route text := coalesce(nullif(btrim(p_route_name),''),'notifications');
begin
  if char_length(btrim(coalesce(p_announcement_key,''))) not between 1 and 120 then
    raise exception 'SYSTEM_ANNOUNCEMENT_KEY_INVALID';
  end if;
  if char_length(btrim(coalesce(p_title,''))) not between 1 and 120 then
    raise exception 'SYSTEM_ANNOUNCEMENT_TITLE_INVALID';
  end if;
  if char_length(btrim(coalesce(p_message,''))) not between 1 and 4000 then
    raise exception 'SYSTEM_ANNOUNCEMENT_MESSAGE_INVALID';
  end if;
  if v_route not in ('notifications','help-center','download','upgrade') then
    raise exception 'SYSTEM_ANNOUNCEMENT_ROUTE_INVALID';
  end if;

  insert into private.system_announcements(
    announcement_key,title,message,route_name
  ) values (
    btrim(p_announcement_key),btrim(p_title),btrim(p_message),v_route
  )
  on conflict (announcement_key) do nothing;

  select * into strict v_announcement
  from private.system_announcements a
  where a.announcement_key=btrim(p_announcement_key)
  for update;

  if v_announcement.title is distinct from btrim(p_title)
     or v_announcement.message is distinct from btrim(p_message)
     or v_announcement.route_name is distinct from v_route then
    raise exception 'SYSTEM_ANNOUNCEMENT_REPLAY_MISMATCH';
  end if;

  insert into public.notifications(
    project_id, recipient_id, notification_type, title, entity_type, entity_id,
    message, source_event_id
  )
  select
    null, u.id, 'system_announcement', v_announcement.title,
    'system_announcement', v_announcement.id, v_announcement.message, null
  from auth.users u
  where u.deleted_at is null
    and u.email_confirmed_at is not null
    and (u.banned_until is null or u.banned_until <= transaction_timestamp())
    and not exists (
      select 1
      from public.account_lifecycle_requests l
      where l.user_id=u.id and l.state<>'canceled'
    )
  on conflict (recipient_id,entity_id,notification_type)
    where entity_type='system_announcement' and notification_type='system_announcement'
  do nothing;

  get diagnostics v_inserted=row_count;

  update private.system_announcements a
  set recipient_count=(
    select count(*)::integer
    from public.notifications n
    where n.notification_type='system_announcement'
      and n.entity_type='system_announcement'
      and n.entity_id=a.id
  )
  where a.id=v_announcement.id
  returning * into v_announcement;

  return jsonb_build_object(
    'ok',true,
    'announcementId',v_announcement.id,
    'announcementKey',v_announcement.announcement_key,
    'recipientCount',v_announcement.recipient_count,
    'insertedCount',v_inserted,
    'routeName',v_announcement.route_name
  );
end;
$$;

revoke all on function private.publish_system_announcement(text,text,text,text)
  from public, anon, authenticated, service_role;

create or replace function public.resolve_notification_target(p_notification_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_notification public.notifications%rowtype;
  v_route text;
begin
  if not public.account_lifecycle_access_allowed((select auth.uid())) then
    return null;
  end if;

  select * into v_notification
  from public.notifications n
  where n.id=p_notification_id
    and n.recipient_id=(select auth.uid())
    and n.hidden_at is null
    and (
      n.project_id is null
      or public.is_active_project_member(n.project_id)
    );

  if not found then
    return null;
  end if;

  if v_notification.notification_type='system_announcement'
     and v_notification.entity_type='system_announcement'
     and v_notification.entity_id is not null then
    select a.route_name into v_route
    from private.system_announcements a
    where a.id=v_notification.entity_id;

    if v_route is null then
      return null;
    end if;

    return jsonb_build_object('routeName',v_route);
  end if;

  if v_notification.project_id is null then
    return null;
  end if;

  if v_notification.entity_type='task'
     and exists(
       select 1 from public.tasks t
       where t.id=v_notification.entity_id
         and t.project_id=v_notification.project_id
     ) then
    return jsonb_build_object(
      'routeName','task-detail',
      'projectId',v_notification.project_id,
      'entityId',v_notification.entity_id
    );
  end if;

  if v_notification.entity_type='task_review_round'
     and exists(
       select 1 from public.task_review_rounds rr
       where rr.id=v_notification.entity_id
         and rr.project_id=v_notification.project_id
     ) then
    return jsonb_build_object(
      'routeName','review-detail',
      'projectId',v_notification.project_id,
      'entityId',v_notification.entity_id
    );
  end if;

  if v_notification.entity_type='project_join_request'
     and exists(
       select 1 from public.project_join_requests j
       where j.id=v_notification.entity_id
         and j.project_id=v_notification.project_id
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

revoke all on function public.resolve_notification_target(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.resolve_notification_target(uuid) to authenticated;

comment on table private.system_announcements is
  'Administrator-published product/update announcements. Recipient read/hidden state remains in public.notifications.';
comment on function private.publish_system_announcement(text,text,text,text) is
  'Admin-only idempotent broadcast keyed by announcement_key. Never grant this function to authenticated or service_role.';
