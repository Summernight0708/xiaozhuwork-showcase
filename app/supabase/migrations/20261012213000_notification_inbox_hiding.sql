-- Personal inbox hiding; never delete event provenance or weaken F2 lifecycle fences.
alter table public.notifications add column hidden_at timestamptz;
-- F2 privacy inventory: the per-recipient timestamp remains subject to manual review.
insert into private.lifecycle_pii_classifications
 (schema_name, table_name, column_name, data_type, classification, disposition)
values ('public','notifications','hidden_at','timestamp with time zone',
        'structured','manual_review_required')
on conflict (schema_name,table_name,column_name) do nothing;
create index notifications_visible_recipient_idx
 on public.notifications(recipient_id,created_at desc)
 where hidden_at is null;

drop policy if exists notifications_select_recipient on public.notifications;
create policy notifications_select_recipient on public.notifications
 for select to authenticated
 using (
   recipient_id = (select auth.uid())
   and hidden_at is null
   and (project_id is null or public.is_active_project_member(project_id))
 );

create or replace function public.get_unread_notification_count()
returns bigint language sql stable security definer set search_path = ''
as $$
 select count(*) from public.notifications n
 where public.account_lifecycle_access_allowed((select auth.uid()))
 and n.recipient_id=(select auth.uid())
 and n.hidden_at is null and n.read_at is null
 and (n.project_id is null or public.is_active_project_member(n.project_id));
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
 if not public.account_lifecycle_access_allowed((select auth.uid())) then return false; end if;
 update public.notifications n set read_at=coalesce(n.read_at,transaction_timestamp())
 where n.id=p_notification_id and n.recipient_id=(select auth.uid())
   and n.hidden_at is null
   and (n.project_id is null or public.is_active_project_member(n.project_id));
 return found;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_count bigint;
begin
 if not public.account_lifecycle_access_allowed((select auth.uid())) then return 0; end if;
 update public.notifications n set read_at=transaction_timestamp()
 where public.account_lifecycle_access_allowed((select auth.uid()))
 and n.recipient_id=(select auth.uid()) and n.hidden_at is null and n.read_at is null
   and (n.project_id is null or public.is_active_project_member(n.project_id));
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

create function public.dismiss_notification(p_notification_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
 if not public.account_lifecycle_access_allowed((select auth.uid())) then return false; end if;
 update public.notifications n set hidden_at=coalesce(n.hidden_at,transaction_timestamp())
 where n.id=p_notification_id and n.recipient_id=(select auth.uid())
  and (n.project_id is null or public.is_active_project_member(n.project_id));
 return found;
end;
$$;

create function public.restore_notification(p_notification_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
 if not public.account_lifecycle_access_allowed((select auth.uid())) then return false; end if;
 update public.notifications n set hidden_at=null
 where n.id=p_notification_id and n.recipient_id=(select auth.uid())
  and n.hidden_at is not null and n.hidden_at>=transaction_timestamp()-interval '5 minutes'
  and (n.project_id is null or public.is_active_project_member(n.project_id));
 return found;
end;
$$;

create function public.dismiss_read_notifications()
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_count bigint;
begin
 if not public.account_lifecycle_access_allowed((select auth.uid())) then return 0; end if;
 update public.notifications n set hidden_at=transaction_timestamp()
 where public.account_lifecycle_access_allowed((select auth.uid()))
 and n.recipient_id=(select auth.uid()) and n.read_at is not null and n.hidden_at is null
  and (n.project_id is null or public.is_active_project_member(n.project_id));
 get diagnostics v_count=row_count;
 return v_count;
end;
$$;

revoke all on function public.dismiss_notification(uuid) from public,anon,authenticated,service_role;
revoke all on function public.restore_notification(uuid) from public,anon,authenticated,service_role;
revoke all on function public.dismiss_read_notifications() from public,anon,authenticated,service_role;
grant execute on function public.dismiss_notification(uuid) to authenticated;
grant execute on function public.restore_notification(uuid) to authenticated;
grant execute on function public.dismiss_read_notifications() to authenticated;
comment on column public.notifications.hidden_at is
 'Recipient-only inbox hiding timestamp. Authoritative business events and notification provenance remain intact.';
