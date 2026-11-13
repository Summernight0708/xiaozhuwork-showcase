begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public', 'user_help_dismissals', 'user hint dismissals table exists');
select ok(has_table_privilege('authenticated', 'public.user_help_dismissals', 'SELECT'), 'authenticated may read');
select ok(has_table_privilege('authenticated', 'public.user_help_dismissals', 'INSERT'), 'authenticated may dismiss');
select ok(not has_table_privilege('authenticated', 'public.user_help_dismissals', 'UPDATE'), 'authenticated may not overwrite');
select ok(not has_table_privilege('authenticated', 'public.user_help_dismissals', 'DELETE'), 'authenticated may not erase');
select ok(not has_table_privilege('anon', 'public.user_help_dismissals', 'SELECT'), 'anon may not read');

insert into auth.users (id,email) values
('c001cafe-0000-0000-0000-000000000001','help-a@example.test'),
('c001cafe-0000-0000-0000-000000000002','help-b@example.test');

select set_config('request.jwt.claim.sub','c001cafe-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into public.user_help_dismissals (user_id,hint_key)
values ('c001cafe-0000-0000-0000-000000000001','v1:intro:leader')
on conflict do nothing;
insert into public.user_help_dismissals (user_id,hint_key)
values ('c001cafe-0000-0000-0000-000000000001','v1:intro:leader')
on conflict do nothing;
select is((select count(*)::integer from public.user_help_dismissals), 1, 'idempotent dismissal on device A');
reset role;

select set_config('request.jwt.claim.sub','c001cafe-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::integer from public.user_help_dismissals), 0, 'device B account cannot read other account');
insert into public.user_help_dismissals (user_id,hint_key)
values ('c001cafe-0000-0000-0000-000000000002','v1:intro:member');
select is((select count(*)::integer from public.user_help_dismissals), 1, 'account B can see own dismissal');
reset role;

delete from auth.users where id='c001cafe-0000-0000-0000-000000000001';
select is((select count(*)::integer from public.user_help_dismissals where user_id='c001cafe-0000-0000-0000-000000000001'), 0, 'deleting account cascades dismissals');
select * from finish();
rollback;
