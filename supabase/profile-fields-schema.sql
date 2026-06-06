-- ============================================================
--  Philidor Chess Academy — extra parent profile fields
--  Adds preferred name + time zone (full_name, phone already exist).
--  Run anytime. Idempotent. Supabase -> SQL Editor -> Run.
-- ============================================================
alter table public.profiles
  add column if not exists preferred_name text,
  add column if not exists timezone       text;
