-- =====================================================================
-- Noor Dentofacial Clinic — 0003 Core Domain Tables
-- =====================================================================
-- Patients, scheduling, EMR, prescriptions, billing, inventory,
-- expenses, notifications. Mirrors the Prisma models in description.md §2.
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
-- appointment_types  (Prisma: AppointmentType) — duration + pricing
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
-- time_slots  (Prisma: TimeSlot) — bookable windows per provider
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
-- slot_reservations  (Prisma: SlotReservation) — short-lived holds
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
-- emr  (Prisma: EMR) — dual-specialty charting
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
-- prescriptions  (Prisma: Prescription) — dental vs facial templates
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
-- bills  (Prisma: Bill) — invoice with clinic/doctor share split
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
  doctor_share        numeric(12,2) not null default 0,   -- drives Doctor Earnings (§6.9a)
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
-- bill_payments — payment recording history (supports partial payments)
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
-- expenses  (Prisma: Expense) — clinic expense ledger
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
-- stock_movements  (Prisma: StockMovement) — add/deduct/adjust log
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
-- inventory_usage_logs  (Prisma: InventoryUsageLog) — usage tied to tx
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
-- device_tokens — mobile push registration (Expo/FCM/APNs), §8
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
