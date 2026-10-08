import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../../branches/presentation/branch_controller.dart';

/// Month view or year view, with the anchor date the user is browsing.
enum PeriodMode { month, year }

class Period {
  const Period(this.mode, this.anchor);
  final PeriodMode mode;
  final DateTime anchor;

  DateTime get start => mode == PeriodMode.month
      ? DateTime(anchor.year, anchor.month)
      : DateTime(anchor.year);

  DateTime get end => mode == PeriodMode.month
      ? DateTime(anchor.year, anchor.month + 1)
      : DateTime(anchor.year + 1);

  Period shift(int by) => Period(
    mode,
    mode == PeriodMode.month
        ? DateTime(anchor.year, anchor.month + by)
        : DateTime(anchor.year + by),
  );

  Period withMode(PeriodMode m) => Period(m, anchor);

  String get label {
    const mon = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return mode == PeriodMode.month
        ? '${mon[anchor.month - 1]} ${anchor.year}'
        : '${anchor.year}';
  }

  /// True when the period contains today — used to disable "next".
  bool get isCurrent {
    final n = DateTime.now();
    return mode == PeriodMode.month
        ? (n.year == anchor.year && n.month == anchor.month)
        : n.year == anchor.year;
  }
}

final expensePeriodProvider = StateProvider<Period>(
  (_) => Period(PeriodMode.month, DateTime.now()),
);

/// null = all categories.
final expenseCategoryFilterProvider = StateProvider<String?>((_) => null);

final expensesInPeriodProvider = StreamProvider.autoDispose<List<ExpenseRow>>((
  ref,
) {
  final p = ref.watch(expensePeriodProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchExpensesBetween(
        p.start,
        p.end,
        branchId: ref.watch(activeBranchProvider),
      );
});

/// Money actually collected in the same period — the income side of profit.
final collectedInPeriodProvider = StreamProvider.autoDispose<int>((ref) {
  final p = ref.watch(expensePeriodProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchCollectedBetween(
        p.start,
        p.end,
        branchId: ref.watch(activeBranchProvider),
      );
});

/// Category uuid → display name, for rows and the breakdown.
final categoryNamesProvider = Provider<Map<String, String>>((ref) {
  final rows = ref.watch(expenseCategoriesProviderAlias).value ?? const [];
  return {for (final r in rows) r.uuid: r.name};
});

/// Alias kept separate so this file doesn't import the lookup providers
/// into every consumer.
final expenseCategoriesProviderAlias = StreamProvider<List<LookupRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchLookups('expense_category'),
);

/// Totals per category for the current period, largest first.
final expenseByCategoryProvider =
    Provider<List<({String name, int total, double share})>>((ref) {
      final rows = ref.watch(expensesInPeriodProvider).value ?? const [];
      final names = ref.watch(categoryNamesProvider);
      final sums = <String, int>{};
      for (final e in rows) {
        sums[e.categoryUuid] = (sums[e.categoryUuid] ?? 0) + e.amount;
      }
      final total = sums.values.fold<int>(0, (s, v) => s + v);
      final out =
          sums.entries
              .map(
                (e) => (
                  name: names[e.key] ?? 'Uncategorised',
                  total: e.value,
                  share: total == 0 ? 0.0 : e.value / total,
                ),
              )
              .toList()
            ..sort((a, b) => b.total.compareTo(a.total));
      return out;
    });

/// Month-by-month totals for the year view: 12 entries, Jan to Dec.
final monthlyExpensesProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final p = ref.watch(expensePeriodProvider);
  final year = p.anchor.year;
  return ref
      .watch(appDatabaseProvider)
      .watchExpensesBetween(
        DateTime(year),
        DateTime(year + 1),
        branchId: ref.watch(activeBranchProvider),
      )
      .map((rows) {
        final out = List<int>.filled(12, 0);
        for (final e in rows) {
          out[e.paidAt.month - 1] += e.amount;
        }
        return out;
      });
});

final monthlyCollectedProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final p = ref.watch(expensePeriodProvider);
  final year = p.anchor.year;
  return ref
      .watch(appDatabaseProvider)
      .watchPaymentsBetween(
        DateTime(year),
        DateTime(year + 1),
        branchId: ref.watch(activeBranchProvider),
      )
      .map((rows) {
        final out = List<int>.filled(12, 0);
        for (final r in rows) {
          out[r.paidAt.month - 1] += r.amount;
        }
        return out;
      });
});

/// Every row of a kind, hidden ones included — the manager needs both.
final allLookupsProvider = StreamProvider.autoDispose
    .family<List<LookupRow>, String>(
      (ref, kind) => ref.watch(appDatabaseProvider).watchAllLookups(kind),
    );

/// categoryUuid → how many live expenses use it, so hiding a category
/// can say what it affects.
final categoryUsageProvider = StreamProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(appDatabaseProvider).watchCategoryUsage(),
);

/// Typed into the topbar search while the Expenses screen is open.
final expenseSearchProvider = StateProvider<String>((_) => '');
