import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/utils/uuids.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/views.dart';
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
  TextColumn get uuid =>
      text().withDefault(const Constant(''))(); // ← this line
  TextColumn get clinicId => text()();
  TextColumn get fullName => text()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get branchId =>
      text().nullable()(); // null = clinic-wide (owner/admin)
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
    Treatments,
    Branches,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openEncryptedConnection());

  @override
  int get schemaVersion => 8;
  Future<String?> clinicName() async =>
      (await select(clinicProfile).getSingleOrNull())?.name;

  Stream<int> watchPatientCount() {
    final c = countAll();
    final q = selectOnly(patients)
      ..addColumns([c])
      ..where(patients.isDeleted.equals(false));
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchInTreatmentCount() {
    final c = countAll();
    final q = selectOnly(patients)
      ..addColumns([c])
      ..where(
        patients.isDeleted.equals(false) &
            patients.status.equals('inTreatment'),
      );
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchAppointmentCount(DateTime start, DateTime end) {
    final c = countAll();
    final q = selectOnly(appointments)
      ..addColumns([c])
      ..where(
        appointments.isDeleted.equals(false) &
            appointments.startsAt.isBiggerOrEqualValue(start) &
            appointments.startsAt.isSmallerThanValue(end),
      );
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchPaidRevenue(DateTime start, DateTime end) {
    final s = invoices.total.sum();
    final q = selectOnly(invoices)
      ..addColumns([s])
      ..where(
        invoices.isDeleted.equals(false) &
            invoices.status.equals('paid') &
            invoices.issuedAt.isBiggerOrEqualValue(start) &
            invoices.issuedAt.isSmallerThanValue(end),
      );
    return q.map((r) => r.read(s) ?? 0).watchSingle();
  }

  Stream<({int sum, int count})> watchUnpaidTotals() {
    final s = invoices.total.sum();
    final c = countAll();
    final q = selectOnly(invoices)
      ..addColumns([s, c])
      ..where(
        invoices.isDeleted.equals(false) &
            invoices.status.isIn(const ['pending', 'overdue']),
      );
    return q
        .map((r) => (sum: r.read(s) ?? 0, count: r.read(c) ?? 0))
        .watchSingle();
  }

  Stream<List<({String procedure, int count})>> watchTopProcedures(
    DateTime start,
    DateTime end, {
    int limit = 5,
  }) {
    final c = countAll();
    final q = selectOnly(appointments)
      ..addColumns([appointments.procedure, c])
      ..where(
        appointments.isDeleted.equals(false) &
            appointments.startsAt.isBiggerOrEqualValue(start) &
            appointments.startsAt.isSmallerThanValue(end),
      )
      ..groupBy([appointments.procedure])
      ..orderBy([OrderingTerm(expression: c, mode: OrderingMode.desc)])
      ..limit(limit);
    return q
        .map(
          (r) => (
            procedure: r.read(appointments.procedure)!,
            count: r.read(c) ?? 0,
          ),
        )
        .watch();
  }

  // Only the current week's paid invoices (small set), bucketed by day in Dart.
  Stream<List<({DateTime issuedAt, int total})>> watchPaidInvoicesBetween(
    DateTime start,
    DateTime end,
  ) {
    final q = select(invoices)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.status.equals('paid') &
            t.issuedAt.isBiggerOrEqualValue(start) &
            t.issuedAt.isSmallerThanValue(end),
      );
    return q.map((r) => (issuedAt: r.issuedAt, total: r.total)).watch();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _indexes();
    },

    onUpgrade: (m, from, to) async {
      if (from < 8) {
        await m.addColumn(appointments, appointments.billed);
      }
      if (from < 7) {
        await m.addColumn(users, users.branchId);
      }
      if (from < 6) {
        await m.createTable(branches);
      }
    },
  );

  Future<void> backfillUserUuids() async {
    for (final u in await (select(
      users,
    )..where((t) => t.uuid.equals(''))).get()) {
      await (update(users)..where((t) => t.id.equals(u.id))).write(
        UsersCompanion(
          uuid: Value(Uuids.v4()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<String?> currentBranchId() async {
    final v = await getSetting('active_branch');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> addStaff({
    required String clinicId,
    String? branchId,
    required String fullName,
    required String username,
    required String passwordHash,
    required String role,
  }) => into(users).insert(
    UsersCompanion.insert(
      clinicId: clinicId,
      branchId: Value(branchId),
      fullName: fullName,
      username: username,
      passwordHash: passwordHash,
      role: role,
    ),
  );
  Future<void> softDeleteUser(int id) =>
      (update(users)..where((t) => t.id.equals(id))).write(
        UsersCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setAppointmentStatus(int id, String status) =>
      (update(appointments)..where((t) => t.id.equals(id))).write(
        AppointmentsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setAppointmentBilled(int id) =>
      (update(appointments)..where((t) => t.id.equals(id))).write(
        AppointmentsCompanion(
          billed: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Stream<Set<int>> watchBilledAppointmentIds() {
    final q = select(appointments)
      ..where((t) => t.billed.equals(true) & t.isDeleted.equals(false));
    return q.watch().map((rows) => rows.map((r) => r.id).toSet());
  }

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
      uuid: Value(Uuids.v4()), // <-- this is what's missing
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
