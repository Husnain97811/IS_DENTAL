# DentOS — QA Test Plan

A practical test plan for the current build. Work top-to-bottom on a **fresh database** the first time, then use the regression checklist after every change.

---

## 0. Test builds & clean state

DentOS behaves differently in debug vs release because of the demo seed.

| Build | Command | Behaviour |
|---|---|---|
| **Debug (seeded)** | `flutter run` | Tables auto-fill with prototype demo data when empty. Good for UI testing. |
| **Release (clean)** | `flutter run --release` | No seeding. Empty until you enter real records. This is what the clinic ships. |

**Wipe to a clean state** (forces the setup wizard + empty tables on next launch):
```bash
find ~/Library -name 'dentos.db*' 2>/dev/null   # locate
# then delete the .db, .db-wal, .db-shm it lists:
rm "<path>/dentos.db" "<path>/dentos.db-wal" "<path>/dentos.db-shm"
```
(On Windows the DB lives under `%APPDATA%`/the app support folder — search for `dentos.db`.)

Test on the **OS the clinic will actually run** (macOS or Windows desktop), not just your dev machine.

---

## 1. Pre-flight (run before any manual testing)

- [ ] `dart analyze` returns **no errors** (info-level lints are fine). This is ground truth — fix errors before touching the UI.
- [ ] `flutter test` runs. ⚠️ The default `test/widget_test.dart` references `MyApp` and will fail — delete or rewrite it first, or `flutter test` reports a false failure.
- [ ] App launches without a hung splash. (If splash spins forever, the license controller threw — check console.)

---

## 2. Smoke test (5-minute happy path)

Do this first on a clean DB. If any step dead-ends, stop and fix before deeper testing.

- [ ] Launch → **Setup wizard** appears (activation → clinic profile → owner account).
- [ ] Activate with a valid license → profile step → create owner → lands on **Login**.
- [ ] Log in with the owner credentials → **Dashboard** renders.
- [ ] Navigate all 8 sidebar routes — no crashes, each screen draws.
- [ ] Toggle theme (sun/moon) and collapse the sidebar (⌘/Ctrl+B) — layout holds.
- [ ] Add one patient, one inventory item, one invoice (see §4). Each appears immediately.
- [ ] Quit and relaunch → you go straight to Login (not setup), and your records are still there.

---

## 3. Licensing & lifecycle (the critical, app-specific paths)

These are the highest-risk areas — a bug here locks a paying clinic out, or lets an expired one in.

### Activation
- [ ] **Valid license** → activates, proceeds to setup.
- [ ] **Tampered license** → edit one character of the signature in `license.json`, re-activate → rejected as **invalid**.
- [ ] **Expired license** → generate one with `expiresAt` in the past via `dart run tool/license_tool.dart` → app routes to the **Locked** screen, not the shell.

### 48-hour connectivity gate
- [ ] **Happy heartbeat:** with internet, the app silently records contact; no lock.
- [ ] **Force the lock (shorten the window to test):** temporarily set the window constant in `connectivity_service.dart` to `Duration(minutes: 2)`, run, then disconnect Wi-Fi and wait past the window → app routes to **Reconnect Required**. Reconnect → it clears. *(Revert the constant after.)*
- [ ] **Anti-rollback:** record a contact, then move the system clock **backward** a day. The monotonic clock must **not** grant extra offline time — the reconnect requirement should still trigger on schedule. This is the key anti-cheat check.

### Login & session
- [ ] **Wrong password ×5** → account locks for the lockout window (shorten the duration temporarily to verify, then revert).
- [ ] **Idle auto-logout:** temporarily lower the idle timer in `idle_lock.dart` from `Duration(minutes: 10)` to `Duration(seconds: 30)`, leave the app untouched → it auto-locks back to Login. *(Revert.)*

### Persistence / encryption
- [ ] Enter data → quit → relaunch → data persists.
- [ ] Confirm the on-disk `dentos.db` is the active store. *(Note: SQLCipher native wiring is deferred, so the dev DB is currently plain SQLite — see §7. Encryption-at-rest is a release-gate item, not a current bug.)*

---

## 4. Editors (newest code — test hardest)

### Add / Edit Patient
- [ ] Open **Add Patient** → empty **Full name** → Save does nothing (blocked). ✅ expected.
- [ ] Name only, rest blank → saves; row appears **instantly** in the table; balance `Rs 0`, correct status chip.
- [ ] Non-numeric **Age** → saves as `0` (no crash).
- [ ] Add an **allergy** + **insurance** → open the patient snapshot drawer → tags render.
- [ ] Relaunch → patient still present.
- [ ] Tap teeth in the odontogram → state cycles and **persists** across relaunch.

### Add / Edit Inventory item
- [ ] Stock `5`, reorder-at `10` → status computes **Low/Critical**, level bar colours accordingly.
- [ ] Stock `0` → **Critical/Out** state.
- [ ] Stock well above reorder → **In Stock** (green bar). Verify the threshold boundaries (`StockLevel` ok/low/critical) flip at the right numbers.

### New Invoice
- [ ] **Create** button is disabled until a patient is selected. ✅ expected.
- [ ] Add 3 line items; try to remove the **last remaining** line → blocked (can't go to zero).
- [ ] Type a non-numeric amount → it's ignored in the running total (no crash).
- [ ] Set an **insurance adjustment** → **Total** updates live (`subtotal − adjustment`).
- [ ] Save → invoice appears in **Recent Invoices** → click it → preview drawer shows correct figures.
- [ ] **Print / PDF** → system print dialog opens; the PDF totals match the editor.
- [ ] **Mark as Paid** → status flips to Paid; the Billing KPIs and Reports recompute.

### Reactivity (verify after each add)
- [ ] Lists update **without** a manual refresh (Riverpod streams). If you ever need to refresh by hand, that's a bug.

---

## 5. Negative & edge cases

- [ ] Very long names / special characters (`'`, `&`, emoji, RTL Urdu text) in all text fields — no layout break, no SQL error.
- [ ] Huge numbers (e.g. stock `99999999`, invoice amount in millions) — totals format correctly, no overflow.
- [ ] Negative amounts/adjustment — decide intended behaviour and confirm it (likely should be blocked or clamped).
- [ ] Rapid double-click on **Save / Create** — must not create duplicate records (the `_busy` guard should prevent this; verify).
- [ ] Cancel mid-edit — nothing persists.
- [ ] Open an editor, quit the app from the OS while it's open — clean exit, no corruption on relaunch.

---

## 6. Module spot-checks

- [ ] **Dashboard** — KPIs and the schedule reflect real data after you've added records (not just demo numbers).
- [ ] **Appointments** — Quick Book writes a real appointment; it shows on the agenda and the mini-calendar dot updates.
- [ ] **Reports** — after creating/paying invoices, the revenue bar chart, procedure-mix donut, and dentist table change accordingly.
- [ ] **Settings** — dark-mode toggle here matches the topbar toggle; profile fields reflect what you set in the wizard.

---

## 7. Known limitations — **do NOT file as bugs**

These are intentional/deferred per the build plan:

- **Demo seed data in debug builds** — by design; gone in release / after a DB wipe.
- **SQLCipher encryption is deferred** — dev DB is plain SQLite (`PRAGMA key` commented). Encryption-at-rest is a pre-release task, not a defect now.
- **Premium multi-branch / multi-user UI** — not built yet (next milestone).
- **6 sync tables** (appointments, invoices, invoice_items, tooth_records, treatment_plans, treatment_steps) — not yet wired to the cloud; only patients + inventory sync today.
- **WhatsApp / patient messaging** — out of scope entirely (staff-only system).
- **Placeholder license key / Supabase creds** — must be replaced with real values before any real-world test of activation or sync.

---

## 8. Regression checklist (run after every change)

1. `dart analyze` clean.
2. Smoke test (§2) on a fresh DB.
3. Re-test whatever module you touched, plus its editor.
4. Confirm persistence (quit/relaunch).
5. If you touched licensing/connectivity/auth — re-run the full §3.

> Tip: keep a copy of a **valid license.json** and a known-good `.env` in a scratch folder so you can re-provision a clean install in seconds.