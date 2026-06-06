-- =====================================================================
-- Noor Dentofacial Clinic — 0002 Profiles, Providers & Auth Helpers
-- =====================================================================
-- Maps the Prisma `User` + `Provider` models onto Supabase auth.
-- A profile mirrors auth.users 1:1 and carries the staff role.
-- Helper functions back the Row-Level-Security policies in 0004.
-- =====================================================================

-- ---------------------------------------------------------------------
-- profiles  (Prisma: User)  — one row per staff auth account
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text        not null default '',
  email       text        unique,
  phone       text,
  role        user_role   not null default 'RECEPTIONIST',
  avatar_url  text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is 'Staff accounts (ADMIN/DOCTOR/RECEPTIONIST). 1:1 with auth.users.';

-- ---------------------------------------------------------------------
-- providers  (Prisma: Provider) — clinical practitioner directory.
-- A DOCTOR profile links to a provider row (specialty, title, primary).
-- providers may also exist without a login (e.g. visiting consultant).
-- ---------------------------------------------------------------------
create table if not exists public.providers (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid        unique references public.profiles (id) on delete set null,
  full_name   text        not null,
  title       text,                       -- e.g. "Senior Facial Aesthetic Specialist"
  specialty   specialty_type,             -- primary specialty; null = general
  is_primary  boolean     not null default false,
  avatar_url  text,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.providers is 'Doctors/practitioners. Bills attribute a doctor share here for earnings.';

create index if not exists providers_profile_idx on public.providers (profile_id);

-- ---------------------------------------------------------------------
-- Auth helper functions (SECURITY DEFINER to avoid RLS recursion)
-- ---------------------------------------------------------------------

-- Returns the role of the currently authenticated user.
-- (Named auth_role, not current_role — current_role is a reserved word.)
create or replace function public.auth_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- True if the current user holds any of the supplied roles.
create or replace function public.has_role(roles user_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = any(roles) and is_active
  );
$$;

-- Convenience: provider id owned by the current (doctor) user, if any.
create or replace function public.current_provider_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.providers where profile_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- updated_at trigger helper (reused by every table below)
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Auto-provision a profile when a new auth user is created.
-- Role + name are taken from sign-up metadata (raw_user_meta_data).
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    coalesce((new.raw_user_meta_data ->> 'role')::user_role, 'RECEPTIONIST')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger providers_set_updated_at
  before update on public.providers
  for each row execute function public.set_updated_at();
