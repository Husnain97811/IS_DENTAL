# DentOS — PROJECT_STATUS.md

> Continuation file. In a new chat: "Read PROJECT_STATUS.md and continue." Keep this updated as work progresses.

## Role & rules
You are my Principal Flutter Engineer on **DentOS** (folder: `is_dental`) — a production, **staff-only** (NOT patient-facing) dental clinic management system. Build module-by-module, pause cleanly, never ship stubs. The prototype HTML + spec in project knowledge are the authoritative design reference. For any change: give the full file or a precise targeted edit with exact path; if a fix depends on a file you can't see, ask me to paste it rather than guessing. I'm on **macOS (zsh)**; Supabase project ref `ydoixtpgcfivorjecigx`.
> Risk flag: build is currently **macOS-only**; target market mostly runs Windows (see PENDING #8).

## Locked tech + design
- **Stack:** Flutter Desktop + Sizer (`.w/.h/.sp`), Riverpod, Drift + SQLCipher (encrypted local DB = source of truth), freezed 3.x (`abstract class X with _$X`), go_router (StatefulShellRoute, 8 routes), fl_chart, pdf+printing, pointycastle (RSA), bcrypt, flutter_dotenv, supabase_flutter, media_kit (desktop video), **three_js (desktop 3D model viewing via ANGLE)**.
- **Theme** "Futuristic Clinical Minimalist": light canvas + dark sidebar; ice `#38BDF8`, teal `#13E0C4`, teal-deep `#0BB6A0`; fonts Sora/Manrope/JetBrains Mono; colors via `context.dent` (DentColors ThemeExtension).
- **Connectivity:** offline-capable but needs internet ≥ every 48h or fully locks (all tiers); monotonic anti-rollback clock; subscription = signed offline license (`expiresAt`) AND Supabase `clinics.status`/`expires_at` on heartbeat.
- **License:** RSA public modulus is a compile-time constant in `license_verifier.dart` (`_modulus`) AND Edge Function `MODULUS_DEC` (same keypair, never in env). `tool/license_tool.dart` mints licenses.
- Out of scope: WhatsApp/patient messaging (**under review** — see PENDING #9, no-show impact).

## Auth model
- Staff login = fully offline/local (Users table, bcrypt).
- Cloud = ONE Supabase auth account per clinic (owner email+password from setup) with `app_metadata.clinic_id` for RLS.
- Supabase `users` table = backup mirror, not auth.

## DONE (Phases 0–5 + cloud)
- Design system, 3-zone shell, router, 8 routes; encrypted Drift DB; RSA-signed offline licensing + 48h gate + monotonic clock.
- Patients (+FDI odontogram, treatment plans); Appointments (+Quick Book); Billing (invoice PDF) + Inventory; Reports (fl_chart); Treatments module.
- Premium branches + seat-based staff + branch-scoped logins.
- Glassmorphic auth screens (`auth_shell.dart`: media_kit looping video + animated gradient + glass card) for login/setup/locked/reconnect; `main_preview.dart` harness (`flutter run -t lib/main_preview.dart`).
- **Self-service onboarding:** Edge Function `supabase/functions/register-clinic/index.ts` verifies signed license (Web Crypto RSASSA-PKCS1-v1_5 SHA-256), creates Supabase auth user tagged with `clinic_id`, upserts `clinics` row (idempotent on dup email). Flutter `CloudRegistration` called from setup wizard; wizard locks clinic name from license, collects username+email+password, "Retry setup" on failure, stores `cloud_email`/`cloud_password`; `CloudService.ensureSignedIn` reads those.
- **Full cloud sync:** `sync_engine.dart` LWW push/pull by `uuid` for patients (+owned tooth_records & treatment_plans/steps via parent-replace), appointments, invoices (+items), inventory, treatments, branches, users; patient_uuid/invoice_uuid FK remap; fault-tolerant per-table `step()` + debugPrint; `syncNow(ref)` manual trigger. Full Supabase SQL schema + RLS (`auth_clinic_id()`) exists. `completeSetup` fires `_conn.heartbeat(...)` so data uploads right after setup.
- **Dashboard** rewritten from hardcoded → fully live providers (KPIs, schedule, weekly revenue, top procedures, clinic status); Today/Week/Month segment works; Open Calendar→appointments, Details→reports.
- Demo data behind `kSeedDemoData` in `core/constants/app_flags.dart`, guarded by `if (kDebugMode && kSeedDemoData)`.

## DONE (Phase 6 — latest session)
- **Context-aware topbar search + live notifications.** `app_topbar.dart` rewritten: global search routes to the CURRENT screen's data (patients / appointments / treatments→editor / billing→select invoice / inventory); results in an `OverlayPortal` dropdown anchored via `LayerLink`; per-route placeholder + month name for appointments. Notification bell = `MenuAnchor` with real counts (low stock, unpaid invoices, recall-due) and a dot only when count > 0.
- **Patient picker + atomic create-or-book.** `patient_picker_field.dart` (sealed `PatientChoice`: Existing/New; live-filter; auto-commits a choice on each keystroke so Confirm enables instantly). `book_with_new_patient.dart` (`bookWithNewPatientProvider`) runs patient upsert + lookup-by-uuid + appointment book inside ONE `db.transaction` and mints the next `PT-#####`. Wired into the Quick Book drawer and a new **New Appointment dialog** (`showAppointmentEditor(context, {patientId})`).
- **Dashboard performance.** Added live aggregate stream methods to `AppDatabase` (`watchPatientCount`, `watchInTreatmentCount`, `watchAppointmentCount`, `watchPaidRevenue`, `watchUnpaidTotals`, `watchTopProcedures`, `watchPaidInvoicesBetween`); dashboard now consumes keyed `StreamProvider`s instead of loading whole tables.
- **Month-scoped appointment search.** `viewedMonthProvider`; `mini_calendar.dart` is a `ConsumerWidget` driven by it (prev/next arrows write it); `watchAppointmentsForMonth(year,month)` + `appointmentsForMonthProvider`.
- **Patient detail screen.** Route `/patients/:id` → `patient_detail_screen.dart` (back header, quick stats, dedicated Last-Visit card, personal details, visit history, invoices, treatment plan, dental-chart card). Providers `patientByIdProvider`, `appointmentsForPatientProvider`; patients-list row arrow pushes to it.
- **3D tooth viewer (Phase 3a — view-only).** `tooth_model_3d.dart` uses `three_js` (Scene / PerspectiveCamera / Ambient + Directional lights / `OrbitControls` with damping, pan off, distance-clamped / `GLTFLoader.fromAsset`). `_DentalChartCard` adds a **Chart / 3D** toggle: 2D odontogram stays the editable clinical tool; 3D is rotate-only. GLB at `assets/tooth_model_3d_untextured.glb`, declared via the whole `assets/` folder.
- **Appointment quick actions.** Per-row vertical **Arrived / Bill** buttons (`_ApptActions`). Arrived → confirm dialog → `setAppointmentStatus(id, 'waiting')`. Bill → opens the existing invoice dialog **prefilled** (patient + procedure); on successful create it flips a new `billed` flag and the button becomes a disabled **Billed** state. `showInvoiceEditor` now returns `Future<bool?>` (true on create).

## Schema / DB
- Added `billed` `BoolColumn` to **Appointments**; `schemaVersion` bumped to **8** with migration `if (from < 8) await m.addColumn(appointments, appointments.billed);`.
- New `AppDatabase` write methods: `setAppointmentStatus(id, statusName)`, `setAppointmentBilled(id)`; stream `watchBilledAppointmentIds()` + `billedAppointmentIdsProvider`. Appointment status is stored as the enum `.name` string (default `'upcoming'`).
- ⚠ **Reconcile schema history:** the previous note claimed v8 = `users.uuid`, but the live `app_database.dart` was at **7** before this session; `users.uuid` exists with default `''` but has **no dedicated migration** (only `backfillUserUuids()`). The `billed` bump is now the v8 migration. Confirm existing installs actually have `users.uuid`, and add a migration test harness before the next schema change (see PENDING #13).

## Gotchas
- freezed 3.x → `abstract class`; run `dart run build_runner build --delete-conflicting-outputs`.
- Riverpod: `.value` not `.valueOrNull`.
- `createOwner`/`addStaff` MUST set `uuid: Value(Uuids.v4())` or `_syncUsers` skips them (filters empty uuids).
- macOS: needs `com.apple.security.network.client` entitlement or Supabase calls silently fail.
- Edge Function curl: use `body.json` + `--data-binary @body.json` (zsh mangles inline JSON braces); `NOT_FOUND` = not deployed, 401 = redeploy `--no-verify-jwt`.
- Wipe DB: quit app, then `find ~/Library -name 'dentos.db*' 2>/dev/null -delete`.
- **three_js / native plugins need a full stop + re-run; hot reload is insufficient.** three_js symbol names vary by version — match the installed package's example.
- **GLB on hand (`tooth_model_3d_untextured.glb`) is ONE fused mesh (26k verts / 40k tris)** → fine for orbit/rotate, NOT for per-tooth picking. Phase 3b needs a per-tooth-separated, FDI-named GLB (Blender separate, or purchased model).
- **"Unable to load asset"** = pubspec asset not declared / no full restart. Declare the whole `assets/` folder, `flutter pub get`, full restart; `flutter clean` as fallback.
- **Supabase appointments** must have `status text default 'upcoming'` AND `billed boolean default false` for those fields to sync.

## NEXT TASK (do this first)
Context-aware search is **DONE**. Pick the next item — ranked by real-world value:
1. **Migration safety harness** — load an old DB and upgrade it through every version in a test; pair with reconciling the `users.uuid` / schemaVersion history. (Protects live patient data.)
2. **Payments depth** — partial payments, per-patient ledger with running balance, daily cash close (day-sheet), printable receipts, local methods (cash / EasyPaisa / JazzCash).
3. **Clinical notes (SOAP)** per visit + medical history; then **periodontal charting**.
- Still blocked: Phase 3b clickable teeth (needs a separated GLB); expanded 2D `ToothState` conditions (needs `tooth_record.dart`).

## PENDING (later)
1. Paste real RSA modulus into `license_verifier.dart` `_modulus` AND Edge Function `MODULUS_DEC`; deploy `register-clinic`; fill `.env` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); run SQL schema.
2. Full validation: function-in-isolation, end-to-end registration, offline staff login, branch logins across devices, **cross-clinic RLS isolation**, **48h anti-rollback**, suspend/renew.
3. Confirm `createOwner` uuid fix + backfill existing owner so it syncs to `users`.
4. SQLCipher native wiring before release (currently interim `sqlite3_flutter_libs`, `PRAGMA key` commented).
5. Bundle Sora/Manrope/JetBrains Mono `.ttf`; macOS entitlement; "Sync now" button + "last synced" indicator in Settings.
6. Update spec doc: offline operation is 48h-all-tiers.
7. Supabase: add `billed` (and confirm `status`) columns on `appointments`.
8. **Windows build/support** — target market mostly runs Windows; macOS-only severely limits reach. (Deployment blocker.)
9. **Appointment reminders** (WhatsApp hand-off, even manual/pre-filled) — reconsider the out-of-scope call; no-shows are the biggest avoidable revenue leak.
10. **Data import / onboarding** from spreadsheets / old software (clinics won't switch without it).
11. **Owner financial reports** — A/R ageing, production vs collection, per-provider productivity.
12. **Clinical record completeness** — SOAP notes; medical history (meds, conditions, ASA, contraindication flags); periodontal charting (6-point pockets, BOP, recession); imaging storage (X-ray/photo per patient/tooth); prescriptions + signed consent; dental lab case tracking.
13. **Engineering hardening** — automated tests (sync, migrations, billing maths); crash/error reporting; RBAC enforcement audit (data layer, not just UI); proven backup/restore + DR; sync-conflict surfacing (LWW silently drops edits); load test at 10k+ patients; in-app auto-update; record-retention policy.
