import 'package:drift/drift.dart';

@DataClassName('ExpenseRow')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();

  /// Always set by the editor. Defaulted rather than NOT NULL so a pull
  /// from an older row can never crash the insert.
  TextColumn get branchId => text().withDefault(const Constant(''))();

  /// lookup_lists.uuid where kind = 'expense_category'.
  TextColumn get categoryUuid => text().withDefault(const Constant(''))();

  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get vendor => text().nullable()();

  /// lookup_lists name where kind = 'payment_method'. Stored as text so a
  /// renamed or deleted method never breaks an old expense.
  TextColumn get method => text().withDefault(const Constant('Cash'))();

  /// Free text beside the method — bank name, wallet, account.
  TextColumn get methodDetail => text().nullable()();

  /// Optional transaction id / TID / cheque no.
  TextColumn get reference => text().nullable()();

  /// Snapshot of the username. Local int user ids don't transfer between machines.
  TextColumn get recordedByName => text().withDefault(const Constant(''))();

  /// Who last edited it. Null until someone edits.
  TextColumn get updatedByName => text().nullable()();
  DateTimeColumn get editedAt => dateTime().nullable()();

  /// Reserved for the inventory link (sourceType 'inventory' + the stock uuid).
  TextColumn get sourceType => text().nullable()();
  TextColumn get sourceUuid => text().nullable()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get deletedByName => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deleteReason => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
