import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';

class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  Future<void> create({
    required String branchId,
    required String categoryUuid,
    required int amount,
    required DateTime paidAt,
    String description = '',
    String? vendor,
    String method = 'Cash',
    String? methodDetail,
    String? reference,
    String by = '',
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            branchId: Value(branchId),
            categoryUuid: Value(categoryUuid),
            amount: amount,
            paidAt: paidAt,
            description: Value(description),
            vendor: Value(vendor),
            method: Value(method),
            methodDetail: Value(methodDetail),
            reference: Value(reference),
            recordedByName: Value(by),
          ),
        );
  }

  /// Edit NEVER goes through insertOnConflictUpdate — uuid is NOT NULL
  /// unique and an absent value throws, hanging the dialog spinner.
  Future<void> edit({
    required int id,
    required String branchId,
    required String categoryUuid,
    required int amount,
    required DateTime paidAt,
    String description = '',
    String? vendor,
    String method = 'Cash',
    String? methodDetail,
    String? reference,
    String by = '',
  }) => (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
    ExpensesCompanion(
      branchId: Value(branchId),
      categoryUuid: Value(categoryUuid),
      amount: Value(amount),
      paidAt: Value(paidAt),
      description: Value(description),
      vendor: Value(vendor),
      method: Value(method),
      methodDetail: Value(methodDetail),
      reference: Value(reference),
      updatedByName: Value(by.isEmpty ? null : by),
      updatedAt: Value(DateTime.now()),
    ),
  );

  /// Soft delete with an audit trail — the row survives, so the deletion syncs.
  Future<void> softDelete(int id, {required String by, String? reason}) =>
      (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          isDeleted: const Value(true),
          deletedByName: Value(by),
          deletedAt: Value(DateTime.now()),
          deleteReason: Value(reason),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Rows that would be copied from [from] into [into] — shown in the
  /// confirm dialog before anything is written.
  Future<List<ExpenseRow>> previewCopy(DateTime from, String? branchId) async {
    final start = DateTime(from.year, from.month);
    final end = DateTime(from.year, from.month + 1);
    return (_db.select(_db.expenses)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(start) &
                t.paidAt.isSmallerThanValue(end) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
        .get();
  }

  /// Copies a month of expenses forward. Rent and salaries repeat; this is
  /// the manual version of recurring, so nothing is ever created behind
  /// the user's back.
  Future<int> copyMonth({
    required DateTime from,
    required DateTime into,
    String? branchId,
    String by = '',
  }) async {
    final rows = await previewCopy(from, branchId);
    if (rows.isEmpty) return 0;
    final clinicId = await _db.currentClinicId() ?? '';
    final lastDay = DateTime(into.year, into.month + 1, 0).day;

    await _db.batch((b) {
      for (final r in rows) {
        final day = r.paidAt.day > lastDay ? lastDay : r.paidAt.day;
        b.insert(
          _db.expenses,
          ExpensesCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId.isEmpty ? r.clinicId : clinicId,
            branchId: Value(r.branchId),
            categoryUuid: Value(r.categoryUuid),
            amount: r.amount,
            paidAt: DateTime(into.year, into.month, day),
            description: Value(r.description),
            vendor: Value(r.vendor),
            method: Value(r.method),
            methodDetail: Value(r.methodDetail),
            recordedByName: Value(by),
          ),
        );
      }
    });
    return rows.length;
  }

  // ── category list (lookup_lists) ────────────────────────────────────────
  Future<void> addLookup(String kind, String name) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final existing = await _db.lookups(kind);
    await _db
        .into(_db.lookupLists)
        .insert(
          LookupListsCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            kind: kind,
            name: name,
            sortOrder: Value(existing.length),
          ),
        );
  }

  Future<void> renameLookup(int id, String name) =>
      (_db.update(_db.lookupLists)..where((t) => t.id.equals(id))).write(
        LookupListsCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Hidden, not removed. Expenses store the category uuid, so a hard
  /// delete would orphan every old row that used it.
  Future<void> hideLookup(int id) =>
      (_db.update(_db.lookupLists)..where((t) => t.id.equals(id))).write(
        LookupListsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> restoreLookup(int id) =>
      (_db.update(_db.lookupLists)..where((t) => t.id.equals(id))).write(
        LookupListsCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Swaps sortOrder with the neighbour, so both rows sync normally.
  /// [by] is -1 for up, +1 for down.
  Future<void> moveLookup(int id, String kind, int by) async {
    final rows = await _db.lookups(kind);
    final i = rows.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final j = i + by;
    if (j < 0 || j >= rows.length) return;

    final now = DateTime.now();
    await _db.batch((b) {
      b.update(
        _db.lookupLists,
        LookupListsCompanion(sortOrder: Value(j), updatedAt: Value(now)),
        where: (t) => t.id.equals(rows[i].id),
      );
      b.update(
        _db.lookupLists,
        LookupListsCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        where: (t) => t.id.equals(rows[j].id),
      );
    });
  }
}

final expenseRepositoryProvider = Provider(
  (ref) => ExpenseRepository(ref.watch(appDatabaseProvider)),
);
