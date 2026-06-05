-- ============================================================
--  Philidor Chess Academy — Multi-child upgrade
--  Run AFTER schema.sql and stats-schema.sql.
--  Supabase -> SQL Editor -> New query -> paste -> Run.
--  Safe to run multiple times.
-- ============================================================

-- ------------------------------------------------------------
--  children: many children per parent.
-- ------------------------------------------------------------
create table if not exists public.children (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  level       text,
  created_at  timestamptz not null default now()
);
create index if not exists children_parent_idx on public.children (parent_id);

alter table public.children enable row level security;

drop policy if exists "parent or admin reads children"  on public.children;
drop policy if exists "parent or admin inserts children" on public.children;
drop policy if exists "parent or admin updates children" on public.children;
drop policy if exists "parent or admin deletes children" on public.children;

-- Parents see/manage their own children; admins manage all.
create policy "parent or admin reads children"
  on public.children for select
  using ( auth.uid() = parent_id or public.is_admin() );

create policy "parent or admin inserts children"
  on public.children for insert
  with check ( auth.uid() = parent_id or public.is_admin() );

create policy "parent or admin updates children"
  on public.children for update
  using ( auth.uid() = parent_id or public.is_admin() );

create policy "parent or admin deletes children"
  on public.children for delete
  using ( auth.uid() = parent_id or public.is_admin() );

-- ------------------------------------------------------------
--  Re-key student_stats to a CHILD (was keyed to the parent).
--  Add child_id, backfill, then make it the identity column.
-- ------------------------------------------------------------
alter table public.student_stats
  add column if not exists child_id uuid references public.children (id) on delete cascade;

-- ------------------------------------------------------------
--  Migrate existing data: create one child per profile that had
--  a child_name, and attach any existing stats row to that child.
-- ------------------------------------------------------------
do $$
declare r record; new_child uuid;
begin
  for r in
    select p.id as parent_id, p.child_name, p.child_level
    from public.profiles p
    where coalesce(p.child_name,'') <> ''
      and not exists (select 1 from public.children c where c.parent_id = p.id)
  loop
    insert into public.children (parent_id, name, level)
    values (r.parent_id, r.child_name, r.child_level)
    returning id into new_child;

    -- attach the parent's old stats row (if any) to this new child
    update public.student_stats
      set child_id = new_child
      where parent_id = r.parent_id and child_id is null;
  end loop;
end $$;

-- New stats rows are identified by child_id going forward.
create unique index if not exists student_stats_child_uidx
  on public.student_stats (child_id);

-- ------------------------------------------------------------
--  RLS for student_stats based on child ownership.
--  (Replaces the parent_id-based policies from stats-schema.sql.)
-- ------------------------------------------------------------
drop policy if exists "parent or admin reads stats" on public.student_stats;
drop policy if exists "admin inserts stats"         on public.student_stats;
drop policy if exists "admin updates stats"         on public.student_stats;
drop policy if exists "owner or admin reads stats"  on public.student_stats;
drop policy if exists "admin writes stats insert"   on public.student_stats;
drop policy if exists "admin writes stats update"   on public.student_stats;

-- A parent may read stats for a child they own; admins read all.
create policy "owner or admin reads stats"
  on public.student_stats for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.children c
      where c.id = student_stats.child_id and c.parent_id = auth.uid()
    )
  );

-- Only admins create/update stats.
create policy "admin writes stats insert"
  on public.student_stats for insert
  with check ( public.is_admin() );

create policy "admin writes stats update"
  on public.student_stats for update
  using ( public.is_admin() );
