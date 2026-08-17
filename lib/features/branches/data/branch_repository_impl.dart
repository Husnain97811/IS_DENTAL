import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/branch.dart';
import '../domain/branch_repository.dart';

class BranchRepositoryImpl implements BranchRepository {
  BranchRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Branch>> watchBranches() =>
      (_db.select(_db.branches)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([
              (t) => OrderingTerm.desc(t.isPrimary),
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => Branch(
                    id: r.id,
                    uuid: r.uuid,
                    name: r.name,
                    location: r.location,
                    isPrimary: r.isPrimary,
                    openMinutes: r.openMinutes,
                    closeMinutes: r.closeMinutes,
                    slotMinutes: r.slotMinutes,
                    closedDays: r.closedDays,
                    waEnabled: r.waEnabled, // ← add
                    waMethod: r.waMethod, // ← add
                    waPhone: r.waPhone, // ← add
                    waApiToken: r.waApiToken, // ← add
                    waPhoneId: r.waPhoneId, // ← add
                    waSessionStatus: r.waSessionStatus, // ← add
                  ),
                )
                .toList(),
          );

  @override
  Future<void> upsertBranch(Branch b) async {
    final clinicId = await _db.currentClinicId() ?? '';
    await _db
        .into(_db.branches)
        .insertOnConflictUpdate(
          BranchesCompanion(
            id: b.id == 0 ? const Value.absent() : Value(b.id),
            uuid: Value(b.uuid.isEmpty ? Uuids.v4() : b.uuid),
            clinicId: Value(clinicId),
            name: Value(b.name),
            location: Value(b.location),
            isPrimary: Value(b.isPrimary),
            // Only set hours on CREATE (id==0). On edit, leave them alone so
            // updateBranchHours() stays the source of truth.
            openMinutes: b.id == 0
                ? Value(b.openMinutes)
                : const Value.absent(),
            closeMinutes: b.id == 0
                ? Value(b.closeMinutes)
                : const Value.absent(),
            slotMinutes: b.id == 0
                ? Value(b.slotMinutes)
                : const Value.absent(),
            closedDays: b.id == 0 ? Value(b.closedDays) : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> softDeleteBranch(int id) =>
      (_db.update(_db.branches)..where((t) => t.id.equals(id))).write(
        BranchesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
