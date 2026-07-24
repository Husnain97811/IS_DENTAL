import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/cloud_service.dart';
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
    await step('inventory', () => _syncInventory(clinicId));
    await step('users', () => _syncUsers(clinicId));
    await step('appointments', () => _syncAppointments(clinicId));
    await step('invoices', () => _syncInvoices(clinicId));
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

  Future<String?> _patientUuid(int id) async => (await (_db.select(
    _db.patients,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.uuid;
  Future<int?> _patientId(String uuid) async => (await (_db.select(
    _db.patients,
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
      final u = DateTime.parse(r['updated_at']);
      final existing = await (_db.select(
        _db.patients,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.patients)
          .insertOnConflictUpdate(
            PatientsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
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
            },
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
      final u = DateTime.parse(r['updated_at']);
      final localPid = await _patientId(r['patient_uuid']);
      if (localPid == null) continue; // parent not here yet; next round
      final existing = await (_db.select(
        _db.appointments,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.appointments)
          .insertOnConflictUpdate(
            AppointmentsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientId: Value(localPid),
              dentist: Value(r['dentist'] ?? ''),
              chair: Value(r['chair'] ?? 1),
              procedure: Value(r['procedure'] ?? ''),
              startsAt: Value(DateTime.parse(r['starts_at'])),
              durationMin: Value(r['duration_min'] ?? 30),
              status: Value(r['status'] ?? 'upcoming'),
              notes: Value(r['notes']),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(u),
            ),
          );
      if (u.isAfter(pullSince)) await _setCur('pull_appointments', u);
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
          'summary': inv.summary,
          'subtotal': inv.subtotal,
          'adjustment': inv.adjustment,
          'total': inv.total,
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
      final u = DateTime.parse(r['updated_at']);
      final localPid = await _patientId(r['patient_uuid']);
      if (localPid == null) continue;
      final existing = await (_db.select(
        _db.invoices,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      final invId = await _db
          .into(_db.invoices)
          .insertOnConflictUpdate(
            InvoicesCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              patientId: Value(localPid),
              invoiceNo: Value(r['invoice_no'] ?? ''),
              issuedAt: Value(DateTime.parse(r['issued_at'])),
              status: Value(r['status'] ?? 'pending'),
              summary: Value(r['summary'] ?? ''),
              subtotal: Value(r['subtotal'] ?? 0),
              adjustment: Value(r['adjustment'] ?? 0),
              total: Value(r['total'] ?? 0),
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
      final u = DateTime.parse(r['updated_at']);
      final existing = await (_db.select(
        _db.inventoryItems,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.inventoryItems)
          .insertOnConflictUpdate(
            InventoryItemsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
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
      final u = DateTime.parse(r['updated_at']);
      final existing = await (_db.select(
        _db.treatments,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.treatments)
          .insertOnConflictUpdate(
            TreatmentsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              name: Value(r['name'] ?? ''),
              category: Value(r['category'] ?? ''),
              price: Value(r['price'] ?? 0),
              duration: Value(r['duration'] ?? ''),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(u),
            ),
          );
      if (u.isAfter(pullSince)) await _setCur('pull_treatments', u);
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
          },
      ], onConflict: 'uuid');
      await _setCur('push_branches', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_branches');
    for (final r in await _pull('branches', clinicId, pullSince)) {
      final u = DateTime.parse(r['updated_at']);
      final existing = await (_db.select(
        _db.branches,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.branches)
          .insertOnConflictUpdate(
            BranchesCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
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
            ),
          );
      if (u.isAfter(pullSince)) await _setCur('pull_branches', u);
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
            'is_deleted': usr.isDeleted,
            'updated_at': _iso(usr.updatedAt),
          },
      ], onConflict: 'uuid');
      await _setCur('push_users', _max(changed.map((e) => e.updatedAt)));
    }
    final pullSince = await _cur('pull_users');
    for (final r in await _pull('users', clinicId, pullSince)) {
      final u = DateTime.parse(r['updated_at']);
      final existing = await (_db.select(
        _db.users,
      )..where((t) => t.uuid.equals(r['uuid']))).getSingleOrNull();
      if (existing != null && !u.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.users)
          .insertOnConflictUpdate(
            UsersCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              fullName: Value(r['full_name'] ?? ''),
              username: Value(r['username'] ?? ''),
              passwordHash: Value(r['password_hash'] ?? ''),
              role: Value(r['role'] ?? 'receptionist'),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(u),
            ),
          );
      if (u.isAfter(pullSince)) await _setCur('pull_users', u);
    }
  }
}

final syncEngineProvider = Provider(
  (ref) => SyncEngine(ref.watch(appDatabaseProvider)),
);
