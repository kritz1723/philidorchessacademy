-- ============================================================
--  Philidor Chess Academy — co-parents / guardians per child
--  Lets a child be linked to MORE THAN ONE parent account, so
--  either guardian who logs in can view that child's dashboard,
--  stats, notes and assigned materials.
--
--  The child's original parent (children.parent_id) remains the
--  "owner"; extra guardians are listed in child_guardians.
--
--  Idempotent. Supabase -> SQL Editor -> paste -> Run.
-- ============================================================

-- 1) join table: which user accounts may view which child
create table if not exists public.child_guardians (
  child_id uuid not null references public.children (id) on delete cascade,
  user_id  uuid not null references auth.users (id)   on delete cascade,
  added_at timestamptz not null default now(),
  primary key (child_id, user_id)
);
create index if not exists cg_user_idx  on public.child_guardians (user_id);
alter table public.child_guardians enable row level security;

-- 2) helper: can the current user see this child? (owner, guardian or admin)
--    SECURITY DEFINER so it can check freely without RLS recursion.
create or replace function public.can_access_child(p_child uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select
    public.is_admin()
    or exists (select 1 from public.children c
               where c.id = p_child and c.parent_id = auth.uid())
    or exists (select 1 from public.child_guardians g
               where g.child_id = p_child and g.user_id = auth.uid());
$$;

-- 3) RLS on child_guardians: viewers can read their links; admins manage.
drop policy if exists "read guardian links"   on public.child_guardians;
create policy "read guardian links" on public.child_guardians for select
  using ( public.can_access_child(child_id) );
drop policy if exists "admin writes guardians" on public.child_guardians;
create policy "admin writes guardians" on public.child_guardians for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- 4) Extra READ policies so a guardian sees the child's data.
--    (Permissive policies are OR-ed with the existing owner/admin ones.)
drop policy if exists "guardian reads child" on public.children;
create policy "guardian reads child" on public.children for select
  using ( exists (select 1 from public.child_guardians g
                  where g.child_id = children.id and g.user_id = auth.uid()) );

drop policy if exists "guardian reads stats" on public.student_stats;
create policy "guardian reads stats" on public.student_stats for select
  using ( exists (select 1 from public.child_guardians g
                  where g.child_id = student_stats.child_id and g.user_id = auth.uid()) );

drop policy if exists "guardian reads history" on public.stats_history;
create policy "guardian reads history" on public.stats_history for select
  using ( exists (select 1 from public.child_guardians g
                  where g.child_id = stats_history.child_id and g.user_id = auth.uid()) );

drop policy if exists "guardian reads notes" on public.coach_notes;
create policy "guardian reads notes" on public.coach_notes for select
  using ( exists (select 1 from public.child_guardians g
                  where g.child_id = coach_notes.child_id and g.user_id = auth.uid()) );

-- 5) Children a signed-in user may view (owner OR guardian) — used by the
--    dashboard so co-parents see the same kids.
create or replace function public.get_my_children()
returns setof public.children
language sql stable security definer set search_path = public
as $$
  select c.* from public.children c
  where c.parent_id = auth.uid()
     or exists (select 1 from public.child_guardians g
                where g.child_id = c.id and g.user_id = auth.uid())
  order by c.created_at;
$$;

-- 6) Materials visible for a child — now aware of guardians.
--    A guardian sees the same released+assigned materials the family sees.
create or replace function public.get_visible_materials(p_child uuid)
returns table (
  id uuid, topic_id uuid, title text, description text, url text,
  storage_path text, sort_order int,
  topic_name text, topic_description text, topic_sort int
)
language sql security definer stable set search_path = public
as $$
  with eff as (
    -- evaluate parent-level assignments as the child's OWNER when the
    -- caller may access the child (owner, guardian or admin preview);
    -- otherwise as the caller themselves.
    select case
             when p_child is not null and public.can_access_child(p_child)
               then (select c.parent_id from public.children c where c.id = p_child)
             else auth.uid()
           end as parent_id
  )
  select m.id, m.topic_id, m.title, m.description, m.url, m.storage_path, m.sort_order,
         t.name, t.description, t.sort_order
  from public.topic_materials m
  join public.topics t on t.id = m.topic_id
  cross join eff
  where
    (public.is_admin() and p_child is null)
    or (
      (m.is_released or (m.release_at is not null and m.release_at <= now()))
      and (
        m.assign_all
        or exists (
          select 1 from public.material_assignments a
          where a.material_id = m.id
            and ( a.parent_id = eff.parent_id
               or ( p_child is not null and a.child_id = p_child
                    and public.can_access_child(p_child) ) )
        )
      )
    )
  order by t.sort_order, t.created_at, m.sort_order, m.created_at;
$$;
