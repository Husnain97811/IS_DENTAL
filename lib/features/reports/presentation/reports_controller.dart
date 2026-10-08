import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import '../../../core/db/app_database.dart';

class ReportsSummary {
  ReportsSummary({
    required this.totalRevenue,
    required this.patientCount,
    required this.procedureCount,
    required this.monthly,
    required this.monthLabels,
    required this.mix,
    required this.dentists,
    required this.transactions,
    required this.totalExpenses,
    required this.monthlyExpenses,
    required this.expenseMix,
    required this.outstanding,
  });

  /// CASH COLLECTED in the period (sum of invoice_payments by payment date),
  /// not invoiced value. Net profit is only meaningful on a cash basis
  /// because expenses are cash the day they are paid.
  final int totalRevenue;
  final int patientCount, procedureCount;
  final List<double> monthly; // collected, thousands
  final List<String> monthLabels;
  final List<({String label, double value})> mix;
  final List<({String name, int value})> dentists;
  final List<
    ({
      String invoiceNo,
      DateTime date,
      String patient,
      int amount,
      String status,
    })
  >
  transactions;

  final int totalExpenses;
  final List<double> monthlyExpenses; // thousands
  final List<({String label, double value})> expenseMix;

  /// Still owed across live, non-cancelled invoices.
  final int outstanding;

  int get netProfit => totalRevenue - totalExpenses;
  double get margin => totalRevenue == 0 ? 0 : netProfit / totalRevenue;
}

String _classify(String s) {
  final l = s.toLowerCase();
  if (l.contains('root canal') || l.contains('endo')) return 'Endodontics';
  if (l.contains('crown') ||
      l.contains('fill') ||
      l.contains('composite') ||
      l.contains('scaling'))
    return 'Restorative';
  if (l.contains('brace') || l.contains('ortho')) return 'Orthodontics';
  if (l.contains('extraction') ||
      l.contains('implant') ||
      l.contains('surgery') ||
      l.contains('wisdom'))
    return 'Surgery';
  return 'Other';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Shared builder. [from] inclusive, [to] exclusive.
Future<ReportsSummary> _build(
  Ref ref, {
  required DateTime from,
  required DateTime to,
}) async {
  final db = ref.watch(appDatabaseProvider);
  final branchId = ref.watch(activeBranchProvider);

  Expression<bool> branch(GeneratedColumn<String> col) => branchId == null
      ? const Constant(true)
      : col.equals(branchId) as Expression<bool>;

  final invoices =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  final patients =
      await (db.select(db.patients)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  final allAppts =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  // Money in: payments, by the date the money arrived.
  final payments =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(from) &
                t.paidAt.isSmallerThanValue(to) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  // Money out.
  final expenses =
      await (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(from) &
                t.paidAt.isSmallerThanValue(to) &
                (branchId == null
                    ? const Constant(true)
                    : t.branchId.equals(branchId)),
          ))
          .get();

  final cats = await db.lookups('expense_category');
  final catNames = {for (final c in cats) c.uuid: c.name};

  final appts = allAppts
      .where((a) => !a.startsAt.isBefore(from) && a.startsAt.isBefore(to))
      .toList();

  // ── monthly buckets across the window ──
  final n = ((to.year - from.year) * 12 + (to.month - from.month)).clamp(
    1,
    120,
  );
  final monthly = List<double>.filled(n, 0);
  final monthlyExp = List<double>.filled(n, 0);
  final labels = <String>[];
  for (var i = 0; i < n; i++) {
    final m = DateTime(from.year, from.month + i);
    labels.add(_months[m.month - 1]);
  }
  int bucket(DateTime dt) =>
      (dt.year - from.year) * 12 + (dt.month - from.month);

  for (final p in payments) {
    final i = bucket(p.paidAt);
    if (i >= 0 && i < n) monthly[i] += p.amount / 1000;
  }
  for (final e in expenses) {
    final i = bucket(e.paidAt);
    if (i >= 0 && i < n) monthlyExp[i] += e.amount / 1000;
  }

  // ── procedure mix: invoices issued in the window ──
  final windowInvoices = invoices
      .where((i) => !i.issuedAt.isBefore(from) && i.issuedAt.isBefore(to))
      .toList();
  final mixMap = <String, double>{};
  for (final i in windowInvoices) {
    mixMap.update(
      _classify(i.summary),
      (v) => v + i.total,
      ifAbsent: () => i.total.toDouble(),
    );
  }
  final mix = mixMap.entries.map((e) => (label: e.key, value: e.value)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // ── expense mix ──
  final expMap = <String, double>{};
  for (final e in expenses) {
    expMap.update(
      catNames[e.categoryUuid] ?? 'Uncategorised',
      (v) => v + e.amount,
      ifAbsent: () => e.amount.toDouble(),
    );
  }
  final expenseMix =
      expMap.entries.map((e) => (label: e.key, value: e.value)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final dMap = <String, int>{};
  for (final a in appts) {
    dMap.update(a.dentist, (v) => v + 1, ifAbsent: () => 1);
  }
  final dentists =
      dMap.entries.map((e) => (name: e.key, value: e.value)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final nameById = {for (final p in patients) p.id: p.fullName};
  final transactions =
      (windowInvoices..sort((a, b) => b.issuedAt.compareTo(a.issuedAt)))
          .map(
            (i) => (
              invoiceNo: i.invoiceNo,
              date: i.issuedAt,
              patient: nameById[i.patientId] ?? '—',
              amount: i.total,
              status: i.amountPaid > 0 && i.amountPaid < i.total
                  ? 'partial'
                  : i.status,
            ),
          )
          .toList();

  var outstanding = 0;
  for (final i in invoices) {
    final due = i.total - i.amountPaid;
    if (due > 0) outstanding += due;
  }

  return ReportsSummary(
    totalRevenue: payments.fold<int>(0, (s, p) => s + p.amount),
    patientCount: patients.length,
    procedureCount: appts.length,
    monthly: monthly,
    monthLabels: labels,
    mix: mix,
    dentists: dentists,
    transactions: transactions,
    totalExpenses: expenses.fold<int>(0, (s, e) => s + e.amount),
    monthlyExpenses: monthlyExp,
    expenseMix: expenseMix,
    outstanding: outstanding,
  );
}

final reportsSummaryProvider = FutureProvider.autoDispose<ReportsSummary>((
  ref,
) {
  final now = DateTime.now();
  return _build(
    ref,
    from: DateTime(now.year, now.month - 11),
    to: DateTime(now.year, now.month + 1),
  );
});

final reportsSummaryRangeProvider = FutureProvider.autoDispose
    .family<ReportsSummary, ({DateTime from, DateTime to})>(
      (ref, range) => _build(
        ref,
        from: DateTime(range.from.year, range.from.month, range.from.day),
        to: DateTime(
          range.to.year,
          range.to.month,
          range.to.day,
        ).add(const Duration(days: 1)),
      ),
    );
