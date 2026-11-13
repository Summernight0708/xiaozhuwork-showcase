alter table public.command_requests
  alter column actor_id drop not null,
  drop constraint command_requests_actor_id_fkey,
  add constraint command_requests_actor_id_fkey
    foreign key (actor_id) references auth.users (id) on delete set null;

alter table public.command_requests
  drop constraint command_requests_account_id_fkey,
  drop constraint command_requests_scope_xor,
  add constraint command_requests_account_id_fkey
    foreign key (account_id) references auth.users (id) on delete set null,
  add constraint command_requests_scope_xor check (
    num_nonnulls(account_id, project_id) = 1
    or (account_id is null and project_id is null and state = 'completed')
  );

alter table public.file_upload_reservations
  alter column actor_id drop not null,
  drop constraint file_upload_reservations_actor_id_fkey,
  add constraint file_upload_reservations_actor_id_fkey
    foreign key (actor_id) references auth.users (id) on delete set null;

alter table public.project_join_requests
  alter column user_id drop not null,
  drop constraint project_join_requests_user_id_fkey,
  add constraint project_join_requests_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete set null;

alter table public.task_assignment_offers
  alter column target_user_id drop not null,
  drop constraint task_assignment_offers_target_user_id_fkey,
  add constraint task_assignment_offers_target_user_id_fkey
    foreign key (target_user_id) references auth.users (id) on delete set null;

create or replace function private.reject_task_file_version_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and old.uploaded_by is not null
     and new.uploaded_by is null
     and (to_jsonb(new) - 'uploaded_by') = (to_jsonb(old) - 'uploaded_by') then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Task file versions are immutable';
end;
$$;

create or replace function private.protect_task_review_round()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_submitter_anonymized boolean;
  v_reviewer_anonymized boolean;
begin
  if tg_op = 'UPDATE' then
    v_submitter_anonymized :=
      old.submitted_by is not null
      and new.submitted_by is null;
    v_reviewer_anonymized :=
      old.reviewed_by is not null
      and new.reviewed_by is null;

    if (v_submitter_anonymized or v_reviewer_anonymized)
       and (new.submitted_by is not distinct from old.submitted_by or v_submitter_anonymized)
       and (new.reviewed_by is not distinct from old.reviewed_by or v_reviewer_anonymized)
       and (to_jsonb(new) - 'submitted_by' - 'reviewed_by')
           = (to_jsonb(old) - 'submitted_by' - 'reviewed_by') then
      return new;
    end if;
  end if;

  if tg_op = 'DELETE' then
    raise exception using errcode='55000', message='Task review rounds cannot be deleted';
  end if;
  if old.state <> 'pending' then
    raise exception using errcode='55000', message='Terminal task review rounds are immutable';
  end if;
  if new.id <> old.id
     or new.project_id <> old.project_id
     or new.task_id <> old.task_id
     or new.round_number <> old.round_number
     or new.submitted_file_version_id <> old.submitted_file_version_id
     or new.submitted_by is distinct from old.submitted_by
     or new.submitted_at <> old.submitted_at
     or new.created_at <> old.created_at then
    raise exception using errcode='55000', message='Task review round identity is immutable';
  end if;
  return new;
end;
$$;

create or replace function private.reject_contribution_item_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and old.member_user_id is not null
     and new.member_user_id is null
     and (to_jsonb(new) - 'member_user_id') = (to_jsonb(old) - 'member_user_id') then
    return new;
  end if;
  raise exception using errcode='55000', message='Contribution items are immutable';
end;
$$;

alter table public.contribution_reports
  add constraint contribution_reports_project_id_id_unique unique (project_id, id);

alter table public.contribution_items
  drop constraint contribution_items_report_id_fkey,
  drop constraint contribution_items_task_id_fkey,
  add constraint contribution_items_project_report_fkey
    foreign key (project_id, report_id)
    references public.contribution_reports (project_id, id)
    on delete cascade,
  add constraint contribution_items_project_task_fkey
    foreign key (project_id, task_id)
    references public.tasks (project_id, id);

alter table public.contribution_confirmations
  drop constraint contribution_confirmations_report_id_fkey,
  add constraint contribution_confirmations_project_report_fkey
    foreign key (project_id, report_id)
    references public.contribution_reports (project_id, id)
    on delete cascade;

revoke all on function private.reject_task_file_version_mutation() from public, anon, authenticated, service_role;
revoke all on function private.protect_task_review_round() from public, anon, authenticated, service_role;
revoke all on function private.reject_contribution_item_mutation() from public, anon, authenticated, service_role;
