-- ============================================================
--  Philidor Chess Academy — Topics (replaces flat Session Material)
--  Run AFTER all earlier SQL files (schema, children, stats,
--  materials, storage). Supabase -> SQL Editor -> Run.
--  Safe to run multiple times (idempotent).
-- ============================================================

-- ---- Safety: ensure is_admin() exists (from stats-schema.sql) ----
create or replace function public.is_admin()
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ============================================================
--  REPAIR: products + open_materials RLS (idempotent)
--  Fixes "new row violates row-level security policy for
--  table products" by recreating the policies cleanly.
-- ============================================================
alter table public.products enable row level security;
drop policy if exists "anyone signed-in reads products" on public.products;
drop policy if exists "admin writes products insert"     on public.products;
drop policy if exists "admin writes products update"     on public.products;
drop policy if exists "admin writes products delete"     on public.products;
create policy "anyone signed-in reads products"
  on public.products for select using ( auth.role() = 'authenticated' );
create policy "admin writes products insert" on public.products for insert with check ( public.is_admin() );
create policy "admin writes products update" on public.products for update using ( public.is_admin() );
create policy "admin writes products delete" on public.products for delete using ( public.is_admin() );

alter table public.open_materials enable row level security;
drop policy if exists "anyone signed-in reads open materials" on public.open_materials;
drop policy if exists "admin writes open insert" on public.open_materials;
drop policy if exists "admin writes open update" on public.open_materials;
drop policy if exists "admin writes open delete" on public.open_materials;
create policy "anyone signed-in reads open materials"
  on public.open_materials for select using ( auth.role() = 'authenticated' );
create policy "admin writes open insert" on public.open_materials for insert with check ( public.is_admin() );
create policy "admin writes open update" on public.open_materials for update using ( public.is_admin() );
create policy "admin writes open delete" on public.open_materials for delete using ( public.is_admin() );

-- ============================================================
--  TOPICS
-- ============================================================
create table if not exists public.topics (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  assign_all  boolean not null default false,   -- visible to ALL parents
  sort_order  int default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.topic_materials (
  id           uuid primary key default gen_random_uuid(),
  topic_id     uuid not null references public.topics(id) on delete cascade,
  title        text not null,
  description  text,
  url          text,            -- EITHER a url/page path …
  storage_path text,            -- … OR an uploaded file in the 'materials' bucket
  sort_order   int default 0,
  created_at   timestamptz not null default now()
);
create index if not exists tm_topic_idx on public.topic_materials(topic_id);

create table if not exists public.topic_assignments (
  id         uuid primary key default gen_random_uuid(),
  topic_id   uuid not null references public.topics(id) on delete cascade,
  parent_id  uuid references auth.users(id) on delete cascade,
  child_id   uuid references public.children(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint ta_one_target check (
    (parent_id is not null and child_id is null) or
    (parent_id is null and child_id is not null)
  )
);
create index if not exists ta_topic_idx  on public.topic_assignments(topic_id);
create index if not exists ta_parent_idx on public.topic_assignments(parent_id);
create index if not exists ta_child_idx  on public.topic_assignments(child_id);
-- Prevent duplicate assignment of the same person to the same topic.
create unique index if not exists ta_uniq_parent
  on public.topic_assignments(topic_id, parent_id) where parent_id is not null;
create unique index if not exists ta_uniq_child
  on public.topic_assignments(topic_id, child_id)  where child_id  is not null;

-- ------------------------------------------------------------
--  Helper: can the current user see this topic?
--  (admin, or topic is assign_all, or assigned to them / a child
--   they own). SECURITY DEFINER so parents don't need direct read
--   access to topic_assignments.
-- ------------------------------------------------------------
create or replace function public.can_see_topic(t_id uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select public.is_admin()
      or exists (select 1 from public.topics t where t.id = t_id and t.assign_all)
      or exists (
           select 1 from public.topic_assignments a
           where a.topic_id = t_id
             and ( a.parent_id = auth.uid()
                or exists (select 1 from public.children c
                           where c.id = a.child_id and c.parent_id = auth.uid()) )
         );
$$;

-- ------------------------------------------------------------
--  RPC: topics visible to the parent for a given ACTIVE child.
--  Honors active-child scoping (a topic assigned to child B does
--  not show while child A is active). p_child may be null.
-- ------------------------------------------------------------
create or replace function public.get_visible_topics(p_child uuid)
returns setof public.topics
language sql security definer stable set search_path = public
as $$
  select t.* from public.topics t
  where public.is_admin()
     or t.assign_all
     or exists (
          select 1 from public.topic_assignments a
          where a.topic_id = t.id
            and ( a.parent_id = auth.uid()
               or (p_child is not null and a.child_id = p_child
                   and exists (select 1 from public.children c
                               where c.id = p_child and c.parent_id = auth.uid())) )
        )
  order by t.sort_order, t.created_at;
$$;

-- ============================================================
--  RLS
-- ============================================================
alter table public.topics            enable row level security;
alter table public.topic_materials   enable row level security;
alter table public.topic_assignments enable row level security;

-- topics
drop policy if exists "see topics"          on public.topics;
drop policy if exists "admin topics insert" on public.topics;
drop policy if exists "admin topics update" on public.topics;
drop policy if exists "admin topics delete" on public.topics;
create policy "see topics"          on public.topics for select using ( public.can_see_topic(id) );
create policy "admin topics insert" on public.topics for insert with check ( public.is_admin() );
create policy "admin topics update" on public.topics for update using ( public.is_admin() );
create policy "admin topics delete" on public.topics for delete using ( public.is_admin() );

-- topic_materials
drop policy if exists "see topic materials"          on public.topic_materials;
drop policy if exists "admin topic materials insert" on public.topic_materials;
drop policy if exists "admin topic materials update" on public.topic_materials;
drop policy if exists "admin topic materials delete" on public.topic_materials;
create policy "see topic materials"          on public.topic_materials for select using ( public.can_see_topic(topic_id) );
create policy "admin topic materials insert" on public.topic_materials for insert with check ( public.is_admin() );
create policy "admin topic materials update" on public.topic_materials for update using ( public.is_admin() );
create policy "admin topic materials delete" on public.topic_materials for delete using ( public.is_admin() );

-- topic_assignments (admin-only; parents' visibility flows through can_see_topic)
drop policy if exists "admin reads assignments"   on public.topic_assignments;
drop policy if exists "admin assign insert"       on public.topic_assignments;
drop policy if exists "admin assign update"       on public.topic_assignments;
drop policy if exists "admin assign delete"       on public.topic_assignments;
create policy "admin reads assignments" on public.topic_assignments for select using ( public.is_admin() );
create policy "admin assign insert"     on public.topic_assignments for insert with check ( public.is_admin() );
create policy "admin assign update"     on public.topic_assignments for update using ( public.is_admin() );
create policy "admin assign delete"     on public.topic_assignments for delete using ( public.is_admin() );
