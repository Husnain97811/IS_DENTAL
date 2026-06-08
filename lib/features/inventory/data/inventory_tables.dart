import 'package:drift/drift.dart';

@DataClassName('InventoryItemRow')
class InventoryItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get inStock => integer().withDefault(const Constant(0))();
  IntColumn get parLevel => integer().withDefault(const Constant(0))();
  IntColumn get reorderAt => integer().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant('units'))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
