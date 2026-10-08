import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/utils/uuids.dart';
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
  static const _kRxStart = 'rx_start_no';
  static const _kRxPrefix = 'rx_prefix';
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
    PatientXrays,
    Medicines,
    PrecautionSets,
    PrecautionLines,
    Prescriptions,
    PrescriptionItems,
    PrescriptionCare,
    RolePermissions,
    LookupLists,
    Expenses,
    InvoicePayments,
    Devices,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openEncryptedConnection());
  static const _kLastSync = 'last_sync_at';

  @override
  int get schemaVersion => 26;
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

  /// X-rays for a patient, newest first.
  Stream<List<XrayRow>> watchXrays(int patientId) =>
      (select(patientXrays)
            ..where(
              (t) => t.patientId.equals(patientId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]))
          .watch();

  /// Count of X-rays stored in a given calendar year (for the basic-tier cap).
  /// Count of X-rays stored within a given period (the clinic's subscription year).
  Future<int> xrayCountBetween(DateTime start, DateTime end) async {
    final rows =
        await (select(patientXrays)..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.createdAt.isBiggerOrEqualValue(start) &
                  t.createdAt.isSmallerThanValue(end),
            ))
            .get();
    return rows.length;
  }

  /// All non-deleted X-rays (optionally branch-filtered) for ZIP export.
  Future<List<XrayRow>> allXrays({String? branchId}) =>
      (select(patientXrays)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  (branchId == null
                      ? const Constant(true)
                      : t.branchId.equals(branchId)),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]))
          .get();

  Future<void> softDeleteXray(int id) =>
      (update(patientXrays)..where((t) => t.id.equals(id))).write(
        const PatientXraysCompanion(isDeleted: Value(true)),
      );

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _indexes();
    },

    onUpgrade: (m, from, to) async {
      if (from < 6) {
        try {
          await m.createTable(branches);
        } catch (_) {}
      }
      if (from < 7) {
        try {
          await m.addColumn(users, users.branchId);
        } catch (_) {}
      }
      if (from < 8) {
        try {
          await m.addColumn(appointments, appointments.billed);
        } catch (_) {}
      }
      if (from < 9) {
        try {
          await m.addColumn(users, users.email);
        } catch (_) {}
        try {
          await m.addColumn(users, users.phone);
        } catch (_) {}
      }
      if (from < 10) {
        try {
          await m.addColumn(treatments, treatments.branchId);
        } catch (_) {}
      }
      if (from < 11) {
        try {
          await m.addColumn(patients, patients.cnic);
        } catch (_) {}
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
      if (from < 13) {
        try {
          await m.createTable(bookingRequests);
        } catch (_) {}
      }
      if (from < 14) {
        try {
          await m.addColumn(treatmentSteps, treatmentSteps.completedAt);
        } catch (_) {}
      }
      if (from < 15) {
        try {
          await m.createTable(offers);
        } catch (_) {}
      }
      if (from < 16) {
        try {
          await m.addColumn(branches, branches.waEnabled);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waMethod);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waPhone);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waApiToken);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waPhoneId);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waSessionStatus);
        } catch (_) {}
      }
      if (from < 17) {
        try {
          await m.addColumn(branches, branches.waQrStatus);
        } catch (_) {}
        try {
          await m.addColumn(branches, branches.waReminderChannel);
        } catch (_) {}
      }
      if (from < 18) {
        try {
          await m.addColumn(offers, offers.sentApp);
        } catch (_) {}
        try {
          await m.addColumn(offers, offers.sentWhatsApp);
        } catch (_) {}
      }
      if (from < 19) {
        try {
          await m.createTable(patientXrays);
        } catch (_) {}
      }
      if (from < 20) {
        try {
          await m.createTable(medicines);
        } catch (_) {}
        try {
          await m.createTable(precautionSets);
        } catch (_) {}
        try {
          await m.createTable(precautionLines);
        } catch (_) {}
        try {
          await m.createTable(prescriptions);
        } catch (_) {}
        try {
          await m.createTable(prescriptionItems);
        } catch (_) {}
        try {
          await m.createTable(prescriptionCare);
        } catch (_) {}
      }
      if (from < 21) {
        try {
          await m.createTable(rolePermissions);
        } catch (_) {}
      }
      if (from < 22) {
        // appointmentId was added to the table definition without a migration,
        // so databases created before then are missing it.
        try {
          await m.addColumn(invoices, invoices.appointmentId);
        } catch (_) {}
        try {
          await m.addColumn(invoices, invoices.cancelledBy);
        } catch (_) {}
        try {
          await m.addColumn(invoices, invoices.cancelledAt);
        } catch (_) {}
      }
      if (from < 23) {
        try {
          await m.addColumn(branches, branches.waLanguage);
        } catch (_) {}
      }
      if (from < 24) {
        try {
          await m.createTable(lookupLists);
        } catch (_) {}
        try {
          await m.createTable(expenses);
        } catch (_) {}
        try {
          await m.createTable(invoicePayments);
        } catch (_) {}
        try {
          await m.addColumn(invoices, invoices.amountPaid);
        } catch (_) {}
        try {
          await _v24Indexes();
        } catch (_) {}
        try {
          await backfillPaymentsForPaidInvoices();
        } catch (_) {}
      }
      if (from < 25) {
        try {
          await m.addColumn(expenses, expenses.updatedByName);
        } catch (_) {}
      }
      if (from < 26) {
        try {
          await m.createTable(devices);
        } catch (_) {}
        try {
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_device_letter '
            'ON devices(clinic_id, letter) WHERE is_deleted = 0;',
          );
        } catch (_) {}
      }
    },
  );
  // ───────────────────────── v24: payments, balance, expenses ──────────────

  /// One payment row per already-paid invoice, so no figure on screen changes
  /// the day a clinic upgrades.
  ///
  /// The uuid is derived from the invoice uuid, NOT random: every machine
  /// backfills independently, and a random uuid would push a second payment
  /// row for the same invoice and double its revenue after sync.
  Future<void> backfillPaymentsForPaidInvoices() async {
    final clinicId = await currentClinicId() ?? '';
    final rows = await (select(
      invoices,
    )..where((t) => t.isDeleted.equals(false) & t.status.equals('paid'))).get();

    for (final inv in rows) {
      final uuid = 'pay-${inv.uuid}';
      final existing = await (select(
        invoicePayments,
      )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
      if (existing == null) {
        await into(invoicePayments).insert(
          InvoicePaymentsCompanion.insert(
            uuid: uuid,
            clinicId: clinicId.isEmpty ? inv.clinicId : clinicId,
            branchId: Value(inv.branchId),
            invoiceId: inv.id,
            invoiceUuid: inv.uuid,
            amount: inv.total,
            paidAt: inv.issuedAt,
            note: const Value('Recorded before payment tracking'),
          ),
        );
      }
      // Only amountPaid is written — updatedAt is deliberately left alone so
      // the upgrade doesn't re-push every historical invoice.
      await (update(invoices)..where((t) => t.id.equals(inv.id))).write(
        InvoicesCompanion(amountPaid: Value(inv.total)),
      );
    }
  }

  /// Recomputes invoices.amountPaid, moves the status between pending and
  /// paid, then refreshes the patient's balance. Call after EVERY payment
  /// insert, edit or delete, and after an invoice total changes.
  Future<void> recalcInvoicePaid(int invoiceId) async {
    final s = invoicePayments.amount.sum();
    final q = selectOnly(invoicePayments)
      ..addColumns([s])
      ..where(
        invoicePayments.invoiceId.equals(invoiceId) &
            invoicePayments.isDeleted.equals(false),
      );
    final paid = (await q.getSingleOrNull())?.read(s) ?? 0;

    final inv = await (select(
      invoices,
    )..where((t) => t.id.equals(invoiceId))).getSingleOrNull();
    if (inv == null) return;

    // A cancelled invoice keeps its status whatever the payments say.
    var status = inv.status;
    if (status != 'cancelled') {
      if (paid >= inv.total && inv.total > 0) {
        status = 'paid';
      } else if (status == 'paid') {
        status = 'pending';
      }
    }

    // No write when nothing changed — otherwise every sync pull bumps
    // updatedAt, re-pushes the invoice, and the two machines ping-pong.
    if (paid != inv.amountPaid || status != inv.status) {
      await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
        InvoicesCompanion(
          amountPaid: Value(paid),
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    await recalcPatientBalance(inv.patientId);
  }

  /// patients.balance is a cache, never typed by hand:
  /// sum(total - amountPaid) over live, non-cancelled invoices.
  Future<void> recalcPatientBalance(int patientId) async {
    final rows =
        await (select(invoices)..where(
              (t) =>
                  t.patientId.equals(patientId) &
                  t.isDeleted.equals(false) &
                  t.status.equals('cancelled').not(),
            ))
            .get();
    var due = 0;
    for (final i in rows) {
      final d = i.total - i.amountPaid;
      if (d > 0) due += d;
    }
    final p = await (select(
      patients,
    )..where((t) => t.id.equals(patientId))).getSingleOrNull();
    if (p == null || p.balance == due) return;
    await (update(patients)..where((t) => t.id.equals(patientId))).write(
      PatientsCompanion(balance: Value(due), updatedAt: Value(DateTime.now())),
    );
  }

  /// Rebuilds every cached figure. Run once after a restore from cloud.
  Future<void> recalcAllPaidAndBalances() async {
    for (final inv in await (select(
      invoices,
    )..where((t) => t.isDeleted.equals(false))).get()) {
      await recalcInvoicePaid(inv.id);
    }
  }

  /// The one place a payment is written. Both the payment dialog and
  /// markPaid() go through here so amountPaid, invoice status and the
  /// patient balance can never drift apart.
  Future<void> insertPayment({
    required int invoiceId,
    required int amount,
    required DateTime paidAt,
    String method = 'Cash',
    String? methodDetail,
    String? reference,
    String note = '',
    String receivedByName = '',
  }) async {
    final inv = await (select(
      invoices,
    )..where((t) => t.id.equals(invoiceId))).getSingleOrNull();
    if (inv == null) return;

    await into(invoicePayments).insert(
      InvoicePaymentsCompanion.insert(
        uuid: Uuids.v4(),
        clinicId: inv.clinicId,
        branchId: Value(inv.branchId),
        invoiceId: inv.id,
        invoiceUuid: inv.uuid,
        amount: amount,
        paidAt: paidAt,
        method: Value(method),
        methodDetail: Value(methodDetail),
        reference: Value(reference),
        note: Value(note),
        receivedByName: Value(receivedByName),
      ),
    );
    await recalcInvoicePaid(inv.id);
  }

  Future<void> softDeletePayment(int id, {String by = ''}) async {
    final row = await (select(
      invoicePayments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (update(invoicePayments)..where((t) => t.id.equals(id))).write(
      InvoicePaymentsCompanion(
        isDeleted: const Value(true),
        deletedByName: Value(by),
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await recalcInvoicePaid(row.invoiceId);
  }

  Future<List<InvoicePaymentRow>> paymentsForInvoice(int invoiceId) =>
      (select(invoicePayments)
            ..where(
              (t) => t.invoiceId.equals(invoiceId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
          .get();

  /// What the patient owes on OTHER invoices — the "previous balance"
  /// line on a receipt.
  Future<int> patientBalanceExcluding(int patientId, int invoiceId) async {
    final rows =
        await (select(invoices)..where(
              (t) =>
                  t.patientId.equals(patientId) &
                  t.isDeleted.equals(false) &
                  t.id.equals(invoiceId).not() &
                  t.status.equals('cancelled').not(),
            ))
            .get();
    var due = 0;
    for (final i in rows) {
      final d = i.total - i.amountPaid;
      if (d > 0) due += d;
    }
    return due;
  }

  Stream<List<InvoicePaymentRow>> watchPaymentsForInvoice(int invoiceId) =>
      (select(invoicePayments)
            ..where(
              (t) => t.invoiceId.equals(invoiceId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
          .watch();

  Future<int> patientBalance(int patientId) async {
    final p = await (select(
      patients,
    )..where((t) => t.id.equals(patientId))).getSingleOrNull();
    return p?.balance ?? 0;
  }

  Stream<int> watchPatientBalance(int patientId) =>
      (select(patients)..where((t) => t.id.equals(patientId)))
          .watchSingleOrNull()
          .map((p) => p?.balance ?? 0);

  /// Cash actually collected in a period — the income side of net profit.
  Stream<int> watchCollectedBetween(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final s = invoicePayments.amount.sum();
    final q = selectOnly(invoicePayments)
      ..addColumns([s])
      ..where(
        invoicePayments.isDeleted.equals(false) &
            invoicePayments.paidAt.isBiggerOrEqualValue(start) &
            invoicePayments.paidAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : invoicePayments.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(s) ?? 0).watchSingle();
  }

  /// Individual payments in a period, for the weekly / monthly charts.
  Stream<List<({DateTime paidAt, int amount})>> watchPaymentsBetween(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final q = select(invoicePayments)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.paidAt.isBiggerOrEqualValue(start) &
            t.paidAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : t.branchId.equals(branchId)),
      );
    return q.map((r) => (paidAt: r.paidAt, amount: r.amount)).watch();
  }

  Stream<int> watchExpenseTotal(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final s = expenses.amount.sum();
    final q = selectOnly(expenses)
      ..addColumns([s])
      ..where(
        expenses.isDeleted.equals(false) &
            expenses.paidAt.isBiggerOrEqualValue(start) &
            expenses.paidAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : expenses.branchId.equals(branchId)),
      );
    return q.map((r) => r.read(s) ?? 0).watchSingle();
  }

  Stream<List<ExpenseRow>> watchExpensesBetween(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) =>
      (select(expenses)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.paidAt.isBiggerOrEqualValue(start) &
                  t.paidAt.isSmallerThanValue(end) &
                  (branchId == null
                      ? const Constant(true)
                      : t.branchId.equals(branchId)),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
          .watch();

  Stream<List<({String categoryUuid, int total})>> watchExpenseByCategory(
    DateTime start,
    DateTime end, {
    String? branchId,
  }) {
    final s = expenses.amount.sum();
    final q = selectOnly(expenses)
      ..addColumns([expenses.categoryUuid, s])
      ..where(
        expenses.isDeleted.equals(false) &
            expenses.paidAt.isBiggerOrEqualValue(start) &
            expenses.paidAt.isSmallerThanValue(end) &
            (branchId == null
                ? const Constant(true)
                : expenses.branchId.equals(branchId)),
      )
      ..groupBy([expenses.categoryUuid])
      ..orderBy([OrderingTerm(expression: s, mode: OrderingMode.desc)]);
    return q
        .map(
          (r) => (
            categoryUuid: r.read(expenses.categoryUuid) ?? '',
            total: r.read(s) ?? 0,
          ),
        )
        .watch();
  }

  Stream<List<LookupRow>> watchLookups(String kind) =>
      (select(lookupLists)
            ..where((t) => t.kind.equals(kind) & t.isDeleted.equals(false))
            ..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch();

  /// Hidden rows included — only the lists manager wants these.
  Stream<List<LookupRow>> watchAllLookups(String kind) =>
      (select(lookupLists)
            ..where((t) => t.kind.equals(kind))
            ..orderBy([
              (t) => OrderingTerm.asc(t.isDeleted),
              (t) => OrderingTerm.asc(t.sortOrder),
            ]))
          .watch();

  /// categoryUuid → count of live expenses using it.
  Stream<Map<String, int>> watchCategoryUsage() {
    final c = countAll();
    final q = selectOnly(expenses)
      ..addColumns([expenses.categoryUuid, c])
      ..where(expenses.isDeleted.equals(false))
      ..groupBy([expenses.categoryUuid]);
    return q.watch().map(
      (rows) => {
        for (final r in rows)
          (r.read(expenses.categoryUuid) ?? ''): r.read(c) ?? 0,
      },
    );
  }

  Future<List<LookupRow>> lookups(String kind) =>
      (select(lookupLists)
            ..where((t) => t.kind.equals(kind) & t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  /// ⚠ Call ONCE at the end of completeSetup for a genuinely new clinic.
  /// Never before a restore — seeding first leaves duplicate rows, exactly
  /// as it did with medicines and precaution sets.
  Future<void> seedLookupsIfEmpty() async {
    if (!await seedAllowed()) return;
    final clinicId = await currentClinicId() ?? '';
    if (clinicId.isEmpty) return;
    final existing = await (select(lookupLists)..limit(1)).getSingleOrNull();
    if (existing != null) return;

    const categories = [
      'Rent',
      'Salaries',
      'Supplies & Consumables',
      'Lab Fees',
      'Utilities',
      'Equipment & Maintenance',
      'Marketing',
      'Transport',
      'Taxes & Govt Fees',
      'Other',
    ];
    const methods = [
      'Cash',
      'Bank Transfer',
      'Card',
      'JazzCash',
      'EasyPaisa',
      'Cheque',
      'Other',
    ];

    Future<void> add(String kind, String name, int order) =>
        into(lookupLists).insert(
          LookupListsCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            kind: kind,
            name: name,
            sortOrder: Value(order),
            isSystem: const Value(true),
          ),
        );

    for (var i = 0; i < categories.length; i++) {
      await add('expense_category', categories[i], i);
    }
    for (var i = 0; i < methods.length; i++) {
      await add('payment_method', methods[i], i);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  // ───────────────────────── v26: device identity ──────────────────────────

  static const _kDeviceUuid = 'device_uuid';
  static const _kDeviceLetter = 'device_letter';
  static const _kSeedAllowed = 'seed_allowed';

  /// May this install create factory defaults (categories, permissions,
  /// medicines)?
  ///
  /// Only a genuinely NEW clinic may. A computer that joined an existing
  /// clinic, or one that restored from the cloud, must never seed: its
  /// tables are empty only because the data has not arrived yet, and
  /// seeding would push defaults up with today's timestamp, which
  /// last-write-wins would then apply over the owner's real settings on
  /// every other machine.
  ///
  /// Absent means allowed, so installs that pre-date this flag keep
  /// behaving exactly as they did.
  Future<bool> seedAllowed() async =>
      (await getSetting(_kSeedAllowed) ?? '1') == '1';

  Future<void> setSeedAllowed(bool v) =>
      setSetting(_kSeedAllowed, v ? '1' : '0');

  /// This install's own identity. Created on first call and never changed.
  ///
  /// Every install starts as 'A'. Only the join flow hands out B and beyond,
  /// so an existing single-PC clinic upgrading to v26 keeps producing exactly
  /// the numbers it always has.
  Future<({String uuid, String letter})> localDevice() async {
    var uuid = await getSetting(_kDeviceUuid) ?? '';
    if (uuid.isEmpty) {
      uuid = Uuids.v4();
      await setSetting(_kDeviceUuid, uuid);
    }
    var letter = await getSetting(_kDeviceLetter) ?? '';
    if (letter.isEmpty) {
      letter = 'A';
      await setSetting(_kDeviceLetter, letter);
    }
    return (uuid: uuid, letter: letter);
  }

  /// Called by the join flow once the server has assigned a letter.
  Future<void> setLocalDeviceLetter(String letter) =>
      setSetting(_kDeviceLetter, letter.toUpperCase());

  /// Appended to every locally generated number. Empty on device A, so the
  /// first computer's numbering is unchanged forever.
  Future<String> numberSuffix() async {
    final d = await localDevice();
    return d.letter == 'A' ? '' : '-${d.letter}';
  }

  Stream<List<DeviceRow>> watchDevices() =>
      (select(devices)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.letter)]))
          .watch();

  Future<List<DeviceRow>> activeDevices() =>
      (select(devices)
            ..where((t) => t.isDeleted.equals(false) & t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.letter)]))
          .get();

  /// Creates or refreshes this computer's row.
  Future<void> upsertDevice({
    required String uuid,
    required String clinicId,
    required String letter,
    String? name,
    String? platform,
    String? joinedByName,
    bool touchLastSeen = false,
  }) async {
    final existing = await (select(
      devices,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

    if (existing == null) {
      await into(devices).insert(
        DevicesCompanion.insert(
          uuid: uuid,
          clinicId: clinicId,
          letter: letter.toUpperCase(),
          name: Value(name ?? ''),
          platform: Value(platform ?? ''),
          joinedByName: Value(joinedByName ?? ''),
          lastSeenAt: Value(touchLastSeen ? DateTime.now() : null),
        ),
      );
      return;
    }

    // Edit, never insertOnConflictUpdate — uuid is NOT NULL unique and an
    // absent value throws.
    await (update(devices)..where((t) => t.id.equals(existing.id))).write(
      DevicesCompanion(
        clinicId: Value(clinicId),
        letter: Value(letter.toUpperCase()),
        name: name == null ? const Value.absent() : Value(name),
        platform: platform == null ? const Value.absent() : Value(platform),
        lastSeenAt: touchLastSeen
            ? Value(DateTime.now())
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Bumped after every successful sync, so the owner can see which
  /// computers are still alive.
  Future<void> touchThisDevice() async {
    final d = await localDevice();
    await (update(devices)..where((t) => t.uuid.equals(d.uuid))).write(
      DevicesCompanion(
        lastSeenAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Owner revoking a machine that was lost or replaced.
  Future<void> deactivateDevice(int id) =>
      (update(devices)..where((t) => t.id.equals(id))).write(
        DevicesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────

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

  Future<void> setBranchWaLanguage(int id, String lang) =>
      (update(branches)..where((t) => t.id.equals(id))).write(
        BranchesCompanion(
          waLanguage: Value(lang),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<String?> currentBranchId() async {
    final v = await getSetting('active_branch');
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> updateBranchWhatsApp({
    required int id,
    required bool waEnabled,
    required String waMethod,
    String? waPhone,
    String? waApiToken,
    String? waPhoneId,
  }) => (update(branches)..where((t) => t.id.equals(id))).write(
    BranchesCompanion(
      waEnabled: Value(waEnabled),
      waMethod: Value(waMethod),
      waPhone: Value(waPhone),
      waApiToken: Value(waApiToken),
      waPhoneId: Value(waPhoneId),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> setBranchQrStatus(int id, String? status) =>
      (update(branches)..where((t) => t.id.equals(id))).write(
        BranchesCompanion(
          waQrStatus: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setBranchOfficialApi({
    required int id,
    String? apiToken,
    String? phoneId,
    String? phone,
  }) => (update(branches)..where((t) => t.id.equals(id))).write(
    BranchesCompanion(
      waApiToken: Value(apiToken),
      waPhoneId: Value(phoneId),
      waPhone: Value(phone),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> setBranchReminderChannel(int id, String channel) =>
      (update(branches)..where((t) => t.id.equals(id))).write(
        BranchesCompanion(
          waReminderChannel: Value(channel),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setBranchWaEnabled(int id, bool enabled) =>
      (update(branches)..where((t) => t.id.equals(id))).write(
        BranchesCompanion(
          waEnabled: Value(enabled),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Next invoice number as a 7-digit string ('0000001', '0000002', …).
  /// Scans existing invoice numbers, takes the max numeric value, adds 1.
  /// Next invoice number as a 7-digit string ('0000001', '0000002', …).
  Future<String> nextInvoiceNo() async {
    final clinicId = await currentClinicId() ?? '';
    final rows = await (select(
      invoices,
    )..where((t) => t.clinicId.equals(clinicId))).get();
    var maxN = 0;
    for (final r in rows) {
      final digits = r.invoiceNo.replaceAll(RegExp(r'[^0-9]'), '');
      final n = int.tryParse(digits) ?? 0;
      if (n > maxN) maxN = n;
    }
    // The max scan above strips non-digits, so a number from another
    // computer ("0000187-B") still reads as 187. The sequence is shared
    // across devices; only the suffix differs.
    return '${(maxN + 1).toString().padLeft(7, '0')}${await numberSuffix()}';
  }

  // for letter head settngs
  Future<String> rxSetting(String key, [String fallback = '']) async =>
      (await getSetting('rx_$key')) ?? fallback;
  Future<void> setRxSetting(String key, String v) => setSetting('rx_$key', v);

  static const _kIdleMins = 'idle_timeout_minutes';

  /// Auto-logout timeout in minutes. 0 = disabled. Default 10.
  Future<int> idleTimeoutMinutes() async =>
      int.tryParse(await getSetting(_kIdleMins) ?? '') ?? 10;

  Future<void> setIdleTimeoutMinutes(int m) =>
      setSetting(_kIdleMins, m.toString());

  /// Next prescription number, 'RX-0000001' style.but you can change first rx from rx_start_no
  static const _kRxStart = 'rx_start_no';
  static const _kRxPrefix = 'rx_prefix';
  Future<int> rxStartNo() async =>
      int.tryParse(await getSetting(_kRxStart) ?? '') ?? 1;
  Future<void> setRxStartNo(int n) => setSetting(_kRxStart, n.toString());

  Future<String> rxPrefix() async => (await getSetting(_kRxPrefix)) ?? 'RX-';
  Future<void> setRxPrefix(String p) => setSetting(_kRxPrefix, p);

  /// Next prescription number. Continues from the highest issued number,
  /// but jumps forward to the configured start if that start is higher.
  /// (Lets a clinic migrating from a paper book begin at e.g. RX-0023500.)
  Future<String> nextRxNo() async {
    final clinicId = await currentClinicId() ?? '';
    final rows = await (select(
      prescriptions,
    )..where((t) => t.clinicId.equals(clinicId))).get();
    var maxN = 0;
    for (final r in rows) {
      final n = int.tryParse(r.rxNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (n > maxN) maxN = n;
    }
    final start = await rxStartNo();
    final next = (maxN + 1) > start ? (maxN + 1) : start;
    final prefix = await rxPrefix();
    return '$prefix${next.toString().padLeft(7, '0')}${await numberSuffix()}';
  }

  /// True if this exact invoice number already exists (active clinic).
  Future<bool> invoiceNoExists(String no) async {
    final clinicId = await currentClinicId() ?? '';
    final row =
        await (select(invoices)
              ..where(
                (t) => t.invoiceNo.equals(no) & t.clinicId.equals(clinicId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Next patient code as 'PT-0000001' style (7-digit, sequential).
  Future<String> nextPatientCode() async {
    final clinicId = await currentClinicId() ?? '';
    final rows = await (select(
      patients,
    )..where((t) => t.clinicId.equals(clinicId))).get();
    var maxN = 0;
    for (final r in rows) {
      final digits = r.code.replaceAll(RegExp(r'[^0-9]'), '');
      final n = int.tryParse(digits) ?? 0;
      if (n > maxN) maxN = n;
    }
    return 'PT-${(maxN + 1).toString().padLeft(7, '0')}${await numberSuffix()}';
  }

  /// True if this patient code already exists (active clinic).
  Future<bool> patientCodeExists(String code) async {
    final clinicId = await currentClinicId() ?? '';
    final row =
        await (select(patients)
              ..where((t) => t.code.equals(code) & t.clinicId.equals(clinicId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
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

  /// Appointment ids that have at least one prescription attached.
  Stream<Set<int>> watchPrescribedAppointmentIds() {
    final q = select(prescriptions)
      ..where((t) => t.isDeleted.equals(false) & t.appointmentId.isNotNull());
    return q.watch().map((rows) => rows.map((r) => r.appointmentId!).toSet());
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
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_invoice_no_clinic '
      'ON invoices(clinic_id, invoice_no) WHERE is_deleted = 0;',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_patient_code_clinic '
      'ON patients(clinic_id, code) WHERE is_deleted = 0;',
    );
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
    await _v24Indexes();
  }

  Future<void> _v24Indexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pay_invoice ON invoice_payments(invoice_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pay_paid_at ON invoice_payments(paid_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_exp_paid_at ON expenses(paid_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_exp_branch ON expenses(branch_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lookup_kind ON lookup_lists(kind);',
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

  /// Clears the 48h grace window so the next licence resolve must talk to
  /// the server. Support + testing tool.
  Future<void> clearContactWindow() => setSetting('last_contact_ms', '');

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
