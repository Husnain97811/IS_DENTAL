import 'package:drift/drift.dart';

@DataClassName('PatientRow')
class Patients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId =>
      text().nullable()(); // Premium scoping (forward-compat)
  TextColumn get code => text()();
  TextColumn get fullName => text()();
  TextColumn get gender => text().withDefault(const Constant('female'))();
  IntColumn get age => integer().withDefault(const Constant(0))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get cnic => text().withDefault(const Constant(''))();
  TextColumn get allergies => text().nullable()();
  TextColumn get insurance => text().nullable()();
  DateTimeColumn get lastVisit => dateTime().nullable()();
  IntColumn get visitCount => integer().withDefault(const Constant(0))();
  IntColumn get balance => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get treatmentSummary => text().withDefault(const Constant(''))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ToothRecordRow')
class ToothRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId => integer().references(Patients, #id)();
  IntColumn get fdi => integer()();
  TextColumn get state => text().withDefault(const Constant('healthy'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TreatmentPlanRow')
class TreatmentPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId => integer().references(Patients, #id)();
  TextColumn get title => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TreatmentStepRow')
class TreatmentSteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId => integer().references(TreatmentPlans, #id)();
  IntColumn get position => integer()();
  TextColumn get label => text()();
  TextColumn get detail => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('todo'))();
}

@DataClassName('AuditLogRow')
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()();
  IntColumn get userId => integer().nullable()();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  TextColumn get entityRef => text().nullable()();
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();
}
