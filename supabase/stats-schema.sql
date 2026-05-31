-- ============================================================
--  Philidor Chess Academy — Student stats + admin role
--  Run this in Supabase -> SQL Editor -> New query -> Run.
--  (Safe to run multiple times.)
-- ============================================================

-- ------------------------------------------------------------
--  admins: users allowed to edit any student's stats.
--  Add yourself after running this (see SETUP note at bottom).
-- ------------------------------------------------------------
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.admins enable row level security;

drop policy if exists "read own admin row" on public.admins;
create policy "read own admin row"
  on public.admins for select
  using ( auth.uid() = user_id );

-- helper: is the current user an admin?
create or replace function public.is_admin()
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ------------------------------------------------------------
--  student_stats: one row per parent/child, all dashboard data.
-- ------------------------------------------------------------
create table if not exists public.student_stats (
  parent_id          uuid primary key references auth.users (id) on delete cascade,
  -- Classroom
  attendance_pct     numeric  default 0,
  classes_attended   int      default 0,
  classes_total      int      default 0,
  hours_in_classroom numeric  default 0,
  leaderboard_points int      default 0,
  -- Quiz
  quizzes_completed  int      default 0,
  quizzes_total      int      default 0,
  problems_solved    int      default 0,
  problems_total     int      default 0,
  quiz_time_taken    text     default '—',
  quiz_points        int      default 0,
  -- Game Arena
  games_played       int      default 0,
  game_time          text     default '—',
  wins               int      default 0,
  losses             int      default 0,
  draws              int      default 0,
  -- Tournament
  tournaments_played int      default 0,
  tournament_best    text     default '—',
  -- Coach notes + meta
  coach_notes        text     default '',
  updated_at         timestamptz default now()
);
alter table public.student_stats enable row level security;

drop policy if exists "parent or admin reads stats" on public.student_stats;
drop policy if exists "admin inserts stats"        on public.student_stats;
drop policy if exists "admin updates stats"        on public.student_stats;

-- Parents read ONLY their own row; admins read all.
create policy "parent or admin reads stats"
  on public.student_stats for select
  using ( auth.uid() = parent_id or public.is_admin() );

-- Only admins can create / edit stats.
create policy "admin inserts stats"
  on public.student_stats for insert
  with check ( public.is_admin() );

create policy "admin updates stats"
  on public.student_stats for update
  using ( public.is_admin() );

-- ------------------------------------------------------------
--  Let admins read ALL profiles (so the admin page can list
--  parents). Parents still read only their own (existing policy).
-- ------------------------------------------------------------
drop policy if exists "admin reads all profiles" on public.profiles;
create policy "admin reads all profiles"
  on public.profiles for select
  using ( auth.uid() = id or public.is_admin() );

-- ============================================================
--  ONE-TIME SETUP: make yourself an admin.
--  1) Sign up / sign in once via parent-login.html with the
--     email you want to be the admin (e.g. admin@philidorchessacademy.in).
--  2) Find your user id:  Authentication -> Users -> copy the UUID.
--  3) Run (replace the UUID):
--        insert into public.admins (user_id)
--        values ('PASTE-YOUR-USER-UUID-HERE')
--        on conflict do nothing;
-- ============================================================
