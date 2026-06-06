# Noor Dentofacial Clinic — Mobile App

A staff-only (ADMIN · DOCTOR · RECEPTIONIST) mobile app for the Noor Dentofacial
Clinic, built with **Expo / React Native** against a **Supabase** backend.

```
Haseeb App/
├── description.md      # original build specification
├── design inspo/       # UI mockups (Sign In, Home, Book Appointment)
├── supabase/           # database: SQL migrations, RLS, seed  ← the "backend"
└── mobile/             # Expo React Native app                ← the "frontend"
```

## Two parts

| Part | Folder | What it is |
|------|--------|-----------|
| **Backend** | [`supabase/`](supabase) | PostgreSQL schema, auth, Row-Level Security, business logic, seed data. Hosted by Supabase. See [`supabase/README.md`](supabase/README.md). |
| **Frontend** | [`mobile/`](mobile) | The phone app the staff use. Talks to Supabase directly. |

## Tech stack

Expo SDK 56 · React Native 0.85 · React Navigation (role-aware tabs) ·
NativeWind (Tailwind) · TanStack Query · `@supabase/supabase-js` ·
expo-secure-store (encrypted JWT) · i18next (English + Urdu, RTL ready).

## Run the app

```bash
cd mobile
npm install        # already done if you've built here
npx expo start     # then press a (Android), i (iOS), or scan the QR in Expo Go
```

### Mock mode (default — no backend needed yet)
With no Supabase credentials the app runs on **in-memory demo data**, so every
screen works offline today. Sign in with any of:

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@noor.clinic` | `password` |
| Doctor | `doctor@noor.clinic` | `password` |
| Receptionist | `reception@noor.clinic` | `password` |

### Going live on Supabase
1. Create a Supabase project.
2. Apply the SQL in [`supabase/`](supabase) (`supabase db push`, then `seed.sql`).
3. Copy `mobile/.env.example` → `mobile/.env` and fill in
   `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY`.
4. Restart `npx expo start -c`. The app now reads/writes real data — no code change.

## Roadmap status — all phases complete ✅

- [x] **Phase 1 — Foundation:** SQL schema + RLS, Expo scaffold, design system, auth + login, role-based tabs, the three designed screens.
- [x] **Phase 2 — Read-only core:** tabbed patient detail (visits/EMR/bills), appointment list, inventory with low-stock.
- [x] **Phase 3 — Receptionist write flows:** register patient (+ camera), book/cancel + slot hold, check-in → queue number, billing + record payment.
- [x] **Phase 4 — Doctor clinical flows:** EMR charting (Dental ↔ Aesthetic), interactive ToothChart, prescription builder → branded PDF.
- [x] **Phase 5 — Doctor earnings:** scoped earnings (paid/pending toggle, 7-day chart, contributing bills).
- [x] **Phase 6 — Admin & inventory writes:** create staff, stock add/adjust, expenses ledger, reports dashboard + charts.
- [x] **Phase 7 — Mobile polish:** biometric unlock, Urdu/RTL + persisted prefs, push registration, offline query cache, on-device PDF (Rx + invoices).
- [x] **Phase 8 — Release:** EAS build profiles, splash/identity config, internal distribution guide ([`mobile/RELEASE.md`](mobile/RELEASE.md)).

See [`mobile/RELEASE.md`](mobile/RELEASE.md) to build and distribute, and
[`supabase/README.md`](supabase/README.md) to stand up the live backend.
