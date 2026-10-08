import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/cloud_service.dart';
import 'package:is_dental/core/utils/uuids.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/db/app_database.dart';

class SyncEngine {
  SyncEngine(this._db);
  final AppDatabase _db;
  final SupabaseClient _sb = Supabase.instance.client;

  Future<String> syncNow(WidgetRef ref) async {
    try {
      debugPrint('SYNC: signing in…');
      await ref.read(cloudServiceProvider).ensureSignedIn();
      final clinicId = await ref.read(appDatabaseProvider).currentClinicId();
      debugPrint('SYNC: start for $clinicId');
      await ref.read(syncEngineProvider).syncAll(clinicId!);
      debugPrint('SYNC: done');
      return 'Synced';
    } catch (e) {
      debugPrint('SYNC: FAILED $e');
      return 'Sync failed: $e';
    }
  }

  Future<void> syncAll(String clinicId) async {
    _skipped.clear();
    Future<void> step(String name, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('SYNC[$name] failed: $e');
      }
    }

    await step('patients', () => _syncPatients(clinicId));
    await step('branches', () => _syncBranches(clinicId));
    await step('treatments', () => _syncTreatments(clinicId));
    await step('medicines', () => _syncMedicines(clinicId));
    await step('precaution_sets', () => _syncPrecautionSets(clinicId));
    await step('inventory', () => _syncInventory(clinicId));
    await step('users', () => _syncUsers(clinicId));
    await step('appointments', () => _syncAppointments(clinicId));
    await step('booking_requests', () => _syncBookingRequests(clinicId));
    await step('permissions', () => _syncPermissions(clinicId));
    await step('offers', () => _syncOffers(clinicId));

    await step('invoices', () => _syncInvoices(clinicId));
    // payments AFTER invoices — a payment needs its invoice to exist locally
    await step('payments', () => _syncPayments(clinicId));
    await step('lookups', () => _syncLookups(clinicId));
    await step('devices', () => _syncDevices(clinicId));
    await step('expenses', () => _syncExpenses(clinicId));
    // housekeeping — remove decided requests older than 30 days
    await step('purge_requests', () => _db.purgeOldDecidedRequests());

    // Mark this computer alive, so the owner can spot a dead machine.
    await step('device_seen', () => _db.touchThisDevice());

    // A skipped row used to vanish into a debugPrint. Store it so the
    // owner can see that something didn't come through.
    await _db.setSetting('sync_skipped', _skipped.take(50).join(','));
    await _db.setSetting('sync_skipped_count', '${_skipped.length}');
    if (_skipped.isNotEmpty) {
      debugPrint('SYNC: ${_skipped.length} row(s) skipped: $_skipped');
    }
  }

  /// DESTRUCTIVE: wipes ALL local data and re-downloads everything fresh from
  /// the cloud. Forces cloud to win — ignores the LWW timestamp guard.
  /// Any local changes not yet pushed are LOST. Use only to recover from a
  /// bad local state by restoring the last cloud version.
  Future<void> restoreFromCloud(String clinicId) async {
    // Everything below is about to be emptied and refilled from the cloud.
    // From this point on this install must never create factory defaults —
    // an empty table means "not pulled yet", not "new clinic".
    await _db.setSeedAllowed(false);

    // 1. wipe local tables (children before parents to respect FKs)
    await _db.transaction(() async {
      await _db.delete(_db.invoiceItems).go();
      await _db.delete(_db.invoicePayments).go();
      await _db.delete(_db.treatmentSteps).go();
      await _db.delete(_db.treatmentPlans).go();
      await _db.delete(_db.toothRecords).go();
      await _db.delete(_db.invoices).go();
      await _db.delete(_db.appointments).go();
      await _db.delete(_db.bookingRequests).go();
      await _db.delete(_db.inventoryItems).go();
      await _db.delete(_db.treatments).go();
      await _db.delete(_db.users).go();
      await _db.delete(_db.branches).go();
      await _db.delete(_db.patients).go();
      await _db.delete(_db.prescriptionItems).go();
      await _db.delete(_db.prescriptionCare).go();
      await _db.delete(_db.prescriptions).go();
      await _db.delete(_db.precautionLines).go();
      await _db.delete(_db.precautionSets).go();
      await _db.delete(_db.medicines).go();
      await _db.delete(_db.offers).go();
      await _db.delete(_db.rolePermissions).go();
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.lookupLists).go();
      await _db.delete(_db.devices).go();
      // ⚠ DO NOT wipe patientXrays — X-rays are LOCAL-ONLY and not in the
      // cloud. Deleting them here would destroy them permanently.
    });

    // 2. reset all sync cursors so pulls fetch EVERYTHING from the start
    final cursorKeys = [
      'pull_patients',
      'push_patients',
      'pull_appointments',
      'push_appointments',
      'pull_offers',
      'push_offers',
      'pull_permissions',
      'push_permissions',

      'pull_medicines',
      'push_medicines',
      'pull_precaution_sets',
      'push_precaution_sets',
      'pull_invoices',
      'push_invoices',
      'pull_inventory',
      'push_inventory',
      'pull_treatments',
      'push_treatments',
      'pull_branches',
      'push_branches',
      'pull_users',
      'push_users',
      'pull_booking_requests',
      'push_booking_requests',
      'pull_payments',
      'push_payments',
      'pull_lookups',
      'push_lookups',
      'pull_expenses',
      'push_expenses',
      'pull_devices',
      'push_devices',
    ];
    for (final k in cursorKeys) {
      await _db.setSetting('sync_$k', '');
    }

    // 3. pull everything fresh from cloud (parents before children)
    _skipped.clear();
    Future<void> part(String name, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        _skipped.add(name);
        debugPrint('RESTORE[$name] failed: $e');
      }
    }

    await part('branches', () => _restoreBranches(clinicId));
    await part('users', () => _restoreUsers(clinicId));
    await part('patients', () => _restorePatients(clinicId));
    await part('treatments', () => _restoreTreatments(clinicId));
    await part('inventory', () => _restoreInventory(clinicId));
    await part('appointments', () => _restoreAppointments(clinicId));
    await part('medicines', () => _restoreMedicines(clinicId));
    await part('precaution_sets', () => _restorePrecautionSets(clinicId));
    await part('booking_requests', () => _restoreBookingRequests(clinicId));
    await part('invoices', () => _restoreInvoices(clinicId));
    await part('permissions', () => _restorePermissions(clinicId));
    await part('offers', () => _restoreOffers(clinicId));
    await part('lookups', () => _restoreLookups(clinicId));
    await part('devices', () => _restoreDevices(clinicId));
    await part('expenses', () => _restoreExpenses(clinicId));
    await part('payments', () => _restorePayments(clinicId)); // after invoices
    // amountPaid and patients.balance are CACHES. The restored values came
    // from whichever machine pushed last; rebuild them from the payments
    // that actually landed here.
    await _db.recalcAllPaidAndBalances();

    await _db.setSetting('sync_skipped', _skipped.take(50).join(','));
    await _db.setSetting('sync_skipped_count', '${_skipped.length}');
  }

  Future<List<Map<String, dynamic>>> _pullAll(
    String t,
    String clinicId,
  ) async => ((await _sb.from(t).select().eq('clinic_id', clinicId)) as List)
      .cast<Map<String, dynamic>>();

  Future<void> _restoreBranches(String clinicId) async {
    for (final r in await _pullAll('branches', clinicId)) {
      await _db
          .into(_db.branches)
          .insert(
            BranchesCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              name: Value(r['name'] ?? ''),
              location: Value(r['location'] ?? ''),
              isPrimary: Value(r['is_primary'] ?? false),
              openMinutes: Value(r['open_minutes'] ?? 600),
              closeMinutes: Value(r['close_minutes'] ?? 1020),
              slotMinutes: Value(r['slot_minutes'] ?? 20),
              closedDays: Value(r['closed_days'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
              waEnabled: Value(r['wa_enabled'] ?? false),
              waMethod: Value(r['wa_method'] ?? 'official'),
              waPhone: Value(r['wa_phone']),
              waApiToken: Value(r['wa_api_token']),
              waPhoneId: Value(r['wa_phone_id']),
              waSessionStatus: Value(r['wa_session_status']),
              waQrStatus: Value(r['wa_qr_status']),
              waReminderChannel: Value(r['wa_reminder_channel'] ?? 'none'),
              waLanguage: Value(r['wa_language'] ?? 'en'),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreUsers(String clinicId) async {
    for (final r in await _pullAll('users', clinicId)) {
      await _db
          .into(_db.users)
          .insert(
            UsersCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              fullName: Value(r['full_name'] ?? ''),
              username: Value(r['username'] ?? ''),
              passwordHash: Value(r['password_hash'] ?? ''),
              role: Value(r['role'] ?? 'receptionist'),
              email: Value(r['email']),
              phone: Value(r['phone']),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restorePatients(String clinicId) async {
    for (final r in await _pullAll('patients', clinicId)) {
      final localId = await _db
          .into(_db.patients)
          .insert(
            PatientsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              code: Value(r['code'] ?? ''),
              fullName: Value(r['full_name'] ?? ''),
              gender: Value(r['gender'] ?? 'female'),
              age: Value(r['age'] ?? 0),
              phone: Value(r['phone'] ?? ''),
              cnic: Value(r['cnic'] ?? ''),
              allergies: Value(r['allergies']),
              insurance: Value(r['insurance']),
              lastVisit: Value(
                r['last_visit'] == null
                    ? null
                    : DateTime.parse(r['last_visit']),
              ),
              visitCount: Value(r['visit_count'] ?? 0),
              balance: Value(r['balance'] ?? 0),
              status: Value(r['status'] ?? 'active'),
              treatmentSummary: Value(r['treatment_summary'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
      await _pullPatientChildren(r['uuid'], localId, clinicId);
    }
  }

  Future<void> _restoreTreatments(String clinicId) async {
    for (final r in await _pullAll('treatments', clinicId)) {
      await _db
          .into(_db.treatments)
          .insert(
            TreatmentsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),

              name: Value(r['name'] ?? ''),
              category: Value(r['category'] ?? ''),
              price: Value(r['price'] ?? 0),
              duration: Value(r['duration'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreInventory(String clinicId) async {
    for (final r in await _pullAll('inventory_items', clinicId)) {
      await _db
          .into(_db.inventoryItems)
          .insert(
            InventoryItemsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              name: Value(r['name'] ?? ''),
              category: Value(r['category'] ?? ''),
              inStock: Value(r['in_stock'] ?? 0),
              parLevel: Value(r['par_level'] ?? 0),
              reorderAt: Value(r['reorder_at'] ?? 0),
              unit: Value(r['unit'] ?? 'units'),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreAppointments(String clinicId) async {
    for (final r in await _pullAll('appointments', clinicId)) {
      final localPid = await _patientId(r['patient_uuid']);
      if (localPid == null) continue;
      await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientId: Value(localPid),
              dentist: Value(r['dentist'] ?? ''),
              chair: Value(r['chair'] ?? 1),
              procedure: Value(r['procedure'] ?? ''),
              billed: Value(r['billed'] ?? false),
              startsAt: Value(DateTime.parse(r['starts_at'])),
              durationMin: Value(r['duration_min'] ?? 30),
              status: Value(r['status'] ?? 'upcoming'),
              notes: Value(r['notes']),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreBookingRequests(String clinicId) async {
    for (final r in await _pullAll('booking_requests', clinicId)) {
      await _db
          .into(_db.bookingRequests)
          .insert(
            BookingRequestsCompanion(
              uuid: Value(r['id']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientUuid: Value(r['patient_uuid'] ?? ''),
              patientAccountId: Value(r['patient_account_id']),
              dentist: Value(r['dentist'] ?? ''),
              procedure: Value(r['procedure'] ?? ''),
              requestedSlot: Value(DateTime.parse(r['requested_slot'])),
              durationMin: Value(r['duration_min'] ?? 30),
              status: Value(r['status'] ?? 'pending'),
              modifiedBy: Value(r['modified_by']),
              acceptedBy: Value(r['accepted_by']),
              decidedAt: Value(
                r['decided_at'] == null
                    ? null
                    : DateTime.parse(r['decided_at']),
              ),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreInvoices(String clinicId) async {
    for (final r in await _pullAll('invoices', clinicId)) {
      final localPid = await _patientId(r['patient_uuid']);
      if (localPid == null) continue;
      final localApptId = r['appointment_uuid'] == null
          ? null
          : await _appointmentId(r['appointment_uuid']);
      final invId = await _db
          .into(_db.invoices)
          .insert(
            InvoicesCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientId: Value(localPid),
              appointmentId: Value(localApptId),
              invoiceNo: Value(r['invoice_no'] ?? ''),
              issuedAt: Value(DateTime.parse(r['issued_at'])),
              status: Value(r['status'] ?? 'pending'),
              cancelledBy: Value(r['cancelled_by']),
              cancelledAt: Value(
                r['cancelled_at'] == null
                    ? null
                    : DateTime.parse(r['cancelled_at']),
              ),
              summary: Value(r['summary'] ?? ''),
              subtotal: Value(r['subtotal'] ?? 0),
              adjustment: Value(r['adjustment'] ?? 0),
              total: Value(r['total'] ?? 0),
              amountPaid: Value(r['amount_paid'] ?? 0),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
      final items =
          (await _sb
                  .from('invoice_items')
                  .select()
                  .eq('invoice_uuid', r['uuid'])
                  .order('position'))
              as List;
      for (final it in items) {
        await _db
            .into(_db.invoiceItems)
            .insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                description: it['description'] ?? '',
                amount: it['amount'] ?? 0,
                qty: Value(it['qty'] ?? 1),
              ),
            );
      }
    }
  }

  Future<void> _restoreMedicines(String clinicId) async {
    for (final r in await _pullAll('medicines', clinicId)) {
      await _db
          .into(_db.medicines)
          .insert(
            MedicinesCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              name: Value(r['name'] ?? ''),
              form: Value(r['form'] ?? ''),
              defaultDosage: Value(r['default_dosage'] ?? ''),
              defaultFrequency: Value(r['default_frequency'] ?? ''),
              category: Value(r['category'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restorePrecautionSets(String clinicId) async {
    for (final r in await _pullAll('precaution_sets', clinicId)) {
      final setId = await _db
          .into(_db.precautionSets)
          .insert(
            PrecautionSetsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              name: Value(r['name'] ?? ''),
              position: Value(r['position'] ?? 0),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
      for (final l in (r['lines'] as List? ?? const [])) {
        await _db
            .into(_db.precautionLines)
            .insert(
              PrecautionLinesCompanion.insert(
                setId: setId,
                position: Value(l['position'] ?? 0),
                urdu: Value(l['urdu'] ?? ''),
                english: Value(l['english'] ?? ''),
              ),
            );
      }
    }
  }

  Future<void> _restoreOffers(String clinicId) async {
    for (final r in await _pullAll('offers', clinicId)) {
      await _db
          .into(_db.offers)
          .insert(
            OffersCompanion(
              uuid: Value(r['id']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              title: Value(r['title'] ?? ''),
              body: Value(r['body'] ?? ''),
              imageUrl: Value(r['image_url']),
              startsAt: Value(
                r['starts_at'] == null ? null : DateTime.parse(r['starts_at']),
              ),
              expiresAt: Value(
                r['expires_at'] == null
                    ? null
                    : DateTime.parse(r['expires_at']),
              ),
              sentCount: Value(r['sent_count'] ?? 0),
              sentApp: Value(r['sent_app'] ?? true),
              sentWhatsApp: Value(r['sent_whats_app'] ?? false),
              createdBy: Value(r['created_by']),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreLookups(String clinicId) async {
    for (final r in await _pullAll('lookup_lists', clinicId)) {
      await _db
          .into(_db.lookupLists)
          .insert(
            LookupListsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              kind: Value(r['kind'] ?? ''),
              name: Value(r['name'] ?? ''),
              sortOrder: Value(r['sort_order'] ?? 0),
              isSystem: Value(r['is_system'] ?? false),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreDevices(String clinicId) async {
    for (final r in await _pullAll('devices', clinicId)) {
      await _db
          .into(_db.devices)
          .insert(
            DevicesCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              letter: Value(r['letter'] ?? 'A'),
              name: Value(r['name'] ?? ''),
              platform: Value(r['platform'] ?? ''),
              joinedByName: Value(r['joined_by_name'] ?? ''),
              joinedAt: Value(
                r['joined_at'] == null
                    ? DateTime.now()
                    : DateTime.parse(r['joined_at']),
              ),
              lastSeenAt: Value(
                r['last_seen_at'] == null
                    ? null
                    : DateTime.parse(r['last_seen_at']),
              ),
              isActive: Value(r['is_active'] ?? true),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restoreExpenses(String clinicId) async {
    for (final r in await _pullAll('expenses', clinicId)) {
      await _db
          .into(_db.expenses)
          .insert(
            ExpensesCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id'] ?? ''),
              categoryUuid: Value(r['category_uuid'] ?? ''),
              amount: Value(r['amount'] ?? 0),
              paidAt: Value(DateTime.parse(r['paid_at'])),
              description: Value(r['description'] ?? ''),
              vendor: Value(r['vendor']),
              method: Value(r['method'] ?? 'Cash'),
              methodDetail: Value(r['method_detail']),
              reference: Value(r['reference']),
              recordedByName: Value(r['recorded_by_name'] ?? ''),
              updatedByName: Value(r['updated_by_name']),
              sourceType: Value(r['source_type']),
              sourceUuid: Value(r['source_uuid']),
              isDeleted: Value(r['is_deleted'] ?? false),
              deletedByName: Value(r['deleted_by_name']),
              deletedAt: Value(
                r['deleted_at'] == null
                    ? null
                    : DateTime.parse(r['deleted_at']),
              ),
              deleteReason: Value(r['delete_reason']),
              createdAt: Value(
                r['created_at'] == null
                    ? DateTime.now()
                    : DateTime.parse(r['created_at']),
              ),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restorePayments(String clinicId) async {
    for (final r in await _pullAll('invoice_payments', clinicId)) {
      final invId = await _invoiceId(r['invoice_uuid']);
      if (invId == null) continue; // invoice gone or cancelled upstream
      await _db
          .into(_db.invoicePayments)
          .insert(
            InvoicePaymentsCompanion(
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              invoiceId: Value(invId),
              invoiceUuid: Value(r['invoice_uuid']),
              amount: Value(r['amount'] ?? 0),
              paidAt: Value(DateTime.parse(r['paid_at'])),
              method: Value(r['method'] ?? 'Cash'),
              methodDetail: Value(r['method_detail']),
              reference: Value(r['reference']),
              receivedByName: Value(r['received_by_name'] ?? ''),
              note: Value(r['note'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              deletedByName: Value(r['deleted_by_name']),
              deletedAt: Value(
                r['deleted_at'] == null
                    ? null
                    : DateTime.parse(r['deleted_at']),
              ),
              createdAt: Value(
                r['created_at'] == null
                    ? DateTime.now()
                    : DateTime.parse(r['created_at']),
              ),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<void> _restorePermissions(String clinicId) async {
    for (final r in await _pullAll('role_permissions', clinicId)) {
      await _db
          .into(_db.rolePermissions)
          .insert(
            RolePermissionsCompanion.insert(
              clinicId: clinicId,
              role: r['role'],
              key: r['key'],
              allowed: Value(r['allowed'] ?? false),
              updatedAt: Value(DateTime.parse(r['updated_at'])),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  // ---- cursor + helpers ----
  Future<DateTime> _cur(String k) async =>
      DateTime.tryParse(await _db.getSetting('sync_$k') ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _setCur(String k, DateTime t) =>
      _db.setSetting('sync_$k', t.toUtc().toIso8601String());
  DateTime _max(Iterable<DateTime> xs) =>
      xs.reduce((a, b) => a.isAfter(b) ? a : b);
  String? _iso(DateTime? d) => d?.toUtc().toIso8601String();
  Future<List<Map<String, dynamic>>> _pull(
    String t,
    String clinicId,
    DateTime since,
  ) async =>
      ((await _sb
                  .from(t)
                  .select()
                  .eq('clinic_id', clinicId)
                  .gt('updated_at', since.toUtc().toIso8601String()))
              as List)
          .cast<Map<String, dynamic>>();

  /// Rows skipped in this run, so a silent failure becomes a visible one.
  final List<String> _skipped = [];

  /// Applies one pulled row. A row that throws — a duplicate patient code,
  /// a malformed date — is recorded and skipped, NOT allowed to escape.
  ///
  /// Without this, one bad row aborts the whole table's pull, and because
  /// appointments/invoices/prescriptions skip rows whose patient isn't local
  /// yet, a single collision stalls the entire clinic's sync indefinitely.
  Future<void> _row(
    String table,
    Object? id,
    Future<void> Function() apply,
  ) async {
    try {
      await apply();
    } catch (e) {
      final key = '$table:$id';
      _skipped.add(key);
      debugPrint('SYNC[$table] SKIPPED row $id: $e');
    }
  }

  Future<String?> _patientUuid(int id) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.uuid;

  Future<String?> _appointmentUuid(int id) async => (await (_db.select(
    _db.appointments,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.uuid;

  Future<int?> _appointmentId(String uuid) async => (await (_db.select(
    _db.appointments,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull())?.id;
  Future<int?> _patientId(String uuid) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull())?.id;

  Future<int?> _invoiceId(String uuid) async => (await (_db.select(
    _db.invoices,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull())?.id;

  // ================= PATIENTS (+ owned tooth/plans) =================
  Future<void> _syncPatients(String clinicId) async {
    final since = await _cur('push_patients');
    final changed = await (_db.select(
      _db.patients,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('patients').upsert([
        for (final p in changed)
          {
            'uuid': p.uuid,
            'clinic_id': clinicId,
            'branch_id': p.branchId,
            'code': p.code,
            'full_name': p.fullName,
            'gender': p.gender,
            'age': p.age,
            'phone': p.phone,
            'cnic': p.cnic,
            'allergies': p.allergies,
            'insurance': p.insurance,
            'last_visit': _iso(p.lastVisit),
            'visit_count': p.visitCount,
            'balance': p.balance,
            'status': p.status,
            'treatment_summary': p.treatmentSummary,
            'is_deleted': p.isDeleted,
            'updated_at': _iso(p.updatedAt),
          },
      ], onConflict: 'uuid');
      for (final p in changed) await _pushPatientChildren(p, clinicId);
      await _setCur('push_patients', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_patients');
    for (final r in await _pull('patients', clinicId, pullSince)) {
      await _row('patients', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.patients,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.patients)
            .insertOnConflictUpdate(
              PatientsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                code: Value(r['code'] ?? ''),
                fullName: Value(r['full_name'] ?? ''),
                gender: Value(r['gender'] ?? 'female'),
                age: Value(r['age'] ?? 0),
                phone: Value(r['phone'] ?? ''),
                cnic: Value(r['cnic'] ?? ''),
                allergies: Value(r['allergies']),
                insurance: Value(r['insurance']),
                lastVisit: Value(
                  r['last_visit'] == null
                      ? null
                      : DateTime.parse(r['last_visit']),
                ),
                visitCount: Value(r['visit_count'] ?? 0),
                balance: Value(r['balance'] ?? 0),
                status: Value(r['status'] ?? 'active'),
                treatmentSummary: Value(r['treatment_summary'] ?? ''),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        final localId = await _patientId(r['uuid']);
        if (localId != null)
          await _pullPatientChildren(r['uuid'], localId, clinicId);
        if (u.isAfter(pullSince)) await _setCur('pull_patients', u);
      });
    }
  }

  Future<void> _pushPatientChildren(PatientRow p, String clinicId) async {
    final teeth = await (_db.select(
      _db.toothRecords,
    )..where((t) => t.patientId.equals(p.id))).get();
    await _sb.from('tooth_records').delete().eq('patient_uuid', p.uuid);
    if (teeth.isNotEmpty) {
      await _sb.from('tooth_records').insert([
        for (final t in teeth)
          {
            'clinic_id': clinicId,
            'patient_uuid': p.uuid,
            'fdi': t.fdi,
            'state': t.state,
            'note': t.note,
          },
      ]);
    }
    final plans = await (_db.select(
      _db.treatmentPlans,
    )..where((t) => t.patientId.equals(p.id))).get();
    await _sb.from('treatment_plans').delete().eq('patient_uuid', p.uuid);
    for (final pl in plans) {
      final steps =
          await (_db.select(_db.treatmentSteps)
                ..where((s) => s.planId.equals(pl.id))
                ..orderBy([(s) => OrderingTerm.asc(s.position)]))
              .get();
      await _sb.from('treatment_plans').insert({
        'clinic_id': clinicId,
        'patient_uuid': p.uuid,
        'title': pl.title,
        'is_deleted': pl.isDeleted,
        'steps': [
          for (final s in steps)
            {
              'position': s.position,
              'label': s.label,
              'detail': s.detail,
              'status': s.status,
              'completed_at': _iso(s.completedAt), // ← NEW
            },
        ],
      });
    }

    // ── prescriptions (items + care as JSON, like treatment plans) ──
    final rxs = await (_db.select(
      _db.prescriptions,
    )..where((t) => t.patientId.equals(p.id))).get();
    await _sb.from('prescriptions').delete().eq('patient_uuid', p.uuid);
    for (final rx in rxs) {
      final items =
          await (_db.select(_db.prescriptionItems)
                ..where((t) => t.prescriptionId.equals(rx.id))
                ..orderBy([(t) => OrderingTerm.asc(t.position)]))
              .get();
      final care =
          await (_db.select(_db.prescriptionCare)
                ..where((t) => t.prescriptionId.equals(rx.id))
                ..orderBy([(t) => OrderingTerm.asc(t.position)]))
              .get();
      await _sb.from('prescriptions').insert({
        'clinic_id': clinicId,
        'branch_id': rx.branchId,
        'patient_uuid': p.uuid,
        'rx_no': rx.rxNo,
        'appointment_label': rx.appointmentLabel,
        'doctor_name': rx.doctorName,
        'advice': rx.advice,
        'issued_at': _iso(rx.issuedAt),
        'is_deleted': rx.isDeleted,
        'items': [
          for (final i in items)
            {
              'position': i.position,
              'medicine': i.medicine,
              'dosage': i.dosage,
              'frequency': i.frequency,
              'duration': i.duration,
              'instructions': i.instructions,
            },
        ],
        'care': [
          for (final c in care)
            {'position': c.position, 'urdu': c.urdu, 'english': c.english},
        ],
      });
    }
  }

  Future<void> _pullPatientChildren(
    String patientUuid,
    int localId,
    String clinicId,
  ) async {
    final teeth =
        (await _sb
                .from('tooth_records')
                .select()
                .eq('patient_uuid', patientUuid))
            as List;
    await (_db.delete(
      _db.toothRecords,
    )..where((t) => t.patientId.equals(localId))).go();
    for (final t in teeth) {
      await _db
          .into(_db.toothRecords)
          .insert(
            ToothRecordsCompanion.insert(
              patientId: localId,
              fdi: t['fdi'],
              state: Value(t['state'] ?? 'healthy'),
              note: Value(t['note']),
            ),
          );
    }
    final plans =
        (await _sb
                .from('treatment_plans')
                .select()
                .eq('patient_uuid', patientUuid))
            as List;
    for (final lp in await (_db.select(
      _db.treatmentPlans,
    )..where((t) => t.patientId.equals(localId))).get()) {
      await (_db.delete(
        _db.treatmentSteps,
      )..where((s) => s.planId.equals(lp.id))).go();
    }
    await (_db.delete(
      _db.treatmentPlans,
    )..where((t) => t.patientId.equals(localId))).go();
    for (final pl in plans) {
      final planId = await _db
          .into(_db.treatmentPlans)
          .insert(
            TreatmentPlansCompanion.insert(
              patientId: localId,
              title: pl['title'] ?? '',
              isDeleted: Value(pl['is_deleted'] ?? false),
            ),
          );
      for (final s in (pl['steps'] as List? ?? const [])) {
        await _db
            .into(_db.treatmentSteps)
            .insert(
              TreatmentStepsCompanion.insert(
                planId: planId,
                position: s['position'] ?? 0,
                label: s['label'] ?? '',
                detail: Value(s['detail'] ?? ''),
                status: Value(s['status'] ?? 'todo'),
                completedAt: Value(
                  // ← NEW
                  s['completed_at'] == null
                      ? null
                      : DateTime.parse(s['completed_at']),
                ),
              ),
            );
      }
    }

    // ── prescriptions ──
    final rxRows =
        (await _sb
                .from('prescriptions')
                .select()
                .eq('patient_uuid', patientUuid))
            as List;

    for (final lr in await (_db.select(
      _db.prescriptions,
    )..where((t) => t.patientId.equals(localId))).get()) {
      await (_db.delete(
        _db.prescriptionItems,
      )..where((t) => t.prescriptionId.equals(lr.id))).go();
      await (_db.delete(
        _db.prescriptionCare,
      )..where((t) => t.prescriptionId.equals(lr.id))).go();
    }
    await (_db.delete(
      _db.prescriptions,
    )..where((t) => t.patientId.equals(localId))).go();

    for (final r in rxRows) {
      final rxId = await _db
          .into(_db.prescriptions)
          .insert(
            PrescriptionsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              branchId: Value(r['branch_id']),
              patientId: localId,
              patientUuid: patientUuid,
              rxNo: Value(r['rx_no'] ?? ''),
              appointmentLabel: Value(r['appointment_label'] ?? ''),
              doctorName: Value(r['doctor_name'] ?? ''),
              advice: Value(r['advice'] ?? ''),
              issuedAt: Value(
                r['issued_at'] == null
                    ? DateTime.now()
                    : DateTime.parse(r['issued_at']),
              ),
              isDeleted: Value(r['is_deleted'] ?? false),
            ),
          );
      for (final i in (r['items'] as List? ?? const [])) {
        await _db
            .into(_db.prescriptionItems)
            .insert(
              PrescriptionItemsCompanion.insert(
                prescriptionId: rxId,
                position: Value(i['position'] ?? 0),
                medicine: i['medicine'] ?? '',
                dosage: Value(i['dosage'] ?? ''),
                frequency: Value(i['frequency'] ?? ''),
                duration: Value(i['duration'] ?? ''),
                instructions: Value(i['instructions'] ?? ''),
              ),
            );
      }
      for (final c in (r['care'] as List? ?? const [])) {
        await _db
            .into(_db.prescriptionCare)
            .insert(
              PrescriptionCareCompanion.insert(
                prescriptionId: rxId,
                position: Value(c['position'] ?? 0),
                urdu: Value(c['urdu'] ?? ''),
                english: Value(c['english'] ?? ''),
              ),
            );
      }
    }
  }

  // ================= APPOINTMENTS =================
  Future<void> _syncAppointments(String clinicId) async {
    final since = await _cur('push_appointments');
    final changed = await (_db.select(
      _db.appointments,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (final a in changed) {
        final pu = await _patientUuid(a.patientId);
        if (pu == null) continue;
        rows.add({
          'uuid': a.uuid,
          'clinic_id': clinicId,
          'branch_id': a.branchId,
          'patient_uuid': pu,
          'dentist': a.dentist,
          'chair': a.chair,
          'procedure': a.procedure,
          'billed': a.billed,
          'starts_at': _iso(a.startsAt),
          'duration_min': a.durationMin,
          'status': a.status,
          'notes': a.notes,
          'is_deleted': a.isDeleted,
          'updated_at': _iso(a.updatedAt),
        });
      }
      if (rows.isNotEmpty)
        await _sb.from('appointments').upsert(rows, onConflict: 'uuid');
      await _setCur('push_appointments', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_appointments');
    for (final r in await _pull('appointments', clinicId, pullSince)) {
      await _row('appointments', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final localPid = await _patientId(r['patient_uuid']);
        if (localPid == null) return; // parent not here yet; next round
        final existing = await (_db.select(
          _db.appointments,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.appointments)
            .insertOnConflictUpdate(
              AppointmentsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                patientId: Value(localPid),
                dentist: Value(r['dentist'] ?? ''),
                chair: Value(r['chair'] ?? 1),
                procedure: Value(r['procedure'] ?? ''),
                billed: Value(r['billed'] ?? false),
                startsAt: Value(DateTime.parse(r['starts_at'])),
                durationMin: Value(r['duration_min'] ?? 30),
                status: Value(r['status'] ?? 'upcoming'),
                notes: Value(r['notes']),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_appointments', u);
      });
    }
  }

  // ================= BOOKING REQUESTS =================
  // Patient-authored (mobile writes). Desktop pulls all, and pushes back only
  // rows it changed (status / modifiedBy / acceptedBy / decidedAt).
  Future<void> _syncBookingRequests(String clinicId) async {
    // ---- PUSH desktop-side changes ----
    final since = await _cur('push_booking_requests');
    final changed = await (_db.select(
      _db.bookingRequests,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('booking_requests').upsert([
        for (final r in changed)
          {
            'id': r.uuid, // Supabase PK is `id` (uuid type), not `uuid`
            'clinic_id': clinicId,
            'branch_id': r.branchId,
            'patient_uuid': r.patientUuid,
            'patient_account_id': r.patientAccountId,
            'dentist': r.dentist,
            'procedure': r.procedure,
            'requested_slot': _iso(r.requestedSlot),
            'duration_min': r.durationMin,
            'status': r.status,
            'modified_by': r.modifiedBy,
            'accepted_by': r.acceptedBy,
            'decided_at': _iso(r.decidedAt),
            'updated_at': _iso(r.updatedAt),
          },
      ], onConflict: 'id');
      await _setCur(
        'push_booking_requests',
        _max(changed.map((e) => e.updatedAt)),
      );
    }

    // ---- PULL all requests for this clinic ----
    final pullSince = await _cur('pull_booking_requests');
    for (final r in await _pull('booking_requests', clinicId, pullSince)) {
      await _row('booking_requests', r['id'], () async {
        final u = DateTime.parse(r['updated_at']);
        final rid = r['id'];
        final existing = await (_db.select(
          _db.bookingRequests,
        )..where((t) => t.uuid.equals(rid))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.bookingRequests)
            .insertOnConflictUpdate(
              BookingRequestsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(rid),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                patientUuid: Value(r['patient_uuid'] ?? ''),
                patientAccountId: Value(r['patient_account_id']),
                dentist: Value(r['dentist'] ?? ''),
                procedure: Value(r['procedure'] ?? ''),
                requestedSlot: Value(DateTime.parse(r['requested_slot'])),
                durationMin: Value(r['duration_min'] ?? 30),
                status: Value(r['status'] ?? 'pending'),
                modifiedBy: Value(r['modified_by']),
                acceptedBy: Value(r['accepted_by']),
                decidedAt: Value(
                  r['decided_at'] == null
                      ? null
                      : DateTime.parse(r['decided_at']),
                ),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_booking_requests', u);
      });
    }
  }

  // ================= INVOICES (+ owned items) =================
  Future<void> _syncInvoices(String clinicId) async {
    final since = await _cur('push_invoices');
    final changed = await (_db.select(
      _db.invoices,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (final inv in changed) {
        final pu = await _patientUuid(inv.patientId);
        if (pu == null) continue;
        rows.add({
          'uuid': inv.uuid,
          'clinic_id': clinicId,
          'branch_id': inv.branchId,
          'patient_uuid': pu,
          'invoice_no': inv.invoiceNo,
          'issued_at': _iso(inv.issuedAt),
          'status': inv.status,
          'appointment_uuid': inv.appointmentId == null
              ? null
              : await _appointmentUuid(inv.appointmentId!),
          'summary': inv.summary,
          'subtotal': inv.subtotal,
          'adjustment': inv.adjustment,
          'total': inv.total,
          'amount_paid': inv.amountPaid,
          'is_deleted': inv.isDeleted,
          'updated_at': _iso(inv.updatedAt),
        });
      }
      if (rows.isNotEmpty)
        await _sb.from('invoices').upsert(rows, onConflict: 'uuid');
      for (final inv in changed) {
        final items = await (_db.select(
          _db.invoiceItems,
        )..where((t) => t.invoiceId.equals(inv.id))).get();
        await _sb.from('invoice_items').delete().eq('invoice_uuid', inv.uuid);
        if (items.isNotEmpty) {
          await _sb.from('invoice_items').insert([
            for (var i = 0; i < items.length; i++)
              {
                'clinic_id': clinicId,
                'invoice_uuid': inv.uuid,
                'position': i,
                'description': items[i].description,
                'amount': items[i].amount,
                'qty': items[i].qty,
              },
          ]);
        }
      }
      await _setCur('push_invoices', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_invoices');
    for (final r in await _pull('invoices', clinicId, pullSince)) {
      await _row('invoices', r['invoice_no'] ?? r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final localPid = await _patientId(r['patient_uuid']);
        if (localPid == null) return;
        final localApptId = r['appointment_uuid'] == null
            ? null
            : await _appointmentId(r['appointment_uuid']);
        final existing = await (_db.select(
          _db.invoices,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        final invId = await _db
            .into(_db.invoices)
            .insertOnConflictUpdate(
              InvoicesCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                patientId: Value(localPid),
                appointmentId: Value(localApptId),
                invoiceNo: Value(r['invoice_no'] ?? ''),
                issuedAt: Value(DateTime.parse(r['issued_at'])),
                status: Value(r['status'] ?? 'pending'),
                summary: Value(r['summary'] ?? ''),
                cancelledBy: Value(r['cancelled_by']),
                cancelledAt: Value(
                  r['cancelled_at'] == null
                      ? null
                      : DateTime.parse(r['cancelled_at']),
                ),
                subtotal: Value(r['subtotal'] ?? 0),
                adjustment: Value(r['adjustment'] ?? 0),
                total: Value(r['total'] ?? 0),
                amountPaid: Value(r['amount_paid'] ?? 0),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        final realId = existing?.id ?? invId;
        final items =
            (await _sb
                    .from('invoice_items')
                    .select()
                    .eq('invoice_uuid', r['uuid'])
                    .order('position'))
                as List;
        await (_db.delete(
          _db.invoiceItems,
        )..where((t) => t.invoiceId.equals(realId))).go();
        for (final it in items) {
          await _db
              .into(_db.invoiceItems)
              .insert(
                InvoiceItemsCompanion.insert(
                  invoiceId: realId,
                  description: it['description'] ?? '',
                  amount: it['amount'] ?? 0,
                  qty: Value(it['qty'] ?? 1),
                ),
              );
        }
        if (u.isAfter(pullSince)) await _setCur('pull_invoices', u);
      });
    }
  }

  // ================= INVOICE PAYMENTS =================
  // Links to its invoice by UUID only — local int ids do not transfer.
  // A payment whose invoice has not arrived yet is SKIPPED, never inserted
  // against a wrong id; it lands on the next pull.
  Future<void> _syncPayments(String clinicId) async {
    final since = await _cur('push_payments');
    final changed = await (_db.select(
      _db.invoicePayments,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('invoice_payments').upsert([
        for (final p in changed)
          {
            'uuid': p.uuid,
            'clinic_id': clinicId,
            'branch_id': p.branchId,
            'invoice_uuid': p.invoiceUuid,
            'amount': p.amount,
            'paid_at': _iso(p.paidAt),
            'method': p.method,
            'method_detail': p.methodDetail,
            'reference': p.reference,
            'received_by_name': p.receivedByName,
            'note': p.note,
            'is_deleted': p.isDeleted,
            'deleted_by_name': p.deletedByName,
            'deleted_at': _iso(p.deletedAt),
            'created_at': _iso(p.createdAt),
            'updated_at': _iso(p.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_payments', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_payments');
    final touched = <int>{};
    for (final r in await _pull('invoice_payments', clinicId, pullSince)) {
      await _row('invoice_payments', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final invId = await _invoiceId(r['invoice_uuid']);
        if (invId == null) return; // parent not here yet; next round
        final existing = await (_db.select(
          _db.invoicePayments,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.invoicePayments)
            .insertOnConflictUpdate(
              InvoicePaymentsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                invoiceId: Value(invId),
                invoiceUuid: Value(r['invoice_uuid']),
                amount: Value(r['amount'] ?? 0),
                paidAt: Value(DateTime.parse(r['paid_at'])),
                method: Value(r['method'] ?? 'Cash'),
                methodDetail: Value(r['method_detail']),
                reference: Value(r['reference']),
                receivedByName: Value(r['received_by_name'] ?? ''),
                note: Value(r['note'] ?? ''),
                isDeleted: Value(r['is_deleted'] ?? false),
                deletedByName: Value(r['deleted_by_name']),
                deletedAt: Value(
                  r['deleted_at'] == null
                      ? null
                      : DateTime.parse(r['deleted_at']),
                ),
                createdAt: Value(
                  r['created_at'] == null
                      ? DateTime.now()
                      : DateTime.parse(r['created_at']),
                ),
                updatedAt: Value(u),
              ),
            );
        touched.add(invId);
        if (u.isAfter(pullSince)) await _setCur('pull_payments', u);
      });
    }
    // Rebuild the caches for every invoice whose payments changed. The
    // pushed amount_paid / balance belong to the machine that sent them.
    for (final id in touched) {
      await _db.recalcInvoicePaid(id);
    }
  }

  // ================= LOOKUP LISTS =================
  Future<void> _syncLookups(String clinicId) async {
    final since = await _cur('push_lookups');
    final changed = await (_db.select(
      _db.lookupLists,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('lookup_lists').upsert([
        for (final l in changed)
          {
            'uuid': l.uuid,
            'clinic_id': clinicId,
            'kind': l.kind,
            'name': l.name,
            'sort_order': l.sortOrder,
            'is_system': l.isSystem,
            'is_deleted': l.isDeleted,
            'updated_at': _iso(l.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_lookups', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_lookups');
    for (final r in await _pull('lookup_lists', clinicId, pullSince)) {
      await _row('lookup_lists', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.lookupLists,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.lookupLists)
            .insertOnConflictUpdate(
              LookupListsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                kind: Value(r['kind'] ?? ''),
                name: Value(r['name'] ?? ''),
                sortOrder: Value(r['sort_order'] ?? 0),
                isSystem: Value(r['is_system'] ?? false),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_lookups', u);
      });
    }
  }

  // ================= EXPENSES =================
  Future<void> _syncExpenses(String clinicId) async {
    final since = await _cur('push_expenses');
    final changed = await (_db.select(
      _db.expenses,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('expenses').upsert([
        for (final e in changed)
          {
            'uuid': e.uuid,
            'clinic_id': clinicId,
            'branch_id': e.branchId,
            'category_uuid': e.categoryUuid,
            'amount': e.amount,
            'paid_at': _iso(e.paidAt),
            'description': e.description,
            'vendor': e.vendor,
            'method': e.method,
            'method_detail': e.methodDetail,
            'reference': e.reference,
            'recorded_by_name': e.recordedByName,
            'updated_by_name': e.updatedByName,
            'source_type': e.sourceType,
            'source_uuid': e.sourceUuid,
            'is_deleted': e.isDeleted,
            'deleted_by_name': e.deletedByName,
            'deleted_at': _iso(e.deletedAt),
            'delete_reason': e.deleteReason,
            'created_at': _iso(e.createdAt),
            'updated_at': _iso(e.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_expenses', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_expenses');
    for (final r in await _pull('expenses', clinicId, pullSince)) {
      await _row('expenses', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.expenses,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(
              ExpensesCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id'] ?? ''),
                categoryUuid: Value(r['category_uuid'] ?? ''),
                amount: Value(r['amount'] ?? 0),
                paidAt: Value(DateTime.parse(r['paid_at'])),
                description: Value(r['description'] ?? ''),
                vendor: Value(r['vendor']),
                method: Value(r['method'] ?? 'Cash'),
                methodDetail: Value(r['method_detail']),
                reference: Value(r['reference']),
                recordedByName: Value(r['recorded_by_name'] ?? ''),
                updatedByName: Value(r['updated_by_name']),
                sourceType: Value(r['source_type']),
                sourceUuid: Value(r['source_uuid']),
                isDeleted: Value(r['is_deleted'] ?? false),
                deletedByName: Value(r['deleted_by_name']),
                deletedAt: Value(
                  r['deleted_at'] == null
                      ? null
                      : DateTime.parse(r['deleted_at']),
                ),
                deleteReason: Value(r['delete_reason']),
                createdAt: Value(
                  r['created_at'] == null
                      ? DateTime.now()
                      : DateTime.parse(r['created_at']),
                ),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_expenses', u);
      });
    }
  }

  // ================= DEVICES =================
  Future<void> _syncDevices(String clinicId) async {
    final since = await _cur('push_devices');
    final changed = await (_db.select(
      _db.devices,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('devices').upsert([
        for (final dv in changed)
          {
            'uuid': dv.uuid,
            'clinic_id': clinicId,
            'letter': dv.letter,
            'name': dv.name,
            'platform': dv.platform,
            'joined_by_name': dv.joinedByName,
            'joined_at': _iso(dv.joinedAt),
            'last_seen_at': _iso(dv.lastSeenAt),
            'is_active': dv.isActive,
            'is_deleted': dv.isDeleted,
            'updated_at': _iso(dv.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_devices', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_devices');
    for (final r in await _pull('devices', clinicId, pullSince)) {
      await _row('devices', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.devices,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.devices)
            .insertOnConflictUpdate(
              DevicesCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                letter: Value(r['letter'] ?? 'A'),
                name: Value(r['name'] ?? ''),
                platform: Value(r['platform'] ?? ''),
                joinedByName: Value(r['joined_by_name'] ?? ''),
                joinedAt: Value(
                  r['joined_at'] == null
                      ? DateTime.now()
                      : DateTime.parse(r['joined_at']),
                ),
                lastSeenAt: Value(
                  r['last_seen_at'] == null
                      ? null
                      : DateTime.parse(r['last_seen_at']),
                ),
                isActive: Value(r['is_active'] ?? true),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_devices', u);
      });
    }
  }

  // ================= ROOT TABLES (no FK remap) =================
  Future<void> _syncInventory(String clinicId) async {
    final since = await _cur('push_inventory');
    final changed = await (_db.select(
      _db.inventoryItems,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('inventory_items').upsert([
        for (final it in changed)
          {
            'uuid': it.uuid,
            'clinic_id': clinicId,
            'branch_id': it.branchId,
            'name': it.name,
            'category': it.category,
            'in_stock': it.inStock,
            'par_level': it.parLevel,
            'reorder_at': it.reorderAt,
            'unit': it.unit,
            'is_deleted': it.isDeleted,
            'updated_at': _iso(it.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_inventory', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_inventory');
    for (final r in await _pull('inventory_items', clinicId, pullSince)) {
      await _row('inventory_items', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.inventoryItems,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.inventoryItems)
            .insertOnConflictUpdate(
              InventoryItemsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                name: Value(r['name'] ?? ''),
                category: Value(r['category'] ?? ''),
                inStock: Value(r['in_stock'] ?? 0),
                parLevel: Value(r['par_level'] ?? 0),
                reorderAt: Value(r['reorder_at'] ?? 0),
                unit: Value(r['unit'] ?? 'units'),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_inventory', u);
      });
    }
  }

  Future<void> _syncTreatments(String clinicId) async {
    final since = await _cur('push_treatments');
    final changed = await (_db.select(
      _db.treatments,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('treatments').upsert([
        for (final t in changed)
          {
            'uuid': t.uuid,
            'clinic_id': clinicId,
            'branch_id': t.branchId,
            'name': t.name,
            'category': t.category,
            'price': t.price,
            'duration': t.duration,
            'is_deleted': t.isDeleted,
            'updated_at': _iso(t.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_treatments', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_treatments');
    for (final r in await _pull('treatments', clinicId, pullSince)) {
      await _row('treatments', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.treatments,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.treatments)
            .insertOnConflictUpdate(
              TreatmentsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                name: Value(r['name'] ?? ''),
                category: Value(r['category'] ?? ''),
                price: Value(r['price'] ?? 0),
                duration: Value(r['duration'] ?? ''),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_treatments', u);
      });
    }
  }

  Future<void> _syncOffers(String clinicId) async {
    final since = await _cur('push_offers');
    final changed = await (_db.select(
      _db.offers,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('offers').upsert([
        for (final o in changed)
          {
            'id': o.uuid, // Supabase PK is `id`, like booking_requests
            'clinic_id': clinicId,
            'branch_id': o.branchId,
            'title': o.title,
            'body': o.body,
            'image_url': o.imageUrl,
            'starts_at': _iso(o.startsAt),
            'expires_at': _iso(o.expiresAt),
            'sent_count': o.sentCount,
            'sent_app': o.sentApp,
            'sent_whats_app': o.sentWhatsApp,
            'created_by': o.createdBy,
            'is_deleted': o.isDeleted,
            'updated_at': _iso(o.updatedAt),
          },
      ], onConflict: 'id');
      await _setCur('push_offers', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_offers');
    for (final r in await _pull('offers', clinicId, pullSince)) {
      await _row('offers', r['id'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.offers,
        )..where((t) => t.uuid.equals(r['id']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.offers)
            .insertOnConflictUpdate(
              OffersCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['id']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                title: Value(r['title'] ?? ''),
                body: Value(r['body'] ?? ''),
                imageUrl: Value(r['image_url']),
                startsAt: Value(
                  r['starts_at'] == null
                      ? null
                      : DateTime.parse(r['starts_at']),
                ),
                expiresAt: Value(
                  r['expires_at'] == null
                      ? null
                      : DateTime.parse(r['expires_at']),
                ),
                sentCount: Value(r['sent_count'] ?? 0),
                sentApp: Value(r['sent_app'] ?? true),
                sentWhatsApp: Value(r['sent_whats_app'] ?? false),
                createdBy: Value(r['created_by']),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_offers', u);
      });
    }
  }

  Future<void> _syncMedicines(String clinicId) async {
    final since = await _cur('push_medicines');
    final changed = await (_db.select(
      _db.medicines,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('medicines').upsert([
        for (final m in changed)
          {
            'uuid': m.uuid,
            'clinic_id': clinicId,
            'name': m.name,
            'form': m.form,
            'default_dosage': m.defaultDosage,
            'default_frequency': m.defaultFrequency,
            'category': m.category,
            'is_deleted': m.isDeleted,
            'updated_at': _iso(m.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_medicines', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_medicines');
    for (final r in await _pull('medicines', clinicId, pullSince)) {
      await _row('medicines', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.medicines,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.medicines)
            .insertOnConflictUpdate(
              MedicinesCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                name: Value(r['name'] ?? ''),
                form: Value(r['form'] ?? ''),
                defaultDosage: Value(r['default_dosage'] ?? ''),
                defaultFrequency: Value(r['default_frequency'] ?? ''),
                category: Value(r['category'] ?? ''),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_medicines', u);
      });
    }
  }

  Future<void> _syncPrecautionSets(String clinicId) async {
    final since = await _cur('push_precaution_sets');
    final changed = await (_db.select(
      _db.precautionSets,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();

    if (changed.isNotEmpty) {
      final rows = <Map<String, dynamic>>[];
      for (final s in changed) {
        final lines =
            await (_db.select(_db.precautionLines)
                  ..where((t) => t.setId.equals(s.id))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
        rows.add({
          'uuid': s.uuid,
          'clinic_id': clinicId,
          'name': s.name,
          'position': s.position,
          'is_deleted': s.isDeleted,
          'updated_at': _iso(s.updatedAt),
          'lines': [
            for (final l in lines)
              {'position': l.position, 'urdu': l.urdu, 'english': l.english},
          ],
        });
      }
      await _sb.from('precaution_sets').upsert(rows, onConflict: 'uuid');
      await _setCur(
        'push_precaution_sets',
        _max(changed.map((e) => e.updatedAt)),
      );
    }

    final pullSince = await _cur('pull_precaution_sets');
    for (final r in await _pull('precaution_sets', clinicId, pullSince)) {
      await _row('precaution_sets', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.precautionSets,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;

        final setId = await _db
            .into(_db.precautionSets)
            .insertOnConflictUpdate(
              PrecautionSetsCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                name: Value(r['name'] ?? ''),
                position: Value(r['position'] ?? 0),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        final realId = existing?.id ?? setId;

        // replace lines wholesale
        await (_db.delete(
          _db.precautionLines,
        )..where((t) => t.setId.equals(realId))).go();
        for (final l in (r['lines'] as List? ?? const [])) {
          await _db
              .into(_db.precautionLines)
              .insert(
                PrecautionLinesCompanion.insert(
                  setId: realId,
                  position: Value(l['position'] ?? 0),
                  urdu: Value(l['urdu'] ?? ''),
                  english: Value(l['english'] ?? ''),
                ),
              );
        }
        if (u.isAfter(pullSince)) await _setCur('pull_precaution_sets', u);
      });
    }
  }

  Future<void> _syncBranches(String clinicId) async {
    final since = await _cur('push_branches');
    final changed = await (_db.select(
      _db.branches,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('branches').upsert([
        for (final b in changed)
          {
            'uuid': b.uuid,
            'clinic_id': clinicId,
            'name': b.name,
            'location': b.location,
            'is_primary': b.isPrimary,
            'open_minutes': b.openMinutes,
            'close_minutes': b.closeMinutes,
            'slot_minutes': b.slotMinutes,
            'closed_days': b.closedDays,
            'is_deleted': b.isDeleted,
            'updated_at': _iso(b.updatedAt),
            'wa_enabled': b.waEnabled,
            'wa_method': b.waMethod,
            'wa_phone': b.waPhone,
            'wa_api_token': b.waApiToken,
            'wa_phone_id': b.waPhoneId,
            'wa_session_status': b.waSessionStatus,
            'wa_qr_status': b.waQrStatus,
            'wa_reminder_channel': b.waReminderChannel,
            'wa_language': b.waLanguage,
          },
      ], onConflict: 'uuid');
      await _setCur('push_branches', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_branches');
    for (final r in await _pull('branches', clinicId, pullSince)) {
      await _row('branches', r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        final existing = await (_db.select(
          _db.branches,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.branches)
            .insertOnConflictUpdate(
              BranchesCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                name: Value(r['name'] ?? ''),
                location: Value(r['location'] ?? ''),
                isPrimary: Value(r['is_primary'] ?? false),
                openMinutes: Value(r['open_minutes'] ?? 600),
                closeMinutes: Value(r['close_minutes'] ?? 1020),
                slotMinutes: Value(r['slot_minutes'] ?? 20),
                closedDays: Value(r['closed_days'] ?? ''),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
                waEnabled: Value(r['wa_enabled'] ?? false),
                waMethod: Value(r['wa_method'] ?? 'official'),
                waPhone: Value(r['wa_phone']),
                waApiToken: Value(r['wa_api_token']),
                waPhoneId: Value(r['wa_phone_id']),
                waSessionStatus: Value(r['wa_session_status']),
                waQrStatus: Value(r['wa_qr_status']),
                waReminderChannel: Value(r['wa_reminder_channel'] ?? 'none'),
                waLanguage: Value(r['wa_language'] ?? 'en'),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_branches', u);
      });
    }
  }

  Future<void> _syncUsers(String clinicId) async {
    final since = await _cur('push_users');
    final changed =
        await (_db.select(_db.users)..where(
              (t) =>
                  t.updatedAt.isBiggerThanValue(since) &
                  t.uuid.equals('').not(),
            ))
            .get();
    if (changed.isNotEmpty) {
      await _sb.from('users').upsert([
        for (final usr in changed)
          {
            'uuid': usr.uuid,
            'clinic_id': clinicId,
            'branch_id': usr.branchId,
            'full_name': usr.fullName,
            'username': usr.username,
            'password_hash': usr.passwordHash,
            'role': usr.role,
            'email': usr.email,
            'phone': usr.phone,
            'is_deleted': usr.isDeleted,
            'updated_at': _iso(usr.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_users', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_users');
    for (final r in await _pull('users', clinicId, pullSince)) {
      await _row('users', r['username'] ?? r['uuid'], () async {
        final u = DateTime.parse(r['updated_at']);
        var existing = await (_db.select(
          _db.users,
        )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
        // Fall back to username match so we don't insert a duplicate
        // (same user created locally + in cloud under different ids).
        existing ??=
            await (_db.select(_db.users)
                  ..where((t) => t.username.equals(r['username'] ?? '')))
                .getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.users)
            .insertOnConflictUpdate(
              UsersCompanion(
                id: existing == null
                    ? const Value.absent()
                    : Value(existing.id),
                uuid: Value(r['uuid']),
                clinicId: Value(clinicId),
                branchId: Value(r['branch_id']),
                fullName: Value(r['full_name'] ?? ''),
                username: Value(r['username'] ?? ''),
                passwordHash: Value(r['password_hash'] ?? ''),
                role: Value(r['role'] ?? 'receptionist'),
                email: Value(r['email']),
                phone: Value(r['phone']),
                isDeleted: Value(r['is_deleted'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_users', u);
      });
    }
  }

  Future<void> _syncPermissions(String clinicId) async {
    final since = await _cur('push_permissions');
    final changed = await (_db.select(
      _db.rolePermissions,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    if (changed.isNotEmpty) {
      await _sb.from('role_permissions').upsert([
        for (final p in changed)
          {
            'clinic_id': clinicId,
            'role': p.role,
            'key': p.key,
            'allowed': p.allowed,
            'updated_at': _iso(p.updatedAt),
          },
      ], onConflict: 'clinic_id,role,key');
      await _setCur('push_permissions', _max(changed.map((e) => e.updatedAt)));
    }

    final pullSince = await _cur('pull_permissions');
    for (final r in await _pull('role_permissions', clinicId, pullSince)) {
      await _row('role_permissions', '${r['role']}|${r['key']}', () async {
        final u = DateTime.parse(r['updated_at']);
        final existing =
            await (_db.select(_db.rolePermissions)..where(
                  (t) => t.role.equals(r['role']) & t.key.equals(r['key']),
                ))
                .getSingleOrNull();
        if (existing != null && !u.isAfter(existing.updatedAt)) return;
        await _db
            .into(_db.rolePermissions)
            .insertOnConflictUpdate(
              RolePermissionsCompanion.insert(
                clinicId: clinicId,
                role: r['role'],
                key: r['key'],
                allowed: Value(r['allowed'] ?? false),
                updatedAt: Value(u),
              ),
            );
        if (u.isAfter(pullSince)) await _setCur('pull_permissions', u);
      });
    }
  }
}

final syncEngineProvider = Provider(
  (ref) => SyncEngine(ref.watch(appDatabaseProvider)),
);
