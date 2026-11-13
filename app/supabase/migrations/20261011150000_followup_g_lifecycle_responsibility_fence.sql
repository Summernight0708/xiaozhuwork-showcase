-- G: an account in pending/blocked lifecycle cannot be assigned new work
-- by another active user. All guards run under SECURITY DEFINER to inspect
-- lifecycle state despite the caller's ordinary RLS restrictions.
create function private.g_lifecycle_reject_new_responsibility()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_new jsonb:=to_jsonb(new);
 v_old jsonb;
 v_user uuid;
 v_new_responsibility boolean:=false;
begin
 if tg_op='UPDATE' then v_old:=to_jsonb(old); end if;
 if tg_table_name='tasks' then
   v_user:=nullif(v_new->>'assignee_id','')::uuid;
   v_new_responsibility:=v_new->>'status' not in ('completed','canceled')
     and (tg_op='INSERT'
       or v_old->>'assignee_id' is distinct from v_new->>'assignee_id'
       or v_old->>'status' in ('completed','canceled'));
 elsif tg_table_name='task_collaborators' then
   v_user:=nullif(v_new->>'user_id','')::uuid;
   v_new_responsibility:=v_new->>'state' in ('pending','accepted')
     and (tg_op='INSERT' or v_old->>'state' is distinct from v_new->>'state');
 elsif tg_table_name='task_assignment_offers' then
   v_user:=nullif(v_new->>'target_user_id','')::uuid;
   v_new_responsibility:=tg_op='INSERT'
     or v_old->>'target_user_id' is distinct from v_new->>'target_user_id';
 elsif tg_table_name='task_primary_handoffs' then
   v_user:=nullif(v_new->>'to_user_id','')::uuid;
   v_new_responsibility:=tg_op='INSERT'
     or v_old->>'to_user_id' is distinct from v_new->>'to_user_id';
 elsif tg_table_name='task_review_rounds' then
   v_user:=nullif(v_new->>'delegated_reviewer_id','')::uuid;
   v_new_responsibility:=v_new->>'state'='pending'
    and (tg_op='INSERT'
       or v_old->>'delegated_reviewer_id' is distinct from v_new->>'delegated_reviewer_id');
 end if;

 if v_user is not null and v_new_responsibility and exists(
    select 1 from public.account_lifecycle_requests r
     where r.user_id=v_user and r.state<>'canceled'
 ) then
  raise exception using errcode='42501',message='ACCOUNT_ACCESS_DISABLED';
 end if;
 return new;
end;
$$;
revoke all on function private.g_lifecycle_reject_new_responsibility()
 from public,anon,authenticated,service_role;
create trigger g_lifecycle_responsibility_tasks
 before insert or update on public.tasks
 for each row execute function private.g_lifecycle_reject_new_responsibility();
create trigger g_lifecycle_responsibility_collaborators
 before insert or update on public.task_collaborators
 for each row execute function private.g_lifecycle_reject_new_responsibility();
create trigger g_lifecycle_responsibility_offers
 before insert or update on public.task_assignment_offers
 for each row execute function private.g_lifecycle_reject_new_responsibility();
create trigger g_lifecycle_responsibility_handoffs
 before insert or update on public.task_primary_handoffs
 for each row execute function private.g_lifecycle_reject_new_responsibility();
create trigger g_lifecycle_responsibility_reviews
 before insert or update on public.task_review_rounds
 for each row execute function private.g_lifecycle_reject_new_responsibility();
