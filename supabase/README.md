# Noor Dentofacial Clinic — Supabase Backend

The clinic's database, auth, and security live in Supabase (Postgres). The
mobile app in [`../mobile`](../mobile) talks to it directly via `@supabase/supabase-js`.

## What's here

| File | Purpose |
|------|---------|
| `migrations/0001_extensions_and_enums.sql` | Extensions + all enum types (roles, statuses) |
| `migrations/0002_profiles_and_helpers.sql` | `profiles` (staff) + `providers` (doctors), auth helpers, new-user trigger |
| `migrations/0003_core_tables.sql` | Patients, scheduling, EMR, prescriptions, billing, inventory, expenses, notifications |
| `migrations/0004_rls_policies.sql` | Row-Level Security — the role model enforced server-side |
| `migrations/0005_functions_and_triggers.sql` | Billing math, payments, stock, queue, slot expiry, **doctor earnings** |
| `migrations/0006_storage.sql` | Storage buckets for patient photos / receipts / brand assets |
| `seed.sql` | Reference + demo data |

## Role model (RLS)

| | ADMIN | DOCTOR | RECEPTIONIST |
|--|--|--|--|
| Patients | full | view | view + edit |
| Appointments / slots | full | update own | full |
| EMR / Prescriptions | full | **write** | view |
| Bills | all | **own only** | all |
| Inventory / staff | **manage** | view | view |

`description.md` §4–5. Security is enforced in `0004_rls_policies.sql`; the app
also hides UI by role but never relies on that for security.

## Apply it

### Option A — Supabase CLI (recommended)
```bash
npm i -g supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push          # applies migrations/*
psql "$DATABASE_URL" -f seed.sql   # or paste seed.sql into the SQL editor
```

### Option B — Dashboard SQL editor
Open each file in `migrations/` **in numeric order** and run it, then run `seed.sql`.

## Creating staff accounts

Auth users are created through Supabase Auth (not SQL). On sign-up, pass
`full_name`, `phone`, and `role` in the user metadata — the `handle_new_user`
trigger creates the matching `profiles` row. To link a doctor to a provider
record, set `providers.profile_id` to that user's id (done from the Admin →
Create Doctor screen).

For local dev you can create the first ADMIN from the dashboard
(Authentication → Add user) and then run:
```sql
update public.profiles set role = 'ADMIN' where email = 'you@example.com';
```

## Doctor earnings

`get_doctor_earnings(provider_id, from, to, paid_only)` returns the scoped
doctor-share aggregation. Doctors are always forced to their own provider id;
admins may pass any. Default counts **paid + pending**; pass `paid_only := true`
for settled money only (description.md §6.9a — toggle exposed in the app).
