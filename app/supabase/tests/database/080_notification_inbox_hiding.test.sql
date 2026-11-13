begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column('public', 'notifications', 'hidden_at', 'inbox hiding is a nullable user-specific timestamp');
select is(
 (select classification from private.lifecycle_pii_classifications
  where schema_name='public' and table_name='notifications' and column_name='hidden_at'),
 'structured', 'new inbox column is included in F2 privacy inventory'
);select has_function('public', 'dismiss_notification', array['uuid'], 'recipient has controlled single-notification dismissal');
select has_function('public', 'restore_notification', array['uuid'], 'recipient has a temporary undo operation');
select has_function('public', 'dismiss_read_notifications', array[]::text[], 'recipient may clear only read notifications');
select ok(not has_table_privilege('authenticated','public.notifications','UPDATE'), 'authenticated clients cannot forge dismissal timestamps');
select ok(not has_table_privilege('authenticated','public.notifications','DELETE'), 'authenticated clients cannot physically delete notification provenance');

insert into auth.users(id,email) values
 ('f8000000-0000-0000-0000-000000000001','inbox-a@example.test'),
 ('f8000000-0000-0000-0000-000000000002','inbox-b@example.test');
insert into public.notifications(id,recipient_id,project_id,notification_type,title,message) values
 ('f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',null,'system','User A notice','one'),
 ('f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000002',null,'system','User B notice','two');

create temporary table inbox_results(label text primary key, value text);
grant all on inbox_results to authenticated;

select set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into inbox_results values('outsider-dismiss',public.dismiss_notification('f8100000-0000-0000-0000-000000000001')::text);
insert into inbox_results values('b-unread',public.get_unread_notification_count()::text);
reset role;

select set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into inbox_results values('a-before',public.get_unread_notification_count()::text);
insert into inbox_results values('a-dismiss',public.dismiss_notification('f8100000-0000-0000-0000-000000000001')::text);
insert into inbox_results values('a-after-dismiss',public.get_unread_notification_count()::text);
insert into inbox_results values('a-repeat-dismiss',public.dismiss_notification('f8100000-0000-0000-0000-000000000001')::text);
insert into inbox_results values('a-restore',public.restore_notification('f8100000-0000-0000-0000-000000000001')::text);
insert into inbox_results values('a-after-undo',public.get_unread_notification_count()::text);
insert into inbox_results values('a-mark',public.mark_notification_read('f8100000-0000-0000-0000-000000000001')::text);
insert into inbox_results values('a-clear',public.dismiss_read_notifications()::text);
insert into inbox_results values('a-after-clear',public.get_unread_notification_count()::text);
reset role;

select is((select value from inbox_results where label='outsider-dismiss'), 'false','another recipient cannot dismiss a private notice');
select is((select value from inbox_results where label='b-unread'), '1','other user unread count is unaffected');
select is((select value from inbox_results where label='a-before'), '1','one user notice starts unread');
select is((select value from inbox_results where label='a-dismiss'), 'true','owner can hide their own notice');
select is((select value from inbox_results where label='a-after-dismiss'), '0','hidden unread notice leaves badge count');
select is((select value from inbox_results where label='a-repeat-dismiss'), 'true','repeated hide is idempotent');
select is((select value from inbox_results where label='a-restore'), 'true','owner can undo recent hide');
select is((select value from inbox_results where label='a-after-undo'), '1','undo restores unread badge count');
select is((select value from inbox_results where label='a-mark'), 'true','owner may mark restored notification read');
select is((select value from inbox_results where label='a-clear'), '1','clear read hides only read notifications');
select is((select value from inbox_results where label='a-after-clear'), '0','cleared read notification is not unread');
select is((select count(*)::integer from public.notifications where recipient_id='f8000000-0000-0000-0000-000000000001'),1,'hiding does not physically delete business notification');
select ok((select hidden_at is not null from public.notifications where id='f8100000-0000-0000-0000-000000000001'),'read notification is hidden after clearing');
select ok((select hidden_at is null from public.notifications where id='f8100000-0000-0000-0000-000000000002'),'other recipient notice stays visible');
-- A signed legacy JWT must not grant inbox access after the Auth user is banned.
insert into public.notifications(id,recipient_id,project_id,notification_type,title,message,hidden_at,read_at) values
 ('f8100000-0000-0000-0000-000000000003','f8000000-0000-0000-0000-000000000002',null,'system','Hidden B','hidden',now(),null),
 ('f8100000-0000-0000-0000-000000000004','f8000000-0000-0000-0000-000000000002',null,'system','Read B','read',null,now());
update auth.users set banned_until=now()+interval '1 day'
where id='f8000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into inbox_results values('b-banned-unread',public.get_unread_notification_count()::text);
insert into inbox_results values('b-banned-dismiss',public.dismiss_notification('f8100000-0000-0000-0000-000000000002')::text);
insert into inbox_results values('b-banned-restore',public.restore_notification('f8100000-0000-0000-0000-000000000003')::text);
insert into inbox_results values('b-banned-clear',public.dismiss_read_notifications()::text);
reset role;

select is((select value from inbox_results where label='b-banned-unread'),'0','disabled Auth identity cannot count old projectless inbox');
select is((select value from inbox_results where label='b-banned-dismiss'),'false','disabled Auth identity cannot hide its old inbox');
select is((select value from inbox_results where label='b-banned-restore'),'false','disabled Auth identity cannot restore its old inbox');
select is((select value from inbox_results where label='b-banned-clear'),'0','disabled Auth identity cannot bulk hide its old inbox');
select ok((select hidden_at is null from public.notifications where id='f8100000-0000-0000-0000-000000000002'), 'disabled Auth identity did not alter unread row');
select ok((select hidden_at is not null from public.notifications where id='f8100000-0000-0000-0000-000000000003'), 'disabled Auth identity did not restore hidden row');
select ok((select hidden_at is null from public.notifications where id='f8100000-0000-0000-0000-000000000004'), 'disabled Auth identity did not clear read row');
select * from finish();
rollback;
