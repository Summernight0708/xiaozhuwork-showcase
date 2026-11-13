-- Dismissal preferences are account-level, not project-level.
create table public.user_help_dismissals (
  user_id uuid not null references auth.users(id) on delete cascade,
  hint_key text not null check (char_length(hint_key) between 1 and 96),
  dismissed_at timestamptz not null default now(),
  primary key (user_id, hint_key)
);

alter table public.user_help_dismissals enable row level security;
revoke all on public.user_help_dismissals from public, anon, authenticated;
grant select, insert on public.user_help_dismissals to authenticated;

create policy user_help_dismissals_read_own
on public.user_help_dismissals for select to authenticated
using (user_id = (select auth.uid()));

create policy user_help_dismissals_insert_own
on public.user_help_dismissals for insert to authenticated
with check (user_id = (select auth.uid()));

comment on table public.user_help_dismissals is 'One immutable dismissal fact per account and versioned help hint. No project/learning progress data.';
