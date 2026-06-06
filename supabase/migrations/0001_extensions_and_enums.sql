-- =====================================================================
-- Noor Dentofacial Clinic — 0001 Extensions & Enums
-- =====================================================================
-- Foundational types shared across the schema. Run first.
-- =====================================================================

-- No CREATE EXTENSION needed: we use the built-in gen_random_uuid()
-- (Postgres 13+ core) for ids and plain text for emails. This avoids the
-- "cannot execute CREATE EXTENSION in a read-only transaction" error in
-- the Supabase SQL editor. (uuid-ossp / pgcrypto / citext not required.)

-- Staff roles. There is NO patient login role (staff-only app, see description.md §4).
do $$ begin
  create type user_role as enum ('ADMIN', 'DOCTOR', 'RECEPTIONIST');
exception when duplicate_object then null; end $$;

-- Clinical specialty — drives EMR/Rx form schema (dental vs aesthetic/facial).
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

-- Notification channels (email today; push added for mobile, description.md §8).
do $$ begin
  create type notification_channel as enum ('EMAIL', 'PUSH', 'SMS');
exception when duplicate_object then null; end $$;

do $$ begin
  create type notification_status as enum ('QUEUED', 'SENT', 'FAILED');
exception when duplicate_object then null; end $$;
