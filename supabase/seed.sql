-- =====================================================================
-- Noor Dentofacial Clinic — Seed / Demo Data
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
