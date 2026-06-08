import 'package:drift/drift.dart';
import '../../patients/data/patient_tables.dart';

@DataClassName('InvoiceRow')
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  IntColumn get patientId => integer().references(Patients, #id)();
  TextColumn get invoiceNo => text()();
  DateTimeColumn get issuedAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get summary => text().withDefault(const Constant(''))();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get adjustment => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('InvoiceItemRow')
class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  TextColumn get description => text()();
  IntColumn get amount => integer()();
  IntColumn get qty => integer().withDefault(const Constant(1))();
}
