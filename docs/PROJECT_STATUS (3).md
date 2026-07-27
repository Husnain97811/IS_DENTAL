# DentOS — PROJECT_STATUS.md

> Continuation file. In a new chat: "Read PROJECT_STATUS.md and continue." Keep this updated as work progresses.

## Role & rules

You are my Principal Flutter Engineer on **DentOS** (folder: `is_dental`) — a production, **staff-only** dental clinic management **desktop** system. A separate **patient mobile app** is now in active build (see MOBILE section). Build module-by-module, pause cleanly, never ship stubs. The prototype HTML + spec in project knowledge are the authoritative design reference. For any change: give the full file or a precise targeted edit with exact path; if a fix depends on a file you can't see, ask me to paste it rather than guessing.

**Working style (important):** share recommendations FIRST and wait for my approval before implementing. Deliver full files or precise targeted edits with exact paths. I write in concise, abbreviated, typo-heavy shorthand — interpret intent, keep explanations simple, I get confused by dense prose. I'm on **macOS (zsh)**; Supabase project ref `ydoixtpgcfivorjecigx`.

> Note: file attachments sometimes arrive EMPTY in chat — if a pasted file looks blank, ask me to paste it inline as text.

## Locked tech + design
- **Stack:** Flutter Desktop + Sizer (`.w/.h/.sp`), Riverpod, Drift + SQLCipher (encrypted local DB = source of truth), freezed 3.x (`abstract class X with _$X`), go_router, fl_chart, pdf+printing, pointycastle (RSA), bcrypt, flutter_dotenv, supabase_flutter, media_kit, three_js, qr_flutter.
- **Theme** "Futuristic Clinical Minimalist": light canvas + dark sidebar; ice `#38BDF8`, teal `#13E0C4`, teal-deep `#0BB6A0`; fonts Sora/Manrope/JetBrains Mono; colors via `context.dent`.
- **Connectivity:** offline-capable, needs internet ≥ every 48h or locks; monotonic anti-rollback clock; subscription = signed offline license (`expiresAt`) AND Supabase `clinics.status`/`expires_at` on heartbeat.
- **License:** RSA modulus compile-time const in `license_verifier.dart` AND Edge Function `MODULUS_DEC`. `tool/license_tool.dart` mints. Confirmed working.

## Auth model
- Staff login = fully offline/local (Users table, bcrypt).
- Cloud = ONE Supabase auth account per clinic (owner email+password) with `app_metadata.clinic_id` for RLS.
- Patient app = SEPARATE: opaque 30-day session token in `patient_accounts`, NOT Supabase Auth. Never shares surface with staff auth.

## Licensing
- Signature-based, NOT machine-locked (`machineFingerprint:'ANY'`). Private key never leaves my Mac; public modulus baked into app + Edge Function.
- `resolveLicense()` re-verifies signature + expiry EVERY launch vs monotonic clock.
- **Renewal = mint NEW license**, later `expiresAt`, SAME clinicId/clinicName. Two gates: (1) license expiry offline, (2) Supabase `clinics.expires_at`/`status` on 48h heartbeat. **I bump `clinics.expires_at` manually** (register-clinic doesn't push expiry).

## Roles & permissions (DONE)
- **Owner** — full; Staff+Branches panels; switch branches; edits ANY branch's hours.
- **Admin** — one branch; Staff (own branch) + My Profile; pinned; edits OWN branch hours.
- **Clinician/Receptionist** — My Profile + Data only; pinned; Clinic Hours read-only.
- Enforced at DATA layer.

## Branch isolation (DONE)
Owner sees all (activeBranch=null) or one branch; others pinned. Per-branch: Patients, Appointments, Invoices, Inventory, Treatments, Dashboard, Reports, Users, Branches, `dentistsProvider`, clinic hours. Filter: `branchId==null ? const Constant(true) : t.branchId.equals(branchId)`.

## DONE — earlier phases (0–8)
Design system, shell, router, encrypted Drift DB, RSA licensing+48h gate; Patients (+FDI odontogram, plans), Appointments (+Quick Book), Billing, Inventory, Reports, Treatments; premium branches + seat staff + branch logins; auth screens; `register-clinic`; full LWW sync; live dashboard; context search; patient detail; 3D tooth viewer; invoice drawer + `pdf_output.dart`; reports 12-mo PDF; settings Data & Backup; live `dentistsProvider`; procedure catalog; `DentDialog`; staff mgmt; settings role-gating.

## DONE — Mobile P1 (desktop foundations) ✅
1. **CNIC (v11)** — `patients.cnic` nullable, digits-only stored, dashed display, validation, dup warning, both-dir mapping, sync, Supabase col.
2. **Clinic ID** — `generateClinicId(name,city)` → `FAST-ISL-######` (first word + city code + 6-digit) at mint time, rides in license as clinicId. NEW clinics only.
3. **QR** — `qr_payload.dart`: patient `{"c","p","v":1}`, clinic `{"c","v":1}`. v1 unsigned (FINAL). `patient_qr_dialog.dart` all-roles. Settings "Patient App" card + `clinic_qr_pdf.dart`.
4. **Invoice** — `invoice_pdf.dart` pro rebuild, QR top-right, per-unit table, totals block. `buildInvoicePdf(inv,{clinicName,clinicId,patientUuid,patientCode?,clinicBranch?})`.

## DONE — Clinic Hours per branch (v12) ✅
- `Branches` +`openMinutes`(600)/`closeMinutes`(1020)/`slotMinutes`(20)/`closedDays`(CSV '1'..'7' Mon..Sun). Defaults = old behavior.
- `updateBranchHours()`; `branch.dart` +4 fields; repo both dirs; **upsertBranch `Value.absent()` for hours on edit** (hours only via updateBranchHours).
- `clinicScheduleProvider` rewired resetting-StateProvider → derived Provider reading active branch hours. `daySlotsProvider` skips closed days.
- Settings "Clinic Hours" card after Branches: owner=all editable, admin=own editable, others read-only.
- Supabase `branches` +4 cols; sync both dirs.

## DONE — Mobile P2 (backend) ✅ THIS SESSION
Edge Functions via **Supabase dashboard** (not CLI). `// @ts-nocheck` at top silences editor "Cannot find name 'Deno'" (runtime-only; not a deploy error). All curl-tested.

**Decisions locked:**
- **QR unsigned v1 (option C, HMAC dropped).** `link-patient` proves QR by uuid-exists-in-clinic. Desktop QR UNCHANGED.
- **Branch scope on SESSION:** `patient_accounts.branch_scope` = branch_id or NULL(all). Set at link from optional `branchId`. Change branch = rescan → new session same patient.
- **Per-dentist busy** (patient app). Desktop stays clinic-wide (unchanged).
- **Same-day allowed**, 30 days ahead.
- **Dentist selection required; clinicians only** on patient app (`DENTIST_ROLES=['clinician']`).
- **Pending request holds slot** until rejected.
- **Duration=branch slot_minutes**; staff modify on ACCEPT (P4).
- **Token=identity**; fns ignore client-sent IDs.

**⚠ TIMEZONE (solved):** desktop stores `starts_at` as local PKT→UTC (10:00 local = `05:00+00`). `available-slots` builds slots at `dateStr + minutes - CLINIC_UTC_OFFSET_MIN(300)` so 10:00-local slot emits `05:00Z`, matching desktop. Verified: book 11:00 desktop → `06:00Z` slot vanishes. Hardcoded +5 (Pakistan only).

**Tables added:**
- `patient_accounts`(id uuid pk, clinic_id, patient_uuid, cnic_hash, device_id, session_token, expires_at, branch_scope, created_at, updated_at). RLS ON + ZERO policies (sealed; service-role only). Idx session_token, (clinic_id,patient_uuid).
- `booking_requests`(id uuid pk, clinic_id, branch_id, patient_uuid, patient_account_id, dentist, procedure, requested_slot tstz, duration_min, status pending|approved|rejected, created_at, updated_at). RLS sealed. Idx (clinic_id,status),(branch_id,requested_slot),(patient_uuid).
- `clinics` +`logo_url` (deferred, null).

**Edge Functions (5):**
- `register-clinic` — sig verify + reject expired; clinic insert-vs-update (new=full insert; existing=update name+tier ONLY, expires_at/status preserved). Auth dup tolerated.
- `resolve-clinic` — no auth. `{clinicId}`→`{ok,clinic:{clinicId,name,logoUrl,branches:[{uuid,name,location,isPrimary}]}}`. Safe cols only; rejects non-active. Reads clinics+branches (option A, no clinic_public table).
- `link-patient` — `{clinicId,method:'qr'|'cnic',patientUuid?|(cnic+fullName),deviceId?,branchId?}`. QR: uuid non-deleted in clinic. CNIC: CNIC exact digits AND full_name trim+lowercase both match (dup CNIC → name filter). Mints 30-day token, delete-then-insert, stores branch_scope. Returns `{ok,session:{token,expiresAt,branchScope},patient:{patientUuid,fullName,code}}`. Vague failure.
- `available-slots` — `{sessionToken,date,branchId?,dentist?}`. Token→scope. In-play branches=scope or all(narrow by branchId). Reads branch hours. Dentists=users role∈DENTIST_ROLES non-deleted; branch_id-null user offered under every in-play branch. Per-dentist busy from appointments+pending requests. PKT offset. Returns `{ok,date,scope,dentists:[{fullName,branchId,branchName}],slots:{"fullName@@branchId":[{time,branchId}]}}`.
- `request-booking` — `{sessionToken,branchId,dentist,procedure,slot,durationMin}`. Scope guard; re-check slot free (409 if taken); insert pending. **FCM=TODO(P5).** Returns `{ok,requestId,status:'pending'}`.

**BUG FIXED:** `addStaff` missing `uuid:Value(Uuids.v4())` → staff never synced (`_syncUsers` skips uuid-empty). Fixed. Backfill via `backfillUserUuids()`. Deleting cloud users won't re-push (cursor) → `setSetting('sync_push_users','')` then Sync. Deleting `users` row ≠ deleting Supabase Auth account (separate).

## Schema / DB — current version: **v12**
- v12→branches hours; v11→patients.cnic; v10→treatments.branchId; v9→users.email/phone; v8→appointments.billed; v7→users.branchId; v6→branches.
- Supabase mirror: patients.cnic ✓, branches hours ✓, clinics.logo_url ✓; pending: appointments.status/billed, treatments.branch_id, users.email/phone.

## ⚠ DISCIPLINE RULES
- **RENEWALS REUSE clinicId VERBATIM** (regenerating orphans data).
- **Manual expiry bump on renewal.**
- **QR v1 shape FINAL** (no HMAC).
- **addStaff/createOwner MUST set uuid.**
- **PKT +5 hardcoded** in available-slots.
- **Edge Functions live in Supabase dashboard, NOT the repo.** `// @ts-nocheck` silences editor Deno error.

## Key file paths
- `lib/core/utils/qr_payload.dart`; `.../patient_qr_dialog.dart`; `lib/features/settings/data/clinic_qr_pdf.dart`
- `lib/features/billing/data/invoice_pdf.dart`
- `lib/features/settings/presentation/settings_screen.dart` — `_patientAppPanel`,`_hoursPanel`,`_showHoursEditor`
- `tool/license_tool.dart` — `generateClinicId`
- `lib/core/db/app_database.dart` — v12, findPatientByCnic, updateBranchHours, backfillUserUuids, addStaff(uuid FIXED)
- `lib/features/branches/data/branch_repository_impl.dart`; `.../domain/branch.dart`
- `lib/features/appointments/presentation/appointments_controller.dart` — clinicScheduleProvider(derived), daySlotsProvider(+closed), dentistsProvider
- `lib/cloud/data/sync_engine.dart`
- Edge Functions (dashboard): register-clinic, resolve-clinic, link-patient, available-slots, request-booking

## Gotchas
- freezed 3.x abstract class; build_runner after schema/freezed.
- `.value` not `.valueOrNull`. addStaff/createOwner set uuid. Branch-stamp `Value<String?>`.
- macOS `com.apple.security.network.client` (Debug/Profile+Release). Freezed field add → full restart.
- **Wipe local:** quit, `find ~/Library -name 'dentos.db*' 2>/dev/null -delete` (fresh v12).
- **Wipe cloud:** children before parents (invoice_items, treatment_steps, treatment_plans, tooth_records, invoices, appointments, inventory_items, treatments, booking_requests, patient_accounts, users, branches, patients). clinics+auth only if re-onboarding.
- `kSeedDemoData` FALSE for clean start.
- **Reset sync cursor:** `setSetting('sync_push_<table>','')` then Sync.
- **available-slots empty dentists** = no user role∈DENTIST_ROLES with branch_id∈scope. Check role spelling + branch assignment + synced (has uuid).

## MOBILE — Patient App (spec: DentOS_Patient_App_Plan.pdf)
- One Flutter app (iOS+Android), published once, serves all clinics.
- **Link:** scan clinic QR OR enter clinic ID → **pick branch scope** (specific branch OR All) → binds session. **Identity:** scan patient QR OR CNIC+full_name (both match). No reception approval.
- **Change branch:** app Settings → rescan clinic QR → pick scope. Same patient/history.
- **Session:** 30-day token, re-login same way, no OTP.
- **7 screens:** Link, Verify, Home, Book, My Appointments, Profile, Notifications.
- **Book:** pick dentist (scope-filtered; scope=all → each tagged RWP/ISL) → date → slots → confirm=request. "Change doctor" re-shows list. Booking=request (desktop approves).
- **Backend DONE (P2).** QR unsigned v1. Per-dentist busy. PKT offset. Branch scope on session.

### ✅ P1 DESKTOP FOUNDATIONS — DONE
### ✅ Clinic Hours per branch (v12) — DONE
### ✅ P2 BACKEND — DONE (this session) — 3 tables + 5 Edge Functions, curl-tested, TZ + per-dentist verified, addStaff uuid bug fixed.

### ▶ P3 — PATIENT APP CORE (NEXT TASK)
Fresh Flutter app (iOS+Android), SEPARATE project from desktop `is_dental`. Screens: Link clinic (resolve-clinic) → branch-scope picker → Verify identity (link-patient QR/CNIC, store token in flutter_secure_storage) → Home (next appt, book btn, recall) → Book (available-slots dentist w/ branch tag → date → slots → request-booking) → My Appointments (upcoming+history) → Profile (details, linked-clinic, change branch, sign out) → Notifications inbox. Calls the 4 patient Edge Functions.

### P4 — DESKTOP REQUESTS LOOP
Sync booking_requests → local Drift table. Appointments "Requests" inbox badge: pending w/ patient, dentist, branch tag, slot, procedure. Accept → mini-editor pre-filled, staff MODIFY time/duration → real appointment (existing book() path) → status='approved'. Reject → 'rejected' (frees slot). Sync push approval results.

### P5 — NOTIFICATIONS & POLISH
FCM setup; request-booking FCM stub→real; reminders 24h/2h; recall nudges; store listings + deep-link page.

## Roadmap (deferred)
- **Migration safety harness** — NOT BUILT; 7 blind migrations (v12). ⚠ Highest-priority; do before next schema change. Manual backup is mitigation.
- Windows build; Data import; Payments/ledger (DEFERRED).
- Clinical record: SOAP, medical history+contraindications, perio, imaging, prescriptions, lab.
- Growth: reminders, recall automation, financial reports, auto-update, Urdu.
- Hardening: tests, crash reporting, RBAC audit, sync-conflict surfacing, load test.

## PENDING
1. Migration safety harness. 2. Verify register-clinic deploy + modulus + .env. 3. Full validation pass (registration, offline login, branch logins, RLS, anti-rollback, suspend/renew). 4. SQLCipher confirm encrypting. 5. Bundle fonts. 6. Remaining mirror cols (appointments.status/billed, treatments.branch_id, users.email/phone). 7. Windows. 8. Data import. 9. Financial reports. 10. Clinical completeness. 11. Hardening. 12. Payments (DEFERRED).

## NEXT TASK
**Mobile P3 — patient app core.** New Flutter app (separate from desktop). Build order: link flow (resolve-clinic → branch-scope picker) → identity (link-patient QR/CNIC, secure token) → Home → Book (available-slots → request-booking) → My Appointments → Profile (change branch) → Notifications.
