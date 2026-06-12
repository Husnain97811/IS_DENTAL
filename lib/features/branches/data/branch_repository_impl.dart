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
