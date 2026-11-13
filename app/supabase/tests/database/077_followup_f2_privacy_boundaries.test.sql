begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values
 ('fa100000-0000-0000-0000-000000000001','f2-session@example.test'),
 ('fa100000-0000-0000-0000-000000000002','f2-peer@example.test');
insert into auth.sessions(id,user_id) values
 ('fa200000-0000-0000-0000-000000000001','fa100000-0000-0000-0000-000000000001'),
 ('fa200000-0000-0000-0000-000000000002','fa100000-0000-0000-0000-000000000002');
insert into public.notifications(id,recipient_id,notification_type,title,message)
 values('fa400000-0000-0000-0000-000000000001','fa100000-0000-0000-0000-000000000001',
 'account','Account','Private projectless notification');
select set_config('request.jwt.claim.sub','fa100000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
select is(public.cmd_request_account_deletion('fa300000-0000-0000-0000-000000000001',0)->>'code',
 'REAUTHENTICATION_REQUIRED','legacy token without a session cannot request deletion');
select set_config('request.jwt.claims','{"session_id":"fa200000-0000-0000-0000-000000000002"}',true);
select is(public.cmd_request_account_deletion('fa300000-0000-0000-0000-000000000001',0)->>'code',
 'REAUTHENTICATION_REQUIRED','another account session cannot authorize deletion');
select set_config('request.jwt.claims','{"session_id":"fa200000-0000-0000-0000-000000000001"}',true);
select is(public.cmd_request_account_deletion('fa300000-0000-0000-0000-000000000001',0)->>'ok',
 'true','original live session can request deletion');
select is(public.cmd_request_account_deletion('fa300000-0000-0000-0000-000000000001',0)->>'replayed',
 'true','live session retains same-key retry');
select is(public.get_unread_notification_count(),0::bigint,'pending old token cannot count projectless notifications');
select is(public.mark_all_notifications_read(),0::bigint,'pending old token cannot bulk mutate projectless notifications');
select is(public.mark_notification_read('fa400000-0000-0000-0000-000000000001'),false,'pending old token cannot mark a projectless notification');
select throws_ok($$select event_data from public.business_events$$,'42501',null,'raw audit JSON cannot bypass identity masks');
select throws_ok($$select event_snapshot from public.contribution_penalties$$,'42501',null,'raw immutable penalty JSON restricted');
select throws_ok($$select result from public.command_requests$$,'42501',null,'raw cached command JSON restricted');
select throws_ok($$select public.cmd_cancel_account_deletion_f2_internal(gen_random_uuid(),1)$$,'42501',null,'internal cancellation cannot bypass live session proof');
reset role;
update auth.sessions set not_after=now()-interval '1 second' where id='fa200000-0000-0000-0000-000000000001';
set local role authenticated;
select is(public.cmd_cancel_account_deletion('fa300000-0000-0000-0000-000000000002',1)->>'code',
 'REAUTHENTICATION_REQUIRED','expired session cannot cancel');
reset role;
delete from auth.sessions where id='fa200000-0000-0000-0000-000000000001';
set local role authenticated;
select is(public.cmd_cancel_account_deletion('fa300000-0000-0000-0000-000000000002',1)->>'code',
 'REAUTHENTICATION_REQUIRED','revoked session cannot cancel with old signed JWT');
reset role;
insert into auth.sessions(id,user_id) values('fa200000-0000-0000-0000-000000000001','fa100000-0000-0000-0000-000000000001');
set local role authenticated;
select is(public.cmd_cancel_account_deletion('fa300000-0000-0000-0000-000000000002',1)->>'ok',
 'true','fresh original session cancels inside window');
select ok(public.account_lifecycle_access_allowed(auth.uid()),'cancellation restores active access');
select is(public.get_unread_notification_count(),1::bigint,'cancellation preserves and restores unread notification');
reset role;
update auth.users set banned_until=now()+interval '1 day' where id='fa100000-0000-0000-0000-000000000001';
set local role authenticated;
select ok(not public.account_lifecycle_access_allowed(auth.uid()),'Auth ban overrides canceled lifecycle');
select is(public.cmd_cancel_account_deletion('fa300000-0000-0000-0000-000000000002',1)->>'code',
 'REAUTHENTICATION_REQUIRED','ban prevents replay from bypassing session proof');
reset role;
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.proname like '%f2_unmasked' or p.proname like '%f2_internal'
 or p.proname in ('get_project_report_export_legacy','get_project_contribution_report_legacy'))
 and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'))),
 'all original internal RPC implementations are inaccessible');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' and c.relrowsecurity
 and not exists(select 1 from pg_policy p where p.polrelid=c.oid and p.polname='account_deletion_access_fence')),
 'all present public RLS tables have lifecycle fence');
select is((select count(*)::int from auth.users where id::text like 'fa100000-%'),2,'both Auth records preserved');
select * from finish();
rollback;
