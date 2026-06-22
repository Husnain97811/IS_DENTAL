import 'package:drift/drift.dart';
import '../../patients/data/patient_tables.dart';

@DataClassName('AppointmentRow')
class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  IntColumn get patientId => integer().references(Patients, #id)();
  TextColumn get dentist => text()();
  IntColumn get chair => integer().withDefault(const Constant(1))();
  TextColumn get procedure => text()();
  DateTimeColumn get startsAt => dateTime()();
  IntColumn get durationMin => integer().withDefault(const Constant(30))();
  TextColumn get status => text().withDefault(const Constant('upcoming'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get billed => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
