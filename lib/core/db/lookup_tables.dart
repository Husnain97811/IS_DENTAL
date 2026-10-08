import 'package:drift/drift.dart';

/// One table for every small owner-editable dropdown list.
/// `kind` selects the list: 'expense_category' | 'payment_method'.
/// Adding another list later costs no new table and no new sync wiring.
@DataClassName('LookupRow')
class LookupLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Seeded by the app. Can be renamed or hidden, but marks the defaults.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
