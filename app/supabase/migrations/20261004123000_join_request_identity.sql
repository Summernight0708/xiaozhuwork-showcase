alter table public.project_join_requests
  add column display_name_snapshot text,
  add constraint project_join_requests_display_name_snapshot_length
    check (
      display_name_snapshot is null
      or char_length(display_name_snapshot) between 1 and 80
    );

update public.project_join_requests jr
set display_name_snapshot = p.display_name
from public.profiles p
where p.id = jr.user_id
  and jr.display_name_snapshot is null;

create function private.capture_join_request_display_name_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.display_name_snapshot is null and new.user_id is not null then
    select p.display_name
    into new.display_name_snapshot
    from public.profiles p
    where p.id = new.user_id;
  end if;

  return new;
end;
$$;

revoke all on function private.capture_join_request_display_name_snapshot()
  from public, anon, authenticated;

create trigger project_join_requests_capture_display_name_snapshot
before insert on public.project_join_requests
for each row execute function private.capture_join_request_display_name_snapshot();

comment on column public.project_join_requests.display_name_snapshot is
  'Applicant display name captured when the join request is created; exposed only through the existing join-request RLS boundary.';
