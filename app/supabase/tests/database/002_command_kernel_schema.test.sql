begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public', 'project_invitations', 'project invitations table exists');
select has_table('public', 'project_join_requests', 'project join requests table exists');
select has_table('public', 'task_assignment_offers', 'task assignment offers table exists');

select has_column('public', 'command_requests', 'id', 'ledger has surrogate id');
select has_column('public', 'command_requests', 'account_id', 'ledger supports account scope');
select has_column('public', 'command_requests', 'payload_hash', 'ledger stores canonical payload hash');
select has_column('public', 'command_requests', 'state', 'ledger tracks claim state');
select has_column('public', 'command_requests', 'resulting_entity_type', 'ledger tracks aggregate type');
select has_column('public', 'command_requests', 'resulting_entity_id', 'ledger tracks aggregate id');
select has_column('public', 'command_requests', 'completed_at', 'ledger tracks completion time');
select col_is_pk('public', 'command_requests', 'id', 'ledger id is primary key');

select has_column('public', 'business_events', 'command_request_id', 'events reference ledger command');
select has_column('public', 'business_events', 'event_seq', 'events are ordered within command');
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'business_events'
      and indexdef ilike '%unique%command_request_id%event_seq%where%command_request_id is not null%'
  ),
  'events enforce one sequence number per command'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'project_members'
      and indexdef ilike '%unique%project_id%where%role%leader%member_state%active%'
  ),
  'only one active leader is allowed per project'
);

select has_column('public', 'project_invitations', 'token_hash', 'invitation stores token hash');
select has_column('public', 'project_invitations', 'uses_count', 'invitation stores usage count');
select has_column('public', 'project_invitations', 'version', 'invitation is versioned');
select has_column('public', 'project_join_requests', 'state', 'join request has state');
select has_column('public', 'project_join_requests', 'display_name_snapshot', 'join request stores applicant display-name snapshot');
select has_column('public', 'task_assignment_offers', 'target_user_id', 'offer has target');
select has_column('public', 'tasks', 'assignment_state', 'task has assignment state');
select has_column('public', 'tasks', 'progress_text', 'task has bounded progress text');

select ok((select relrowsecurity from pg_class where oid = 'public.project_invitations'::regclass), 'invitations enable RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.project_join_requests'::regclass), 'join requests enable RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.task_assignment_offers'::regclass), 'assignment offers enable RLS');
select ok(not has_table_privilege('authenticated', 'public.project_invitations', 'SELECT'), 'client cannot read invitation ledger');
select ok(not has_table_privilege('authenticated', 'public.command_requests', 'SELECT'), 'client cannot read command ledger');
select ok(not has_table_privilege('authenticated', 'public.project_join_requests', 'INSERT'), 'client cannot directly create join requests');
select ok(not has_table_privilege('authenticated', 'public.task_assignment_offers', 'UPDATE'), 'client cannot directly mutate offers');
select ok(has_table_privilege('authenticated', 'public.project_join_requests_visible', 'SELECT'), 'authenticated may read privacy-safe authorized join requests');
select ok(has_table_privilege('authenticated', 'public.task_assignment_offers', 'SELECT'), 'authenticated may read authorized offers');

select has_function('public', 'cmd_create_project', array['uuid','integer','text','timestamp with time zone','text','text','text','text','boolean','boolean','timestamp with time zone','boolean'], 'create project RPC exists');
select has_function('public', 'cmd_create_project_invite', array['uuid','uuid','integer','text','integer','integer'], 'create invite RPC exists');
select has_function('public', 'cmd_revoke_project_invite', array['uuid','uuid','uuid','integer'], 'revoke invite RPC exists');
select has_function('public', 'preview_project_invite', array['text'], 'preview invite RPC exists');
select has_function('public', 'cmd_join_project_via_invite', array['text','uuid','integer'], 'join via invite RPC exists');
select has_function('public', 'cmd_review_project_join_request', array['uuid','uuid','text','uuid','integer'], 'review join request RPC exists');
select has_function('public', 'cmd_create_task', array['uuid','uuid','integer','text','text','timestamp with time zone','smallint','text','uuid','text','boolean'], 'create task RPC exists');
select has_function('public', 'cmd_claim_task', array['uuid','uuid','uuid','integer'], 'claim task RPC exists');
select has_function('public', 'cmd_respond_to_task_assignment', array['uuid','uuid','uuid','text','uuid','integer'], 'respond to offer RPC exists');
select has_function('public', 'cmd_update_task_progress', array['uuid','uuid','uuid','integer','text','text','text'], 'update progress RPC exists');

select results_eq(
  $$select count(*)::bigint from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('cmd_create_project','cmd_create_project_invite','cmd_revoke_project_invite','preview_project_invite','cmd_join_project_via_invite','cmd_review_project_join_request','cmd_create_task','cmd_claim_task','cmd_respond_to_task_assignment','cmd_update_task_progress') and p.prosecdef and p.proconfig @> array['search_path=""']$$,
  array[10::bigint],
  'all public RPCs are security definer with empty search_path'
);
select ok(not has_function_privilege('public', 'public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean)', 'EXECUTE'), 'PUBLIC cannot execute write RPC');
select ok(not has_function_privilege('anon', 'public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean)', 'EXECUTE'), 'anon cannot execute write RPC');
select ok(has_function_privilege('authenticated', 'public.cmd_create_project(uuid,integer,text,timestamptz,text,text,text,text,boolean,boolean,timestamptz,boolean)', 'EXECUTE'), 'authenticated can execute write RPC');
select ok(has_function_privilege('anon', 'public.preview_project_invite(text)', 'EXECUTE'), 'anon can preview invitations');
select ok(has_function_privilege('authenticated', 'public.preview_project_invite(text)', 'EXECUTE'), 'authenticated can preview invitations');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon has no private schema usage');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated has no private schema usage');
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and (
      has_function_privilege('anon', p.oid, 'EXECUTE') or
      has_function_privilege('authenticated', p.oid, 'EXECUTE') or
      has_function_privilege('public', p.oid, 'EXECUTE')
    )
  ),
  'API roles cannot execute private helpers'
);

select * from finish();
rollback;
