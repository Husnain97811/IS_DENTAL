import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../branches/presentation/branch_controller.dart';

/// Income, expenses and profit over the same window the Reports screen uses.
///
/// Income is CASH COLLECTED (sum of invoice_payments by payment date), not
/// invoiced value — the only basis on which "net profit" means anything
/// next to cash expenses. Cancelled invoices are excluded automatically:
/// a cancelled invoice with no payments contributes nothing, and money
/// genuinely received stays counted.
class ProfitSummary {
  const ProfitSummary({
    required this.collected,
    required this.expenses,
    required this.monthlyCollected,
    required this.monthlyExpenses,
    required this.monthLabels,
    required this.expenseMix,
  });

  final int collected;
  final int expenses;
  final List<int> monthlyCollected; // thousands, oldest first
  final List<int> monthlyExpenses; // thousands, oldest first
  final List<String> monthLabels;
  final List<({String name, int total})> expenseMix;

  int get netProfit => collected - expenses;
  double get margin => collected == 0 ? 0 : netProfit / collected;
}

const _mon = [
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

/// Last 12 months, to pair with reportsSummaryProvider.
final profitSummaryProvider = FutureProvider.autoDispose<ProfitSummary>((
  ref,
) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 11);
  final end = DateTime(now.year, now.month + 1);
  return _build(ref, start, end, months: 12);
});

/// Custom range, to pair with reportsSummaryRangeProvider.
final profitSummaryRangeProvider = FutureProvider.autoDispose
    .family<ProfitSummary, ({DateTime start, DateTime end})>(
      (ref, r) => _build(ref, r.start, r.end),
    );

Future<ProfitSummary> _build(
  Ref ref,
  DateTime start,
  DateTime end, {
  int? months,
}) async {
  final db = ref.watch(appDatabaseProvider);
  final branchId = ref.watch(activeBranchProvider);

  final payments = await db
      .watchPaymentsBetween(start, end, branchId: branchId)
      .first;
  final expenseRows = await db
      .watchExpensesBetween(start, end, branchId: branchId)
      .first;
  final cats = await db.lookups('expense_category');
  final names = {for (final c in cats) c.uuid: c.name};

  final n =
      months ??
      ((end.year - start.year) * 12 + (end.month - start.month)).clamp(1, 60);
  final inc = List<int>.filled(n, 0);
  final exp = List<int>.filled(n, 0);
  final labels = <String>[];
  for (var i = 0; i < n; i++) {
    final m = DateTime(start.year, start.month + i);
    labels.add(_mon[m.month - 1]);
  }

  int bucket(DateTime dt) =>
      (dt.year - start.year) * 12 + (dt.month - start.month);

  for (final p in payments) {
    final i = bucket(p.paidAt);
    if (i >= 0 && i < n) inc[i] += p.amount;
  }
  for (final e in expenseRows) {
    final i = bucket(e.paidAt);
    if (i >= 0 && i < n) exp[i] += e.amount;
  }

  final mix = <String, int>{};
  for (final e in expenseRows) {
    mix[e.categoryUuid] = (mix[e.categoryUuid] ?? 0) + e.amount;
  }
  final mixList =
      mix.entries
          .map((e) => (name: names[e.key] ?? 'Uncategorised', total: e.value))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));

  return ProfitSummary(
    collected: payments.fold<int>(0, (s, p) => s + p.amount),
    expenses: expenseRows.fold<int>(0, (s, e) => s + e.amount),
    monthlyCollected: inc.map((v) => (v / 1000).round()).toList(),
    monthlyExpenses: exp.map((v) => (v / 1000).round()).toList(),
    monthLabels: labels,
    expenseMix: mixList,
  );
}
