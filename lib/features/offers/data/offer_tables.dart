import 'package:drift/drift.dart';

@DataClassName('OfferRow')
class Offers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()(); // null = all branches
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  IntColumn get sentCount => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
