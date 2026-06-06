-- =====================================================================
-- Noor Dentofacial Clinic — 0007 Staff fields + patient scoping
-- =====================================================================
-- Adds: doctor employment type (in-house / visiting) and an admin-set
-- revenue share % on each provider; and restricts a DOCTOR to only see
-- patients they have an appointment with.
-- Safe to run on the existing database (idempotent).
-- =====================================================================

-- ---- Provider: employment type + revenue share ----------------------
alter table public.providers
  add column if not exists employment_type text not null default 'IN_HOUSE'
    check (employment_type in ('IN_HOUSE', 'VISITING')),
  add column if not exists default_share_pct numeric(5,2) not null default 0
    check (default_share_pct between 0 and 100);

comment on column public.providers.employment_type is 'IN_HOUSE or VISITING (admin sets at registration).';
comment on column public.providers.default_share_pct is 'Doctor revenue share %, applied to their bills.';

-- ---- Patients: a doctor only sees patients they treat ---------------
-- Replace the blanket all-staff select with role-scoped policies.
drop policy if exists patients_select on public.patients;

-- Admin + receptionist: full patient list.
create policy patients_select_frontdesk on public.patients
  for select using (public.has_role(array['ADMIN','RECEPTIONIST']::user_role[]));

-- Doctor: only patients who have an appointment with this doctor.
create policy patients_select_doctor on public.patients
  for select using (
    public.has_role(array['DOCTOR']::user_role[])
    and exists (
      select 1 from public.appointments a
      where a.patient_id = patients.id
        and a.provider_id = public.current_provider_id()
    )
  );
