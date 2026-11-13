begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','task_external_evidence','evidence table exists');
select has_table('public','task_external_evidence_revisions','revision table exists');
select ok((select relrowsecurity from pg_class where oid='public.task_external_evidence'::regclass),'evidence RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.task_external_evidence_revisions'::regclass),'revisions RLS enabled');
select ok(not has_table_privilege(r,t,p),'no direct '||r||' '||p||' on '||t)
from unnest(array['anon','authenticated','service_role']) r,
unnest(array['public.task_external_evidence','public.task_external_evidence_revisions']) t,
unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p;
select ok(not has_table_privilege('anon','public.task_external_evidence','SELECT'),'anonymous metadata denied');
select ok(not has_function_privilege('anon','public.cmd_remove_external_evidence(uuid,uuid,uuid,integer)','EXECUTE'),'anonymous RPC denied');
select ok(not has_function_privilege('authenticated','private.external_evidence_command(text,uuid,uuid,text,text,uuid,integer)','EXECUTE'),'internal implementation not callable');

select is(private.external_evidence_url_host('https://GitHub.COM/team/repo'),'github.com','normalizes DNS host');
select is(private.external_evidence_url_host('https://docs.google.com:443/a%20document'),'docs.google.com','443 and encoded path space allowed');
select is(private.external_evidence_url_host(url),null,'reject URL '||url) from unnest(array[
  'http://example.org','file:///etc/passwd','javascript:alert(1)',
  'https://user:pass@example.org','https://example.org@localhost',
  'https://localhost','https://api.localhost','https://host.local','https://host.internal',
  'https://host.lan','https://host.home.arpa','https://host','https://127.0.0.1',
  'https://10.0.0.1','https://169.254.169.254','https://192.168.1.1','https://100.64.0.1',
  'https://0.0.0.0','https://192.0.2.1','https://224.0.0.1','https://8.8.8.8',
  'https://2130706433','https://0x7f000001','https://0177.0.0.1','https://127.1',
  'https://0x7f.0.0.1','https://[::1]','https://[::ffff:127.0.0.1]',
  'https://[2001:4860::8888]','https://%31%32%37.0.0.1',E'https://example.org\\@localhost',
  'https://example.org.','https://example..org','https://-example.org','https://example.org:444',
  'https://example.org:0443',E'https://example.org\n',' https://example.org','HTTPS://example.org',
  'https://example.org/%0aHeader','https://example.org/%250d','https://example.org/%5cfoo',
  'https://example.org/%zz','https://ｅxample.org','https://example.123','https://example.test',
  'https://example.invalid','https://localhost.localdomain','https://example.org/'||repeat('x',2048)
]) url;

insert into auth.users(id,email) select ('d4100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
  'd-evidence-'||n||'@example.test' from generate_series(1,8) n;
insert into public.projects(id,name,deadline_at,leader_id,created_by) values
('d4200000-0000-0000-0000-000000000001','D evidence',now()+interval '20 days','d4100000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001'),
('d4200000-0000-0000-0000-000000000002','Other project',now()+interval '20 days','d4100000-0000-0000-0000-000000000008','d4100000-0000-0000-0000-000000000008');
insert into public.project_members(project_id,user_id,role,is_observer)
select 'd4200000-0000-0000-0000-000000000001',('d4100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
  case n when 1 then 'leader' when 5 then 'observer' when 6 then 'admin' else 'member' end,n=5
from generate_series(1,7) n;
insert into public.project_members(project_id,user_id,role) values
('d4200000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000008','leader');
insert into public.tasks(id,project_id,title,created_by,assignee_id,deadline_at,status,assignment_state,accepted_at) values
('d4300000-0000-0000-0000-000000000001','d4200000-0000-0000-0000-000000000001','Evidence task','d4100000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000002',now()+interval '10 days','in_progress','assigned',now()),
('d4300000-0000-0000-0000-000000000002','d4200000-0000-0000-0000-000000000002','Other task','d4100000-0000-0000-0000-000000000008',null,now()+interval '10 days','not_started','claimable',null);
insert into public.task_collaborators(project_id,task_id,user_id,state,responded_at) values
('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000004','accepted',now()),
('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000007','pending',null);
create temp table evidence_test_state(key text primary key, result jsonb);
grant all on evidence_test_state to authenticated;
create function pg_temp.evidence_create(p_request uuid default gen_random_uuid(),p_version integer default 1,p_url text default 'https://GitHub.COM:443/team/repo')
returns jsonb language sql as $$
select public.cmd_create_external_evidence('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001',p_url,'Source evidence',p_request,p_version);
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','','true');
select is(pg_temp.evidence_create()->>'code','UNAUTHENTICATED','missing identity rejected');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000008',true);
select is(pg_temp.evidence_create()->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','outsider cannot write');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000005',true);
select is(pg_temp.evidence_create()->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','observer receives F0 denial');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000006',true);
select is(pg_temp.evidence_create()->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','admin is not automatically a task actor');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000007',true);
select is(pg_temp.evidence_create()->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','pending collaborator cannot write');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000002',true);
select is(pg_temp.evidence_create(null)->>'code','VALIDATION_FAILED','request ID required');
select is(pg_temp.evidence_create(gen_random_uuid(),null)->>'code','STALE_VERSION','version required');
select is(pg_temp.evidence_create(gen_random_uuid(),1,'https://127.0.0.1')->>'field','httpsUrl','RPC rejects unsafe URL');
select is(public.cmd_create_external_evidence('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001','https://github.com',repeat('x',2001),gen_random_uuid(),1)->>'field','description','overlong description rejected');
insert into evidence_test_state values ('created',pg_temp.evidence_create('d4900000-0000-0000-0000-000000000001'));
select is((select result->>'ok' from evidence_test_state where key='created'),'true','Free primary creates evidence');
select is((select result->>'aggregateType' from evidence_test_state where key='created'),'task','create uses task aggregate');
select is((select result->>'aggregateVersion' from evidence_test_state where key='created'),'2','create advances task fence');
select is((select https_url from public.task_external_evidence where project_id='d4200000-0000-0000-0000-000000000001'),'https://GitHub.COM:443/team/repo','preserves original HTTPS URL');
select is(pg_temp.evidence_create('d4900000-0000-0000-0000-000000000001')->>'replayed','true','same payload replay');
select is(pg_temp.evidence_create('d4900000-0000-0000-0000-000000000001',1,'https://example.org')->>'code','IDEMPOTENCY_KEY_REUSED','changed payload is rejected');
select is(pg_temp.evidence_create()->>'code','STALE_VERSION','new request cannot reuse stale task version');
select is((select count(*) from public.task_external_evidence where project_id='d4200000-0000-0000-0000-000000000001'),1::bigint,'replay creates no duplicate');
select throws_ok($$update public.task_external_evidence set description='forged'$$,'42501',null,'client direct updates denied');
select is(public.cmd_create_external_evidence('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000002','https://github.com','cross',gen_random_uuid(),1)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','cross-project task denied');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000004',true);
select is(public.cmd_update_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'https://github.com/new','change',gen_random_uuid(),1)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','collaborator cannot rewrite another submitter');
select is(pg_temp.evidence_create(gen_random_uuid(),2)->>'ok','true','accepted collaborator can submit own evidence');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000003',true);
insert into evidence_test_state select 'updated',public.cmd_update_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'https://docs.google.com/new','Revised evidence','d4900000-0000-0000-0000-000000000002',1);
select is((select result->>'ok' from evidence_test_state where key='updated'),'true','task creator may edit');
select is((select result->>'aggregateVersion' from evidence_test_state where key='updated'),'2','update advances evidence version');
select is((select description from public.task_external_evidence_revisions where evidence_id=(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created')),'Source evidence','pre-update description retained');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000008',true);
select is((select count(*) from public.task_external_evidence),0::bigint,'outsider cannot enumerate evidence');
select is((select count(*) from public.task_external_evidence_revisions),0::bigint,'outsider cannot enumerate history');
select is(public.cmd_remove_external_evidence('d4200000-0000-0000-0000-000000000002',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),gen_random_uuid(),2)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','cross-project evidence denied');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000005',true);
select is((select count(*) from public.task_external_evidence),2::bigint,'observer may read project evidence');
select is((select count(*) from public.task_external_evidence_revisions),1::bigint,'observer may read project audit');
reset role;
select throws_ok($$update public.task_external_evidence_revisions set description='forged'$$,'55000','External evidence revisions are immutable','even privileged metadata rewrite rejected');
select throws_ok($$delete from public.task_external_evidence_revisions$$,'55000','External evidence revisions are immutable','history deletion rejected');
select throws_ok($$update public.business_events set event_type='forged' where project_id='d4200000-0000-0000-0000-000000000001'$$,'55000','Business events are immutable','existing audit guard unchanged');
select throws_ok($$delete from public.tasks where id='d4300000-0000-0000-0000-000000000001'$$,'23503',null,'evidence prevents hard deleting historical task');
select is((select count(*) from public.task_files where project_id='d4200000-0000-0000-0000-000000000001'),0::bigint,'links create no Storage files');
update public.projects set archived_at=now() where id='d4200000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000001',true);
select is(pg_temp.evidence_create(gen_random_uuid(),3)->>'code','PROJECT_NOT_ACTIVE','archive blocks create');
select is(public.cmd_update_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'https://github.com','x',gen_random_uuid(),2)->>'code','PROJECT_NOT_ACTIVE','archive blocks update');
select is(public.cmd_remove_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),gen_random_uuid(),2)->>'code','PROJECT_NOT_ACTIVE','archive blocks remove');
select is((select count(*) from public.task_external_evidence),2::bigint,'archived history remains readable');
reset role;
update public.projects set archived_at=null where id='d4200000-0000-0000-0000-000000000001';
update public.tasks set status='awaiting_review' where id='d4300000-0000-0000-0000-000000000001';
set local role authenticated;
select is(pg_temp.evidence_create(gen_random_uuid(),3)->>'code','INVALID_TRANSITION','review metadata is frozen');
reset role;
update public.tasks set status='in_progress' where id='d4300000-0000-0000-0000-000000000001';
set local role authenticated;
insert into evidence_test_state select 'removed',public.cmd_remove_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'d4900000-0000-0000-0000-000000000003',2);
select is((select result->>'ok' from evidence_test_state where key='removed'),'true','leader soft revokes');
select is(public.cmd_remove_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'d4900000-0000-0000-0000-000000000003',2)->>'replayed','true','remove replay adds no revision');
select is(public.cmd_remove_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),gen_random_uuid(),3)->>'code','EVIDENCE_WITHDRAWN','new request cannot remove twice');
select is(public.cmd_update_external_evidence('d4200000-0000-0000-0000-000000000001',(select (result->'data'->>'evidenceId')::uuid from evidence_test_state where key='created'),'https://github.com','restore',gen_random_uuid(),3)->>'code','EVIDENCE_WITHDRAWN','withdrawn link cannot be resurrected');
select is((select count(*) from public.task_external_evidence_revisions),2::bigint,'one immutable snapshot per successful change');
reset role;
select is((select count(*) from public.business_events where project_id='d4200000-0000-0000-0000-000000000001' and event_type like 'external_evidence_%'),4::bigint,'exactly one event per successful operation');
select ok(bool_and(event_data ?& array['schemaVersion','policyVersion','occurrenceKey','occurredAt','aggregateVersion','responsibleUserId']), 'F0 envelope complete') from public.business_events where project_id='d4200000-0000-0000-0000-000000000001';
select ok(bool_and(event_data->>'occurrenceKey' <> request_id::text),'occurrence keys independent of request IDs') from public.business_events where project_id='d4200000-0000-0000-0000-000000000001';
select throws_ok($$insert into public.business_events(project_id,event_type,entity_type,entity_id,event_data)
  select project_id,event_type,entity_type,entity_id,event_data from public.business_events
  where project_id='d4200000-0000-0000-0000-000000000001' limit 1$$,'23505',null,'domain occurrence is unique independently of commands');
update public.project_members set member_state='removed',departed_at=now() where project_id='d4200000-0000-0000-0000-000000000001' and user_id='d4100000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000002',true);
select is(pg_temp.evidence_create('d4900000-0000-0000-0000-000000000001')->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','removed member cannot replay historical success');
select is((select count(*) from public.task_external_evidence),0::bigint,'removed member loses reads');
reset role;
-- Identity unlinking is the ONLY allowed revision update and cannot alter history.
select lives_ok($$update public.task_external_evidence_revisions set submitted_by=null,changed_by=null$$,'trusted lifecycle can unlink identities');
select is((select description from public.task_external_evidence_revisions where version=1),'Source evidence','identity unlink preserves original metadata');
-- A nulled submitter must never turn a SQL NULL permission result into authorization.
update public.task_external_evidence set submitted_by=null
  where project_id='d4200000-0000-0000-0000-000000000001' and revoked_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000004',true);
select is(public.cmd_update_external_evidence('d4200000-0000-0000-0000-000000000001',
  (select id from public.task_external_evidence where revoked_at is null),
  'https://github.com/forged','forged',gen_random_uuid(),1)->>'code',
  'NOT_FOUND_OR_NOT_AUTHORIZED','null submitter does not authorize collaborator mutation');
reset role;
select ok(bool_and(confdeltype='n'),'all evidence user references null rather than cascade') from pg_constraint
  where conrelid in ('public.task_external_evidence'::regclass,'public.task_external_evidence_revisions'::regclass)
    and confrelid='auth.users'::regclass;
select ok(bool_and(prosecdef and proconfig @> array['search_path=""']),'public RPCs are SECURITY DEFINER with empty search path')
from pg_proc where pronamespace='public'::regnamespace and proname in (
  'cmd_create_external_evidence','cmd_update_external_evidence','cmd_remove_external_evidence');
insert into public.account_entitlements(user_id,plan,status,starts_at,expires_at,grant_source)
values ('d4100000-0000-0000-0000-000000000001','pro','active',now()-interval '1 day',now()+interval '20 days','test'),
       ('d4100000-0000-0000-0000-000000000005','pro','active',now()-interval '1 day',now()+interval '20 days','test');
set local role authenticated;
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000004',true);
select is(pg_temp.evidence_create(gen_random_uuid(),3)->>'ok','true','Pro project preserves accepted collaborator rights');
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000005',true);
select is(pg_temp.evidence_create(gen_random_uuid(),4)->>'code','NOT_FOUND_OR_NOT_AUTHORIZED','Pro does not elevate observer rights');
reset role;
update public.projects set lifecycle_state='contribution_review' where id='d4200000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000004',true);
select is(pg_temp.evidence_create(gen_random_uuid(),4)->>'code','PROJECT_NOT_ACTIVE','contribution stage also freezes writes');
reset role;
select * from finish();
rollback;
