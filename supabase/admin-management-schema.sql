-- ============================================================
--  Philidor Chess Academy — Admin management
--  Lets admins deactivate a parent's login and delete a child.
--  Run AFTER the earlier schema files. Idempotent.
--  Supabase -> SQL Editor -> paste -> Run.
-- ============================================================

-- 1) Parent active flag (deactivation = app-level block in the portal).
alter table public.profiles
  add column if not exists is_active boolean not null default true;

-- 2) Admins can read every profile and toggle is_active.
--    (Existing self-access policies remain; these are additive.)
drop policy if exists "admin reads all profiles"  on public.profiles;
drop policy if exists "admin updates profiles"     on public.profiles;
create policy "admin reads all profiles" on public.profiles
  for select using ( public.is_admin() );
create policy "admin updates profiles" on public.profiles
  for update using ( public.is_admin() ) with check ( public.is_admin() );

-- 3) Admins can read / update / delete any child.
drop policy if exists "admin reads children"   on public.children;
drop policy if exists "admin updates children" on public.children;
drop policy if exists "admin deletes children" on public.children;
create policy "admin reads children"   on public.children for select using ( public.is_admin() );
create policy "admin updates children" on public.children for update using ( public.is_admin() );
create policy "admin deletes children" on public.children for delete using ( public.is_admin() );

-- 4) Admins can delete a child's stats (so deleting a kid is clean even
--    if the FK isn't ON DELETE CASCADE). topic/material assignments are
--    already ON DELETE CASCADE from children.
drop policy if exists "admin deletes stats" on public.student_stats;
create policy "admin deletes stats" on public.student_stats
  for delete using ( public.is_admin() );
