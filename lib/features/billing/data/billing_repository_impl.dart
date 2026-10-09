import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/uuids.dart';
import '../domain/billing_repository.dart';
import '../domain/invoice.dart';

class BillingRepositoryImpl implements BillingRepository {
  BillingRepositoryImpl(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Invoice>> watchInvoices({String? branchId}) {
    final q =
        _db.select(_db.invoices).join([
            innerJoin(
              _db.patients,
              _db.patients.id.equalsExp(_db.invoices.patientId),
            ),
          ])
          ..where(
            _db.invoices.isDeleted.equals(false) &
                _db.invoices.status.equals('cancelled').not() &
                (branchId == null
                    ? const Constant(true)
                    : _db.invoices.branchId.equals(branchId)),
          )
          ..orderBy([OrderingTerm.desc(_db.invoices.issuedAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final i = r.readTable(_db.invoices);
        final p = r.readTable(_db.patients);
        return Invoice(
          id: i.id,
          uuid: i.uuid,
          patientId: i.patientId,
          patientName: p.fullName,
          invoiceNo: i.invoiceNo,
          issuedAt: i.issuedAt,
          status: InvoiceStatus.values.byName(i.status),
          summary: i.summary,
          subtotal: i.subtotal,
          adjustment: i.adjustment,
          total: i.total,
          amountPaid: i.amountPaid,
        );
      }).toList(),
    );
  }

  @override
  Future<void> createInvoice({
    required int patientId,
    required String invoiceNo,
    required DateTime issuedAt,
    required String status,
    required String summary,
    required int adjustment,
    required List<({String description, int amount})> items,
  }) async {
    final clinicId = await _db.currentClinicId() ?? '';
    final subtotal = items.fold<int>(0, (s, e) => s + e.amount);
    final invId = await _db
        .into(_db.invoices)
        .insert(
          InvoicesCompanion.insert(
            uuid: Uuids.v4(),
            clinicId: clinicId,
            branchId: Value(await _db.currentBranchId()),

            patientId: patientId,
            invoiceNo: invoiceNo,
            issuedAt: issuedAt,
            status: Value(status),
            summary: Value(summary),
            subtotal: Value(subtotal),
            adjustment: Value(adjustment),
            total: Value(subtotal - adjustment),
          ),
        );
    for (final it in items) {
      await _db
          .into(_db.invoiceItems)
          .insert(
            InvoiceItemsCompanion.insert(
              invoiceId: invId,
              description: it.description,
              amount: it.amount,
            ),
          );
    }
    await _db.recalcInvoicePaid(invId);
  }

  @override
  Stream<List<Invoice>> watchCancelled({String? branchId}) {
    final q =
        _db.select(_db.invoices).join([
            innerJoin(
              _db.patients,
              _db.patients.id.equalsExp(_db.invoices.patientId),
            ),
          ])
          ..where(
            _db.invoices.isDeleted.equals(false) &
                _db.invoices.status.equals('cancelled') &
                (branchId == null
                    ? const Constant(true)
                    : _db.invoices.branchId.equals(branchId)),
          )
          ..orderBy([OrderingTerm.desc(_db.invoices.cancelledAt)]);
    return q.watch().map(
      (rows) => rows.map((r) {
        final i = r.readTable(_db.invoices);
        final p = r.readTable(_db.patients);
        return Invoice(
          id: i.id,
          uuid: i.uuid,
          patientId: i.patientId,
          patientName: p.fullName,
          invoiceNo: i.invoiceNo,
          issuedAt: i.issuedAt,
          status: InvoiceStatus.values.byName(i.status),
          summary: i.summary,
          subtotal: i.subtotal,
          adjustment: i.adjustment,
          total: i.total,
          amountPaid: i.amountPaid,
          cancelledBy: i.cancelledBy,
          cancelledAt: i.cancelledAt,
        );
      }).toList(),
    );
  }

  @override
  Future<void> cancelInvoice(int id, {required String by}) async {
    final inv = await (_db.select(
      _db.invoices,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await (_db.update(_db.invoices)..where((t) => t.id.equals(id))).write(
      InvoicesCompanion(
        status: const Value('cancelled'),
        cancelledBy: Value(by),
        cancelledAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Payments already received stay in revenue; the patient just no
    // longer owes this invoice.
    if (inv != null) await _db.recalcPatientBalance(inv.patientId);
  }

  @override
  Stream<Invoice?> watchInvoice(int id) {
    // Watch the INVOICE row, not just its items. A payment changes
    // amountPaid and status and touches no item, so watching items alone
    // meant the drawer never refreshed after taking money — it only
    // updated when you clicked away and back.
    final q = _db.select(_db.invoices).join([
      innerJoin(
        _db.patients,
        _db.patients.id.equalsExp(_db.invoices.patientId),
      ),
    ])..where(_db.invoices.id.equals(id));

    return q.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final i = row.readTable(_db.invoices);
      final p = row.readTable(_db.patients);
      final itemRows = await (_db.select(
        _db.invoiceItems,
      )..where((t) => t.invoiceId.equals(id))).get();
      return Invoice(
        id: i.id,
        uuid: i.uuid,
        patientId: i.patientId,
        patientName: p.fullName,
        invoiceNo: i.invoiceNo,
        issuedAt: i.issuedAt,
        status: InvoiceStatus.values.byName(i.status),
        summary: i.summary,
        subtotal: i.subtotal,
        adjustment: i.adjustment,
        total: i.total,
        amountPaid: i.amountPaid,
        items: itemRows
            .map(
              (it) => InvoiceItem(
                id: it.id,
                description: it.description,
                amount: it.amount,
                qty: it.qty,
              ),
            )
            .toList(),
      );
    });
  }

  /// Records the remaining balance as a cash payment today.
  /// Status, amountPaid and the patient balance follow from that.
  @override
  Future<void> markPaid(int id) async {
    final inv = await (_db.select(
      _db.invoices,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (inv == null) return;
    final due = inv.total - inv.amountPaid;
    if (due <= 0) {
      await _db.recalcInvoicePaid(id);
      return;
    }
    await _db.insertPayment(
      invoiceId: id,
      amount: due,
      paidAt: DateTime.now(),
      note: 'Marked as paid',
    );
  }

  @override
  Future<void> seedDemoInvoicesIfEmpty() async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null) return;
    if ((await _db.select(_db.invoices).get()).isNotEmpty) return;
    final patients = await _db.select(_db.patients).get();
    if (patients.isEmpty) return;
    int idFor(String code) => patients
        .firstWhere((p) => p.code == code, orElse: () => patients.first)
        .id;

    Future<void> add(
      String no,
      String code,
      DateTime date,
      String status,
      String summary,
      List<(String, int)> items, {
      int adjustment = 0,
    }) async {
      final subtotal = items.fold<int>(0, (s, e) => s + e.$2);
      final invId = await _db
          .into(_db.invoices)
          .insert(
            InvoicesCompanion.insert(
              uuid: Uuids.v4(),
              clinicId: clinicId,
              patientId: idFor(code),
              invoiceNo: no,
              issuedAt: date,
              status: Value(status),
              summary: Value(summary),
              subtotal: Value(subtotal),
              adjustment: Value(adjustment),
              total: Value(subtotal - adjustment),
            ),
          );
      for (final it in items) {
        await _db
            .into(_db.invoiceItems)
            .insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                description: it.$1,
                amount: it.$2,
              ),
            );
      }
    }

    await add(
      'INV-0186',
      'PT-10472',
      DateTime(2026, 6, 3),
      'pending',
      'Root Canal Therapy',
      [
        ('Root Canal Therapy · #36', 18000),
        ('Digital X-Ray (2)', 2400),
        ('Consultation', 1500),
      ],
      adjustment: 5000,
    );
    await add(
      'INV-0185',
      'PT-10455',
      DateTime(2026, 6, 3),
      'paid',
      'Composite Filling',
      [('Composite Filling · #14', 4500)],
    );
    await add(
      'INV-0184',
      'PT-10468',
      DateTime(2026, 6, 3),
      'paid',
      'Scaling & Polishing',
      [('Scaling & Polishing', 3500)],
    );
    await add(
      'INV-0182',
      'PT-10440',
      DateTime(2026, 5, 21),
      'overdue',
      'Crown Fitting',
      [('Zirconia Crown · #46', 25000)],
    );
    await add(
      'INV-0180',
      'PT-10399',
      DateTime(2026, 5, 18),
      'paid',
      'Braces Adjustment',
      [('Braces Adjustment', 3000)],
    );
    await add(
      'INV-0179',
      'PT-10302',
      DateTime(2026, 5, 12),
      'pending',
      'Tooth Extraction',
      [('Tooth Extraction', 3000)],
    );
  }
}
