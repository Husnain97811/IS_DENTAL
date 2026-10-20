import 'package:drift/drift.dart';

/// One end-of-day cash count, per day per branch.
///
/// The uuid is built from the clinic, branch and day — not random — so if
/// two computers close the same day they update the SAME row instead of
/// creating two closings.
@DataClassName('CashClosingRow')
class CashClosings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().withDefault(const Constant(''))();

  /// The day closed, as 'yyyy-mm-dd'. Text on purpose: a calendar day must
  /// never shift because two computers are in different time zones.
  TextColumn get day => text()();

  /// Cash in the drawer when the day started.
  IntColumn get openingFloat => integer().withDefault(const Constant(0))();

  /// Snapshot at closing: cash payments received and cash expenses paid.
  IntColumn get cashIn => integer().withDefault(const Constant(0))();
  IntColumn get cashOut => integer().withDefault(const Constant(0))();

  /// openingFloat + cashIn - cashOut, at the moment of closing.
  IntColumn get expected => integer().withDefault(const Constant(0))();

  /// What staff actually counted.
  IntColumn get counted => integer().withDefault(const Constant(0))();

  /// Cash removed at closing (handed to owner / banked). What stays in the
  /// drawer — counted - takenOut — becomes tomorrow's opening cash.
  IntColumn get takenOut => integer().withDefault(const Constant(0))();

  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get closedByName => text().withDefault(const Constant(''))();
  DateTimeColumn get closedAt => dateTime().withDefault(currentDateAndTime)();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Commission percentage per dentist.
///
/// Dentists are matched by the name used on appointments. The uuid is built
/// from the clinic and the lower-cased name, so every computer edits the
/// same row for the same dentist.
@DataClassName('DentistRateRow')
class DentistRates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get dentistName => text()();

  /// 0–100. 40 means the dentist gets 40% of what was collected.
  RealColumn get percent => real().withDefault(const Constant(0))();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
