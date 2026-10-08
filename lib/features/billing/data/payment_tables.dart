import 'package:drift/drift.dart';
import 'billing_tables.dart';

/// One row per payment received. An invoice can have many.
/// Revenue = the sum of these, bucketed by [paidAt] — so 10k now and
/// 2k next month land in the months the money actually arrived.
@DataClassName('InvoicePaymentRow')
class InvoicePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get clinicId => text()();
  TextColumn get branchId => text().nullable()();

  /// Local link, for fast joins on this machine.
  IntColumn get invoiceId => integer().references(Invoices, #id)();

  /// Cross-machine link. Resolved back to invoiceId on pull.
  TextColumn get invoiceUuid => text()();

  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();

  TextColumn get method => text().withDefault(const Constant('Cash'))();
  TextColumn get methodDetail => text().nullable()();

  /// Transaction id / TID / cheque no.
  TextColumn get reference => text().nullable()();

  TextColumn get receivedByName => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get deletedByName => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
