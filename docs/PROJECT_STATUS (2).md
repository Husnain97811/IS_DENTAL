# DentOS — PROJECT_STATUS.md

> Continuation file. In a new chat: "Read PROJECT_STATUS.md and continue." Keep this updated as work progresses.

## Role & rules

You are my Principal Flutter Engineer on **DentOS** (folder: `is_dental`) — a production, **staff-only** dental clinic management **desktop** system. A separate **patient mobile app** is now planned (see MOBILE section). Build module-by-module, pause cleanly, never ship stubs. The prototype HTML + spec in project knowledge are the authoritative design reference. For any change: give the full file or a precise targeted edit with exact path; if a fix depends on a file you can't see, ask me to paste it rather than guessing.

**Working style (important):** share recommendations FIRST and wait for my approval before implementing. Deliver full files or precise targeted edits with exact paths. I write in concise, abbreviated, typo-heavy shorthand — interpret intent, keep explanations simple, I get confused by dense prose. I'm on **macOS (zsh)**; Supabase project ref `ydoixtpgcfivorjecigx`.

> Note: file attachments sometimes arrive EMPTY in chat — if a pasted file looks blank, ask me to paste it inline as text.

## Locked tech + design
- **Stack:** Flutter Desktop + Sizer (`.w/.h/.sp`), Riverpod, Drift + SQLCipher (encrypted local DB = source of truth), freezed 3.x (`abstract class X with _$X`), go_router (StatefulShellRoute, 8 routes), fl_chart, pdf+printing, pointycastle (RSA), bcrypt, flutter_dotenv, supabase_flutter, media_kit (desktop video), three_js (desktop 3D via ANGLE), qr_flutter (patient/clinic QR).
- **Theme** "Futuristic Clinical Minimalist": light canvas + dark sidebar; ice `#38BDF8`, teal `#13E0C4`, teal-deep `#0BB6A0`; fonts Sora/Manrope/JetBrains Mono; colors via `context.dent` (DentColors ThemeExtension).
- **Connectivity:** offline-capable, needs internet ≥ every 48h or locks; monotonic anti-rollback clock; subscription = signed offline license (`expiresAt`) AND Supabase `clinics.status`/`expires_at` on heartbeat.
- **License:** RSA modulus compile-time constant in `license_verifier.dart` AND Edge Function `MODULUS_DEC`. `tool/license_tool.dart` mints licenses. **Confirmed working.**

## Auth model
- Staff login = fully offline/local (Users table, bcrypt).
- Cloud = ONE Supabase auth account per clinic (owner email+password) with `app_metadata.clinic_id` for RLS.
- Patient app (planned) = SEPARATE auth model, never shares surface with staff auth.

## Licensing — how it works (confirmed this session)
- **Signature-based, NOT machine-locked.** `machineFingerprint: 'ANY'` today → a license activates on any machine. Private key (`vendor_keypair.json`) never leaves my Mac; public modulus baked into app (`license_verifier.dart`) + Edge Function (`MODULUS_DEC`) — both from the same keypair; regenerating the keypair breaks both until updated.
- **First-time activation (any machine):** app rebuilds canonical JSON from pasted license, verifies signature against baked-in modulus. Pure math, offline, works anywhere. Client can't forge (no private key).
- **`resolveLicense()` re-verifies signature + expiry on EVERY launch** (not just activation), against the monotonic clock.
- **Renewal after expiry = mint a NEW license** with later `expiresAt`, SAME clinicId/clinicName; client pastes into activation again. Two gates: (1) license `expiresAt` offline, (2) Supabase `clinics.expires_at`/`status` on 48h heartbeat. Fresh license passes gate 1 immediately; **I bump `clinics.expires_at` manually in the DB** for gate 2 (register-clinic does NOT push expiry — my choice).

## Roles & permissions (DONE)
- **Owner** — full access; sees Staff + Branches panels in Settings; switches branches freely; picks any branch when creating staff; edits/deletes users.
- **Admin** — assigned to ONE branch; sees Staff panel (own branch only) + My Profile card; pinned branch (no switching); new staff locked to admin's branch; cannot touch Branches panel.
- **Clinician / Receptionist** — see only My Profile card + Data panel; pinned branch; no staff/branch management.
- Enforced at the DATA layer (branch-filtered queries), not just hidden UI.

## Branch isolation (DONE — the big feature)
Strict per-branch data isolation. Owner sees all (activeBranch = null) or one branch; everyone else is pinned to their branch from login and physically cannot query other branches.

**Per-branch tables** (filtered by `branchId`, stamped on write, watch `activeBranchProvider`): Patients, Appointments, Invoices, Inventory, Treatments, Dashboard (7 aggregate methods), Reports, Users/staff, Settings Branches panel, `dentistsProvider`.

**Filter pattern everywhere:** `branchId == null ? const Constant(true) : t.branchId.equals(branchId)`.

**Backfill:** `AppDatabase.backfillBranchIds()` stamps legacy null-branch rows into the FIRST branch. Run once via temp initState, then removed.

**Switcher UX:** `BranchSwitcher` on dashboard only (removed from topbar). Owner-only switching w/ DentDialog confirm; others see pinned read-only label. Auto-refresh free via Riverpod. Stale-dropdown reset in quick_book_drawer + appointment_editor.

## DONE — earlier phases (0–8)
- **Phases 0–5 + cloud:** design system, shell, router, encrypted Drift DB, RSA licensing + 48h gate; Patients (+FDI odontogram, treatment plans), Appointments (+Quick Book), Billing (invoice PDF), Inventory, Reports (fl_chart), Treatments; premium branches + seat-based staff + branch logins; glassmorphic auth screens; self-service onboarding Edge Function (`register-clinic`); full LWW cloud sync (`sync_engine.dart`); live dashboard.
- **Phase 6:** context-aware topbar search + live notifications; patient picker + atomic create-or-book; dashboard perf; month-scoped appointment search; patient detail screen (`/patients/:id`); 3D tooth viewer; appointment Arrived/Bill quick actions (+`billed` flag).
- **Phase 7:** invoice drawer wired; `pdf_output.dart` shared Print/PDF chooser; reports 12-month + `reports_pdf.dart` multi-page A4 + range export; settings Data & Backup; topbar DB-status dialog.
- **Phase 8:** live `dentistsProvider`; procedure catalog wiring (`proceduresProvider`/`procedurePriceProvider`); reusable `DentDialog` (`showDentDialog`, `DentDialogKind.success/warning/error`, copyable rows, optional input, returns `Future<bool?>`); staff management overhaul (auto-username `firstname@clinicslug`, email/phone v9, edit/soft-delete tombstone); settings role-gating; live sidebar footer; topbar cleanup.

## DONE (Mobile Phase P1 — desktop foundations — THIS SESSION) ✅
The hooks the patient app needs, all four built and tested:

1. **CNIC column (migration v11).** `patients.cnic` nullable text (mandatory enforced in editor, not schema). Stored **digits-only** (`3520212345671`), displayed dashed (`35202-1234567-1`). `onUpgrade` guarded `addColumn` (try/catch — fresh DBs already had the column from the table class). Editor: 13-digit + first-digit 1–7 validation, `formatCnicDashed()` helper, `CnicInputFormatter` (existing), soft duplicate warning via `findPatientByCnic()` + DentDialog. Repo write+read paths both map `cnic` (`upsertPatient` + `_toPatient`). Sync: push `'cnic': p.cnic`, pull `cnic: Value(r['cnic'] ?? '')`. Supabase: `alter table patients add column if not exists cnic text`.
2. **Clinic ID format.** `generateClinicId(name, city)` in `tool/license_tool.dart` → `FAST-ISL-######` = **first word of name** (uppercased, alnum) + **city code** (lookup map: islamabad→ISL, rawalpindi→RWP, lahore→LHR, karachi→KHI, peshawar→PEW, faisalabad→FSD, multan→MUX, quetta→UET; fallback first-3-letters) + **6-digit** random. Generated at **license-mint time**, rides inside signed license as `clinicId`, flows activation → `saveProfile` → `ClinicProfile.clinicId`. NEW clinics only; existing clinic_ids untouched (sync keys on them). City is NOT in the signed license (mint-time arg only — no canonical change).
3. **Patient/clinic QR.** `qr_flutter` dep added. `lib/core/utils/qr_payload.dart` — shared encoder: `buildPatientQrPayload({clinicId, patientUuid})` → `{"c":..,"p":..,"v":1}`; `buildClinicQrPayload({clinicId})` → `{"c":..,"v":1}`. **v1 = unsigned (P1); bumps to v:2 with `sig` when HMAC lands in P2.** `patient_qr_dialog.dart` — `showPatientQrDialog(context, patient)`, full-screen QR, **no role gate** (all roles). Wired in `patient_snapshot_drawer.dart`: tap avatar (has QR badge) OR "Show Patient QR" button. Settings "Patient App" card (`_patientAppPanel`, all roles, above `_dataPanel`): clinic QR + Clinic ID + Copy + Print (`clinic_qr_pdf.dart`).
4. **Professional invoice redesign.** `invoice_pdf.dart` fully rebuilt: clinic name + branch header, **QR top-right** (~32mm/90pt, error-correction MEDIUM, "Scan to access your appointments") reusing `buildPatientQrPayload` — **same payload as on-screen QR, one scan works everywhere**; BILLED TO + `#code`; status pill (Paid/Pending/Overdue); itemized table **Description / Qty / Unit Price / Amount** with **per-unit math (line = amount × qty)**; Subtotal → Adjustment → Total Due block; footer with Clinic ID. Signature widened: `buildInvoicePdf(inv, {clinicName, clinicId, patientUuid, patientCode?, clinicBranch?})`. Caller (`invoice_drawer.dart`) resolves uuid via `patientByIdProvider(inv.patientId)` + clinicId via `currentClinicId()` inside the `build:` callback.

## Schema / DB — current version: **v11**
- v11 → `patients.cnic` (nullable text) — guarded addColumn (try/catch for fresh DBs that already had it)
- v10 → `treatments.branchId`; v9 → `users.email`+`phone`; v8 → `appointments.billed`; v7 → `users.branchId`; v6 → `branches` table
- `onUpgrade` ladder top: `if(from<11){ try addColumn(patients.cnic) catch _ }` then v10…v6 as before.
- **Confirmed working** (migration ran clean, add/edit/dup/sync tested).
- Supabase mirror columns needed: `patients.cnic`; `appointments.status`+`billed`; `treatments.branch_id`; `users.email`/`phone`.

## register-clinic Edge Function (UPDATED this session)
- Verifies signature + rejects expired license (unchanged).
- **Clinic row: insert-vs-update split.** New clinic → full insert (id/name/tier/status='active'/expires_at). Existing clinic (renewal/re-activation) → **update name+tier ONLY**; `expires_at` and `status` preserved (managed manually in DB). Auth-user dup is tolerated (falls through).

## ⚠ DISCIPLINE RULES (must not violate)
- **RENEWALS REUSE THE EXISTING clinicId VERBATIM.** `generateClinicId` produces a new random ID every run — for a renewal, hardcode the client's existing ID in `licenseFields`, do NOT regenerate. Regenerating orphans ALL their synced data (sync/RLS key on clinicId). Keep a list of issued IDs. (Optional future: `issued_clinics.json` ledger in the tool.)
- **Manual expiry on renewal:** register-clinic won't push expiry; bump `clinics.expires_at` in the DB by hand each renewal.
- **QR payload versioning:** never change v1 shape; add fields under v2 when signing lands.

## Key file paths
- `lib/core/utils/qr_payload.dart` — **NEW** shared QR encoders (patient + clinic), version const
- `lib/features/patients/presentation/widgets/patient_qr_dialog.dart` — **NEW** `showPatientQrDialog`, all-roles
- `lib/features/settings/data/clinic_qr_pdf.dart` — **NEW** printable clinic-QR A4 page
- `lib/features/billing/data/invoice_pdf.dart` — **REBUILT** pro invoice + embedded patient QR (per-unit)
- `lib/features/billing/presentation/widgets/invoice_drawer.dart` — Print caller passes clinicId/patientUuid/code/branch
- `lib/core/shell/widgets/formatters.dart` — `CnicInputFormatter` (existing) + `formatCnicDashed()` (new)
- `lib/features/patients/presentation/widgets/patient_editor.dart` — CNIC validation + dup warning + digits-store
- `lib/features/patients/data/patient_repository_impl.dart` — `cnic` in upsert + `_toPatient`
- `lib/features/patients/presentation/widgets/patient_snapshot_drawer.dart` — tap-avatar + Show-QR button
- `lib/features/settings/presentation/settings_screen.dart` — `_patientAppPanel` (all roles)
- `tool/license_tool.dart` — `generateClinicId(name, city)` minter
- `lib/core/db/app_database.dart` — schema v11, `findPatientByCnic()`, all branch/aggregate methods
- `lib/core/widgets/dent_dialog.dart` — `showDentDialog` (kind/title/message/confirm/cancel/rows/input → Future<bool?>)
- `lib/cloud/data/sync_engine.dart` — LWW push/pull; patients now include `cnic`
- `lib/licensing/data/license_service.dart` + `presentation/license_controller.dart` — activate/resolve/completeSetup
- `lib/features/settings/presentation/setup_wizard.dart` (SetupWizard) — activation → profile → owner

## Gotchas
- freezed 3.x → `abstract class`; `dart run build_runner build --delete-conflicting-outputs` after schema/freezed changes.
- Riverpod: `.value` not `.valueOrNull`. Plain `Provider` for `proceduresProvider`.
- `createOwner`/`addStaff` MUST set `uuid: Value(Uuids.v4())` or sync skips them.
- Branch-stamp on write: type `Value<String?>` explicitly or Dart infers `Value<dynamic>` and errors.
- Stale dropdown after branch switch → reset selection if value left the list.
- macOS needs `com.apple.security.network.client` entitlement (Debug/Profile + Release).
- three_js / native plugins → full stop + re-run, not hot reload.
- After adding a freezed field → full restart (hot reload keeps old constructor).
- **Wipe local DB:** quit app, `find ~/Library -name 'dentos.db*' 2>/dev/null -delete` (recreates fresh at v11 via onCreate).
- **Wipe cloud:** Supabase SQL, delete children before parents (invoice_items, treatment_steps, treatment_plans, tooth_records, invoices, appointments, inventory_items, treatments, users, branches, patients). Delete `clinics` + auth user only if re-testing onboarding.
- `kSeedDemoData` in `app_flags.dart` gates demo seeding — keep FALSE for a real clean start or `seedDemoDataIfEmpty()` repopulates 8 dummy patients.
- **Invoice QR caller edge case:** `patientByIdProvider` is branch-filtered; owner pinned to branch A printing a branch-B patient's invoice → uuid empty. Fine for P1; add a branch-agnostic `patientById` fetch if it ever bites.
- **QR print quality:** ≥32mm, MEDIUM error correction, pure black/white, quiet zone via white container — required for reliable paper→phone scans.

## MOBILE — Patient App (spec approved, PDF: DentOS_Patient_App_Plan.pdf)
- One Flutter app (iOS+Android), published once, serves all DentOS clinics.
- **Linking:** Scan clinic QR OR enter clinic ID (`FAST-ISL-######`). **Identity:** scan patient QR OR CNIC + full name (exact match in clinic). No reception approval. CNIC mandatory.
- **Session:** 30-day auto-logout, re-login same way, no OTP/SMS.
- **7 screens:** Link clinic, Verify identity, Home, Book, My Appointments, Profile, Notifications.
- **Booking = request** (clinic approves on desktop, never hard-books).
- **Backend:** 3 tables (patient_accounts, booking_requests, clinic_public), 4 Edge Functions (resolve-clinic, link-patient, available-slots, request-booking), patient RLS (own rows only), FCM.
- **QR signing:** unsigned QR in P1 (done); add HMAC in P2 (payload → v:2 with `sig`).

### ✅ P1 — DESKTOP FOUNDATIONS — DONE (this session)
CNIC + migration v11 · clinic-ID `FAST-ISL-######` at mint time · patient/clinic QR (unsigned v1) · pro invoice with embedded patient QR. All tested. Fresh-start wipe done (dummy data cleared, re-onboarded).

### ▶ P2 — BACKEND (NEXT TASK)
Build order recommendation: start with the simplest end-to-end slice, then layer auth.
1. **`clinic_public` table + `resolve-clinic` Edge Function** — no auth; scan clinic QR / type clinic code → returns display_name, logo_url, branches. Proves the link screen end-to-end first.
2. **`patient_accounts` table + RLS + `link-patient`** — verify patient QR signature OR CNIC+name exact match within clinic; mint 30-day session. **HMAC signing keys land here (QR → v:2).**
3. **`booking_requests` table + `available-slots` + `request-booking`** — server-side free-slot computation; insert request; FCM trigger to clinic.
4. **FCM project setup** + patient RLS hardening (own rows only, all clinic data via Edge Functions).
Needs when starting: current `register-clinic` (have it), Supabase schema for `clinics`/`appointments`/`patients` columns the functions read, decision on HMAC key storage (Edge Function env secret).

### P3–P5 (later)
P3 patient app core (Flutter link/identity/home/book/appointments/profile) · P4 desktop Requests inbox + approve→real appointment + sync additions · P5 FCM wiring, reminders, recall nudges, store listings.

## Roadmap (desktop, deferred behind mobile)
- **Migration safety harness** — STILL NOT BUILT; now 5 blind migrations (v11 latest). ⚠ Highest-priority safety item; do before next schema change. Manual DB backup is current mitigation.
- Windows build (I'll do later); Data import; Payments/ledger (DEFERRED — not needed now).
- Clinical system-of-record: SOAP, medical history + contraindication flags, perio charting, imaging, prescriptions, lab tracking.
- Growth: reminders, recall automation, owner financial reports (A/R aging, production vs collection), auto-update, Urdu localization.
- Hardening: automated tests (sync/migrations/billing), crash reporting, RBAC audit, sync-conflict surfacing, load test 10k+.

## PENDING
1. Migration safety harness (before next schema change).
2. Verify register-clinic deploy state + real RSA modulus + `.env`.
3. Full validation pass: registration, offline login, branch logins, cross-clinic RLS, 48h anti-rollback, suspend/renew.
4. SQLCipher native wiring — confirm actually encrypting.
5. Bundle Sora/Manrope/JetBrains Mono `.ttf` fonts.
6. Supabase mirror columns: `patients.cnic`, `appointments.status`+`billed`, `treatments.branch_id`, `users.email`/`phone`.
7. Windows build. 8. Data import. 9. Owner financial reports. 10. Clinical record completeness. 11. Engineering hardening. 12. Payments/ledger (DEFERRED).

## NEXT TASK
**Mobile Phase P2 — backend.** Start with `clinic_public` table + `resolve-clinic` Edge Function (simplest, no auth) for an end-to-end link-screen slice, then `patient_accounts`+RLS+`link-patient` (HMAC signing keys, QR→v:2), then booking tables+functions, then FCM.
