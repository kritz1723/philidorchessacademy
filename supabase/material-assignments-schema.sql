-- ============================================================
--  Philidor Chess Academy — Material-level assignment + release
--  Run AFTER topics-schema.sql. Supabase -> SQL Editor -> Run.
--  Safe to run multiple times (idempotent).
--
--  Adds:
--   * per-material RELEASE control (manual toggle + optional
--     auto-release date) so you reveal materials as you cover them;
--   * per-material ASSIGNMENT (each material is assigned to people
--     on its own — fully independent of the topic).
--
--  Visibility of a material to a parent (for the active child):
--     released  AND  (assigned to them at material level OR assign_all)
--  The topic is now just the grouping/heading.
-- ============================================================

-- ---- 1) new columns on topic_materials ----
alter table public.topic_materials
  add column if not exists assign_all  boolean     not null default false,
  add column if not exists is_released boolean     not null default false,
  add column if not exists release_at  timestamptz;

-- ---- 2) per-material assignments ----
create table if not exists public.material_assignments (
  id          uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.topic_materials(id) on delete cascade,
  parent_id   uuid references auth.users(id)      on delete cascade,
  child_id    uuid references public.children(id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint ma_one_target check (
    (parent_id is not null and child_id is null) or
    (parent_id is null and child_id is not null)
  )
);
create index if not exists ma_mat_idx    on public.material_assignments(material_id);
create index if not exists ma_parent_idx on public.material_assignments(parent_id);
create index if not exists ma_child_idx  on public.material_assignments(child_id);
create unique index if not exists ma_uniq_parent
  on public.material_assignments(material_id, parent_id) where parent_id is not null;
create unique index if not exists ma_uniq_child
  on public.material_assignments(material_id, child_id)  where child_id  is not null;

-- ---- 3) RLS (admin-only; parent visibility flows via the RPC below) ----
alter table public.material_assignments enable row level security;
drop policy if exists "admin reads m-assignments" on public.material_assignments;
drop policy if exists "admin m-assign insert"     on public.material_assignments;
drop policy if exists "admin m-assign update"     on public.material_assignments;
drop policy if exists "admin m-assign delete"     on public.material_assignments;
create policy "admin reads m-assignments" on public.material_assignments for select using ( public.is_admin() );
create policy "admin m-assign insert"     on public.material_assignments for insert with check ( public.is_admin() );
create policy "admin m-assign update"     on public.material_assignments for update using ( public.is_admin() );
create policy "admin m-assign delete"     on public.material_assignments for delete using ( public.is_admin() );

-- ---- 4) helper: is a material released right now? ----
create or replace function public.is_material_released(m public.topic_materials)
returns boolean
language sql immutable
as $$
  select m.is_released or (m.release_at is not null and m.release_at <= now());
$$;

-- ---- 5) RPC: materials visible to the parent for the active child ----
--      Released AND assigned (or assign_all). Admins see everything.
--      Returns the topic fields too so the dashboard can group them.
create or replace function public.get_visible_materials(p_child uuid)
returns table (
  id                uuid,
  topic_id          uuid,
  title             text,
  description       text,
  url               text,
  storage_path      text,
  sort_order        int,
  topic_name        text,
  topic_description text,
  topic_sort        int
)
language sql security definer stable set search_path = public
as $$
  select m.id, m.topic_id, m.title, m.description, m.url, m.storage_path, m.sort_order,
         t.name, t.description, t.sort_order
  from public.topic_materials m
  join public.topics t on t.id = m.topic_id
  where
    public.is_admin()
    or (
      (m.is_released or (m.release_at is not null and m.release_at <= now()))
      and (
        m.assign_all
        or exists (
          select 1 from public.material_assignments a
          where a.material_id = m.id
            and ( a.parent_id = auth.uid()
               or ( p_child is not null and a.child_id = p_child
                    and exists (select 1 from public.children c
                                where c.id = p_child and c.parent_id = auth.uid()) ) )
        )
      )
    )
  order by t.sort_order, t.created_at, m.sort_order, m.created_at;
$$;
