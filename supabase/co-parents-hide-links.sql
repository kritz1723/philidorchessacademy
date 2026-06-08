-- ============================================================
--  Philidor Chess Academy — hide co-parent links from parents
--  Co-parent links (child_guardians) are visible to ADMINS ONLY.
--  Neither parent can see that another parent also monitors a child.
--
--  The parent dashboard uses get_my_children() (security definer) and
--  never reads child_guardians directly, so nothing breaks.
--
--  Idempotent. Supabase -> SQL Editor -> paste -> Run.
-- ============================================================

-- remove the policy that let a guardian read their own child's links
drop policy if exists "read guardian links" on public.child_guardians;

-- ensure admin-only access (covers select/insert/update/delete)
drop policy if exists "admin writes guardians"   on public.child_guardians;
drop policy if exists "admin manages guardians"   on public.child_guardians;
create policy "admin manages guardians" on public.child_guardians for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- refresh PostgREST so the change takes effect immediately
notify pgrst, 'reload schema';
