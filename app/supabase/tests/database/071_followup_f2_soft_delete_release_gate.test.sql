begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_table('private','account_soft_delete_release_approvals','independent deletion release gate table exists');
select ok(not has_table_privilege('service_role','private.account_soft_delete_release_approvals','INSERT'),'service cannot self-authorize privacy approval');
select ok(not has_table_privilege('authenticated','private.account_soft_delete_release_approvals','SELECT'),'browser cannot enumerate approvals');
insert into auth.users(id,email) values
 ('f7a00000-0000-0000-0000-000000000011','approval-subject@example.test');
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until,auth_revoked_at)
 values('f7a00000-0000-0000-0000-000000000011','blocked',3,3,now()-interval '32 days',now()-interval '2 days',now()-interval '1 day');
select ok(not private.f2_has_soft_delete_release('f7a00000-0000-0000-0000-000000000011',3),
 'default unapproved lifecycle cannot invoke deletion');
create temp table approval_checks(code text);
grant all on approval_checks to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into approval_checks select result->>'code'
 from public.lifecycle_prepare_soft_delete_service('f7a00000-0000-0000-0000-000000000011',3) as result;
reset role;
select is((select code from approval_checks),'INDEPENDENT_PRIVACY_APPROVAL_REQUIRED','direct service prepares fail closed');
insert into private.account_soft_delete_release_approvals(
user_id,generation,privacy_manifest_sha256,storage_manifest_sha256,
legal_reviewer_id,security_reviewer_id,legal_hold_cleared,exported_artifacts_reviewed,
backups_and_logs_reviewed,consent_verified) values
('f7a00000-0000-0000-0000-000000000011',3,repeat('a',64),repeat('b',64),
'f7a00000-0000-0000-0000-000000000012','f7a00000-0000-0000-0000-000000000013',
true,true,true,true);
select ok(not private.f2_has_soft_delete_release('f7a00000-0000-0000-0000-000000000011',3),
 'arbitrary manifest hash no longer authorizes Auth deletion');
select set_config('request.jwt.claim.role','service_role',true);
select public.lifecycle_scan_pii_service('f7a00000-0000-0000-0000-000000000011',3,'f7a00000-0000-0000-0000-000000000099');
insert into private.lifecycle_cleanup_reviews(user_id,generation,manifest_id,legal_hold,retain_until,
 legal_reviewer_id,security_reviewer_id,evidence_sha256,approved_at,expires_at)
 select a.user_id,a.generation,m.id,false,now()-interval '1 day',a.legal_reviewer_id,
 a.security_reviewer_id,repeat('c',64),now(),now()+interval '1 day'
 from private.account_soft_delete_release_approvals a join private.lifecycle_privacy_manifests m
 on m.user_id=a.user_id and m.generation=a.generation
 where a.user_id='f7a00000-0000-0000-0000-000000000011';
update private.account_soft_delete_release_approvals a set privacy_manifest_sha256=m.manifest_sha256
 from private.lifecycle_privacy_manifests m where m.user_id=a.user_id and m.generation=a.generation;
select ok(private.f2_has_soft_delete_release('f7a00000-0000-0000-0000-000000000011',3),
 'separate reviewers authorize one generation only');
select ok(not private.f2_has_soft_delete_release('f7a00000-0000-0000-0000-000000000011',4),
 'approval never carries forward to a different generation');
select ok(not private.f2_has_soft_delete_release('f7a00000-0000-0000-0000-000000000012',3),
 'approval cannot be used for different user');
create temp table f2_approved_worker_candidates(user_id uuid);
grant all on f2_approved_worker_candidates to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into f2_approved_worker_candidates
 select user_id from public.lifecycle_list_soft_delete_candidates_service(10);
reset role;
select ok(exists(select 1 from f2_approved_worker_candidates
 where user_id='f7a00000-0000-0000-0000-000000000011'),
 'approved subject appears in Worker queue');
select * from finish();
rollback;
