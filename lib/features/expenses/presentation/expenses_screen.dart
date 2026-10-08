import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../core/constants/views.dart';
import '../data/expense_repository.dart';

String _m(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Rs 1,250,000 reads badly in a KPI card — Rs 12.5L does not.
String _compact(int v) {
  final a = v.abs();
  if (a >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
  if (a >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
  return _m(v);
}

const _monShort = [
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

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;

    // Guard first — the header must not render for someone without access.
    if (!ref.watch(canProvider(Perm.viewExpenses))) {
      return _locked(d);
    }

    final canManage = ref.watch(canProvider(Perm.manageExpenses));
    final canFin = ref.watch(canProvider(Perm.viewFinancials));
    final period = ref.watch(expensePeriodProvider);
    final rowsAsync = ref.watch(expensesInPeriodProvider);
    final collected = ref.watch(collectedInPeriodProvider).value ?? 0;
    final filter = ref.watch(expenseCategoryFilterProvider);
    final names = ref.watch(categoryNamesProvider);

    final all = rowsAsync.value ?? const <ExpenseRow>[];
    final q = ref.watch(expenseSearchProvider).trim().toLowerCase();
    final rows = all.where((e) {
      if (filter != null && e.categoryUuid != filter) return false;
      if (q.isEmpty) return true;
      return [
        e.description,
        e.vendor ?? '',
        e.reference ?? '',
        e.method,
        e.methodDetail ?? '',
        names[e.categoryUuid] ?? '',
        '${e.amount}',
      ].any((f) => f.toLowerCase().contains(q));
    }).toList();

    // KPIs always describe the whole period — a search narrows the table,
    // never the totals, so profit can't silently change while you type.
    final total = all.fold<int>(0, (s, e) => s + e.amount);
    final shown = rows.fold<int>(0, (s, e) => s + e.amount);
    final profit = collected - total;
    final filtering = filter != null || q.isNotEmpty;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1080;
        final narrow = c.maxWidth < 760;
        final pad = narrow ? 16.0 : 26.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 22, pad, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _periodBar(context, ref, d, period, narrow),
              const SizedBox(height: 18),

              if (canFin)
                _summaryHero(d, collected, total, profit, period, narrow)
              else
                _plainTotals(d, total, all.length, period),
              const SizedBox(height: 18),

              // Side by side when there's room; stacked when there isn't.
              if (wide && period.mode == PeriodMode.year)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _yearPanel(ref, d, canFin)),
                      const SizedBox(width: 18),
                      Expanded(flex: 2, child: _categoryPanel(ref, d, filter)),
                    ],
                  ),
                )
              else ...[
                if (period.mode == PeriodMode.year) ...[
                  _yearPanel(ref, d, canFin),
                  const SizedBox(height: 18),
                ],
                _categoryPanel(ref, d, filter),
              ],
              const SizedBox(height: 18),

              DentPanel(
                title: filter == null
                    ? 'Expenses'
                    : names[filter] ?? 'Expenses',
                subtitle: filtering
                    ? '${rows.length} of ${all.length} shown · Rs ${_m(shown)}'
                    : '${all.length} entries · Rs ${_m(total)}',
                trailing: filtering
                    ? PanelLink(
                        'Clear filter',
                        onTap: () {
                          ref
                                  .read(expenseCategoryFilterProvider.notifier)
                                  .state =
                              null;
                          ref.read(expenseSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
                child: rowsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('$e', style: TextStyle(color: d.alert)),
                  ),
                  data: (_) => rows.isEmpty
                      ? _empty(d, period, filtering, canManage, context)
                      : Column(
                          children: [
                            if (!narrow) _header(d),
                            for (final e in rows)
                              narrow
                                  ? _card(context, ref, d, e, names, canManage)
                                  : _row(context, ref, d, e, names, canManage),
                            _footer(d, rows.length, shown),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── states ───────────────────────────────────────────────────────────────
  Widget _locked(DentColors d) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 34, color: d.text4),
          const SizedBox(height: 14),
          Text(
            'Expenses are not available for your role.',
            style: TextStyle(color: d.text3, fontSize: 11.sp),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask the clinic owner if you need access.',
            style: TextStyle(color: d.text4, fontSize: 9.5.sp),
          ),
        ],
      ),
    ),
  );

  Widget _empty(
    DentColors d,
    Period p,
    bool filtering,
    bool canManage,
    BuildContext context,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 48, 20, 52),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: d.surface2,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(
            filtering
                ? Icons.search_off_rounded
                : Icons.account_balance_wallet_outlined,
            size: 26,
            color: d.text4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          filtering ? 'No matching expenses' : 'Nothing recorded yet',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          filtering
              ? 'Try a different search or clear the category filter.'
              : 'Rent, salaries, lab fees and supplies for ${p.label} '
                    'will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: d.text4, fontSize: 9.5.sp, height: 1.5),
        ),
        if (!filtering && canManage) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => showExpenseEditor(context),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Add the first one'),
          ),
        ],
      ],
    ),
  );

  // ── period selector ──────────────────────────────────────────────────────
  // Add / Copy / Manage live in the topbar — this row is navigation only.
  Widget _periodBar(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    Period p,
    bool narrow,
  ) {
    final stepper = Container(
      height: 42,
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(d, Icons.chevron_left_rounded, 'Previous', () {
            ref.read(expensePeriodProvider.notifier).state = p.shift(-1);
          }),
          Container(width: 1, height: 20, color: d.line),
          SizedBox(
            width: narrow ? 120 : 150,
            child: Text(
              p.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: d.text1,
              ),
            ),
          ),
          Container(width: 1, height: 20, color: d.line),
          _stepBtn(
            d,
            Icons.chevron_right_rounded,
            'Next',
            p.isCurrent
                ? null
                : () => ref.read(expensePeriodProvider.notifier).state = p
                      .shift(1),
          ),
        ],
      ),
    );

    final modes = SegmentedControl(
      items: const ['Month', 'Year'],
      selected: p.mode == PeriodMode.month ? 0 : 1,
      onChanged: (i) => ref.read(expensePeriodProvider.notifier).state = p
          .withMode(i == 0 ? PeriodMode.month : PeriodMode.year),
    );

    final today = TextButton(
      onPressed: p.isCurrent
          ? null
          : () => ref.read(expensePeriodProvider.notifier).state = Period(
              p.mode,
              DateTime.now(),
            ),
      style: TextButton.styleFrom(foregroundColor: d.ice),
      child: Text(
        p.mode == PeriodMode.month ? 'This month' : 'This year',
        style: TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.w600),
      ),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [stepper, const Spacer(), today]),
          const SizedBox(height: 10),
          modes,
        ],
      );
    }
    return Row(
      children: [
        stepper,
        const SizedBox(width: 12),
        modes,
        const SizedBox(width: 4),
        today,
        const Spacer(),
      ],
    );
  }

  Widget _stepBtn(
    DentColors d,
    IconData icon,
    String tip,
    VoidCallback? onTap,
  ) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 42,
        child: Icon(icon, size: 19, color: onTap == null ? d.line : d.text2),
      ),
    ),
  );

  // ── summary ──────────────────────────────────────────────────────────────
  Widget _summaryHero(
    DentColors d,
    int collected,
    int expenses,
    int profit,
    Period p,
    bool narrow,
  ) {
    final up = profit >= 0;
    final margin = collected == 0 ? 0.0 : profit / collected;
    final spentShare = collected == 0
        ? 0.0
        : (expenses / collected).clamp(0.0, 1.0);

    final hero = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'NET PROFIT · ${p.label.toUpperCase()}',
          style: TextStyle(
            color: d.text4,
            fontSize: 7.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              up ? '' : '– ',
              style: TextStyle(
                color: d.text2,
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _m(profit.abs()),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: up ? d.text1 : d.alert,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (up ? d.ok : d.alert).withValues(alpha: .11),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 13.sp,
                color: up ? d.ok : d.alert,
              ),
              const SizedBox(width: 5),
              Text(
                '${(margin * 100).toStringAsFixed(1)}% margin',
                style: TextStyle(
                  color: up ? d.ok : d.alert,
                  fontSize: 8.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final split = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _flowRow(d, 'Collected', collected, d.teal, Icons.south_west_rounded),
        const SizedBox(height: 14),
        _flowRow(d, 'Expenses', expenses, d.warn, Icons.north_east_rounded),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: spentShare,
            minHeight: 8,
            backgroundColor: d.teal.withValues(alpha: .18),
            valueColor: AlwaysStoppedAnimation(d.warn),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          collected == 0
              ? 'Nothing collected in this period yet.'
              : '${(spentShare * 100).round()}% of what you collected '
                    'went back out.',
          style: TextStyle(color: d.text4, fontSize: 8.sp),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(narrow ? 18 : 24),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: 22),
                Divider(color: d.line, height: 1),
                const SizedBox(height: 18),
                split,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: hero),
                  const SizedBox(width: 20),
                  VerticalDivider(color: d.line, width: 1),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: split),
                ],
              ),
            ),
    );
  }

  Widget _flowRow(
    DentColors d,
    String label,
    int value,
    Color tone,
    IconData icon,
  ) => Row(
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 15, color: tone),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: d.text3,
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Text(
        'Rs ${_m(value)}',
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: d.text1,
          fontSize: 12.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  /// Someone with viewExpenses but not viewFinancials sees spending only —
  /// never collected revenue, never profit.
  Widget _plainTotals(DentColors d, int total, int count, Period p) =>
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d.warn.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: d.warn,
                size: 21,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL SPENT · ${p.label.toUpperCase()}',
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 7.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rs ${_m(total)}',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: d.text1,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$count ${count == 1 ? "entry" : "entries"}',
              style: TextStyle(color: d.text4, fontSize: 9.5.sp),
            ),
          ],
        ),
      );

  // ── year breakdown ───────────────────────────────────────────────────────
  Widget _yearPanel(WidgetRef ref, DentColors d, bool canFin) {
    final exp = ref.watch(monthlyExpensesProvider).value ?? List.filled(12, 0);
    final inc = ref.watch(monthlyCollectedProvider).value ?? List.filled(12, 0);
    final peak = [
      ...exp,
      if (canFin) ...inc,
    ].fold<int>(1, (a, b) => b > a ? b : a);
    final thisMonth = DateTime.now().month;
    final year = ref.watch(expensePeriodProvider).anchor.year;
    final isThisYear = DateTime.now().year == year;

    return DentPanel(
      title: 'Month by month',
      subtitle: canFin ? 'Collected vs expenses' : 'Expenses per month',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          children: [
            if (canFin) ...[
              Row(
                children: [
                  _legendDot(d, d.teal, 'Collected'),
                  const SizedBox(width: 16),
                  _legendDot(d, d.warn, 'Expenses'),
                ],
              ),
              const SizedBox(height: 14),
            ],
            for (var i = 0; i < 12; i++)
              Opacity(
                // Months that haven't happened yet shouldn't look like
                // months where the clinic simply spent nothing.
                opacity: isThisYear && i + 1 > thisMonth ? .35 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          _monShort[i],
                          style: AppTypography.mono(
                            size: 8.5.sp,
                            color: i + 1 == thisMonth && isThisYear
                                ? d.ice
                                : d.text3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            if (canFin) ...[
                              _bar(d, inc[i] / peak, d.teal),
                              const SizedBox(height: 3),
                            ],
                            _bar(d, exp[i] / peak, d.warn),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 78,
                        child: Text(
                          'Rs ${_compact(exp[i])}',
                          textAlign: TextAlign.right,
                          style: AppTypography.mono(
                            size: 8.5.sp,
                            color: d.text2,
                          ),
                        ),
                      ),
                      if (canFin) ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 86,
                          child: Text(
                            '${inc[i] - exp[i] < 0 ? "– " : ""}Rs '
                            '${_compact((inc[i] - exp[i]).abs())}',
                            textAlign: TextAlign.right,
                            style: AppTypography.mono(
                              size: 8.5.sp,
                              color: inc[i] - exp[i] < 0 ? d.alert : d.teal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(DentColors d, Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(color: d.text4, fontSize: 8.sp),
      ),
    ],
  );

  Widget _bar(DentColors d, double frac, Color color) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: LinearProgressIndicator(
      value: frac.isNaN ? 0 : frac.clamp(0.0, 1.0),
      minHeight: 6,
      backgroundColor: d.surface2,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );

  // ── by category ──────────────────────────────────────────────────────────
  Widget _categoryPanel(WidgetRef ref, DentColors d, String? filter) {
    final rows = ref.watch(expenseByCategoryProvider);
    final cats = ref.watch(expenseCategoriesProviderAlias).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    final palette = [d.ice, d.teal, d.tealDeep, d.warn, d.text4];
    String? uuidOf(String name) =>
        cats.where((c) => c.name == name).map((c) => c.uuid).firstOrNull;

    return DentPanel(
      title: 'By category',
      subtitle: filter == null
          ? 'Click a row to filter'
          : 'Click the highlighted row to clear',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Builder(
                builder: (_) {
                  final r = rows[i];
                  final u = uuidOf(r.name);
                  final on = u != null && u == filter;
                  final tone = palette[i % palette.length];
                  return InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () =>
                        ref.read(expenseCategoryFilterProvider.notifier).state =
                            on ? null : u,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: on ? d.surface2 : null,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: on ? d.ice : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: tone,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: TextStyle(
                                    color: on ? d.ice : d.text1,
                                    fontSize: 9.5.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Rs ${_m(r.total)}',
                                style: AppTypography.mono(
                                  size: 9.sp,
                                  color: d.text1,
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${(r.share * 100).round()}%',
                                  textAlign: TextAlign.right,
                                  style: AppTypography.mono(
                                    size: 8.sp,
                                    color: d.text4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          _bar(d, r.share, tone),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── table ────────────────────────────────────────────────────────────────
  Widget _header(DentColors d) {
    TextStyle h() => TextStyle(
      color: d.text4,
      fontSize: 7.5.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: d.surface2,
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('DATE', style: h())),
          const SizedBox(width: 14),
          Expanded(flex: 3, child: Text('CATEGORY', style: h())),
          Expanded(flex: 4, child: Text('DETAILS', style: h())),
          Expanded(flex: 3, child: Text('METHOD', style: h())),
          SizedBox(
            width: 110,
            child: Text('AMOUNT', style: h(), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    ExpenseRow e,
    Map<String, String> names,
    bool canManage,
  ) {
    final isOwner = ref.watch(authControllerProvider)?.role == AppRole.owner;
    return InkWell(
      onTap: canManage ? () => showExpenseEditor(context, existing: e) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            SizedBox(width: 52, child: _dateChip(d, e.paidAt)),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: Text(
                names[e.categoryUuid] ?? 'Uncategorised',
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.description.isEmpty ? '—' : e.description,
                    style: TextStyle(color: d.text2, fontSize: 9.5.sp),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((e.vendor ?? '').isNotEmpty ||
                      (e.reference ?? '').isNotEmpty)
                    Text(
                      [
                        if ((e.vendor ?? '').isNotEmpty) e.vendor!,
                        if ((e.reference ?? '').isNotEmpty)
                          'TID ${e.reference}',
                      ].join(' · '),
                      style: TextStyle(color: d.text4, fontSize: 7.5.sp),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(flex: 3, child: _methodPill(d, e)),
            SizedBox(
              width: 110,
              child: Text(
                'Rs ${_m(e.amount)}',
                textAlign: TextAlign.right,
                style: AppTypography.mono(
                  size: 10.sp,
                  color: d.text1,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Owner only — staff shouldn't be auditing each other.
                  if (isOwner)
                    IconButton(
                      tooltip: 'Who added this',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: d.text4,
                      ),
                      onPressed: () => showExpenseAudit(
                        context,
                        e,
                        names[e.categoryUuid] ?? 'Uncategorised',
                      ),
                    ),
                  if (canManage)
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: d.text4,
                      ),
                      onPressed: () => _delete(context, ref, e, names),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Narrow layout: the same row as a stacked card, so nothing truncates.
  Widget _card(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    ExpenseRow e,
    Map<String, String> names,
    bool canManage,
  ) {
    final isOwner = ref.watch(authControllerProvider)?.role == AppRole.owner;
    return InkWell(
      onTap: canManage ? () => showExpenseEditor(context, existing: e) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateChip(d, e.paidAt),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          names[e.categoryUuid] ?? 'Uncategorised',
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 10.5.sp,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Rs ${_m(e.amount)}',
                        style: AppTypography.mono(
                          size: 10.5.sp,
                          color: d.text1,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (e.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      e.description,
                      style: TextStyle(color: d.text2, fontSize: 9.5.sp),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _methodPill(d, e),
                      if ((e.vendor ?? '').isNotEmpty)
                        Text(
                          e.vendor!,
                          style: TextStyle(color: d.text4, fontSize: 8.sp),
                        ),
                      if ((e.reference ?? '').isNotEmpty)
                        Text(
                          'TID ${e.reference}',
                          style: AppTypography.mono(
                            size: 7.5.sp,
                            color: d.text4,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (isOwner)
                  IconButton(
                    tooltip: 'Who added this',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: d.text4,
                    ),
                    onPressed: () => showExpenseAudit(
                      context,
                      e,
                      names[e.categoryUuid] ?? 'Uncategorised',
                    ),
                  ),
                if (canManage)
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: d.text4,
                    ),
                    onPressed: () => _delete(context, ref, e, names),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(DentColors d, DateTime dt) => Container(
    width: 46,
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      children: [
        Text(
          '${dt.day}',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _monShort[dt.month - 1].toUpperCase(),
          style: TextStyle(
            color: d.text4,
            fontSize: 6.5.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
      ],
    ),
  );

  Widget _methodPill(DentColors d, ExpenseRow e) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: d.line),
      ),
      child: Text(
        [
          e.method,
          if ((e.methodDetail ?? '').isNotEmpty) e.methodDetail!,
        ].join(' · '),
        style: TextStyle(
          color: d.text3,
          fontSize: 8.sp,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _footer(DentColors d, int count, int sum) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: d.surface2,
      border: Border(top: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Text(
          '$count ${count == 1 ? "entry" : "entries"}',
          style: TextStyle(color: d.text4, fontSize: 9.sp),
        ),
        const Spacer(),
        Text(
          'Total  ',
          style: TextStyle(
            color: d.text3,
            fontSize: 9.5.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'Rs ${_m(sum)}',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: d.text1,
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ExpenseRow e,
    Map<String, String> names,
  ) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Delete this expense?',
      message:
          'Rs ${_m(e.amount)} · ${names[e.categoryUuid] ?? "Uncategorised"} · '
          '${e.paidAt.day}/${e.paidAt.month}/${e.paidAt.year}. '
          'It is kept for your records with who deleted it, and removed '
          'from all totals.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep it',
    );
    if (ok != true) return;
    final who = ref.read(authControllerProvider)?.username ?? '';
    await ref.read(expenseRepositoryProvider).softDelete(e.id, by: who);
    syncInBackground(ref);
  }
}
