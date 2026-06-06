# Noor Dentofacial Clinic — Mobile App Build Specification

> A functional and technical reference for building the **phone app** version of the existing Noor Dentofacial Clinic web platform. This document describes what the current web system does, how the mobile app should mirror and adapt it, and a recommended path to start building.

---

## 1. Purpose & Context

The existing product is a full-stack **clinic management & EMR system** for a combined **dental + aesthetic/facial** practice, covering patient registration, appointments, medical charting, prescriptions, billing, inventory, and reporting, with role-based access for admins, doctors, and receptionists.

The goal now is a **mobile (phone) app**. The most important architectural fact for this effort:

> **The backend does not change.** Your Express + TypeScript + Prisma API already exposes everything over HTTP. The mobile app is a **new client** that talks to the same REST endpoints with the same JWT auth. This dramatically reduces the work — you are building a UI layer, not a new system.

---

## 2. Existing System Summary (Reference)

### Tech Stack (current web app)

| Layer | Technology |
|-------|-----------|
| Frontend | React 19 + Vite, React Router 7, Tailwind CSS 4, Recharts, i18next (English + Urdu), Axios |
| Backend | Node.js + Express 5, TypeScript, Prisma ORM |
| Database | PostgreSQL (production) / SQLite `dev.db` (local) |
| Auth | JWT tokens + bcrypt password hashing |
| Other | Nodemailer (email), Multer (uploads), node-cron (scheduled jobs) |
| Deployment | Vercel (frontend + backend), Render (alt backend) |

### Architecture

```
Mobile App (new client) ─┐
                         ├─HTTP/JWT─►  Backend (Express/TS)  ──Prisma──►  PostgreSQL
Web App (existing)     ─┘                  │
                                           ├─ Routes: auth, patients, appointments,
                                           │          appointment-types, time-slots,
                                           │          slot-reservations, patient-history,
                                           │          billing, inventory, doctors, providers
                                           ├─ Services: auth, file, notification (email),
                                           │            reservation cleanup (cron)
                                           └─ Middleware: JWT auth + RBAC
```

### Backend API Route Groups (reused by mobile)

`/api/auth` · `/api/patients` · `/api/billing` · `/api/inventory` · `/api/providers` · plus appointments, appointment-types, time-slots, slot-reservations, patient-history, and doctor routes mounted under `/api`. Health check at `/api/health`.

### Database Models (Prisma)

`User`, `Patient`, `Appointment`, `EMR`, `Prescription`, `Bill`, `Expense`, `TimeSlot`, `NotificationLog`, `InventoryItem`, `InventoryUsageLog`, `StockMovement`, `AppointmentType`, `SlotReservation`, `Provider`.

---

## 3. Recommended Mobile Approach

| Decision | Recommendation | Why |
|----------|---------------|-----|
| **Framework** | **React Native (with Expo)** | You already know React/JSX/Axios/i18next. Most concepts and even some logic transfer directly. Expo speeds up camera, push notifications, secure storage, and builds. |
| **Navigation** | React Navigation (stack + bottom tabs) | Replaces React Router 7. Tab bar per role, stacks for drill-downs. |
| **Styling** | NativeWind (Tailwind for RN) | Lets you reuse your Tailwind mental model and class names. |
| **State/Data** | TanStack Query (React Query) + Axios | Caching, retries, offline-friendly. Cleaner than raw Axios for a data-heavy app. |
| **Auth storage** | `expo-secure-store` | JWT must live in encrypted storage, **not** AsyncStorage. |
| **Charts** | `react-native-gifted-charts` or Victory Native | Recharts is web-only; pick an RN-native chart lib. |
| **i18n** | `i18next` + `react-i18next` (same as web) | Reuse existing `en`/`ur` locale files; add RTL handling for Urdu. |
| **Printing** | `expo-print` + `expo-sharing` | Generate PDFs on-device for Rx/invoices and share/print via the OS. |

> Alternative: **Flutter** if you prefer Dart and a single high-performance codebase, but React Native keeps you in your existing skill set and lets you share logic with the web app. This spec assumes React Native.

---

## 4. Scope: Staff-Only App

This mobile app is **for clinic staff only** — ADMIN, DOCTOR, and RECEPTIONIST. There is **no patient-facing role** in the app; patients do not log in or book through it. (Patients still exist as *records* managed by staff — that is patient **management**, not a patient user.)

This is a **single app with role-aware UI**: after login the JWT's role drives which tabs and screens appear. Because it is internal-only, you can distribute it through internal channels (TestFlight / Play internal testing / MDM) rather than positioning it as a public consumer app. Role gating is noted per feature below and is always enforced server-side by the existing JWT + RBAC middleware.

---

## 5. User Roles & Mobile Access

| Role | Primary mobile use | Tab set (suggested) |
|------|-------------------|---------------------|
| **ADMIN** | Oversight on the go: staff, inventory, finances, reports | Dashboard · Patients · Inventory · Reports · More |
| **DOCTOR** | Their queue, patient charts, EMR, prescriptions, **own earnings** | Queue · Patients · Charting · Rx · Earnings · More |
| **RECEPTIONIST** | Booking, patient registration, **viewing patient details**, billing, queue | Appointments · Patients · Billing · Queue · More |

There are three roles only — no patient login. Both the **doctor** and the **receptionist** can open a patient and see their full details; the doctor additionally has an **Earnings** view showing the revenue they personally generated (see §6.6 / §6.9).

Access control stays enforced **server-side** by the existing JWT + RBAC middleware. The mobile app should *also* hide/show UI by role, but never rely on client-side gating for security.

---

## 6. Feature-by-Feature Functional Spec

Each feature lists what it does today and the mobile-specific adaptation.

### 6.1 Authentication & Account Management
- **Core:** Secure login (JWT + hashed passwords); forgot/reset password via email; admin-created Doctor and Receptionist accounts.
- **Mobile:**
  - Login screen storing the JWT in `expo-secure-store`; auto-login on launch if token valid.
  - Forgot-password opens the email flow (deep link back into the app for reset, or web fallback).
  - **Biometric unlock** (Face ID / fingerprint) as a convenience layer over the stored token.
  - Auto-logout / token-refresh handling on 401 responses.

### 6.2 Patient Management
- **Core:** Register/maintain patient records (demographics, contact, phone validation); patient profiles with full visit/treatment history; photo uploads (Multer).
- **Access:** **Receptionists and doctors can both view full patient details** (demographics, contact, visit and treatment history); receptionists also register/edit records. Admins have full access.
- **Mobile:**
  - Patient list with search and pull-to-refresh.
  - Patient detail screen with tabbed history (visits, treatments, EMR, bills) — available to receptionist and doctor.
  - **Camera + gallery** photo capture for patient records via `expo-image-picker`, uploaded to the existing Multer endpoint as multipart form data.
  - Phone-number validation matching the web rules.

### 6.3 Appointment Scheduling
- **Core:** Time-slot management with held reservations and cron cleanup of expired slots; configurable appointment types tied to duration + pricing; queue numbering on check-in; lifecycle book → confirm → complete/cancel; email notifications (logged). *(The web app also has patient-facing booking, but the mobile app is staff-only, so booking here is done by the receptionist.)*
- **Mobile:**
  - Slot picker showing available time slots (calls time-slots / slot-reservations endpoints); a slot is **held** while the receptionist completes the booking, consistent with the web reservation logic.
  - Appointment-type selector showing duration and price.
  - Calendar/day/list views of appointments per role.
  - **Check-in** action that assigns/shows the queue number.
  - Lifecycle actions (confirm, complete, cancel) gated by role; cancellation workflow for receptionists.
  - **Push notifications** for booking confirmations and changes (mobile-native replacement/augmentation for email; see §8).

### 6.4 Electronic Medical Records (EMR)
- **Core:** Dual-specialty charting that switches between **DENTAL** and **AESTHETIC/FACIAL** formats; captures chief complaint, diagnosis, treatment plan; interactive **ToothChart** persisted per patient; aesthetic/facial fields stored as structured JSON; traditional medical-format views.
- **Mobile:**
  - Specialty toggle (Dental / Aesthetic) that swaps the form schema.
  - **Touch-friendly interactive tooth chart** — this is the trickiest port. Build it as an SVG/canvas component sized for phone tapping (consider a larger zoomable view); persist the same per-patient structure the web app uses.
  - Structured-JSON aesthetic fields rendered as native form inputs.
  - Read-only "medical-format" view for quick review.
  - Doctor-only by RBAC.

### 6.5 Prescriptions
- **Core:** Generate and print prescriptions with clinic branding; separate **dental** (`PrintDentalRx`) and **facial/aesthetic** (`PrintFacialRx`) templates; printable formatted output.
- **Mobile:**
  - Rx builder reusing the two template types.
  - Render the branded Rx to **PDF on-device** (`expo-print`) using the NDC logo assets, then print/share via the OS sheet (AirPrint / Android print / WhatsApp / email).

### 6.6 Billing & Payments
- **Core:** Auto-generated invoices priced from appointment/treatment type; fee breakdown (consultation + test fee → total) split into **clinic share** and **doctor share**; payment recording and status (PENDING/paid); printable invoices/receipts (`PrintInvoice`).
- **Mobile:**
  - Invoice detail with the same fee breakdown and share split.
  - Record-payment action updating status.
  - PDF invoice/receipt generation and share/print on-device.
  - Receptionist + admin access for creating/recording payments.
  - **Doctor earnings:** the per-bill **doctor share** already attributes revenue to a doctor, so each doctor can see the total they have personally earned (see §6.9 Doctor Earnings). This is read-only for the doctor and scoped to their own bills only.

### 6.7 Inventory Management
- **Core:** Track inventory items with stock levels; stock-movement logging (add/deduct) and usage logs tied to treatments; admin add/manage pages; low-stock visibility.
- **Mobile:**
  - Inventory list with low-stock highlighting.
  - Quick stock adjustment (add/deduct) writing stock movements.
  - Optional **barcode/QR scanning** (`expo-camera`) to look up or adjust items fast — a strong mobile-only win.
  - Admin access.

### 6.8 Expense Tracking
- **Core:** Record clinic expenses and maintain an expense ledger; distinguishes one-off expenses from the running log.
- **Mobile:**
  - Add-expense form; ledger list with filters.
  - Optional **receipt photo capture** attached to an expense.

### 6.9 Dashboards & Reports
- **Core:** Admin/main dashboard + dedicated Doctor dashboard; Reports page with Recharts (financials, appointments, activity); revenue/share analytics from billing.
- **Mobile:**
  - Role-specific dashboard as the landing tab (KPIs as cards).
  - Charts rebuilt with an RN chart library (Recharts won't run in RN).
  - Keep charts simple and phone-legible; allow tap-through to detail.

### 6.9a Doctor Earnings (Revenue Generated) — new
- **What it is:** A dedicated view where an **individual doctor sees the revenue they personally generated** — i.e., the money earned from patients they treated. This is the sum of the **doctor share** across that doctor's bills.
- **Data source:** No new model needed. Bills already record a **doctor share** and are linked to the treating doctor (via `Bill` / `Provider` / `User`), so the figure is a server-side aggregation of the logged-in doctor's bills.
- **Suggested backend:** A scoped endpoint (e.g. `GET /api/billing/earnings/me` or a `doctorId`-filtered query) that returns the doctor's totals; **the doctor only ever sees their own numbers**, enforced by RBAC. Admin can see all doctors' earnings via the existing reports.
- **Mobile UI:**
  - **Earnings tab / card** on the Doctor dashboard showing total earned, plus breakdowns by period (today / this week / this month / custom range).
  - Optional trend chart (earnings over time) and a list of contributing bills (patient, treatment type, date, doctor share, paid/pending).
  - Make clear whether figures count **paid only** vs. **paid + pending** — expose a toggle or label so it isn't ambiguous.

### 6.10 Internationalization (i18n)
- **Core:** Full English + Urdu via i18next with locale files for both.
- **Mobile:**
  - Reuse existing `en` / `ur` translation JSON.
  - Add **RTL layout** handling for Urdu (`I18nManager.forceRTL`); test mirrored layouts.
  - Language toggle in settings; persist choice.

### 6.11 Printing & Documents
- **Core:** Branded print templates (prescriptions, invoices/receipts, business cards) using NDC logo assets.
- **Mobile:**
  - All "print" actions become **generate-PDF-then-share/print** via the OS.
  - Bundle the NDC logo/brand assets into the app for offline document generation.

---

## 7. Screen Inventory (suggested, by role)

**Shared:** Splash · Login · Forgot/Reset Password · Settings (language, biometric, logout).

**Receptionist:** Dashboard · Appointments (calendar/list) · Book/Cancel · Patient List · Register Patient · **Patient Detail (full details)** · Queue · Billing (invoice list, invoice detail, record payment).

**Doctor:** Doctor Dashboard · My Queue · Patient List · Patient Detail · EMR Charting (Dental/Aesthetic + ToothChart) · Prescription Builder · **My Earnings (revenue generated)**.

**Admin:** Dashboard · Patients · Create Doctor · Create Receptionist · Inventory (list, add, adjust) · Expenses · Reports (incl. all-doctor earnings).

---

## 8. Mobile-Specific Concerns (don't skip these)

- **Push notifications** — replace/augment email notifications using Expo push or FCM/APNs for booking confirmations, changes, queue-ready alerts. The backend already logs notifications (`NotificationLog`); add device-token registration and push dispatch alongside Nodemailer.
- **Secure token storage** — JWT in `expo-secure-store`; never in plain AsyncStorage. Handle expiry/refresh on 401.
- **Offline behavior** — decide what works offline (e.g., view cached patient/appointment lists) vs. online-only (writes). TanStack Query cache helps for read resilience.
- **Camera/media** — patient photos, expense receipts, optional inventory barcode scanning.
- **RTL** — Urdu requires mirrored layouts; budget time to test every screen in both directions.
- **API base URL / environments** — config for dev (SQLite/local) vs. prod (PostgreSQL on Vercel/Render); the app should point at the deployed API.
- **CORS / network** — ensure the deployed backend permits the mobile origin; mobile uses native HTTP so CORS is less of an issue than web, but confirm auth headers flow correctly.
- **File uploads** — multipart form-data to the existing Multer endpoints from RN.

---

## 9. Suggested Build Roadmap

1. **Foundation** — Expo project, navigation skeleton, NativeWind, Axios + TanStack Query, secure JWT auth + login/logout, role-based tab routing (admin / doctor / receptionist).
2. **Read-only core** — dashboards, patient list/detail, appointment list, inventory list (prove the API integration end-to-end).
3. **Receptionist write flows** — register patient, view patient details, book/cancel appointments, queue, billing + record payment.
4. **Doctor clinical flows** — EMR charting, ToothChart, prescription builder + PDF.
5. **Doctor earnings** — the per-doctor revenue view (scoped earnings endpoint + Earnings screen/chart).
6. **Admin & inventory writes** — create staff, inventory adjustments, expenses, reports/charts (incl. all-doctor earnings).
7. **Mobile polish** — push notifications, offline caching, biometric unlock, Urdu/RTL, on-device PDF printing.
8. **Release** — store assets, EAS builds, internal distribution (TestFlight / Play internal / MDM).

---

## 10. Open Decisions to Confirm Before Building

- **Framework:** confirm React Native/Expo (assumed here) vs. Flutter/native.
- **Doctor earnings basis:** should the doctor's revenue total count **paid bills only** or **paid + pending**? And what default period (month-to-date, all-time)?
- **Notifications:** push-only, email-only, or both?
- **Offline:** which screens must work without a connection?
- **ToothChart:** acceptable to redesign the interaction for touch/zoom on small screens?
- **Distribution:** how are staff builds delivered — TestFlight / Play internal testing / MDM?

---

*This document maps the existing Noor Dentofacial Clinic web platform to a mobile build. Because the Express/Prisma backend is reused unchanged, the bulk of mobile work is a new React Native client against the existing API plus the mobile-native concerns in §8.*