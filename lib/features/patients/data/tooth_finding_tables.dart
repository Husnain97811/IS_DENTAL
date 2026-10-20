import 'package:drift/drift.dart';

/// One clinical observation on one tooth.
///
/// Replaces the single `tooth_records.state` per tooth: a tooth can now hold
/// any number of findings at once (root canal AND crown, caries next to an old
/// filling), each with its own surfaces, status, date and dentist.
///
/// Nothing is ever overwritten. Removing a finding soft-deletes it, so the
/// tooth's history always shows what was recorded, when, and by whom.
@DataClassName('ToothFindingRow')
class ToothFindings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();

  /// Local link for fast queries on this computer.
  IntColumn get patientId => integer()();

  /// Cross-computer link. Resolved back to patientId on pull.
  TextColumn get patientUuid => text()();

  /// FDI tooth number: 11–48 adult, 51–85 primary.
  IntColumn get fdi => integer()();

  /// caries | filling | sealant | crown | rct | extraction | implant | bridge | missing
  TextColumn get kind => text()();

  /// found | existing | planned | done
  TextColumn get status => text()();

  /// Surfaces in clinical order, e.g. "MO", "MOD". Empty for whole-tooth
  /// findings, and for imported fillings whose surfaces were never recorded.
  TextColumn get surfaces => text().withDefault(const Constant(''))();

  TextColumn get note => text().nullable()();

  TextColumn get createdByName => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get completedByName => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get deletedByName => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
