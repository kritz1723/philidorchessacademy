-- ============================================================
--  Philidor Chess Academy — File uploads (Supabase Storage)
--  Run AFTER materials-schema.sql.
--  Supabase -> SQL Editor -> New query -> paste -> Run.
--  Safe to run multiple times.
-- ============================================================
--
--  This sets up a PRIVATE storage bucket "materials" and the
--  access rules. Files are private: the app generates short-lived
--  signed URLs so only signed-in parents can open them.
--
--  We also add a storage_path column to remember which object a
--  material row points to (so we can sign a URL on demand).
-- ============================================================

-- 1) Create a private bucket named "materials" (id = name).
insert into storage.buckets (id, name, public)
values ('materials', 'materials', false)
on conflict (id) do update set public = false;

-- 2) Remember the uploaded object path on each material row.
alter table public.session_materials
  add column if not exists storage_path text;
alter table public.open_materials
  add column if not exists storage_path text;

--    A material may now point to EITHER a url OR an uploaded file,
--    so url is no longer required. (Was NOT NULL.)
alter table public.session_materials alter column url drop not null;

-- 3) Storage RLS policies on storage.objects for this bucket.
--    - Only admins can upload / change / delete files.
--    - Any signed-in (authenticated) user may READ objects, which
--      is what lets the app mint signed URLs for them. Privacy of
--      WHICH file a parent can see is enforced by the material
--      tables' own RLS (a parent only learns the path of files
--      assigned to them / their child, or open materials).
drop policy if exists "materials admin upload"  on storage.objects;
drop policy if exists "materials admin update"  on storage.objects;
drop policy if exists "materials admin delete"  on storage.objects;
drop policy if exists "materials signed read"   on storage.objects;

create policy "materials admin upload"
  on storage.objects for insert to authenticated
  with check ( bucket_id = 'materials' and public.is_admin() );

create policy "materials admin update"
  on storage.objects for update to authenticated
  using ( bucket_id = 'materials' and public.is_admin() );

create policy "materials admin delete"
  on storage.objects for delete to authenticated
  using ( bucket_id = 'materials' and public.is_admin() );

create policy "materials signed read"
  on storage.objects for select to authenticated
  using ( bucket_id = 'materials' );
