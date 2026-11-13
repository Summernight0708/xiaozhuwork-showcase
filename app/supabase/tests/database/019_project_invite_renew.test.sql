begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id,email) values
('91000000-0000-0000-0000-000000000001','renew-leader@example.test'),
('91000000-0000-0000-0000-000000000002','renew-outsider@example.test');
update public.profiles set display_name='Renew User'
where id::text like '91000000-0000-0000-0000-%';

insert into public.projects(id,name,deadline_at,leader_id,created_by,version) values (
  '92000000-0000-0000-0000-000000000001','Renew Project',
  now()+interval '30 days','91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',1
);
insert into public.project_members(project_id,user_id,role,member_state) values (
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001','leader','active'
);
insert into public.project_invitations(
  id,project_id,created_by,token_hash,mode,expires_at,max_uses,uses_count,version
) values
('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
 '91000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('renew-valid','utf8'),'sha256'),
 'direct',now()+interval '5 days',8,0,1),
('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001',
 '91000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('renew-expired','utf8'),'sha256'),
 'direct',now()-interval '1 hour',8,0,1),
('93000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000001',
 '91000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('renew-revoked','utf8'),'sha256'),
 'direct',now()+interval '5 days',8,0,1),
('93000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000001',
 '91000000-0000-0000-0000-000000000001',
 extensions.digest(convert_to('renew-exhausted','utf8'),'sha256'),
 'direct',now()+interval '5 days',1,1,1);
update public.project_invitations set revoked_at=now()
where id='93000000-0000-0000-0000-000000000003';

create temporary table renew_results(label text primary key,result jsonb);
grant all on renew_results to authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);

set local role authenticated;
insert into renew_results values ('renew', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001',1,7
));
reset role;
select is((select result->>'ok' from renew_results where label='renew'),'true',
  'leader renews a valid invitation');
select is((select result->'data'->>'invitationVersion' from renew_results where label='renew'),'2',
  'renew increments invitation version');
select ok((select expires_at between now()+interval '11 days 23 hours' and now()+interval '12 days 1 hour'
  from public.project_invitations where id='93000000-0000-0000-0000-000000000001'),
  'renew extends existing expiry');
select ok(not (select result->'data' ? 'token' from renew_results where label='renew'),
  'renew never returns raw token');
select is((select count(*)::integer from public.business_events
  where event_type='project_invitation_renewed'
    and entity_id='93000000-0000-0000-0000-000000000001'),1,
  'renew emits one event');

set local role authenticated;
insert into renew_results values ('replay', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001',1,7
));
insert into renew_results values ('key-reuse', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001',1,8
));
insert into renew_results values ('stale', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002',1,7
));
insert into renew_results values ('expired', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000002',
  '94000000-0000-0000-0000-000000000003',1,7
));
insert into renew_results values ('revoked', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000003',
  '94000000-0000-0000-0000-000000000004',1,7
));
insert into renew_results values ('exhausted', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000004',
  '94000000-0000-0000-0000-000000000005',1,7
));
reset role;

select is((select result->>'replayed' from renew_results where label='replay'),'true',
  'identical renew request replays');
select is((select count(*)::integer from public.business_events
  where event_type='project_invitation_renewed'
    and entity_id='93000000-0000-0000-0000-000000000001'),1,
  'replay does not duplicate event');
select is((select result->>'code' from renew_results where label='key-reuse'),'IDEMPOTENCY_KEY_REUSED',
  'different payload rejects reused request id');
select is((select result->>'code' from renew_results where label='stale'),'STALE_VERSION',
  'stale invitation version is rejected');
select is((select result->>'code' from renew_results where label='expired'),'INVALID_TRANSITION',
  'expired invitation cannot be renewed');
select is((select result->'details'->>'reason' from renew_results where label='expired'),'expired',
  'expired rejection is explicit');
select is((select result->'details'->>'reason' from renew_results where label='revoked'),'revoked',
  'revoked rejection is explicit');
select is((select result->'details'->>'reason' from renew_results where label='exhausted'),'exhausted',
  'exhausted rejection is explicit');

select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into renew_results values ('outsider', public.cmd_renew_project_invite(
  '92000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000002',
  '94000000-0000-0000-0000-000000000006',1,7
));
reset role;
select is((select result->>'code' from renew_results where label='outsider'),'NOT_FOUND_OR_NOT_AUTHORIZED',
  'non-leader cannot renew invitation');

select * from finish();
rollback;
