import 'package:drift/drift.dart';

/// Things an owner may want to look back on: who opened the Detailed
/// Reporting Hub and when, wrong PINs, lockouts, PIN changes and resets.
///
/// Append-only and synced, so the owner sees what happened on every
/// computer. Phase 3's Watch list adds more kinds (discounts, price
/// changes, sign-ins) to the same table.
@DataClassName('ActivityEventRow')
class ActivityEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().withDefault(const Constant(''))();

  /// hub_open · hub_exit · hub_pin_wrong · hub_pin_locked · hub_pin_set ·
  /// hub_pin_changed · hub_pin_reset · hub_idle_lock · hub_idle_exit
  TextColumn get kind => text()();

  /// Who did it — names are snapshots, so they survive the user being
  /// removed later.
  TextColumn get userUuid => text().withDefault(const Constant(''))();
  TextColumn get userName => text().withDefault(const Constant(''))();

  /// Computer letter (A, B …).
  TextColumn get device => text().withDefault(const Constant(''))();
  TextColumn get detail => text().withDefault(const Constant(''))();
  DateTimeColumn get happenedAt => dateTime().withDefault(currentDateAndTime)();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
