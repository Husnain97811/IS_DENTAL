import 'package:drift/drift.dart';

/// Clinic's medicine catalog — set up once, picked from when prescribing.
@DataClassName('MedicineRow')
class Medicines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()();
  TextColumn get form =>
      text().withDefault(const Constant(''))(); // Tablet | Capsule | Syrup…
  TextColumn get defaultDosage => text().withDefault(const Constant(''))();
  TextColumn get defaultFrequency => text().withDefault(const Constant(''))();
  TextColumn get category =>
      text().withDefault(const Constant(''))(); // Antibiotic | Painkiller…
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// A named group of aftercare lines, e.g. "After Extraction".
@DataClassName('PrecautionSetRow')
class PrecautionSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()(); // "After Extraction"
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One aftercare line — Urdu and/or English.
@DataClassName('PrecautionLineRow')
class PrecautionLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get setId => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get urdu => text().withDefault(const Constant(''))();
  TextColumn get english => text().withDefault(const Constant(''))();
}

/// A prescription. Items ride along as JSON on sync (same pattern as plans).
@DataClassName('PrescriptionRow')
class Prescriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  IntColumn get patientId => integer()();
  TextColumn get patientUuid => text()();
  TextColumn get rxNo => text().withDefault(const Constant(''))(); // RX-0000045
  IntColumn get appointmentId => integer().nullable()(); // linked visit
  TextColumn get appointmentLabel =>
      text().withDefault(const Constant(''))(); // "19 Aug · Extraction #36"
  TextColumn get doctorName =>
      text().withDefault(const Constant(''))(); // from the linked visit
  TextColumn get advice => text().withDefault(const Constant(''))();
  DateTimeColumn get issuedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PrescriptionItemRow')
class PrescriptionItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get prescriptionId => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get medicine => text()();
  TextColumn get dosage => text().withDefault(const Constant(''))();
  TextColumn get frequency => text().withDefault(const Constant(''))();
  TextColumn get duration => text().withDefault(const Constant(''))();
  TextColumn get instructions => text().withDefault(const Constant(''))();
}

/// Precaution lines chosen for a specific prescription (snapshot — so editing
/// a template later never changes an already-issued prescription).
@DataClassName('PrescriptionCareRow')
class PrescriptionCare extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get prescriptionId => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get urdu => text().withDefault(const Constant(''))();
  TextColumn get english => text().withDefault(const Constant(''))();
}
