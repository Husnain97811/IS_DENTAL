# DentOS — PROJECT_STATUS.md

> Continuation file. In a new chat: "Read PROJECT_STATUS.md and continue." Keep this updated as work progresses.

## Role & rules

You are my Principal Flutter Engineer on **DentOS** (folder: `is_dental`) — a production, **staff-only** dental clinic management **desktop** system. A separate **patient mobile app** is now planned (see MOBILE section). Build module-by-module, pause cleanly, never ship stubs. The prototype HTML + spec in project knowledge are the authoritative design reference. For any change: give the full file or a precise targeted edit with exact path; if a fix depends on a file you can't see, ask me to paste it rather than guessing.

**Working style (important):** share recommendations FIRST and wait for my approval before implementing. Deliver full files or precise targeted edits with exact paths. I write in concise, abbreviated, typo-heavy shorthand — interpret intent, keep explanations simple, I get confused by dense prose. I'm on **macOS (zsh)**; Supabase project ref `ydoixtpgcfivorjecigx`.

> Note: file attachments sometimes arrive EMPTY in chat — if a pasted file looks blank, ask me to paste it inline as text.

## Locked tech + design
- **Stack:** Flutter Desktop + Sizer (`.w/.h/.sp`), Riverpod, Drift + SQLCipher (encrypted local DB = source of truth), freezed 3.x (`abstract class X with _$X`), go_router (StatefulShellRoute, 8 routes), fl_chart, pdf+printing, pointycastle (RSA), bcrypt, flutter_dotenv, supabase_flutter, media_kit (desktop video), three_js (desktop 3D via ANGLE).
- **Theme** "Futuristic Clinical Minimalist": light canvas + dark sidebar; ice `#38BDF8`, teal `#13E0C4`, teal-deep `#0BB6A0`; fonts Sora/Manrope/JetBrains Mono; colors via `context.dent` (DentColors ThemeExtension).
- **Connectivity:** offline-capable, needs internet ≥ every 48h or locks; monotonic anti-rollback clock; subscription = signed offline license (`expiresAt`) AND Supabase `clinics.status`/`expires_at` on heartbeat.
- **License:** RSA modulus compile-time constant in `license_verifier.dart` AND Edge Function `MODULUS_DEC`. `tool/license_tool.dart` mints licenses. **Confirmed working.**

## Auth model
- Staff login = fully offline/local (Users table, bcrypt).
- Cloud = ONE Supabase auth account per clinic (owner email+password) with `app_metadata.clinic_id` for RLS.
- Patient app (planned) = SEPARATE auth model, never shares surface with staff auth.

## Roles & permissions (DONE this session)
- **Owner** — full access; sees Staff + Branches panels in Settings; switches branches freely; picks any branch when creating staff; edits/deletes users.
- **Admin** — assigned to ONE branch; sees Staff panel (own branch only) + My Profile card; pinned branch (no switching); new staff locked to admin's branch; cannot touch Branches panel.
- **Clinician / Receptionist** — see only My Profile card + Data panel; pinned branch; no staff/branch management.
- Enforced at the DATA layer (branch-filtered queries), not just hidden UI.

## Branch isolation (DONE this session — the big feature)
Strict per-branch data isolation. Owner sees all (activeBranch = null) or one branch; everyone else is pinned to their branch from login and physically cannot query other branches.

**Per-branch tables** (filtered by `branchId`, stamped on write, watch `activeBranchProvider`):
- Patients (was already correct — the template)
- Appointments — `book()` stamps branch; `watchAppointmentsForDay/Month`, `watchMarkedDays` take `branchId`; `appointmentsForDayProvider`, `appointmentsForMonthProvider`, `markedDaysProvider`, `appointmentsForDayFamilyProvider` pass `activeBranchProvider`
- Invoices — `createInvoice()` stamps branch; `watchInvoices({branchId})`; `invoicesStreamProvider` passes branch
- Inventory — `upsertItem()` stamps branch on NEW rows only; `watchItems({branchId})`; `inventoryStreamProvider` passes branch
- Treatments — `upsertTreatment()` stamps branch on new; `watchTreatments({branchId})`; `treatmentsStreamProvider` passes branch. (Reversed earlier "clinic-wide" decision — now PER-BRANCH. `proceduresProvider`/`procedurePriceProvider` inherit the filter automatically.)
- Dashboard — all 7 `AppDatabase` aggregate methods take `{branchId}`; dashboard providers pass `activeBranchProvider`
- Reports — `reportsSummaryProvider` + `reportsSummaryRangeProvider` filter invoices/patients/appointments by branch
- Users/staff — `staffProvider` filters by branch (admin=own, owner=selected); `totalStaffCountProvider` = seats across ALL branches (count stays total, list filters)
- Settings Branches panel — filtered in-widget by active branch (NOT in the global provider, so switcher keeps full list)
- `dentistsProvider` — filters clinicians by active branch

**Filter pattern everywhere:** `branchId == null ? const Constant(true) : t.branchId.equals(branchId)`.

**Backfill:** `AppDatabase.backfillBranchIds()` stamps legacy null-branch rows (patients/appointments/invoices/inventory/treatments) into the FIRST branch. Run once via temp initState, then removed.

**Switcher UX:** `BranchSwitcher` REMOVED from topbar, now on dashboard only. Switching pops a `DentDialog` confirm ("Switch branch? app reloads…") then `.select()`. Auto-refresh is free via Riverpod (every provider watches `activeBranchProvider`). Owner-only switching; admin/clinician/receptionist see pinned read-only label.

**Stale-dropdown fix:** quick_book_drawer + appointment_editor — dentist/procedure selection resets if the current value leaves the list after a branch switch (`if (list.isEmpty) x=null; else if (x==null || !list.contains(x)) x=list.first;`). Prevents "exactly one item" DropdownButton crash.

## DONE — earlier phases (0–7)
- **Phases 0–5 + cloud:** design system, shell, router, encrypted Drift DB, RSA licensing + 48h gate; Patients (+FDI odontogram, treatment plans), Appointments (+Quick Book), Billing (invoice PDF), Inventory, Reports (fl_chart), Treatments; premium branches + seat-based staff + branch logins; glassmorphic auth screens; self-service onboarding Edge Function (`register-clinic`); full LWW cloud sync (`sync_engine.dart`); live dashboard.
- **Phase 6:** context-aware topbar search + live notifications; patient picker + atomic create-or-book; dashboard perf (live aggregate streams); month-scoped appointment search; patient detail screen (`/patients/:id`); 3D tooth viewer (view-only, `tooth_model_3d.dart`, three_js); appointment Arrived/Bill quick actions (+`billed` flag).
- **Phase 7:** invoice drawer wired + ContextualDrawer cleaned; `pdf_output.dart` shared Print/PDF chooser (printer check + error dialog); reports 12-month + transactions list + `reports_pdf.dart` multi-page A4 + All/Custom-range export; settings Data & Backup (syncNow top-level, `recordSyncNow`/`lastSyncAt`, Manage sheet with 3 export tiles); topbar DB-status dialog.

## DONE (Phase 8 — this session)
- **Live dentists** (`dentistsProvider`) — replaced hardcoded `kDentists`/`kDentistsShort`; streams owner+clinician from Users, branch-filtered. Wired into quick_book_drawer, appointment_editor, appointments_screen dentist filter (exact `==` match now, not `startsWith`).
- **Procedure catalog wiring** — `proceduresProvider` + `procedurePriceProvider` (from `treatmentsStreamProvider`). Booking dropdowns now use live catalog (not hardcoded `kProcedures`); invoice editor auto-fills price when billed from appointment; "Add from catalog" picker in invoice editor; consultation fee = catalog lookup (name contains "consult") first, else `_kFallbackConsultFee = 2000`.
- **Reusable `DentDialog`** (`lib/core/widgets/dent_dialog.dart`): `showDentDialog(context, kind: success/warning/error, title, message, confirmLabel, cancelLabel?, rows: [DentDialogRow(label,value)] copyable, inputLabel?/inputHint?/inputInitial?)`. Returns `Future<bool?>`. Used for staff-created confirmation, logout, delete user/branch, branch-switch confirm.
- **Staff management overhaul** (`staff_editor.dart`):
  - Auto-username `firstname@clinicslug` (slug = clinic name lowercased, non-alphanumeric stripped)
  - Email + Phone fields (both required); needed `Users.email`/`Users.phone` columns (v9)
  - On create: copies `Username:…\nPassword:…` to clipboard silently → closes dialog → shows `DentDialog` success with copyable rows
  - Owner can EDIT users (`updateStaff`, password blank = keep current); admin cannot; edit pencil on non-owner rows (owner only)
  - Branch: owner picks (defaults to active branch, "All branches" removed — must pick specific); admin locked to own branch; validation blocks null branch
  - Soft-delete now tombstones username (`deleted_<ts>_<name>`) so it frees up for reuse; `cleanupDeletedUsernames()` one-time method for legacy stuck names
- **Settings role-gating** — My Profile card (name/role/branch/initials) shown to admin + clinician + receptionist (not owner); Staff panel owner+admin; Branches panel owner only. Logout button (DentDialog confirm → `authControllerProvider.notifier.logout()` → router redirect to /login). Clinic Name + Branch fields locked (read-only w/ lock icon). Delete user/branch → DentDialog confirm.
- **Sidebar footer** — `_userTile` now live from `authControllerProvider` (real name, role label, initials) instead of hardcoded "Dr. Sarah Ahmed".
- **Topbar** — BranchSwitcher removed; `_DbStatusButton` (storage icon → dialog: encryption/sync-mode/last-synced/storage + Settings shortcut); primary "Save Changes" button HIDDEN on settings route (`if route != AppRoutes.settings`).
- **Branch login flow** — confirmed working: `AuthController.login` calls `activeBranchProvider.select(session.branchId)` so branch staff auto-pin, no manual branch pick.

## Schema / DB — current version: **v10**
- v8 → `appointments.billed` (bool)
- v9 → `users.email`, `users.phone` (both nullable text)
- v10 → `treatments.branchId` (nullable text) — for per-branch treatments
- `onUpgrade` ladder: `if(from<10) addColumn(treatments.branchId); if(from<9) addColumn(users.email)+addColumn(users.phone); if(from<8) addColumn(appointments.billed); if(from<7) addColumn(users.branchId); if(from<6) createTable(branches)`
- **Confirmed working** by user (migrations run, treatments per-branch verified).
- Key `AppDatabase` methods: `setAppointmentStatus`, `setAppointmentBilled`, `watchBilledAppointmentIds`, `recordSyncNow`/`lastSyncAt` (key `last_sync_at`), `setAppointmentBranch`-style stamps, `backfillBranchIds()`, `cleanupDeletedUsernames()`, `updateStaff()`, `currentBranchId()`.
- Supabase mirror columns needed: `appointments.status` + `appointments.billed`; `treatments.branch_id`; `users.email`/`users.phone`.

## Key file paths
- `lib/core/widgets/dent_dialog.dart` — reusable success/warning/error dialog (copyable rows + optional input)
- `lib/core/utils/pdf_output.dart` — Print/PDF chooser with printer check
- `lib/features/reports/data/reports_pdf.dart` — multi-page reports PDF
- `lib/features/reports/presentation/reports_controller.dart` — `reportsSummaryProvider`, `reportsSummaryRangeProvider`
- `lib/features/billing/data/invoice_pdf.dart` — invoice PDF (BASIC — flagged for professional redesign, see MOBILE P1)
- `lib/features/billing/presentation/widgets/invoice_editor.dart` — `showInvoiceEditor(context,{patientId?,procedure?})→Future<bool?>`; `_Line` (desc/amt controllers), `_addFromCatalog`, consult-fee auto-add
- `lib/features/appointments/presentation/widgets/quick_book_drawer.dart` + `appointment_editor.dart` — live dentists + procedures, stale-dropdown reset
- `lib/features/appointments/presentation/appointments_controller.dart` — `dentistsProvider`, branch-filtered appointment providers
- `lib/features/treatments/presentation/treatments_controller.dart` — `proceduresProvider`, `procedurePriceProvider`
- `lib/features/settings/presentation/settings_screen.dart` — role-gated panels, My Profile, logout, Manage sheet; `syncNow` top-level
- `lib/features/settings/presentation/staff_editor.dart` — create/edit staff, email/phone, auto-username, DentDialog confirm
- `lib/features/settings/presentation/settings_controller.dart` — `staffProvider` (branch-filtered), `totalStaffCountProvider`
- `lib/features/branches/presentation/branch_controller.dart` — `activeBranchProvider`, `branchesStreamProvider`
- `lib/features/branches/presentation/widgets/branch_switcher.dart` — dashboard-only, owner-switch w/ confirm
- `lib/auth/presentation/auth_controller.dart` — `authControllerProvider` (AuthSession: userId/fullName/username/role/branchId, `.isAdmin`, `.initials`)
- `lib/core/db/app_database.dart` — schema v10, all aggregate + branch methods
- `lib/core/shell/widgets/app_topbar.dart` — search/notifications/DB-status/primary action

## Gotchas
- freezed 3.x → `abstract class`; `dart run build_runner build --delete-conflicting-outputs` after schema/freezed changes.
- Riverpod: `.value` not `.valueOrNull`. Plain `Provider` for `proceduresProvider` (returns List directly, not AsyncValue).
- `createOwner`/`addStaff` MUST set `uuid: Value(Uuids.v4())` or sync skips them.
- Branch-stamp on write: `final Value<String?> stampBranch = x.id==0 ? Value(await _db.currentBranchId()) : const Value.absent();` — type it `Value<String?>` explicitly or Dart infers `Value<dynamic>` and errors.
- Stale dropdown after branch switch → always reset selection if value left the list (crash: "exactly one item with DropdownButton's value").
- macOS needs `com.apple.security.network.client` entitlement.
- three_js / native plugins need full stop + re-run, not hot reload.
- After adding a freezed field (e.g. ReportsSummary), hot reload keeps old constructor → full restart.
- Wipe local DB: quit app, `find ~/Library -name 'dentos.db*' 2>/dev/null -delete`.
- Wipe cloud: Supabase SQL editor, delete child tables before parents (invoice_items, treatment_steps, treatment_plans, tooth_records, invoices, appointments, inventory_items, treatments, users, branches, patients). Keep `clinics` + auth user unless testing full onboarding.
- Backfill/cleanup one-time methods: run via temp initState, then REMOVE the temp block.
- New per-branch tables mean EACH branch needs its own procedures/staff — no shared catalog anymore.

## MOBILE — Patient App (planned, spec approved)
Full spec PDF produced this session: **DentOS_Patient_App_Plan.pdf**. Summary:
- One patient app (Flutter, iOS+Android), published once, serves all DentOS clinics.
- **Linking:** two options up-front — Scan clinic QR OR enter clinic ID. Clinic ID format `SMILE-RWP-01897563` (name-slug + 6-digit random). **New format for NEW clinics only; existing clinic_ids untouched (sync keys on them).**
- **Identity (2 paths):** scan personal patient QR, OR enter CNIC + full name (exact match in that clinic). **No reception approval step. CNIC is mandatory.**
- **Session:** 30-day auto-logout, re-login same way. NO OTP/SMS (zero per-login cost).
- **7 screens:** Link clinic, Verify identity, Home, Book, My Appointments, Profile, Notifications.
- **Booking = request** (clinic approves on desktop, never hard-books).
- **Backend:** 3 tables (patient_accounts, booking_requests, clinic_public), 4 Edge Functions (resolve-clinic, link-patient, available-slots, request-booking), patient RLS (own rows only), FCM notifications.
- **QR signing:** Option B for P1 (unsigned QR, CNIC is the security), add HMAC in P2 with Edge Functions.

### MOBILE Phase P1 — DESKTOP FOUNDATIONS (NEXT TASK, in progress)
This is where we are. Build order:
1. **CNIC column** on Patients (mandatory) — schema migration v11 + editor field (13-digit Pakistani CNIC validation) + Supabase `alter table patients add column cnic text`
2. **Clinic ID revamp** — new `SMILE-RWP-01897563` format (slug + 6-digit random) for new registrations; add `clinic_code` display field; existing clinic_id untouched
3. **Patient QR** — `qr_flutter` package; "Show QR" button on patient detail screen (encodes clinic_id + patient_uuid, unsigned for P1); Settings "Patient App" card with clinic QR + clinic code + Print
4. **Professional invoice redesign** — `invoice_pdf.dart` is currently BASIC/dummy. Rebuild: clinic header/logo, proper billing layout, itemized table, totals, **embedded patient QR** (use `pw.BarcodeWidget` from the pdf package — no new dep), footer. The patient QR on the invoice doubles as their login QR.

**Needed to start P1 (paste inline as TEXT, files arrive empty):**
- current `schemaVersion` (should be 10 → CNIC migration = v11)
- `patient_editor.dart` (add CNIC field)
- `Patients` table class (add `cnic` column in right place)
- confirm QR Option B for P1

## Roadmap (desktop, deferred behind mobile per user's call)
- **Phase 0 — Migration safety harness** (still not built; ~4 migrations done blind; do before next schema change). ⚠ Highest-priority safety item.
- **Phase 1 — Windows build** (user will do later); Payments depth (DEFERRED by user — no outstanding-balance system needed for now); Data import.
- **Phase 2 — Clinical system-of-record:** SOAP notes, medical history + contraindication flags, periodontal charting, imaging, prescriptions, lab case tracking.
- **Phase 3 — Growth:** appointment reminders, recall automation, owner financial reports (A/R aging, production vs collection), auto-update, Urdu localization.
- **Phase 4 — Hardening:** automated tests (sync/migrations/billing), crash reporting, RBAC audit, sync-conflict surfacing (LWW drops losing edit), load test 10k+, record-retention policy.

## PENDING
1. Migration safety harness (schemaVersion now **10** — do before next schema change; CNIC will make it 11).
2. Real RSA modulus + deploy register-clinic + `.env` — license confirmed working; verify deploy state.
3. Full validation pass: registration, offline login, branch logins, cross-clinic RLS, 48h anti-rollback, suspend/renew.
4. SQLCipher native wiring — CONFIRM actually encrypting (user said "everything fine" — treat as done unless proven otherwise).
5. Bundle Sora/Manrope/JetBrains Mono `.ttf` fonts.
6. Supabase mirror columns: `appointments.status`+`billed`, `treatments.branch_id`, `users.email`/`phone`.
7. Windows build (user will do later).
8. Data import from spreadsheets.
9. Owner financial reports (A/R aging, production vs collection).
10. Clinical record completeness (SOAP, medical history, perio, imaging, Rx, lab).
11. Engineering hardening (tests, crash reporting, RBAC audit, sync-conflict, load test).
12. Payments/ledger — DEFERRED by user (not needed for now).

## NEXT TASK
**Mobile Phase P1 — desktop foundations.** Start with CNIC column + migration v11 (needs schemaVersion confirm + patient_editor.dart + Patients table pasted inline). Then clinic ID revamp, patient QR + Settings Patient-App card, professional invoice redesign with embedded QR.
