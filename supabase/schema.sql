-- ============================================================
--  Philidor Chess Academy — Parent Portal database schema
--  Run this ONCE in your Supabase project:
--    Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
-- ============================================================

-- ------------------------------------------------------------
--  profiles: one row per parent account.
--  Passwords are NOT stored here — Supabase Auth stores them
--  securely (bcrypt-hashed) in the protected auth.users table.
--  This table only holds the extra profile details we collect.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  full_name    text,
  phone        text,
  child_name   text,
  child_level  text,
  created_at   timestamptz not null default now()
);

-- ------------------------------------------------------------
--  Row Level Security: each parent can only see / edit
--  their OWN profile row. This is what makes exposing the
--  anon key in the frontend safe.
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "Parents can view own profile"   on public.profiles;
drop policy if exists "Parents can insert own profile"  on public.profiles;
drop policy if exists "Parents can update own profile"  on public.profiles;

create policy "Parents can view own profile"
  on public.profiles for select
  using ( auth.uid() = id );

create policy "Parents can insert own profile"
  on public.profiles for insert
  with check ( auth.uid() = id );

create policy "Parents can update own profile"
  on public.profiles for update
  using ( auth.uid() = id );

-- ------------------------------------------------------------
--  Auto-create a profile row whenever a new auth user signs up.
--  The extra fields (full_name, phone, child_name, child_level)
--  are passed from the signup form via auth metadata.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, child_name, child_level)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'child_name',
    new.raw_user_meta_data ->> 'child_level'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
