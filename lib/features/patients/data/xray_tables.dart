import 'package:drift/drift.dart';

@DataClassName('XrayRow')
class PatientXrays extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  IntColumn get patientId => integer()(); // local patient id
  TextColumn get patientUuid => text()(); // stable ref
  TextColumn get filePath => text()(); // absolute path on disk
  TextColumn get fileName => text()(); // original name
  TextColumn get fileType =>
      text().withDefault(const Constant('image'))(); // 'image' | 'pdf'
  TextColumn get caption => text().withDefault(const Constant(''))();
  DateTimeColumn get takenAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
