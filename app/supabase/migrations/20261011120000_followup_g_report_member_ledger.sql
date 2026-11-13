-- G: immutable per-member report source for projects using E governance.
-- Existing formal reports retain legacy_single_assignee and unmodified legacy items.
alter table public.contribution_reports
  add column snapshot_basis text not null default 'legacy_single_assignee'
  check(snapshot_basis in ('legacy_single_assignee','member_ledger_v1'));

create table public.contribution_report_member_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.contribution_reports(id) on delete restrict,
  project_id uuid not null references public.projects(id) on delete restrict,
  task_id uuid not null references public.tasks(id) on delete restrict,
  member_user_id uuid references auth.users(id) on delete set null,
  member_name_snapshot text not null,
  entry_type text not null check(entry_type in ('task_share','penalty','adjustment')),
  entry_id uuid not null,
  task_title_snapshot text not null,
  task_weight numeric(12,4),
  share numeric(5,4) not null check(share between 0 and 1),
  signed_amount numeric(12,4) not null,
  completed_at_snapshot timestamptz not null,
  captured_at timestamptz not null default transaction_timestamp(),
  unique(report_id,entry_type,entry_id)
);
alter table public.contribution_report_member_ledger_entries enable row level security;
create policy g_report_ledger_read on public.contribution_report_member_ledger_entries
 for select to authenticated using(public.is_active_project_member(project_id));
revoke all on public.contribution_report_member_ledger_entries from public,anon,authenticated,service_role;
grant select on public.contribution_report_member_ledger_entries to authenticated;
create trigger g_archived_write_reject
 before insert or update or delete on public.contribution_report_member_ledger_entries
 for each row execute function private.followup_reject_archived_project_write();

-- Never mutate a captured formal ledger. A later proposal/appeal cannot rewrite history.
create function private.g_report_ledger_immutable()
returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='55000',message='Immutable contribution report ledger'; end; $$;
revoke all on function private.g_report_ledger_immutable() from public,anon,authenticated,service_role;
create trigger g_report_ledger_immutable
 before update or delete on public.contribution_report_member_ledger_entries
 for each row execute function private.g_report_ledger_immutable();

create function private.g_report_capture_basis()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_governed boolean;
begin
  if new.contribution_mode<>'weighted' then return new; end if;
  select exists(
    select 1 from public.tasks t
    where t.project_id=new.project_id and t.status='completed'
      and (exists(select 1 from public.task_share_proposals s where s.task_id=t.id)
        or exists(select 1 from public.task_collaborators c
          where c.project_id=t.project_id and c.task_id=t.id and c.state='accepted'))
  ) into v_governed;
  if not v_governed then return new; end if;

  if exists(
    select 1 from public.project_contribution_share_readiness sr
     where sr.project_id=new.project_id and not sr.shares_ready
  ) or exists(
    select 1 from public.contribution_penalty_appeals a
     where a.project_id=new.project_id and a.status='pending'
  ) then
    raise exception using errcode='23514',message='SHARES_NOT_CONFIRMED';
  end if;
  new.snapshot_basis:='member_ledger_v1';
  return new;
end;
$$;
revoke all on function private.g_report_capture_basis()
 from public,anon,authenticated,service_role;
create trigger g_report_basis_before_create
 before insert on public.contribution_reports
 for each row execute function private.g_report_capture_basis();

create function private.g_report_capture_member_ledger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.snapshot_basis <> 'member_ledger_v1' then return new; end if;
  insert into public.contribution_report_member_ledger_entries(
    report_id,project_id,task_id,member_user_id,member_name_snapshot,
    entry_type,entry_id,task_title_snapshot,task_weight,share,signed_amount,
    completed_at_snapshot
  )
  select new.id,ledger.project_id,ledger.task_id,ledger.member_user_id,
    coalesce(
      nullif(btrim(pm.display_name_snapshot),''),
      nullif(btrim(pr.display_name),''),
      case when ledger.member_user_id is null then '已注销成员'
        else '成员-'||left(ledger.member_user_id::text,8) end
    ),
    ledger.entry_type,ledger.entry_id,t.title,
    case when ledger.entry_type='task_share'
      then round(t.weight::numeric,4) else null end,
    case when ledger.entry_type='task_share'
      then round(sh.share_bps::numeric/10000,4) else 0.0000::numeric end,
    ledger.signed_amount,
    coalesce(t.completed_at,pen.assessed_at,sh.created_at,adjpen.assessed_at)
  from public.project_contribution_ledger_entries ledger
  join public.tasks t on t.id=ledger.task_id and t.project_id=ledger.project_id
  left join public.task_contribution_ledger sh
    on ledger.entry_type='task_share' and sh.id=ledger.entry_id
  left join public.contribution_penalties pen
    on ledger.entry_type='penalty' and pen.id=ledger.entry_id
  left join public.contribution_penalty_adjustments adj
    on ledger.entry_type='adjustment' and adj.id=ledger.entry_id
  left join public.contribution_penalties adjpen on adjpen.id=adj.penalty_id
  left join public.project_members pm
    on pm.project_id=ledger.project_id and pm.user_id=ledger.member_user_id
  left join public.profiles pr on pr.id=ledger.member_user_id
  where ledger.project_id=new.project_id
    and coalesce(t.completed_at,pen.assessed_at,sh.created_at,adjpen.assessed_at) is not null
  order by ledger.task_id,ledger.entry_type,ledger.entry_id;
  if not exists(
    select 1 from public.contribution_report_member_ledger_entries
      where report_id=new.id
  ) then
    raise exception using errcode='23514',message='LEDGER_SNAPSHOT_EMPTY';
  end if;
  return new;
end;
$$;
revoke all on function private.g_report_capture_member_ledger() from public,anon,authenticated,service_role;
create trigger g_report_capture_member_ledger_on_insert
 after insert on public.contribution_reports
 for each row execute function private.g_report_capture_member_ledger();

create function private.g_report_formal_readiness()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.state='formal' and old.state is distinct from new.state
     and new.snapshot_basis='member_ledger_v1' then
    if exists(select 1 from public.project_contribution_share_readiness sr
      where sr.project_id=new.project_id and not sr.shares_ready)
    or exists(select 1 from public.contribution_penalty_appeals a
      where a.project_id=new.project_id and a.status='pending')
    or not exists(select 1 from public.contribution_report_member_ledger_entries
      where report_id=new.id) then
      raise exception using errcode='23514',message='SHARES_NOT_CONFIRMED';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.g_report_formal_readiness() from public,anon,authenticated,service_role;
create trigger g_report_formal_readiness_on_update
 before update of state on public.contribution_reports
 for each row execute function private.g_report_formal_readiness();

-- Keep the old read schema as the definitive fallback for all historical reports.
alter function public.get_project_contribution_report(uuid) rename to get_project_contribution_report_legacy;
revoke all on function public.get_project_contribution_report_legacy(uuid)
 from public,anon,authenticated,service_role;
create function public.get_project_contribution_report(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_original jsonb; v_basis text; v_report_id uuid; v_items jsonb;
begin
  v_original:=public.get_project_contribution_report_legacy(p_project_id);
  if v_original is null or v_original ? 'code' then return v_original; end if;
  v_report_id:=(v_original->>'reportId')::uuid;
  select snapshot_basis into v_basis from public.contribution_reports where id=v_report_id;
  if v_basis<>'member_ledger_v1' then return v_original; end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'taskId',d.task_id,'memberUserId',d.member_user_id,
    'taskWeight',d.task_weight,'share',d.share,
    'contributionValue',d.signed_amount,'taskTitle',d.task_title_snapshot,
    'completedAt',d.completed_at_snapshot
  )) order by d.task_id,d.entry_type,d.entry_id),'[]'::jsonb)
  into v_items from public.contribution_report_member_ledger_entries d
   where d.report_id=v_report_id;
  return jsonb_set(v_original,'{items}',v_items);
end;
$$;
revoke all on function public.get_project_contribution_report(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_project_contribution_report(uuid) to authenticated;

alter function public.get_project_report_export(uuid) rename to get_project_report_export_legacy;
revoke all on function public.get_project_report_export_legacy(uuid)
 from public,anon,authenticated,service_role;
create function public.get_project_report_export(p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_original jsonb; v_basis text; v_items jsonb;
begin
  v_original:=public.get_project_report_export_legacy(p_report_id);
  if v_original is null or v_original ? 'code' then return v_original; end if;
  select snapshot_basis into v_basis from public.contribution_reports where id=p_report_id;
  if v_basis<>'member_ledger_v1' then return v_original; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'taskId',d.task_id,'taskTitle',d.task_title_snapshot,
    'memberUserId',d.member_user_id,'memberDisplayName',d.member_name_snapshot,
    'taskWeightAuthority',case when d.task_weight is null then null
      else to_char(d.task_weight,'FM9999999990.0000') end,
    'taskWeightDisplay',case when d.task_weight is null then null
      else to_char(round(d.task_weight,2),'FM9999999990.00') end,
    'shareAuthority',to_char(d.share,'FM9999999990.0000'),
    'shareDisplay',to_char(round(d.share,2),'FM9999999990.00'),
    'contributionValueAuthority',to_char(d.signed_amount,'FM9999999990.0000'),
    'contributionValueDisplay',to_char(round(d.signed_amount,2),'FM9999999990.00'),
    'completedAt',d.completed_at_snapshot
  ) order by d.task_id,d.entry_type,d.entry_id),'[]'::jsonb)
    into v_items from public.contribution_report_member_ledger_entries d
    where d.report_id=p_report_id;
  return jsonb_set(v_original,'{items}',v_items);
end;
$$;
revoke all on function public.get_project_report_export(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.get_project_report_export(uuid) to authenticated;
