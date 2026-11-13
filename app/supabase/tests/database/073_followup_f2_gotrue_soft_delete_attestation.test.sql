begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select ok(not has_function_privilege('authenticated',
 'public.lifecycle_finalize_soft_delete_service(uuid,integer)','EXECUTE'),
 'client cannot forge Auth soft-deletion proof');
insert into auth.users(id,email) values
 ('f8900000-0000-0000-0000-000000000001','real-identity@example.test');
insert into public.account_lifecycle_requests(
 user_id,state,generation,version,requested_at,cancel_until,auth_revoked_at)
 values('f8900000-0000-0000-0000-000000000001','blocked',5,5,
 now()-interval '40 days',now()-interval '10 days',now()-interval '9 days');
insert into private.account_soft_delete_release_approvals(
 user_id,generation,privacy_manifest_sha256,storage_manifest_sha256,
 legal_reviewer_id,security_reviewer_id,legal_hold_cleared,
 exported_artifacts_reviewed,backups_and_logs_reviewed,consent_verified)
 values('f8900000-0000-0000-0000-000000000001',5,repeat('a',64),
 repeat('b',64),
 'f8900000-0000-0000-0000-000000000002',
 'f8900000-0000-0000-0000-000000000003',true,true,true,true);
insert into auth.identities(user_id,provider_id,provider,identity_data)
 values('f8900000-0000-0000-0000-000000000001','real-identity@example.test',
 'email','{"email":"real-identity@example.test"}'::jsonb);

create temp table f2_gotrue_proof(stage text,result jsonb);
-- Rollback-only synthetic review, not an approval inserted by the worker.
select set_config('request.jwt.claim.role','service_role',true);
select public.lifecycle_scan_pii_service('f8900000-0000-0000-0000-000000000001',5,'f8900000-0000-0000-0000-000000000099');
insert into private.lifecycle_cleanup_reviews(user_id,generation,manifest_id,legal_hold,retain_until,
 legal_reviewer_id,security_reviewer_id,evidence_sha256,approved_at,expires_at)
 select a.user_id,a.generation,m.id,false,now()-interval '1 day',a.legal_reviewer_id,
 a.security_reviewer_id,repeat('c',64),now(),now()+interval '1 day'
 from private.account_soft_delete_release_approvals a join private.lifecycle_privacy_manifests m
 on m.user_id=a.user_id and m.generation=a.generation
 where a.user_id='f8900000-0000-0000-0000-000000000001';
update private.account_soft_delete_release_approvals a set privacy_manifest_sha256=m.manifest_sha256
 from private.lifecycle_privacy_manifests m where m.user_id=a.user_id and m.generation=a.generation;
grant all on f2_gotrue_proof to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_gotrue_proof values('before',
 public.lifecycle_finalize_soft_delete_service(
 'f8900000-0000-0000-0000-000000000001',5));
reset role;
select is((select result->>'code' from f2_gotrue_proof where stage='before'),
 'AUTH_SOFT_DELETE_NOT_VERIFIED','undeleted GoTrue user is refused');

-- A disposable SQL fixture emulates GoTrue's actual field mutations,
-- including retained-but-scrubbed identities. It never invokes GoTrue Admin.
update public.profiles
 set display_name='已注销成员',real_name=null,student_number=null
 where id='f8900000-0000-0000-0000-000000000001';
update auth.users set deleted_at=now(),email=repeat('A',43),
 phone=repeat('B',15),encrypted_password=null,
 raw_user_meta_data='{}'::jsonb,raw_app_meta_data='{}'::jsonb
 where id='f8900000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_gotrue_proof values('unmasked-identity',
 public.lifecycle_finalize_soft_delete_service(
 'f8900000-0000-0000-0000-000000000001',5));
reset role;
select is((select result->>'code' from f2_gotrue_proof
 where stage='unmasked-identity'),
 'AUTH_SOFT_DELETE_NOT_VERIFIED',
 'GoTrue identity PII must be scrubbed, not merely marked deleted');

update auth.identities set identity_data='{}'::jsonb,
 provider_id=repeat('C',43)
 where user_id='f8900000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_gotrue_proof values('verified',
 public.lifecycle_finalize_soft_delete_service(
 'f8900000-0000-0000-0000-000000000001',5));
insert into f2_gotrue_proof values('replay',
 public.lifecycle_finalize_soft_delete_service(
 'f8900000-0000-0000-0000-000000000001',5));
reset role;
select is((select result->>'authSoftDeleted' from f2_gotrue_proof
 where stage='verified'),'true','actual GoTrue obfuscation can be attested');
select is((select result->>'identityRowsScrubbed' from f2_gotrue_proof
 where stage='verified'),'1','retained identity count is reported accurately');
select is((select result->>'replayed' from f2_gotrue_proof
 where stage='replay'),'true','checkpoint replay is idempotent');
select is((select state from public.account_lifecycle_requests
 where user_id='f8900000-0000-0000-0000-000000000001'),
 'blocked','proof does not falsely claim historical full erasure');
select ok((select auth_soft_deleted_at is not null
 from public.account_lifecycle_requests
 where user_id='f8900000-0000-0000-0000-000000000001'),
 'generation-scoped checkpoint was recorded');
select * from finish();
rollback;
