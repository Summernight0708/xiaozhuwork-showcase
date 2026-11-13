begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('private','system_announcements','system announcement provenance table exists');
select has_function(
  'private','publish_system_announcement',
  array['text','text','text','text'],
  'admin broadcast function exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'private.publish_system_announcement(text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated users cannot publish system announcements'
);
select ok(
  not has_function_privilege(
    'service_role',
    'private.publish_system_announcement(text,text,text,text)',
    'EXECUTE'
  ),
  'service role cannot silently publish product announcements'
);

insert into auth.users(id,email,email_confirmed_at,banned_until) values
 ('f9000000-0000-0000-0000-000000000001','system-active@example.test',now(),null),
 ('f9000000-0000-0000-0000-000000000002','system-banned@example.test',now(),now()+interval '1 day'),
 ('f9000000-0000-0000-0000-000000000003','system-deleting@example.test',now(),null);

insert into public.account_lifecycle_requests(
 user_id,state,generation,version,requested_at,cancel_until
) values (
 'f9000000-0000-0000-0000-000000000003','pending',1,1,now(),now()+interval '1 day'
);

create temporary table announcement_result(label text primary key,value jsonb);
insert into announcement_result
select 'first',private.publish_system_announcement(
 'release-2026-10-12',
 '版本更新',
 '文件页和任务页已重新设计。',
 'help-center'
);
insert into announcement_result
select 'replay',private.publish_system_announcement(
 'release-2026-10-12',
 '版本更新',
 '文件页和任务页已重新设计。',
 'help-center'
);

select is(
 (select (value->>'recipientCount')::integer from announcement_result where label='first'),
 (select (value->>'insertedCount')::integer from announcement_result where label='first'),
 'broadcast recipient count matches inserted notifications; fixture eligibility checked below'
);
select is(
 (select (value->>'insertedCount')::integer from announcement_result where label='replay'),
 0,
 'replaying the same announcement key is idempotent'
);
select is(
 (select count(*)::integer from private.system_announcements),
 1,
 'idempotent replay keeps a single announcement provenance row'
);
select is(
 (select count(*)::integer from public.notifications
  where notification_type='system_announcement'
    and recipient_id='f9000000-0000-0000-0000-000000000001'),
 1,
 'active account receives the announcement once'
);
select is(
 (select count(*)::integer from public.notifications
  where notification_type='system_announcement'
    and recipient_id in (
      'f9000000-0000-0000-0000-000000000002',
      'f9000000-0000-0000-0000-000000000003'
    )),
 0,
 'banned and deletion-pending accounts do not receive broadcasts'
);

select set_config('request.jwt.claim.sub','f9000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(
 public.get_unread_notification_count(),
 1::bigint,
 'system announcement participates in unread count'
);
select is(
 public.resolve_notification_target(
   (select id from public.notifications
    where recipient_id='f9000000-0000-0000-0000-000000000001'
      and notification_type='system_announcement')
 )->>'routeName',
 'help-center',
 'system announcement resolves only to its allow-listed global route'
);
reset role;

select throws_ok(
 $$select private.publish_system_announcement(
   'release-2026-10-12',
   '不同标题',
   '文件页和任务页已重新设计。',
   'help-center'
 )$$,
 'P0001',
 'SYSTEM_ANNOUNCEMENT_REPLAY_MISMATCH',
 'same key with changed payload fails closed'
);

select * from finish();
rollback;
