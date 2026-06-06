-- ============================================================
--  Philidor Chess Academy — key student_stats by CHILD, not parent
--
--  The original student_stats table used parent_id as its PRIMARY
--  KEY, which allows only ONE stats row per parent. Families with
--  more than one child (e.g. siblings) then collide: the first
--  child's row is written, and every sibling's insert fails with
--    duplicate key value violates unique constraint "student_stats_pkey"
--
--  This migration repoints the table so there is one row PER CHILD:
--    • ensures a child_id column linked to children(id)
--    • drops the parent_id primary key
--    • makes child_id the primary key (one stats row per child)
--    • keeps parent_id as a normal column (still used by RLS)
--
--  Idempotent. Safe to run multiple times.
--  Supabase -> SQL Editor -> paste -> Run.
-- ============================================================

-- 1. Make sure the child_id column exists and points at children.
alter table public.student_stats
  add column if not exists child_id uuid references public.children (id) on delete cascade;

-- 2. Remove any stale rows that predate per-child stats (no child_id).
--    These are leftovers from the old per-parent design and cannot be
--    promoted to a child-keyed row.
delete from public.student_stats where child_id is null;

-- 3. Swap the primary key from parent_id to child_id.
do $$
begin
  -- drop the old parent-keyed primary key if it is still in place
  if exists (
    select 1
    from   pg_constraint
    where  conrelid = 'public.student_stats'::regclass
    and    contype  = 'p'
    and    conname  = 'student_stats_pkey'
  ) then
    -- only drop if it is NOT already keyed on child_id
    if not exists (
      select 1
      from   pg_index i
      join   pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
      where  i.indrelid = 'public.student_stats'::regclass
      and    i.indisprimary
      and    a.attname = 'child_id'
    ) then
      alter table public.student_stats drop constraint student_stats_pkey;
    end if;
  end if;

  -- child_id must be non-null to serve as the primary key
  alter table public.student_stats alter column child_id set not null;

  -- add the new child-keyed primary key if the table has no PK yet
  if not exists (
    select 1
    from   pg_constraint
    where  conrelid = 'public.student_stats'::regclass
    and    contype  = 'p'
  ) then
    alter table public.student_stats
      add constraint student_stats_pkey primary key (child_id);
  end if;
end $$;

-- 4. parent_id is no longer the key, but RLS still reads it, so it must
--    stay populated. Keep it NOT NULL (the importer/admin always set it).
--    (No change needed; documented here for clarity.)
