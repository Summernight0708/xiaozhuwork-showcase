-- G: connect C's existing immutable provenance helpers to real authoritative transitions.
-- Task updates are completed first. These hooks never recreate source facts from client data.

create function private.g_open_epoch_on_acceptance()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.accepted_at is distinct from new.accepted_at
    and new.accepted_at is not null
    and new.assignee_id is not null
    and new.assignment_state='assigned'
    and new.status not in ('completed','canceled') then
      perform private.followup_open_responsibility_epoch(
        new.project_id,new.id,new.assignee_id,new.accepted_at,'accepted_assignment'
      );
  end if;
  return new;
end;
$$;
revoke all on function private.g_open_epoch_on_acceptance()
 from public,anon,authenticated,service_role;

create trigger g_open_responsibility_on_acceptance
after update of accepted_at on public.tasks
for each row when (old.accepted_at is distinct from new.accepted_at)
execute function private.g_open_epoch_on_acceptance();

-- The primary submit command emits one authoritative task_submitted_for_review
-- event only after writing tasks and task_review_rounds. Its event is therefore
-- the transaction-safe point at which C may use that command ID for event_seq=2.
create function private.g_record_first_submission_from_event()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_task public.tasks%rowtype;
  v_round public.task_review_rounds%rowtype;
begin
  if new.event_type<>'task_submitted_for_review'
     or new.entity_type<>'task_review_round'
     or new.command_request_id is null
     or new.event_seq is distinct from 1 then
    return new;
  end if;
  select * into v_round from public.task_review_rounds
   where id=new.entity_id and project_id=new.project_id;
  if v_round.id is null or v_round.round_number<>1 then
    return new;
  end if;
  select * into v_task from public.tasks
   where id=v_round.task_id and project_id=new.project_id;
  if v_task.id is null or v_task.first_submitted_at is null
     or v_task.first_submitted_at is distinct from v_round.submitted_at
     or v_task.status<>'awaiting_review'
     or (new.event_data->>'taskId') is distinct from v_task.id::text then
    raise exception using errcode='23514',message='G_FIRST_SUBMISSION_AUTHORITY_MISMATCH';
  end if;

  perform private.followup_record_first_submission(
    new.project_id,v_task.id,new.actor_id,new.command_request_id,
    new.request_id,v_task.first_submitted_at,v_task.version
  );
  return new;
end;
$$;
revoke all on function private.g_record_first_submission_from_event()
 from public,anon,authenticated,service_role;

create trigger g_record_first_submission_on_authoritative_event
after insert on public.business_events
for each row when (new.event_type='task_submitted_for_review')
execute function private.g_record_first_submission_from_event();
