import 'package:drift/drift.dart';

/// One row per computer running this clinic's DentOS install.
///
/// The [letter] is what keeps locally-generated numbers from colliding:
/// device A appends nothing (so existing clinics are untouched), B appends
/// "-B", and so on. Assigned once when a computer joins and never changed —
/// two PCs that have not synced for a week still cannot produce the same
/// patient code.
@DataClassName('DeviceRow')
class Devices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();

  /// 'A'…'Z'. Unique per clinic.
  TextColumn get letter => text().withLength(min: 1, max: 1)();

  /// What the owner sees in Settings: "Reception PC", "Dr Khan's laptop".
  TextColumn get name => text().withDefault(const Constant(''))();

  /// macOS / windows / linux, plus the OS version.
  TextColumn get platform => text().withDefault(const Constant(''))();

  /// Username of whoever set this computer up.
  TextColumn get joinedByName => text().withDefault(const Constant(''))();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every successful sync — how the owner spots a dead machine.
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  /// Revoked by the owner. A revoked device frees its letter only when the
  /// owner explicitly removes it, never automatically.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
