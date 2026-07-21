import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/inventory_item.dart';
import '../domain/inventory_repository.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  InventoryRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<InventoryItem>> watchItems({String? branchId}) =>
      (_db.select(_db.inventoryItems)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  (branchId == null
                      ? const Constant(true)
                      : t.branchId.equals(branchId)),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => InventoryItem(
                    id: r.id,
                    uuid: r.uuid,
                    name: r.name,
                    category: r.category,
                    inStock: r.inStock,
                    parLevel: r.parLevel,
                    reorderAt: r.reorderAt,
                    unit: r.unit,
                  ),
                )
                .toList(),
          );

  @override
  Future<void> adjustStock(int id, int delta) async {
    final row = await (_db.select(
      _db.inventoryItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.inventoryItems)..where((t) => t.id.equals(id))).write(
      InventoryItemsCompanion(
        inStock: Value((row.inStock + delta).clamp(0, 1 << 30)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> upsertItem(InventoryItem item) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final Value<String?> stampBranch = item.id == 0
        ? Value(await _db.currentBranchId())
        : const Value.absent();
    await _db
        .into(_db.inventoryItems)
        .insertOnConflictUpdate(
          InventoryItemsCompanion(
            id: item.id == 0 ? const Value.absent() : Value(item.id),
            uuid: Value(item.uuid.isEmpty ? Uuids.v4() : item.uuid),
            clinicId: Value(clinicId),
            branchId: stampBranch,
            name: Value(item.name),
            category: Value(item.category),
            inStock: Value(item.inStock),
            parLevel: Value(item.parLevel),
            reorderAt: Value(item.reorderAt),
            unit: Value(item.unit),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> seedDemoIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;
    if ((await _db.select(_db.inventoryItems).get()).isNotEmpty) return;
    final demo = <(String, String, int, int, int)>[
      ('Composite Resin (A2)', 'Restorative', 42, 80, 30),
      ('Local Anesthetic (Carpule)', 'Pharmacy', 18, 30, 25),
      ('Disposable Gloves (Box)', 'Consumables', 6, 40, 25),
      ('Gutta Percha Points', 'Endodontics', 55, 60, 30),
      ('Impression Material', 'Prosthodontics', 9, 25, 12),
      ('Dental Burs (Assorted)', 'Instruments', 120, 150, 50),
      ('X-Ray Films', 'Imaging', 38, 50, 20),
    ];
    for (final it in demo) {
      await _db
          .into(_db.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              name: it.$1,
              category: it.$2,
              inStock: Value(it.$3),
              parLevel: Value(it.$4),
              reorderAt: Value(it.$5),
            ),
          );
    }
  }
}
