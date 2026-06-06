-- ============================================================
--  Philidor Chess Academy — admin-approved sign-ups
--  New parent accounts are created in a PENDING state (is_active
--  = false) and cannot enter the portal until an admin approves
--  them in Admin → People (toggle Active).
--
--  This recreates the new-user trigger so every fresh signup is
--  inactive by default. Existing accounts are unaffected.
--
--  Idempotent. Supabase -> SQL Editor -> paste -> Run.
--  (Run AFTER admin-management-schema.sql, which adds is_active.)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, child_name, child_level, is_active)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'child_name',
    new.raw_user_meta_data ->> 'child_level',
    false          -- pending: awaiting admin approval
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
