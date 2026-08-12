import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/utils/uuids.dart';
import 'package:is_dental/features/offers/data/offer_tables.dart';
import 'package:is_dental/features/requests/data/booking_request_tables.dart';

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
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
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
    BookingRequests,
    Offers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openEncryptedConnection());
  static const _kLastSync = 'last_sync_at';

  @override
  int get schemaVersion => 15;
  Future<String?> clinicName() async =>
      (await select(clinicProfile).getSingleOrNull())?.name;

  /// Deletes bookinng requests that were approved OR rejected more than
  /// 30 days ago. The real appointment (for approved ones) is never touched —
  /// it lives in the appointmentss table. Pending requests are never purged.
  Future<int> purgeOldDecidedRequests() async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
    return (delete(bookingRequests)..where(
          (t) =>
              t.status.isIn(const ['approved', 'rejected']) &
              t.decidedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  /// One-time: assign a branch to all rows that have no branchId yet.
  /// Uses the first branch as the default home for legacy data.
  Future<int> backfillBranchIds() async {
    final firstBranch =
        await (select(branches)
              ..where((t) => t.isDeleted.equals(false))
              ..limit(1))
            .getSingleOrNull();
    if (firstBranch == null) return 0; // no branches → nothing to do
    final uuid = firstBranch.uuid;

    var touched = 0;

    Future<void> stamp(TableInfo table, GeneratedColumn branchCol) async {
      touched += await customUpdate(
        'UPDATE ${table.actualTableName} '
        'SET branch_id = ? '
        'WHERE branch_id IS NULL OR branch_id = ?',
        variables: [Variable.withString(uuid), Variable.withString('')],
        updates: {table},
      );
    }

    await stamp(patients, patients.branchId);
    await stamp(appointments, appointments.branchId);
    await stamp(invoices, invoices.branchId);
    await stamp(inventoryItems, inventoryItems.branchId);
    await stamp(treatments, treatments.branchId); // ← add this line

    return touched;
  }

  Stream<int> watchPatientCount({String? branchId}) {
    final c = countAll();
    final q = selectOnly(patients)
      ..addColumns([c])
      ..where(
        patients.isDeleted.equals(false) &
            (branchId == null
                ? const Constant(true)
                : patients.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchInTreatmentCount({String? branchId}) {
    final c = countAll();
    final q = selectOnly(patients)
      ..addColumns([c])
      ..where(
        patients.isDeleted.equals(false) &
            patients.status.equals('inTreatment') &
            (branchId == null
                ? const Constant(true)
                : patients.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchAppointmentCount(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final c = countAll();
    final q = selectOnly(appointments)
      ..addColumns([c])
      ..where(
        appointments.isDeleted.equals(false) &
            appointments.startsAt.isBiggerOrEqualValue(start) &
            appointments.startsAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : appointments.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<int> watchPaidRevenue(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final s = invoices.total.sum();
    final q = selectOnly(invoices)
      ..addColumns([s])
      ..where(
        invoices.isDeleted.equals(false) &
            invoices.status.equals('paid') &
            invoices.issuedAt.isBiggerOrEqualValue(start) &
            invoices.issuedAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : invoices.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(s) ?? 0).watchSingle();
  }

  Stream<({int sum, int count})> watchUnpaidTotals({String? branchId}) {
    final s = invoices.total.sum();
    final c = countAll();
    final q = selectOnly(invoices)
      ..addColumns([s, c])
      ..where(
        invoices.isDeleted.equals(false) &
            invoices.status.isIn(const ['pending', 'overdue']) &
            (branchId == null
                ? const Constant(true)
                : invoices.branchId.equals(branchId)),
      );
    return q
        .map((r) => (sum: r.read(s) ?? 0, count: r.read(c) ?? 0))
        .watchSingle();
  }

  Stream<List<({String procedure, int count})>> watchTopProcedures(
    DateTime start,
    DateTime end, {
    int limit = 5,
    String? branchId,
  }) {
    final c = countAll();
    final q = selectOnly(appointments)
      ..addColumns([appointments.procedure, c])
      ..where(
        appointments.isDeleted.equals(false) &
            appointments.startsAt.isBiggerOrEqualValue(start) &
            appointments.startsAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : appointments.branchId.equals(branchId)),
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

  Stream<List<({DateTime issuedAt, int total})>> watchPaidInvoicesBetween(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final q = select(invoices)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.status.equals('paid') &
            t.issuedAt.isBiggerOrEqualValue(start) &
            t.issuedAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : t.branchId.equals(branchId)),
      );
    return q.map((r) => (issuedAt: r.issuedAt, total: r.total)).watch();
  }

  Future<void> recordSyncNow() =>
      setSetting(_kLastSync, DateTime.now().toIso8601String());

  Future<DateTime?> lastSyncAt() async {
    final v = await getSetting(_kLastSync);
    if (v == null || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _indexes();
    },

    onUpgrade: (m, from, to) async {
      if (from < 15) {
        await m.createTable(offers);
      }
      if (from < 14) {
        try {
          await m.addColumn(treatmentSteps, treatmentSteps.completedAt);
        } catch (_) {
          if (from < 13) {
            await m.createTable(bookingRequests);
          }
          if (from < 12) {
            try {
              await m.addColumn(branches, branches.openMinutes);
            } catch (_) {}
            try {
              await m.addColumn(branches, branches.closeMinutes);
            } catch (_) {}
            try {
              await m.addColumn(branches, branches.slotMinutes);
            } catch (_) {}
            try {
              await m.addColumn(branches, branches.closedDays);
            } catch (_) {}
          }
          if (from < 11) {
            // Guarded: DBs created fresh while cnic was already in the table
            // class already have the column — plain addColumn would throw.
            try {
              await m.addColumn(patients, patients.cnic);
            } catch (_) {
              /* column already exists */
            }
          }
          if (from < 10) {
            await m.addColumn(treatments, treatments.branchId);
          }
          if (from < 9) {
            await m.addColumn(users, users.email);
            await m.addColumn(users, users.phone);
          }
          if (from < 8) {
            await m.addColumn(appointments, appointments.billed);
          }
          if (from < 7) {
            await m.addColumn(users, users.branchId);
          }
          if (from < 6) {
            await m.createTable(branches);
          }
        }
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

  Future<void> updateBranchHours({
    required int id,
    required int openMinutes,
    required int closeMinutes,
    required int slotMinutes,
    required String closedDays,
  }) => (update(branches)..where((t) => t.id.equals(id))).write(
    BranchesCompanion(
      openMinutes: Value(openMinutes),
      closeMinutes: Value(closeMinutes),
      slotMinutes: Value(slotMinutes),
      closedDays: Value(closedDays),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> addStaff({
    required String clinicId,
    String? branchId,
    required String fullName,
    required String username,
    required String passwordHash,
    required String role,
    String? email,
    String? phone,
  }) => into(users).insert(
    UsersCompanion.insert(
      uuid: Value(Uuids.v4()), // ← ADD THIS LINE
      clinicId: clinicId,
      branchId: Value(branchId),
      fullName: fullName,
      username: username,
      passwordHash: passwordHash,
      role: role,
      email: Value(email),
      phone: Value(phone),
    ),
  );

  Future<void> updateStaff({
    required int id,
    required String fullName,
    required String username,
    String? passwordHash, // null = keep existing
    required String role,
    String? branchId,
    String? email,
    String? phone,
  }) => (update(users)..where((t) => t.id.equals(id))).write(
    UsersCompanion(
      fullName: Value(fullName),
      username: Value(username),
      role: Value(role),
      branchId: Value(branchId),
      email: Value(email),
      phone: Value(phone),
      updatedAt: Value(DateTime.now()),
      // only overwrite the password when a new one is provided
      passwordHash: passwordHash == null
          ? const Value.absent()
          : Value(passwordHash),
    ),
  );

  Future<void> softDeleteUser(int id) async {
    final row = await (select(
      users,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await (update(users)..where((t) => t.id.equals(id))).write(
      UsersCompanion(
        isDeleted: const Value(true),
        username: Value('deleted_${stamp}_${row.username}'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

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

  /// appointmentId → invoice status ('pending' | 'paid' | 'overdue')
  Stream<Map<int, String>> watchAppointmentInvoiceStatuses() {
    final q = select(invoices)
      ..where((t) => t.isDeleted.equals(false) & t.appointmentId.isNotNull());
    return q.watch().map(
      (rows) => {for (final r in rows) r.appointmentId!: r.status},
    );
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

  /// Active patient with this CNIC (digits-only), excluding [excludeId].
  Future<PatientRow?> findPatientByCnic(String cnic, {int? excludeId}) =>
      (select(patients)
            ..where(
              (t) =>
                  t.cnic.equals(cnic) &
                  t.isDeleted.equals(false) &
                  (excludeId == null
                      ? const Constant(true)
                      : t.id.equals(excludeId).not()),
            )
            ..limit(1))
          .getSingleOrNull();

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
