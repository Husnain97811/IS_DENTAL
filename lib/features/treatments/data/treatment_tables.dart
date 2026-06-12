import 'package:drift/drift.dart';

@DataClassName('TreatmentRow')
class Treatments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get price => integer().withDefault(const Constant(0))();
  TextColumn get duration => text().withDefault(const Constant(''))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
