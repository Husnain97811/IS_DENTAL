import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/appointments/data/appointment_tables.dart';
import 'package:is_dental/features/billing/data/billing_tables.dart';
import 'package:is_dental/features/inventory/data/inventory_tables.dart';
import 'package:is_dental/features/patients/data/patient_tables.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_connection.dart';

part 'app_database.g.dart';

/// Key/value store for app meta: license blob, anti-rollback clock, setup flag, theme.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class ClinicProfile extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()();
  TextColumn get name => text()();
  TextColumn get branch => text()();
  TextColumn get currency => text().withDefault(const Constant('PKR (Rs)'))();
  TextColumn get tier => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clinicId => text()();
  TextColumn get fullName => text()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text()(); // owner | admin | clinician | receptionist
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [
    AppSettings,
    ClinicProfile,
    Users,
    Patients,
    ToothRecords,
    TreatmentPlans,
    TreatmentSteps,
    AuditLog,
    Appointments,
    Invoices,
    InvoiceItems,
    InventoryItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openEncryptedConnection());

  @override
  int get schemaVersion => 4;
  Future<String?> clinicName() async =>
      (await select(clinicProfile).getSingleOrNull())?.name;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _indexes();
    },

    onUpgrade: (m, from, to) async {
      if (from < 4) {
        await m.createTable(invoices);
        await m.createTable(invoiceItems);
        await m.createTable(inventoryItems);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_inv_patient ON invoices(patient_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_inv_status ON invoices(status);',
        );
      }
    },
  );

  Future<void> _indexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pat_name ON patients(full_name);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pat_phone ON patients(phone);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pat_code ON patients(code);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tooth_patient ON tooth_records(patient_id);',
    );
  }

  Future<String?> currentClinicId() async =>
      (await select(clinicProfile).getSingleOrNull())?.clinicId;

  Future<User?> findActiveUser(String username) =>
      (select(users)..where(
            (t) => t.username.equals(username) & t.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  // --- settings KV ---
  Future<String?> getSetting(String k) async => (await (select(
    appSettings,
  )..where((t) => t.key.equals(k))).getSingleOrNull())?.value;

  Future<void> setSetting(String k, String v) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: k, value: v));

  // --- users / profile ---
  Future<int> userCount() async => (await (select(
    users,
  )..where((t) => t.isDeleted.equals(false))).get()).length;

  Future<void> createOwner({
    required String clinicId,
    required String fullName,
    required String username,
    required String passwordHash,
    String role = 'owner',
  }) => into(users).insert(
    UsersCompanion.insert(
      clinicId: clinicId,
      fullName: fullName,
      username: username,
      passwordHash: passwordHash,
      role: role,
    ),
  );

  Future<void> saveProfile({
    required String clinicId,
    required String name,
    required String branch,
    required String currency,
    required String tier,
  }) async {
    await delete(clinicProfile).go();
    await into(clinicProfile).insert(
      ClinicProfileCompanion.insert(
        clinicId: clinicId,
        name: name,
        branch: branch,
        currency: Value(currency),
        tier: tier,
      ),
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
