import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/db/app_database.dart';

class SyncEngine {
  SyncEngine(this._db);
  final AppDatabase _db;
  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> syncAll(String clinicId) async {
    await _syncPatients(clinicId);
    await _syncInventory(clinicId);
    // Repeat the same push/pull pattern for: appointments, invoices, invoice_items,
    // tooth_records, treatment_plans, treatment_steps.
  }

  Future<DateTime> _cursor(String key) async =>
      DateTime.tryParse(await _db.getSetting('sync_$key') ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _setCursor(String key, DateTime t) =>
      _db.setSetting('sync_$key', t.toUtc().toIso8601String());

  Future<void> _syncPatients(String clinicId) async {
    // PUSH local changes
    final pushSince = await _cursor('push_patients');
    final localChanged = await (_db.select(
      _db.patients,
    )..where((t) => t.updatedAt.isBiggerThanValue(pushSince))).get();
    if (localChanged.isNotEmpty) {
      await _sb.from('patients').upsert([
        for (final p in localChanged)
          {
            'uuid': p.uuid,
            'clinic_id': clinicId,
            'branch_id': p.branchId,
            'code': p.code,
            'full_name': p.fullName,
            'gender': p.gender,
            'age': p.age,
            'phone': p.phone,
            'allergies': p.allergies,
            'insurance': p.insurance,
            'last_visit': p.lastVisit?.toUtc().toIso8601String(),
            'visit_count': p.visitCount,
            'balance': p.balance,
            'status': p.status,
            'treatment_summary': p.treatmentSummary,
            'is_deleted': p.isDeleted,
            'updated_at': p.updatedAt.toUtc().toIso8601String(),
          },
      ], onConflict: 'uuid');
      await _setCursor(
        'push_patients',
        localChanged
            .map((e) => e.updatedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
      );
    }
    // PULL remote changes (LWW)
    final pullSince = await _cursor('pull_patients');
    final remote = await _sb
        .from('patients')
        .select()
        .eq('clinic_id', clinicId)
        .gt('updated_at', pullSince.toUtc().toIso8601String());
    for (final r in (remote as List)) {
      final updatedAt = DateTime.parse(r['updated_at'] as String);
      final existing = await (_db.select(
        _db.patients,
      )..where((t) => t.uuid.equals(r['uuid'] as String))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt))
        continue; // local is newer → keep
      await _db
          .into(_db.patients)
          .insertOnConflictUpdate(
            PatientsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              code: Value(r['code']),
              fullName: Value(r['full_name']),
              gender: Value(r['gender'] ?? 'female'),
              age: Value(r['age'] ?? 0),
              phone: Value(r['phone'] ?? ''),
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
              updatedAt: Value(updatedAt),
            ),
          );
      if (updatedAt.isAfter(pullSince))
        await _setCursor('pull_patients', updatedAt);
    }
  }

  Future<void> _syncInventory(String clinicId) async {
    final pushSince = await _cursor('push_inventory');
    final changed = await (_db.select(
      _db.inventoryItems,
    )..where((t) => t.updatedAt.isBiggerThanValue(pushSince))).get();
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
            'updated_at': it.updatedAt.toUtc().toIso8601String(),
          },
      ], onConflict: 'uuid');
      await _setCursor(
        'push_inventory',
        changed.map((e) => e.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
      );
    }
    final pullSince = await _cursor('pull_inventory');
    final remote = await _sb
        .from('inventory_items')
        .select()
        .eq('clinic_id', clinicId)
        .gt('updated_at', pullSince.toUtc().toIso8601String());
    for (final r in (remote as List)) {
      final updatedAt = DateTime.parse(r['updated_at'] as String);
      final existing = await (_db.select(
        _db.inventoryItems,
      )..where((t) => t.uuid.equals(r['uuid'] as String))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;
      await _db
          .into(_db.inventoryItems)
          .insertOnConflictUpdate(
            InventoryItemsCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              uuid: Value(r['uuid']),
              clinicId: Value(clinicId),
              branchId: Value(r['branch_id']),
              name: Value(r['name']),
              category: Value(r['category']),
              inStock: Value(r['in_stock'] ?? 0),
              parLevel: Value(r['par_level'] ?? 0),
              reorderAt: Value(r['reorder_at'] ?? 0),
              unit: Value(r['unit'] ?? 'units'),
              isDeleted: Value(r['is_deleted'] ?? false),
              updatedAt: Value(updatedAt),
            ),
          );
      if (updatedAt.isAfter(pullSince))
        await _setCursor('pull_inventory', updatedAt);
    }
  }
}

final syncEngineProvider = Provider(
  (ref) => SyncEngine(ref.watch(appDatabaseProvider)),
);
