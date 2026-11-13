begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_column('public','account_lifecycle_requests','auth_soft_deleted_at','separate verified Auth soft delete checkpoint exists');
select has_function('public','lifecycle_prepare_soft_delete_service',array['uuid','integer'],'profile privacy preparation service exists');
select has_function('public','lifecycle_finalize_soft_delete_service',array['uuid','integer'],'Auth proof checkpoint service exists');
select ok(not has_function_privilege('authenticated','public.lifecycle_prepare_soft_delete_service(uuid,integer)','EXECUTE'),'browser cannot execute personal redaction');
select ok(not has_function_privilege('authenticated','public.lifecycle_finalize_soft_delete_service(uuid,integer)','EXECUTE'),'browser cannot forge Auth soft deletion');
select ok(has_function_privilege('service_role','public.lifecycle_finalize_soft_delete_service(uuid,integer)','EXECUTE'),'service_role can call checkpoint');
insert into auth.users(id,email) values
 ('f7a00000-0000-0000-0000-000000000001','f2-old-member@example.test'),
 ('f7a00000-0000-0000-0000-000000000002','f2-other-member@example.test');
update public.profiles set display_name='Private Name',real_name='Sensitive Name',
 student_number='Sensitive Student' where id='f7a00000-0000-0000-0000-000000000001';
insert into public.projects(id,name,deadline_at,created_by,leader_id)
 values('f7b00000-0000-0000-0000-000000000001','Shared Work',now()+interval '9 days',
 'f7a00000-0000-0000-0000-000000000002','f7a00000-0000-0000-0000-000000000002');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values
 ('f7b00000-0000-0000-0000-000000000001','f7a00000-0000-0000-0000-000000000002','leader','active',false),
 ('f7b00000-0000-0000-0000-000000000001','f7a00000-0000-0000-0000-000000000001','member','active',false);
insert into public.account_lifecycle_requests(user_id,state,generation,version,
  requested_at,cancel_until,auth_revoked_at)
 values('f7a00000-0000-0000-0000-000000000001','blocked',2,2,
 now()-interval '32 days',now()-interval '2 days',now()-interval '1 day');
insert into private.account_soft_delete_release_approvals(
 user_id,generation,privacy_manifest_sha256,storage_manifest_sha256,
 legal_reviewer_id,security_reviewer_id,legal_hold_cleared,exported_artifacts_reviewed,
 backups_and_logs_reviewed,consent_verified
) values(
 'f7a00000-0000-0000-0000-000000000001',2,repeat('a',64),repeat('b',64),
 'f7a00000-0000-0000-0000-000000000010',
 'f7a00000-0000-0000-0000-000000000020',
 true,true,true,true
);
create temp table f2_soft_results(label text,result jsonb);
-- Rollback-only synthetic human review, now bound to the actual manifest.
select set_config('request.jwt.claim.role','service_role',true);
select public.lifecycle_scan_pii_service('f7a00000-0000-0000-0000-000000000001',2,'f7a00000-0000-0000-0000-000000000099');
insert into private.lifecycle_cleanup_reviews(user_id,generation,manifest_id,legal_hold,retain_until,
 legal_reviewer_id,security_reviewer_id,evidence_sha256,approved_at,expires_at)
 select a.user_id,a.generation,m.id,false,now()-interval '1 day',a.legal_reviewer_id,
 a.security_reviewer_id,repeat('c',64),now(),now()+interval '1 day'
 from private.account_soft_delete_release_approvals a join private.lifecycle_privacy_manifests m
 on m.user_id=a.user_id and m.generation=a.generation
 where a.user_id='f7a00000-0000-0000-0000-000000000001';
update private.account_soft_delete_release_approvals a set privacy_manifest_sha256=m.manifest_sha256
 from private.lifecycle_privacy_manifests m where m.user_id=a.user_id and m.generation=a.generation;
grant all on f2_soft_results to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_soft_results values('wrong-generation',
 public.lifecycle_prepare_soft_delete_service('f7a00000-0000-0000-0000-000000000001',1));
insert into f2_soft_results values('before-external-Auth',
 public.lifecycle_finalize_soft_delete_service('f7a00000-0000-0000-0000-000000000001',2));
insert into f2_soft_results values('prepare',
 public.lifecycle_prepare_soft_delete_service('f7a00000-0000-0000-0000-000000000001',2));
reset role;
select is((select result->>'code' from f2_soft_results where label='wrong-generation'),
 'SOFT_DELETE_NOT_DUE','stale generation cannot scrub profile');
select is((select result->>'code' from f2_soft_results where label='before-external-Auth'),
 'AUTH_SOFT_DELETE_NOT_VERIFIED','SQL checkpoint refuses nonexistent Auth soft deletion');
select is((select result->>'prepared' from f2_soft_results where label='prepare'),'true','valid expired case prepares profile');
select is((select display_name from public.profiles where id='f7a00000-0000-0000-0000-000000000001'),'已注销成员','profile label redacted');
select is((select real_name from public.profiles where id='f7a00000-0000-0000-0000-000000000001'),null::text,'real name erased');
select is((select student_number from public.profiles where id='f7a00000-0000-0000-0000-000000000001'),null::text,'student number erased');
select is((select count(*)::integer from public.project_members where project_id='f7b00000-0000-0000-0000-000000000001'),2,'co-member history remains intact');
select is((select state from public.account_lifecycle_requests where user_id='f7a00000-0000-0000-0000-000000000001'),'blocked','profile preparation never declares full redaction');
-- Simulates a *verified* GoTrue Admin soft-delete in disposable SQL fixtures.
update auth.users set deleted_at=now(),email=repeat('A',43),phone=repeat('B',15),
  encrypted_password=null,raw_user_meta_data='{}'::jsonb,
  raw_app_meta_data='{}'::jsonb
 where id='f7a00000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_soft_results values('finalize',
 public.lifecycle_finalize_soft_delete_service('f7a00000-0000-0000-0000-000000000001',2));
insert into f2_soft_results values('replay',
 public.lifecycle_finalize_soft_delete_service('f7a00000-0000-0000-0000-000000000001',2));
reset role;
select is((select result->>'authSoftDeleted' from f2_soft_results where label='finalize'),'true','verified Auth soft deletion checkpoint accepted');
select is((select result->>'replayed' from f2_soft_results where label='replay'),'true','repeat service proof is idempotent');
select ok((select auth_soft_deleted_at is not null from public.account_lifecycle_requests where user_id='f7a00000-0000-0000-0000-000000000001'),'confirmed external Auth soft delete recorded');
select is((select state from public.account_lifecycle_requests where user_id='f7a00000-0000-0000-0000-000000000001'),'blocked','no false complete-redaction state');
select is((select count(*)::integer from auth.users where id in ('f7a00000-0000-0000-0000-000000000001','f7a00000-0000-0000-0000-000000000002')),2,'auth foreign keys retained without cascade');
select * from finish();
rollback;
