-- =====================================================================
-- Noor Dentofacial Clinic - COMPLETE database setup (one-paste)
-- Generated from migrations/ + seed.sql. Paste the whole file into the
-- Supabase SQL Editor and click Run. No CREATE EXTENSION required.
-- =====================================================================


-- >>>>>>>>>>>>>>>>>>>> migrations\0001_extensions_and_enums.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0001 Extensions & Enums
-- =====================================================================
-- Foundational types shared across the schema. Run first.
-- =====================================================================

-- No CREATE EXTENSION needed: we use the built-in gen_random_uuid()
-- (Postgres 13+ core) for ids and plain text for emails. This avoids the
-- "cannot execute CREATE EXTENSION in a read-only transaction" error in
-- the Supabase SQL editor. (uuid-ossp / pgcrypto / citext not required.)

-- Staff roles. There is NO patient login role (staff-only app, see description.md Â§4).
do $$ begin
  create type user_role as enum ('ADMIN', 'DOCTOR', 'RECEPTIONIST');
exception when duplicate_object then null; end $$;

-- Clinical specialty â€” drives EMR/Rx form schema (dental vs aesthetic/facial).
do $$ begin
  create type specialty_type as enum ('DENTAL', 'AESTHETIC');
exception when duplicate_object then null; end $$;

-- Appointment lifecycle: book -> confirm -> complete / cancel (+ no-show).
do $$ begin
  create type appointment_status as enum ('BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED', 'NO_SHOW');
exception when duplicate_object then null; end $$;

-- Slot reservation state (held while receptionist completes a booking; cron-expired).
do $$ begin
  create type reservation_status as enum ('HELD', 'CONFIRMED', 'RELEASED', 'EXPIRED');
exception when duplicate_object then null; end $$;

-- Billing status.
do $$ begin
  create type bill_status as enum ('PENDING', 'PARTIAL', 'PAID', 'CANCELLED');
exception when duplicate_object then null; end $$;

-- Prescription template family.
do $$ begin
  create type prescription_type as enum ('DENTAL', 'FACIAL');
exception when duplicate_object then null; end $$;

-- Inventory stock movement direction.
do $$ begin
  create type stock_movement_type as enum ('ADD', 'DEDUCT', 'ADJUST');
exception when duplicate_object then null; end $$;

-- Notification channels (email today; push added for mobile, description.md Â§8).
do $$ begin
  create type notification_channel as enum ('EMAIL', 'PUSH', 'SMS');
exception when duplicate_object then null; end $$;

do $$ begin
  create type notification_status as enum ('QUEUED', 'SENT', 'FAILED');
exception when duplicate_object then null; end $$;


-- >>>>>>>>>>>>>>>>>>>> migrations\0002_profiles_and_helpers.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0002 Profiles, Providers & Auth Helpers
-- =====================================================================
-- Maps the Prisma `User` + `Provider` models onto Supabase auth.
-- A profile mirrors auth.users 1:1 and carries the staff role.
-- Helper functions back the Row-Level-Security policies in 0004.
-- =====================================================================

-- ---------------------------------------------------------------------
-- profiles  (Prisma: User)  â€” one row per staff auth account
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
-- providers  (Prisma: Provider) â€” clinical practitioner directory.
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
-- (Named auth_role, not current_role â€” current_role is a reserved word.)
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


-- >>>>>>>>>>>>>>>>>>>> migrations\0003_core_tables.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0003 Core Domain Tables
-- =====================================================================
-- Patients, scheduling, EMR, prescriptions, billing, inventory,
-- expenses, notifications. Mirrors the Prisma models in description.md Â§2.
-- =====================================================================

-- ---------------------------------------------------------------------
-- patients  (Prisma: Patient)
-- ---------------------------------------------------------------------
create table if not exists public.patients (
  id            uuid primary key default gen_random_uuid(),
  mrn           text unique,                       -- medical record number (human id)
  full_name     text not null,
  phone         text not null,                     -- validated app-side & by check below
  email         text,
  gender        text,
  date_of_birth date,
  address       text,
  photo_url     text,                              -- Supabase Storage path (camera/gallery)
  notes         text,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint patients_phone_format check (phone ~ '^[+0-9 ()-]{7,20}$')
);

create index if not exists patients_name_idx  on public.patients using gin (to_tsvector('simple', full_name));
create index if not exists patients_phone_idx on public.patients (phone);

-- ---------------------------------------------------------------------
-- appointment_types  (Prisma: AppointmentType) â€” duration + pricing
-- ---------------------------------------------------------------------
create table if not exists public.appointment_types (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,                -- "General Check-up", "Tooth Extraction"
  specialty          specialty_type,
  duration_minutes   int  not null default 30 check (duration_minutes > 0),
  consultation_fee   numeric(12,2) not null default 0,
  test_fee           numeric(12,2) not null default 0,
  default_doctor_pct numeric(5,2)  not null default 0 check (default_doctor_pct between 0 and 100),
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- time_slots  (Prisma: TimeSlot) â€” bookable windows per provider
-- ---------------------------------------------------------------------
create table if not exists public.time_slots (
  id           uuid primary key default gen_random_uuid(),
  provider_id  uuid references public.providers (id) on delete cascade,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  is_available boolean not null default true,
  created_at   timestamptz not null default now(),
  constraint time_slots_window check (ends_at > starts_at)
);

create index if not exists time_slots_provider_time_idx on public.time_slots (provider_id, starts_at);

-- ---------------------------------------------------------------------
-- slot_reservations  (Prisma: SlotReservation) â€” short-lived holds
-- A slot is HELD while the receptionist completes a booking; a cron
-- job (0005) expires stale holds. Mirrors web reservation logic.
-- ---------------------------------------------------------------------
create table if not exists public.slot_reservations (
  id           uuid primary key default gen_random_uuid(),
  time_slot_id uuid not null references public.time_slots (id) on delete cascade,
  held_by      uuid references public.profiles (id) on delete set null,
  patient_id   uuid references public.patients (id) on delete set null,
  status       reservation_status not null default 'HELD',
  expires_at   timestamptz not null default (now() + interval '10 minutes'),
  created_at   timestamptz not null default now()
);

create index if not exists slot_reservations_slot_idx   on public.slot_reservations (time_slot_id);
create index if not exists slot_reservations_status_idx on public.slot_reservations (status, expires_at);
-- Only one active hold per slot.
create unique index if not exists slot_reservations_one_active
  on public.slot_reservations (time_slot_id)
  where status = 'HELD';

-- ---------------------------------------------------------------------
-- appointments  (Prisma: Appointment)
-- ---------------------------------------------------------------------
create table if not exists public.appointments (
  id                  uuid primary key default gen_random_uuid(),
  patient_id          uuid not null references public.patients (id) on delete restrict,
  provider_id         uuid references public.providers (id) on delete set null,
  appointment_type_id uuid references public.appointment_types (id) on delete set null,
  time_slot_id        uuid references public.time_slots (id) on delete set null,
  status              appointment_status not null default 'BOOKED',
  scheduled_for       timestamptz not null,
  queue_number        int,                          -- assigned on check-in
  reason              text,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists appointments_patient_idx  on public.appointments (patient_id);
create index if not exists appointments_provider_idx on public.appointments (provider_id, scheduled_for);
create index if not exists appointments_status_idx   on public.appointments (status, scheduled_for);

-- ---------------------------------------------------------------------
-- emr  (Prisma: EMR) â€” dual-specialty charting
-- Dental tooth chart + aesthetic fields stored as structured JSON.
-- ---------------------------------------------------------------------
create table if not exists public.emr (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete cascade,
  appointment_id  uuid references public.appointments (id) on delete set null,
  provider_id     uuid references public.providers (id) on delete set null,
  specialty       specialty_type not null,
  chief_complaint text,
  diagnosis       text,
  treatment_plan  text,
  tooth_chart     jsonb not null default '{}'::jsonb,   -- per-tooth state (dental)
  aesthetic_data  jsonb not null default '{}'::jsonb,   -- structured facial/aesthetic fields
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists emr_patient_idx on public.emr (patient_id, created_at desc);

-- ---------------------------------------------------------------------
-- prescriptions  (Prisma: Prescription) â€” dental vs facial templates
-- ---------------------------------------------------------------------
create table if not exists public.prescriptions (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.patients (id) on delete cascade,
  emr_id         uuid references public.emr (id) on delete set null,
  provider_id    uuid references public.providers (id) on delete set null,
  rx_type        prescription_type not null,
  items          jsonb not null default '[]'::jsonb,   -- [{drug, dose, frequency, duration, notes}]
  advice         text,
  follow_up_date date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists prescriptions_patient_idx on public.prescriptions (patient_id, created_at desc);

-- ---------------------------------------------------------------------
-- bills  (Prisma: Bill) â€” invoice with clinic/doctor share split
-- ---------------------------------------------------------------------
create table if not exists public.bills (
  id                  uuid primary key default gen_random_uuid(),
  invoice_no          text unique,
  patient_id          uuid not null references public.patients (id) on delete restrict,
  appointment_id      uuid references public.appointments (id) on delete set null,
  provider_id         uuid references public.providers (id) on delete set null,  -- doctor credited
  consultation_fee    numeric(12,2) not null default 0,
  test_fee            numeric(12,2) not null default 0,
  discount            numeric(12,2) not null default 0,
  total_amount        numeric(12,2) not null default 0,
  doctor_share        numeric(12,2) not null default 0,   -- drives Doctor Earnings (Â§6.9a)
  clinic_share        numeric(12,2) not null default 0,
  amount_paid         numeric(12,2) not null default 0,
  status              bill_status not null default 'PENDING',
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists bills_patient_idx  on public.bills (patient_id);
create index if not exists bills_provider_idx on public.bills (provider_id, status, created_at);
create index if not exists bills_status_idx   on public.bills (status);

-- ---------------------------------------------------------------------
-- bill_payments â€” payment recording history (supports partial payments)
-- ---------------------------------------------------------------------
create table if not exists public.bill_payments (
  id          uuid primary key default gen_random_uuid(),
  bill_id     uuid not null references public.bills (id) on delete cascade,
  amount      numeric(12,2) not null check (amount > 0),
  method      text,                                -- cash / card / transfer
  recorded_by uuid references public.profiles (id) on delete set null,
  paid_at     timestamptz not null default now()
);

create index if not exists bill_payments_bill_idx on public.bill_payments (bill_id);

-- ---------------------------------------------------------------------
-- expenses  (Prisma: Expense) â€” clinic expense ledger
-- ---------------------------------------------------------------------
create table if not exists public.expenses (
  id          uuid primary key default gen_random_uuid(),
  category    text,
  description text not null,
  amount      numeric(12,2) not null check (amount >= 0),
  receipt_url text,                                -- optional receipt photo
  spent_at    date not null default current_date,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists expenses_date_idx on public.expenses (spent_at desc);

-- ---------------------------------------------------------------------
-- inventory_items  (Prisma: InventoryItem)
-- ---------------------------------------------------------------------
create table if not exists public.inventory_items (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  sku           text unique,                       -- barcode/QR lookup value
  unit          text,                              -- box / piece / ml
  quantity      numeric(12,2) not null default 0,
  reorder_level numeric(12,2) not null default 0,  -- low-stock threshold
  unit_cost     numeric(12,2) not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists inventory_low_stock_idx on public.inventory_items (quantity, reorder_level);

-- ---------------------------------------------------------------------
-- stock_movements  (Prisma: StockMovement) â€” add/deduct/adjust log
-- ---------------------------------------------------------------------
create table if not exists public.stock_movements (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.inventory_items (id) on delete cascade,
  type        stock_movement_type not null,
  quantity    numeric(12,2) not null,
  reason      text,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists stock_movements_item_idx on public.stock_movements (item_id, created_at desc);

-- ---------------------------------------------------------------------
-- inventory_usage_logs  (Prisma: InventoryUsageLog) â€” usage tied to tx
-- ---------------------------------------------------------------------
create table if not exists public.inventory_usage_logs (
  id            uuid primary key default gen_random_uuid(),
  item_id       uuid not null references public.inventory_items (id) on delete cascade,
  appointment_id uuid references public.appointments (id) on delete set null,
  emr_id        uuid references public.emr (id) on delete set null,
  quantity      numeric(12,2) not null,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- notification_logs  (Prisma: NotificationLog)
-- ---------------------------------------------------------------------
create table if not exists public.notification_logs (
  id          uuid primary key default gen_random_uuid(),
  recipient_id uuid references public.profiles (id) on delete set null,
  patient_id  uuid references public.patients (id) on delete set null,
  channel     notification_channel not null default 'EMAIL',
  status      notification_status  not null default 'QUEUED',
  subject     text,
  body        text,
  error       text,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- device_tokens â€” mobile push registration (Expo/FCM/APNs), Â§8
-- ---------------------------------------------------------------------
create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  token       text not null,
  platform    text,                                -- ios / android
  created_at  timestamptz not null default now(),
  unique (profile_id, token)
);

-- updated_at triggers
create trigger patients_set_updated_at          before update on public.patients          for each row execute function public.set_updated_at();
create trigger appointment_types_set_updated_at before update on public.appointment_types for each row execute function public.set_updated_at();
create trigger appointments_set_updated_at      before update on public.appointments      for each row execute function public.set_updated_at();
create trigger emr_set_updated_at               before update on public.emr               for each row execute function public.set_updated_at();
create trigger prescriptions_set_updated_at     before update on public.prescriptions     for each row execute function public.set_updated_at();
create trigger bills_set_updated_at             before update on public.bills             for each row execute function public.set_updated_at();
create trigger inventory_items_set_updated_at   before update on public.inventory_items   for each row execute function public.set_updated_at();


-- >>>>>>>>>>>>>>>>>>>> migrations\0004_rls_policies.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0004 Row-Level Security
-- =====================================================================
-- Server-side enforcement of the role model (description.md Â§4â€“5).
-- The mobile app ALSO hides UI by role, but security lives here.
--   ADMIN        â€” full access
--   RECEPTIONIST â€” patients, scheduling, billing, queue
--   DOCTOR       â€” view patients, own appointments, EMR/Rx, OWN bills only
-- =====================================================================

-- Enable RLS everywhere.
alter table public.profiles            enable row level security;
alter table public.providers           enable row level security;
alter table public.patients            enable row level security;
alter table public.appointment_types   enable row level security;
alter table public.time_slots          enable row level security;
alter table public.slot_reservations   enable row level security;
alter table public.appointments        enable row level security;
alter table public.emr                 enable row level security;
alter table public.prescriptions       enable row level security;
alter table public.bills               enable row level security;
alter table public.bill_payments       enable row level security;
alter table public.expenses            enable row level security;
alter table public.inventory_items     enable row level security;
alter table public.stock_movements     enable row level security;
alter table public.inventory_usage_logs enable row level security;
alter table public.notification_logs   enable row level security;
alter table public.device_tokens       enable row level security;

-- Shortcut arrays
--   all staff: ADMIN+DOCTOR+RECEPTIONIST
--   front desk: ADMIN+RECEPTIONIST
--   clinical:  ADMIN+DOCTOR

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
create policy profiles_select_self_or_admin on public.profiles
  for select using (id = auth.uid() or public.has_role(array['ADMIN']::user_role[]));
create policy profiles_select_staff_directory on public.profiles
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy profiles_update_self on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid() and role = public.auth_role());
create policy profiles_admin_write on public.profiles
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- providers â€” readable by all staff, managed by admin
-- ---------------------------------------------------------------------
create policy providers_select on public.providers
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy providers_admin_write on public.providers
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- patients â€” all staff read; front desk + admin write
-- ---------------------------------------------------------------------
create policy patients_select on public.patients
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy patients_write on public.patients
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

-- ---------------------------------------------------------------------
-- appointment_types â€” all staff read; admin write
-- ---------------------------------------------------------------------
create policy appt_types_select on public.appointment_types
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy appt_types_admin_write on public.appointment_types
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- time_slots & slot_reservations â€” all staff read; front desk + admin write
-- ---------------------------------------------------------------------
create policy time_slots_select on public.time_slots
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy time_slots_write on public.time_slots
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

create policy reservations_select on public.slot_reservations
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy reservations_write on public.slot_reservations
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

-- ---------------------------------------------------------------------
-- appointments â€” all staff read; front desk + admin write;
-- a doctor may update the status of their OWN appointments (check-in/complete)
-- ---------------------------------------------------------------------
create policy appointments_select on public.appointments
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy appointments_frontdesk_write on public.appointments
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy appointments_doctor_update_own on public.appointments
  for update using (
    public.has_role(array['DOCTOR']::user_role[])
    and provider_id = public.current_provider_id()
  )
  with check (provider_id = public.current_provider_id());

-- ---------------------------------------------------------------------
-- emr & prescriptions â€” all staff READ (doctor + receptionist may view);
-- only clinical roles (doctor/admin) write.
-- ---------------------------------------------------------------------
create policy emr_select on public.emr
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy emr_clinical_write on public.emr
  for all using (public.has_role(array['ADMIN','DOCTOR']::user_role[]))
  with check (public.has_role(array['ADMIN','DOCTOR']::user_role[]));

create policy rx_select on public.prescriptions
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy rx_clinical_write on public.prescriptions
  for all using (public.has_role(array['ADMIN','DOCTOR']::user_role[]))
  with check (public.has_role(array['ADMIN','DOCTOR']::user_role[]));

-- ---------------------------------------------------------------------
-- bills â€” DOCTOR sees ONLY their own (earnings scope, Â§6.9a);
-- front desk + admin see/manage all.
-- ---------------------------------------------------------------------
create policy bills_select_frontdesk on public.bills
  for select using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy bills_select_doctor_own on public.bills
  for select using (
    public.has_role(array['DOCTOR']::user_role[])
    and provider_id = public.current_provider_id()
  );
create policy bills_write_frontdesk on public.bills
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

create policy bill_payments_select on public.bill_payments
  for select using (
    public.has_role(array['ADMIN','RECEPTIONIST']::user_role[])
    or exists (
      select 1 from public.bills b
      where b.id = bill_payments.bill_id
        and b.provider_id = public.current_provider_id()
    )
  );
create policy bill_payments_write on public.bill_payments
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

-- ---------------------------------------------------------------------
-- expenses â€” admin manage; receptionist may add
-- ---------------------------------------------------------------------
create policy expenses_select on public.expenses
  for select using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy expenses_insert on public.expenses
  for insert with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy expenses_admin_modify on public.expenses
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- inventory â€” all staff read; admin write
-- ---------------------------------------------------------------------
create policy inventory_select on public.inventory_items
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy inventory_admin_write on public.inventory_items
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

create policy stock_movements_select on public.stock_movements
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy stock_movements_admin_write on public.stock_movements
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

create policy usage_logs_select on public.inventory_usage_logs
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy usage_logs_write on public.inventory_usage_logs
  for all using (public.has_role(array['ADMIN','DOCTOR']::user_role[]))
  with check (public.has_role(array['ADMIN','DOCTOR']::user_role[]));

-- ---------------------------------------------------------------------
-- notification_logs â€” admin + own recipient read
-- ---------------------------------------------------------------------
create policy notifications_select on public.notification_logs
  for select using (
    recipient_id = auth.uid() or public.has_role(array['ADMIN']::user_role[])
  );
create policy notifications_admin_write on public.notification_logs
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- device_tokens â€” users manage only their own
-- ---------------------------------------------------------------------
create policy device_tokens_own on public.device_tokens
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());


-- >>>>>>>>>>>>>>>>>>>> migrations\0005_functions_and_triggers.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0005 Business Logic
-- =====================================================================
-- Derived billing math, payment rollups, stock adjustment, queue
-- numbering, slot-reservation expiry, and the scoped Doctor Earnings
-- aggregation (description.md Â§6.6 / Â§6.9a).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Billing: keep total + share split consistent.
-- total = consultation + test - discount.
-- If shares weren't supplied, clinic_share absorbs the remainder.
-- ---------------------------------------------------------------------
create or replace function public.compute_bill_amounts()
returns trigger
language plpgsql
as $$
begin
  new.total_amount := coalesce(new.consultation_fee,0) + coalesce(new.test_fee,0) - coalesce(new.discount,0);
  if new.total_amount < 0 then new.total_amount := 0; end if;

  -- clamp doctor share to total, clinic share is the remainder
  if new.doctor_share is null then new.doctor_share := 0; end if;
  if new.doctor_share > new.total_amount then new.doctor_share := new.total_amount; end if;
  new.clinic_share := new.total_amount - new.doctor_share;

  -- derive status from amount_paid unless explicitly cancelled
  if new.status <> 'CANCELLED' then
    if new.amount_paid <= 0 then
      new.status := 'PENDING';
    elsif new.amount_paid < new.total_amount then
      new.status := 'PARTIAL';
    else
      new.status := 'PAID';
    end if;
  end if;
  return new;
end;
$$;

create trigger bills_compute_amounts
  before insert or update on public.bills
  for each row execute function public.compute_bill_amounts();

-- ---------------------------------------------------------------------
-- Payment rollup: a new payment bumps the bill's amount_paid (which
-- re-triggers status via compute_bill_amounts on the UPDATE).
-- ---------------------------------------------------------------------
create or replace function public.apply_bill_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bills
     set amount_paid = amount_paid + new.amount
   where id = new.bill_id;
  return new;
end;
$$;

create trigger bill_payments_rollup
  after insert on public.bill_payments
  for each row execute function public.apply_bill_payment();

-- ---------------------------------------------------------------------
-- Inventory: a stock movement mutates on-hand quantity.
-- ---------------------------------------------------------------------
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.inventory_items
     set quantity = case new.type
                      when 'ADD'    then quantity + new.quantity
                      when 'DEDUCT' then quantity - new.quantity
                      when 'ADJUST' then new.quantity          -- absolute set
                    end
   where id = new.item_id;
  return new;
end;
$$;

create trigger stock_movements_apply
  after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- ---------------------------------------------------------------------
-- Queue numbering: assign the next number for the appointment's day
-- when it transitions to CHECKED_IN. Idempotent (won't renumber).
-- ---------------------------------------------------------------------
create or replace function public.assign_queue_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_no int;
begin
  if new.status = 'CHECKED_IN'
     and (old.status is distinct from 'CHECKED_IN')
     and new.queue_number is null then
    select coalesce(max(queue_number), 0) + 1 into next_no
      from public.appointments
     where date(scheduled_for) = date(new.scheduled_for);
    new.queue_number := next_no;
  end if;
  return new;
end;
$$;

create trigger appointments_assign_queue
  before update on public.appointments
  for each row execute function public.assign_queue_number();

-- ---------------------------------------------------------------------
-- Slot reservations: expire stale holds and free the slot.
-- Call from pg_cron (see bottom) â€” mirrors the web node-cron cleanup.
-- ---------------------------------------------------------------------
create or replace function public.expire_slot_reservations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  affected int;
begin
  with expired as (
    update public.slot_reservations
       set status = 'EXPIRED'
     where status = 'HELD' and expires_at < now()
     returning time_slot_id
  )
  update public.time_slots t
     set is_available = true
    from expired e
   where t.id = e.time_slot_id;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- Hold helper: atomically mark a slot unavailable + create a HELD row.
create or replace function public.hold_slot(p_time_slot_id uuid, p_patient_id uuid default null)
returns public.slot_reservations
language plpgsql
security definer
set search_path = public
as $$
declare
  res public.slot_reservations;
begin
  update public.time_slots
     set is_available = false
   where id = p_time_slot_id and is_available = true;
  if not found then
    raise exception 'Slot is no longer available';
  end if;
  insert into public.slot_reservations (time_slot_id, held_by, patient_id)
  values (p_time_slot_id, auth.uid(), p_patient_id)
  returning * into res;
  return res;
end;
$$;

-- ---------------------------------------------------------------------
-- Doctor Earnings (Â§6.9a): scoped aggregation of the doctor share.
-- A doctor can ONLY query their own figure; admin may pass a provider.
-- paid_only=true counts settled money; false counts paid + pending.
-- ---------------------------------------------------------------------
create or replace function public.get_doctor_earnings(
  p_provider_id uuid default null,
  p_from        timestamptz default null,
  p_to          timestamptz default null,
  p_paid_only   boolean default false
)
returns table (
  provider_id   uuid,
  total_share   numeric,
  paid_share    numeric,
  pending_share numeric,
  bill_count    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  -- Resolve scope: admins may inspect any provider; everyone else is
  -- forced to their own provider id regardless of what they pass.
  if public.has_role(array['ADMIN']::user_role[]) then
    target := coalesce(p_provider_id, public.current_provider_id());
  else
    target := public.current_provider_id();
  end if;

  if target is null then
    return;  -- caller is not a provider and gave no id
  end if;

  return query
  select
    b.provider_id,
    sum(b.doctor_share)                                                   as total_share,
    sum(case when b.status = 'PAID' then b.doctor_share else 0 end)       as paid_share,
    sum(case when b.status <> 'PAID' then b.doctor_share else 0 end)      as pending_share,
    count(*)                                                              as bill_count
  from public.bills b
  where b.provider_id = target
    and b.status <> 'CANCELLED'
    and (p_from is null or b.created_at >= p_from)
    and (p_to   is null or b.created_at <  p_to)
    and (not p_paid_only or b.status = 'PAID')
  group by b.provider_id;
end;
$$;

grant execute on function public.get_doctor_earnings(uuid, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.hold_slot(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Scheduled cleanup via pg_cron (available on Supabase). Safe-guarded:
-- only schedules if the extension is present.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'expire-slot-reservations',
      '* * * * *',                       -- every minute
      $cron$ select public.expire_slot_reservations(); $cron$
    );
  end if;
exception when others then
  raise notice 'pg_cron not configured: %', sqlerrm;
end $$;


-- >>>>>>>>>>>>>>>>>>>> migrations\0006_storage.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” 0006 Storage Buckets
-- =====================================================================
-- Buckets for patient photos and expense receipts (camera/gallery).
-- Access is restricted to authenticated staff via storage RLS.
-- =====================================================================

insert into storage.buckets (id, name, public)
values
  ('patient-photos',  'patient-photos',  false),
  ('expense-receipts','expense-receipts',false),
  ('rx-assets',       'rx-assets',       true)     -- NDC logo/brand for PDF gen
on conflict (id) do nothing;

-- Any active staff member may read/write clinical media.
create policy "staff read patient photos" on storage.objects
  for select using (
    bucket_id = 'patient-photos'
    and public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[])
  );
create policy "front desk write patient photos" on storage.objects
  for insert with check (
    bucket_id = 'patient-photos'
    and public.has_role(array['ADMIN','RECEPTIONIST']::user_role[])
  );

create policy "staff read receipts" on storage.objects
  for select using (
    bucket_id = 'expense-receipts'
    and public.has_role(array['ADMIN','RECEPTIONIST']::user_role[])
  );
create policy "staff write receipts" on storage.objects
  for insert with check (
    bucket_id = 'expense-receipts'
    and public.has_role(array['ADMIN','RECEPTIONIST']::user_role[])
  );


-- >>>>>>>>>>>>>>>>>>>> seed.sql <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- Noor Dentofacial Clinic â€” Seed / Demo Data
-- =====================================================================
-- Reference data + a few demo rows so the app has something to show.
--
-- NOTE: staff *auth* accounts must be created through Supabase Auth
-- (the trigger in 0002 then creates their profile). After creating the
-- auth users, set their roles/providers by editing the UPDATEs below to
-- use the real auth UUIDs, or run create-staff from the Admin screen.
-- This seed only inserts data that does NOT require an auth user.
-- =====================================================================

-- ---- Appointment types (match the Book Appointment mockup) -----------
insert into public.appointment_types (name, specialty, duration_minutes, consultation_fee, test_fee, default_doctor_pct)
values
  ('General Check-up',   'DENTAL',    30, 2000, 0,    40),
  ('Tooth Extraction',   'DENTAL',    45, 5000, 1000, 50),
  ('Scaling & Polishing','DENTAL',    40, 3500, 0,    45),
  ('Botox Consultation', 'AESTHETIC', 30, 4000, 0,    50),
  ('Dermal Fillers',     'AESTHETIC', 60, 15000,0,    55),
  ('Facial Rejuvenation','AESTHETIC', 60, 12000,0,    50)
on conflict do nothing;

-- ---- Providers without login (can be linked to a profile later) ------
insert into public.providers (full_name, title, specialty, is_primary)
values
  ('Dr. Ethan Walker', 'Senior Facial Aesthetic Specialist', 'AESTHETIC', true),
  ('Dr. Sarah Chen',   'Maxillofacial Surgeon',              'DENTAL',    false),
  ('Dr. Jenkins',      'General Dentist',                    'DENTAL',    false)
on conflict do nothing;

-- ---- Inventory --------------------------------------------------------
insert into public.inventory_items (name, sku, unit, quantity, reorder_level, unit_cost)
values
  ('Dental Anesthetic Cartridge', 'NDC-AN-001', 'box',   3,  5, 1200),
  ('Composite Filling Resin',     'NDC-CF-002', 'tube', 12, 10,  800),
  ('Disposable Gloves (M)',       'NDC-GL-003', 'box',  25, 15,  450),
  ('Dermal Filler 1ml',           'NDC-DF-004', 'vial',  4,  6, 9000),
  ('Botulinum Toxin 100u',        'NDC-BT-005', 'vial',  2,  3,18000)
on conflict do nothing;

-- ---- Demo patients ----------------------------------------------------
insert into public.patients (mrn, full_name, phone, gender, date_of_birth)
values
  ('NDC-0001', 'Eleanor Vance', '+923001234567', 'Female', '1990-04-12'),
  ('NDC-0002', 'Arthur Morgan', '+923004445566', 'Male',   '1985-09-30'),
  ('NDC-0003', 'Sarah Linton',  '+923007778899', 'Female', '1998-01-22')
on conflict do nothing;

