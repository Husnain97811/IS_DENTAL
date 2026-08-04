import 'package:drift/drift.dart';

@DataClassName('BookingRequestRow')
class BookingRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();
  TextColumn get patientUuid => text()();
  TextColumn get patientAccountId => text().nullable()();
  TextColumn get dentist => text()(); // matches users.full_name
  TextColumn get procedure => text()();
  DateTimeColumn get requestedSlot => dateTime()(); // stored UTC
  IntColumn get durationMin => integer().withDefault(const Constant(30))();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending|approved|rejected
  TextColumn get modifiedBy =>
      text().nullable()(); // username of staff who last modified
  TextColumn get acceptedBy =>
      text().nullable()(); // username of staff who approved
  DateTimeColumn get decidedAt =>
      dateTime().nullable()(); // when approved/rejected — drives 30-day purge
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
