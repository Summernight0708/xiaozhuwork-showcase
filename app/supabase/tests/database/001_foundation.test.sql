begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

select has_table('public', 'projects', 'projects table exists');
select has_table('public', 'project_members', 'project_members table exists');
select has_table('public', 'tasks', 'tasks table exists');
select has_table('public', 'task_dependencies', 'task_dependencies table exists');
select has_table('public', 'business_events', 'business_events table exists');
select has_table('public', 'command_requests', 'command_requests table exists');
select has_table('public', 'notifications', 'notifications table exists');
select has_table('public', 'profiles', 'profiles table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.projects'::regclass), 'projects enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.project_members'::regclass), 'project_members enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.tasks'::regclass), 'tasks enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.task_dependencies'::regclass), 'task_dependencies enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.business_events'::regclass), 'business_events enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.command_requests'::regclass), 'command_requests enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'notifications enables RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'profiles enables RLS');
select ok(not has_table_privilege('authenticated', 'public.projects', 'INSERT'), 'authenticated cannot create projects through direct table writes');
select ok(not has_table_privilege('authenticated', 'public.project_members', 'INSERT'), 'authenticated cannot change membership through direct table writes');
select ok(not has_table_privilege('authenticated', 'public.tasks', 'UPDATE'), 'authenticated cannot mutate tasks through direct table writes');
select ok(not has_table_privilege('authenticated', 'public.business_events', 'INSERT'), 'authenticated cannot forge audit events');

select * from finish();
rollback;
