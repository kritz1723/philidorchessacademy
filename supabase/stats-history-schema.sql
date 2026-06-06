-- ============================================================
--  Philidor Chess Academy — stats history (for progress trends)
--  Stores a snapshot of each child's stats on every sync so the
--  dashboard can show trends + "what changed since last update".
--  Run AFTER the earlier schema files. Idempotent.
--  Supabase -> SQL Editor -> paste -> Run.
-- ============================================================
create table if not exists public.stats_history (
  id                 uuid primary key default gen_random_uuid(),
  child_id           uuid not null references public.children(id) on delete cascade,
  captured_at        timestamptz not null default now(),
  attendance_pct     int,
  leaderboard_points int,
  hours_in_classroom numeric,
  games_played       int,
  wins               int,
  losses             int,
  draws              int,
  quizzes_completed  int,
  problems_solved    int,
  quiz_points        int,
  tournaments_played int
);
create index if not exists sh_child_idx on public.stats_history(child_id, captured_at);

alter table public.stats_history enable row level security;

-- Parents read their own child's history; admins read all.
drop policy if exists "read child history" on public.stats_history;
create policy "read child history" on public.stats_history for select using (
  public.is_admin()
  or exists (select 1 from public.children c where c.id = child_id and c.parent_id = auth.uid())
);

-- The sync bot inserts via the service_role key (bypasses RLS).
-- Admins may also insert manually.
drop policy if exists "admin insert history" on public.stats_history;
create policy "admin insert history" on public.stats_history for insert with check ( public.is_admin() );
