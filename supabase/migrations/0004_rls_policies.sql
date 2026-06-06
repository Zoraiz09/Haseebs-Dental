-- =====================================================================
-- Noor Dentofacial Clinic — 0004 Row-Level Security
-- =====================================================================
-- Server-side enforcement of the role model (description.md §4–5).
-- The mobile app ALSO hides UI by role, but security lives here.
--   ADMIN        — full access
--   RECEPTIONIST — patients, scheduling, billing, queue
--   DOCTOR       — view patients, own appointments, EMR/Rx, OWN bills only
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
-- providers — readable by all staff, managed by admin
-- ---------------------------------------------------------------------
create policy providers_select on public.providers
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy providers_admin_write on public.providers
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- patients — all staff read; front desk + admin write
-- ---------------------------------------------------------------------
create policy patients_select on public.patients
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy patients_write on public.patients
  for all using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]))
  with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

-- ---------------------------------------------------------------------
-- appointment_types — all staff read; admin write
-- ---------------------------------------------------------------------
create policy appt_types_select on public.appointment_types
  for select using (public.has_role(array['ADMIN','DOCTOR','RECEPTIONIST']::user_role[]));
create policy appt_types_admin_write on public.appointment_types
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- time_slots & slot_reservations — all staff read; front desk + admin write
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
-- appointments — all staff read; front desk + admin write;
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
-- emr & prescriptions — all staff READ (doctor + receptionist may view);
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
-- bills — DOCTOR sees ONLY their own (earnings scope, §6.9a);
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
-- expenses — admin manage; receptionist may add
-- ---------------------------------------------------------------------
create policy expenses_select on public.expenses
  for select using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy expenses_insert on public.expenses
  for insert with check (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));
create policy expenses_admin_modify on public.expenses
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- inventory — all staff read; admin write
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
-- notification_logs — admin + own recipient read
-- ---------------------------------------------------------------------
create policy notifications_select on public.notification_logs
  for select using (
    recipient_id = auth.uid() or public.has_role(array['ADMIN']::user_role[])
  );
create policy notifications_admin_write on public.notification_logs
  for all using (public.has_role(array['ADMIN']::user_role[]))
  with check (public.has_role(array['ADMIN']::user_role[]));

-- ---------------------------------------------------------------------
-- device_tokens — users manage only their own
-- ---------------------------------------------------------------------
create policy device_tokens_own on public.device_tokens
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());
