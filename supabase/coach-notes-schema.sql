-- ============================================================
--  Philidor Chess Academy — Coach's notes as dated entries
--  Replaces the single free-text coach_notes field on student_stats
--  with a log of timestamped entries (one row per note), so the
--  parent dashboard can show a running record like "child records".
--
--  Idempotent. Supabase -> SQL Editor -> paste -> Run.
-- ============================================================
create table if not exists public.coach_notes (
  id         uuid primary key default gen_random_uuid(),
  child_id   uuid not null references public.children (id) on delete cascade,
  body       text not null,
  author_id  uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists coach_notes_child_idx
  on public.coach_notes (child_id, created_at desc);

alter table public.coach_notes enable row level security;

-- Parents read notes for their own children; admins read all.
drop policy if exists "read coach notes" on public.coach_notes;
create policy "read coach notes" on public.coach_notes for select
  using (
    public.is_admin()
    or exists (select 1 from public.children c
               where c.id = child_id and c.parent_id = auth.uid())
  );

-- Only admins write notes.
drop policy if exists "admin writes coach notes"  on public.coach_notes;
create policy "admin writes coach notes" on public.coach_notes for insert
  with check (public.is_admin());

drop policy if exists "admin deletes coach notes" on public.coach_notes;
create policy "admin deletes coach notes" on public.coach_notes for delete
  using (public.is_admin());
