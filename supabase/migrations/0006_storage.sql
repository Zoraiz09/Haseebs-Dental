-- =====================================================================
-- Noor Dentofacial Clinic — 0006 Storage Buckets
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
