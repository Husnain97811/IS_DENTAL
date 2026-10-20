import 'package:drift/drift.dart';

/// X-rays AND before/after photos. Photos share this table on purpose:
/// encryption, the synced list, and computer-to-computer transfer all work
/// for them with no second copy of that machinery. `kind` tells them apart.
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

  // ── v31: before & after photos ──
  /// 'xray' | 'before' | 'after' | 'progress'. Old rows are X-rays.
  TextColumn get kind => text().withDefault(const Constant('xray'))();

  /// Photos of one treatment ("case") share this id.
  TextColumn get pairGroup => text().nullable()();
  TextColumn get tooth => text().withDefault(const Constant(''))();
  TextColumn get treatment => text().withDefault(const Constant(''))();

  /// Patient agreed to the photo being used in clinic marketing.
  BoolColumn get consent => boolean().withDefault(const Constant(false))();

  // ── v32: showcase ──
  /// Who ticked consent, and when — the record if a patient ever asks.
  TextColumn get consentBy => text().withDefault(const Constant(''))();
  DateTimeColumn get consentAt => dateTime().nullable()();

  /// Starred as one of the clinic's best cases.
  BoolColumn get featured => boolean().withDefault(const Constant(false))();

  /// Marketing crop "x,y,w,h" (0–1 of the photo, always 4:3) — e.g. the
  /// smile only, so no face is ever shown. Null = the whole photo.
  TextColumn get crop => text().nullable()();
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
