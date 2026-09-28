import 'package:drift/drift.dart';

/// One row per (role, key). Owner is never stored — owner is always allowed.
@DataClassName('PermissionRow')
class RolePermissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()();
  TextColumn get role => text()(); // admin | clinician | receptionist
  TextColumn get key => text()(); // viewFinancials | …
  BoolColumn get allowed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {clinicId, role, key},
  ];
}
