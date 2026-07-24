import 'package:drift/drift.dart';

@DataClassName('BranchRow')
class Branches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()();
  TextColumn get location => text().withDefault(const Constant(''))();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  IntColumn get openMinutes =>
      integer().withDefault(const Constant(600))(); // 10:00
  IntColumn get closeMinutes =>
      integer().withDefault(const Constant(1020))(); // 17:00
  IntColumn get slotMinutes => integer().withDefault(const Constant(20))();
  TextColumn get closedDays =>
      text().withDefault(const Constant(''))(); // CSV 1..7 (Mon..Sun)
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
