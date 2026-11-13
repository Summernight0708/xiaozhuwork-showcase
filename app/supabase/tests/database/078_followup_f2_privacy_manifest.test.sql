begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email) values('fb100000-0000-0000-0000-000000000001','literal+f2@example.test');
update public.profiles set display_name='Manifest Sensitive Name' where id='fb100000-0000-0000-0000-000000000001';
insert into public.account_lifecycle_requests(user_id,state,generation,version,requested_at,cancel_until,auth_revoked_at)
 values('fb100000-0000-0000-0000-000000000001','blocked',1,1,now()-interval '40 days',now()-interval '10 days',now()-interval '9 days');
create temp table manifest_results(label text,result jsonb);
grant all on manifest_results to service_role;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
insert into manifest_results values('scan',public.lifecycle_scan_pii_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000001'));
insert into manifest_results values('retry',public.lifecycle_scan_pii_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000001'));
insert into manifest_results select 'manifest',public.lifecycle_get_pii_manifest_service((result->>'manifestId')::uuid) from manifest_results where label='scan';
insert into manifest_results values('assess',public.lifecycle_assess_cleanup_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000002'));
insert into manifest_results values('assess-retry',public.lifecycle_assess_cleanup_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000002'));
select throws_ok($$insert into private.lifecycle_cleanup_reviews(user_id,generation,manifest_id) values(gen_random_uuid(),1,gen_random_uuid())$$,'42501',null,'service cannot manufacture legal approval');
reset role;
select is((select result->>'ok' from manifest_results where label='scan'),'true','scan succeeds');
select is((select result->>'replayed' from manifest_results where label='retry'),'true','same request retries saved manifest');
select is((select count(*)::int from private.lifecycle_privacy_manifests where user_id='fb100000-0000-0000-0000-000000000001'),1,'one durable manifest');
select is((select count(*)::int from private.account_lifecycle_audit where user_id='fb100000-0000-0000-0000-000000000001' and action='privacy_manifest_scanned'),1,'one scan audit');
select is((select result->>'unclassifiedColumns' from manifest_results where label='scan'),'0','current schema classified as review candidates');
select ok((select result->'manifest'->'fields' @> '[{"table":"profiles","column":"display_name","candidateRows":1}]' from manifest_results where label='manifest'),'literal subject name counted');
select ok((select result->'manifest'->'fields' @> '[{"table":"command_requests","column":"result"}]' from manifest_results where label='manifest'),'generic result JSON scanned');
select ok((select result->'manifest'->'fields' @> '[{"table":"contribution_penalty_appeals","column":"resolution"}]' from manifest_results where label='manifest'),'generic resolution JSON scanned');
select ok((select result->'manifest'->'fields' @> '[{"schema":"storage","table":"objects","column":"metadata"}]' from manifest_results where label='manifest'),'storage metadata scanned');
select ok((select result->'manifest'->'externalReview' @> '{"attachmentContents":"unverified","generatedExports":"unverified","signedUrlsAndCopies":"unverified","backupsAndLogs":"unverified","externalLinksAndCaches":"unverified"}' from manifest_results where label='manifest'),'all external surfaces remain explicit unresolved reviews');
select ok((select result::text not like '%literal+f2@example.test%' and result::text not like '%Manifest Sensitive Name%' from manifest_results where label='manifest'),'no personal values persisted in manifest');
select is((select result->>'code' from manifest_results where label='assess'),'LEGAL_RETENTION_MANIFEST_REVIEW_REQUIRED','missing legal review fails closed');
select is((select result->>'replayed' from manifest_results where label='assess-retry'),'true','assessment retry is idempotent');
select is((select count(*)::int from private.account_lifecycle_audit where user_id='fb100000-0000-0000-0000-000000000001' and action='cleanup_assessed'),1,'assessment audit once');
-- Synthetic, rollback-only review fixture; application/service cannot write it.
insert into private.lifecycle_cleanup_reviews(user_id,generation,manifest_id,legal_hold,retain_until,
 legal_reviewer_id,security_reviewer_id,evidence_sha256,approved_at,expires_at)
 select user_id,generation,id,false,now()-interval '1 day',
 'fb300000-0000-0000-0000-000000000001','fb300000-0000-0000-0000-000000000002',repeat('c',64),now(),now()+interval '1 day'
 from private.lifecycle_privacy_manifests where user_id='fb100000-0000-0000-0000-000000000001';
select ok(private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'bounded two-person review accepted for assessment only');
update private.lifecycle_cleanup_reviews set legal_hold=true;
select ok(not private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'new legal hold immediately overrides previous approval');
update private.lifecycle_cleanup_reviews set legal_hold=null;
select ok(not private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'unknown legal-hold status fails closed');
update private.lifecycle_cleanup_reviews set legal_hold=false;
select throws_ok($$update private.lifecycle_cleanup_reviews set security_reviewer_id=legal_reviewer_id$$,'23514',null,'same reviewer cannot approve twice');
update private.lifecycle_cleanup_reviews set revoked_at=now();
select ok(not private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'revocation blocks review');
update private.lifecycle_cleanup_reviews set revoked_at=null,retain_until=now()+interval '1 day';
select ok(not private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'retention deadline blocks review');
update private.lifecycle_cleanup_reviews set retain_until=now()-interval '1 day';
set local role service_role;
select is(public.lifecycle_assess_cleanup_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000003')->>'executionAllowed','false','approved assessment still cannot execute deletion');
select is((select execution_allowed from public.lifecycle_list_cleanup_candidates_service(10) where user_id='fb100000-0000-0000-0000-000000000001'),false,'candidate list cannot authorize execution');
reset role;
-- New arbitrary JSON is detected by schema drift; do not auto-classify/approve.
alter table public.profiles add column f2_unclassified_payload jsonb;
update public.profiles set f2_unclassified_payload='{"nested":[{"memo":"Manifest Sensitive Name"}]}' where id='fb100000-0000-0000-0000-000000000001';
select ok(not private.f2_cleanup_review_valid('fb100000-0000-0000-0000-000000000001',1),'schema drift invalidates previous approval immediately');
set local role service_role;
insert into manifest_results values('drift',public.lifecycle_scan_pii_service('fb100000-0000-0000-0000-000000000001',1,'fb200000-0000-0000-0000-000000000004'));
insert into manifest_results select 'drift-manifest',public.lifecycle_get_pii_manifest_service((result->>'manifestId')::uuid) from manifest_results where label='drift';
reset role;
select is((select result->>'unclassifiedColumns' from manifest_results where label='drift'),'1'::text,'unknown JSON column explicitly blocks release');
select ok((select result->'manifest'->'fields' @> '[{"table":"profiles","column":"f2_unclassified_payload","candidateRows":1}]' from manifest_results where label='drift-manifest'),'nested JSON counted without field-name heuristic');
select is((select display_name from public.profiles where id='fb100000-0000-0000-0000-000000000001'),'Manifest Sensitive Name','scanner preserves original identity');
select is((select state from public.account_lifecycle_requests where user_id='fb100000-0000-0000-0000-000000000001'),'blocked','no false erasure completion');
select set_config('request.jwt.claim.role','',true);
select throws_ok($$select public.lifecycle_scan_pii_service('fb100000-0000-0000-0000-000000000001',1,gen_random_uuid())$$,'42501','SERVICE_ROLE_REQUIRED','missing service JWT role fails closed even for privileged SQL caller');
select ok(not has_function_privilege('authenticated','public.lifecycle_scan_pii_service(uuid,integer,uuid)','EXECUTE'),'browser cannot scan identity inventory');
select ok(not has_function_privilege('anon','public.lifecycle_list_cleanup_candidates_service(integer)','EXECUTE'),'anonymous cannot enumerate candidates');
select * from finish();
rollback;
