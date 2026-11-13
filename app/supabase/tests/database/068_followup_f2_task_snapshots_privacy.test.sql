begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_view('public','project_join_requests_visible','request snapshot view exists');
select has_view('public','task_collaborators_visible','collaborator snapshot view exists');
select has_view('public','task_primary_handoffs_visible','handoff snapshot view exists');
select has_view('public','task_change_proposals_visible','change-proposal snapshot view exists');

select ok(not has_column_privilege('authenticated','public.project_join_requests','display_name_snapshot','SELECT'),'request identity snapshot private');
select ok(not has_column_privilege('authenticated','public.task_collaborators','user_name_snapshot','SELECT'),'collaborator identity snapshot private');
select ok(not has_column_privilege('authenticated','public.task_collaborators','invited_by_name_snapshot','SELECT'),'inviter identity snapshot private');
select ok(not has_column_privilege('authenticated','public.task_primary_handoffs','from_user_name_snapshot','SELECT'),'handoff source identity snapshot private');
select ok(not has_column_privilege('authenticated','public.task_primary_handoffs','to_user_name_snapshot','SELECT'),'handoff destination identity snapshot private');
select ok(not has_column_privilege('authenticated','public.task_change_proposals','proposer_name_snapshot','SELECT'),'proposal author snapshot private');
select ok(not has_column_privilege('authenticated','public.task_change_proposals','required_confirmer_name_snapshot','SELECT'),'required confirmer snapshot private');
select ok(has_column_privilege('authenticated','public.task_change_proposals','state','SELECT'),'business proposal state remains accessible');

-- Explicitly deny a valid Auth account that is not a member of the project.
insert into auth.users(id,email) values
 ('f6900000-0000-0000-0000-000000000001','f2-privacy-project-owner@example.test'),
 ('f6900000-0000-0000-0000-000000000002','f2-privacy-project-outsider@example.test');
insert into public.projects(id,name,deadline_at,created_by,leader_id)
 values('f6910000-0000-0000-0000-000000000001','F2 read scopes',now()+interval '7 days',
 'f6900000-0000-0000-0000-000000000001','f6900000-0000-0000-0000-000000000001');
insert into public.project_members(project_id,user_id,role,member_state,is_observer)
 values('f6910000-0000-0000-0000-000000000001','f6900000-0000-0000-0000-000000000001','leader','active',false);

create temp table f2_visible_counts(n integer);
grant all on f2_visible_counts to authenticated;
select set_config('request.jwt.claim.sub','f6900000-0000-0000-0000-000000000002',true);
set local role authenticated;
insert into f2_visible_counts
 select
 (select count(*) from public.task_collaborators_visible where project_id='f6910000-0000-0000-0000-000000000001')
 +(select count(*) from public.task_primary_handoffs_visible where project_id='f6910000-0000-0000-0000-000000000001')
 +(select count(*) from public.task_change_proposals_visible where project_id='f6910000-0000-0000-0000-000000000001')
 +(select count(*) from public.project_join_requests_visible where project_id='f6910000-0000-0000-0000-000000000001');
reset role;
select is((select n from f2_visible_counts),0,'outsider sees no cross-project protected read surface');

select * from finish();
rollback;
