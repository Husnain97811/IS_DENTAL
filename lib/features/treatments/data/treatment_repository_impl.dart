import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/treatment.dart';
import '../domain/treatment_repository.dart';

class TreatmentRepositoryImpl implements TreatmentRepository {
  TreatmentRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Treatment>> watchTreatments() =>
      (_db.select(_db.treatments)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([
              (t) => OrderingTerm.asc(t.category),
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => Treatment(
                    id: r.id,
                    uuid: r.uuid,
                    name: r.name,
                    category: r.category,
                    price: r.price,
                    duration: r.duration,
                  ),
                )
                .toList(),
          );

  @override
  Future<void> upsertTreatment(Treatment t) async {
    final clinicId = await _db.currentClinicId() ?? '';
    await _db
        .into(_db.treatments)
        .insertOnConflictUpdate(
          TreatmentsCompanion(
            id: t.id == 0 ? const Value.absent() : Value(t.id),
            uuid: Value(t.uuid.isEmpty ? Uuids.v4() : t.uuid),
            clinicId: Value(clinicId),
            name: Value(t.name),
            category: Value(t.category),
            price: Value(t.price),
            duration: Value(t.duration),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> softDeleteTreatment(int id) =>
      (_db.update(_db.treatments)..where((t) => t.id.equals(id))).write(
        TreatmentsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> seedDemoIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;
    if ((await _db.select(_db.treatments).get()).isNotEmpty) return;
    final demo = <(String, String, int, String)>[
      ('Scaling & Polishing', 'Hygiene', 3500, '30 min'),
      ('Composite Filling', 'Restorative', 4500, '40 min'),
      ('Root Canal Therapy', 'Endodontics', 18000, '45–60 min'),
      ('Tooth Extraction', 'Surgery', 3000, '30 min'),
      ('Zirconia Crown', 'Prosthodontics', 25000, '2 visits'),
      ('Dental Implant', 'Surgery', 85000, 'Multi-visit'),
      ('Braces (Metal)', 'Orthodontics', 120000, '12–18 mo'),
      ('Teeth Whitening', 'Cosmetic', 15000, '60 min'),
      ('Wisdom Tooth Surgery', 'Surgery', 22000, '60 min'),
    ];
    for (final t in demo) {
      await _db
          .into(_db.treatments)
          .insert(
            TreatmentsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              name: t.$1,
              category: t.$2,
              price: Value(t.$3),
              duration: Value(t.$4),
            ),
          );
    }
  }
}
