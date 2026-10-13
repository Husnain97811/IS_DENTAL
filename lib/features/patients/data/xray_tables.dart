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

  // ── v27: encryption at rest ──
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();

  /// Fingerprint of the ORIGINAL image — verifies transfers in Phase 3.
  TextColumn get sha256 => text().nullable()();
  IntColumn get byteSize => integer().withDefault(const Constant(0))();

  /// Nullable on purpose: SQLite can't add a column whose default is the
  /// current time, so the migration would fail. Set in code instead.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  // ── v28: multiple computers ──
  /// Which key in the keyring opens this file.
  TextColumn get keyId => text().nullable()();

  /// False = the file is on another computer; this row is a placeholder
  /// that arrived with the synced list.
  BoolColumn get isLocal => boolean().withDefault(const Constant(true))();

  /// Device uuid of the computer that took it.
  TextColumn get originDevice => text().nullable()();
}

/// Which X-rays each computer actually holds. Each computer writes ONLY its
/// own row, so two machines can never overwrite each other's list.
@DataClassName('DeviceInventoryRow')
class DeviceInventories extends Table {
  TextColumn get deviceUuid => text()();
  TextColumn get clinicId => text()();

  /// JSON array of X-ray uuids present on that computer.
  TextColumn get xrayUuids => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {deviceUuid};
}
