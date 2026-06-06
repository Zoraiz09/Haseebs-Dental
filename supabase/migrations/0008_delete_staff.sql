-- =====================================================================
-- Noor Dentofacial Clinic — 0008 Admin: delete staff account
-- =====================================================================
-- A SECURITY DEFINER function lets an ADMIN permanently delete a staff
-- member's login (auth user) + their provider row. Deleting the auth
-- user cascades to public.profiles (FK on delete cascade).
-- Deactivation (is_active=false) is handled app-side via admin RLS and
-- does not need this function.
-- =====================================================================

create or replace function public.delete_staff(target uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Only admins, and never yourself.
  if not public.has_role(array['ADMIN']::user_role[]) then
    raise exception 'Only admins can delete staff accounts';
  end if;
  if target = auth.uid() then
    raise exception 'You cannot delete your own account';
  end if;

  delete from public.providers where profile_id = target;
  delete from auth.users where id = target;   -- cascades to public.profiles
end;
$$;

grant execute on function public.delete_staff(uuid) to authenticated;
