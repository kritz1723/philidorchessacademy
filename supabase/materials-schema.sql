-- ============================================================
--  Philidor Chess Academy — Materials & Products
--  Run AFTER children-schema.sql.
--  Supabase -> SQL Editor -> New query -> paste -> Run.
--  Safe to run multiple times.
-- ============================================================

-- ------------------------------------------------------------
--  session_materials: private material the admin builds (HTML
--  pages / links) and maps to a parent OR a specific child.
--  Exactly one of (parent_id, child_id) is set per assignment.
-- ------------------------------------------------------------
create table if not exists public.session_materials (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  url         text not null,                 -- link or path to the HTML page
  session_no  text,                           -- optional label e.g. "Session 4"
  parent_id   uuid references auth.users (id) on delete cascade,
  child_id    uuid references public.children (id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint one_target check (
    (parent_id is not null and child_id is null) or
    (parent_id is null and child_id is not null)
  )
);
create index if not exists sm_parent_idx on public.session_materials (parent_id);
create index if not exists sm_child_idx  on public.session_materials (child_id);

alter table public.session_materials enable row level security;

drop policy if exists "read own session materials" on public.session_materials;
drop policy if exists "admin writes session materials insert" on public.session_materials;
drop policy if exists "admin writes session materials update" on public.session_materials;
drop policy if exists "admin writes session materials delete" on public.session_materials;

-- A parent can read material mapped to them OR to one of their children; admins read all.
create policy "read own session materials"
  on public.session_materials for select
  using (
    public.is_admin()
    or parent_id = auth.uid()
    or exists (select 1 from public.children c where c.id = session_materials.child_id and c.parent_id = auth.uid())
  );

create policy "admin writes session materials insert"
  on public.session_materials for insert with check ( public.is_admin() );
create policy "admin writes session materials update"
  on public.session_materials for update using ( public.is_admin() );
create policy "admin writes session materials delete"
  on public.session_materials for delete using ( public.is_admin() );

-- ------------------------------------------------------------
--  open_materials: generic "Open Source Reference Materials"
--  (books, videos, links) visible to ALL signed-in parents.
-- ------------------------------------------------------------
create table if not exists public.open_materials (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  author      text,
  kind        text default 'Book',           -- Book | Video | Article | Other
  url         text,
  description text,
  sort_order  int default 0,
  created_at  timestamptz not null default now()
);
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

-- ------------------------------------------------------------
--  products: Amazon (or other) purchase links for parents.
-- ------------------------------------------------------------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  price       text,                            -- free-text e.g. "₹499"
  image_url   text,
  buy_url     text not null,
  sort_order  int default 0,
  created_at  timestamptz not null default now()
);
alter table public.products enable row level security;

drop policy if exists "anyone signed-in reads products" on public.products;
drop policy if exists "admin writes products insert" on public.products;
drop policy if exists "admin writes products update" on public.products;
drop policy if exists "admin writes products delete" on public.products;

create policy "anyone signed-in reads products"
  on public.products for select using ( auth.role() = 'authenticated' );
create policy "admin writes products insert" on public.products for insert with check ( public.is_admin() );
create policy "admin writes products update" on public.products for update using ( public.is_admin() );
create policy "admin writes products delete" on public.products for delete using ( public.is_admin() );
