import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../widgets/hub_ui.dart';

/// Money — collected, spent and kept for the period, day by day, where it
/// went, how it came in, and who still owes.
class MoneySection extends StatelessWidget {
  const MoneySection({
    super.key,
    required this.data,
    required this.period,
    required this.periodPicker,
  });

  final HubData data;
  final HubPeriod period;
  final Widget periodPicker;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final m = data.money;
    final vs = period.vs;
    final margin = m.collected <= 0
        ? null
        : (m.net / m.collected * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'Money',
          subtitle: '${period.describe} · compared with ${period.vs}',
          trailing: periodPicker,
        ),
        HubGrid(
          minWidth: 230,
          maxColumns: 4,
          children: [
            HubKpi(
              label: 'Collected',
              amount: m.collected,
              sub: 'Money actually received',
              delta: hubDelta(m.collected, m.prevCollected, vs),
            ),
            HubKpi(
              label: 'Expenses',
              amount: m.expenses,
              sub: m.byCategory.isEmpty
                  ? 'No expenses recorded'
                  : 'Biggest: ${m.byCategory.first.name}',
              delta: hubDelta(m.expenses, m.prevExpenses, vs, upIsGood: false),
            ),
            HubKpi(
              label: 'Net profit',
              amount: m.net,
              valueColor: m.net < 0 ? d.alert : d.ok,
              sub: margin == null
                  ? 'Collected minus expenses'
                  : 'You keep $margin% of what comes in',
              delta: hubDelta(m.net, m.prevNet, vs),
            ),
            HubKpi(
              label: 'Billed',
              amount: m.billed,
              sub:
                  '${m.billedCount} invoice${m.billedCount == 1 ? '' : 's'} '
                  'raised in the period',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DailyCard(money: m, period: period),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _SplitCard(
            icon: Icons.pie_chart_outline_rounded,
            tone: d.warn,
            title: 'Where the money went',
            subtitle: 'Expenses by category',
            rows: m.byCategory,
            color: d.warn,
            empty: 'No expenses in this period.',
            link: const HubGoLink('Expenses', HubGo.expenses),
          ),
          right: _SplitCard(
            icon: Icons.account_balance_outlined,
            tone: d.ice,
            title: 'How patients paid',
            subtitle: 'Collected by payment method',
            rows: m.byMethod,
            color: d.ice,
            empty: 'No payments in this period.',
          ),
        ),
        const SizedBox(height: 18),
        _OwedCard(money: m),
      ],
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.money, required this.period});
  final HubMoney money;
  final HubPeriod period;

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _name(DateTime t, {bool long = false}) => switch (money.unit) {
    HubBarUnit.hour => hubHour(t.hour * 60),
    HubBarUnit.day =>
      long ? '${_wd[t.weekday - 1]} ${hubShortDate(t)}' : '${t.day}',
    HubBarUnit.week => long ? 'Week of ${hubShortDate(t)}' : hubShortDate(t),
    HubBarUnit.month =>
      long ? '${hubMonthName(t)} ${t.year}' : hubMonthName(t).substring(0, 3),
  };

  String get _unitWord => switch (money.unit) {
    HubBarUnit.hour => 'hour',
    HubBarUnit.day => 'day',
    HubBarUnit.week => 'week',
    HubBarUnit.month => 'month',
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final bars = money.bars;
    final past = bars.where((b) => !b.future).toList();
    final top = bars.fold<int>(0, (m, b) => math.max(m, b.amount));
    // index of the best bar so far (records have no identity to compare)
    var bestAt = -1;
    for (var i = 0; i < bars.length; i++) {
      if (bars[i].future || bars[i].amount == 0) continue;
      if (bestAt < 0 || bars[i].amount > bars[bestAt].amount) bestAt = i;
    }
    final best = bestAt < 0 ? null : bars[bestAt];
    final avg = past.isEmpty ? 0 : (money.collected / past.length).round();
    final quiet = past.where((b) => b.amount == 0).length;
    final n = bars.length;
    final labelEvery = n <= 12 ? 1 : (n <= 31 ? 5 : (n / 8).ceil());
    final now = DateTime.now();

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.display,
              color: d.text1,
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: d.text3, fontSize: 9.2.sp),
          ),
        ],
      ),
    );

    return HubCard(
      icon: Icons.bar_chart_rounded,
      tone: d.teal,
      title: 'Collected each $_unitWord',
      subtitle: '${period.describe} · hover a bar for the amount',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: top == 0
                ? const HubEmpty(
                    'Nothing collected in this period yet.',
                    icon: Icons.bar_chart_rounded,
                  )
                : SizedBox(
                    height: 190,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _Bar(
                              label: _name(bars[i].start),
                              amount: bars[i].amount,
                              fraction: bars[i].amount / top,
                              future: bars[i].future,
                              current:
                                  !bars[i].future &&
                                  (i == n - 1 || bars[i + 1].future) &&
                                  period.end.isAfter(now),
                              best: i == bestAt,
                              tooltip:
                                  '${_name(bars[i].start, long: true)} · '
                                  '${hubRs(bars[i].amount, hidden: hidden)}',
                              showLabel:
                                  i == 0 || i == n - 1 || i % labelEvery == 0,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Divider(height: 1, color: d.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                stat(hubRs(avg, hidden: hidden), 'Average per $_unitWord'),
                stat(
                  best == null || best.amount == 0
                      ? '—'
                      : hubRs(best.amount, hidden: hidden),
                  best == null || best.amount == 0
                      ? 'Best $_unitWord'
                      : 'Best · ${_name(best.start, long: true)}',
                ),
                stat(
                  '$quiet',
                  quiet == 1
                      ? '${_unitWord[0].toUpperCase()}${_unitWord.substring(1)} with nothing in'
                      : '${_unitWord[0].toUpperCase()}${_unitWord.substring(1)}s with nothing in',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.future,
    required this.current,
    required this.best,
    required this.tooltip,
    required this.showLabel,
  });

  final String label;
  final int amount;
  final double fraction;
  final bool future, current, best, showLabel;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final color = future
        ? d.line
        : current
        ? d.ice
        : best
        ? d.tealDeep
        : d.teal;
    return Tooltip(
      message: future ? '$label · still to come' : tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: FractionallySizedBox(
                heightFactor: future
                    ? 0.04
                    : math.max(amount == 0 ? 0.02 : 0.05, fraction),
                child: Container(
                  decoration: BoxDecoration(
                    color: amount == 0 && !future ? d.line : color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: showLabel
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: current ? d.ice : d.text4,
                          fontSize: 9.sp,
                          fontWeight: current
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.color,
    required this.empty,
    this.link,
  });

  final IconData icon;
  final Color tone, color;
  final String title, subtitle, empty;
  final List<({String name, int total})> rows;
  final Widget? link;

  @override
  Widget build(BuildContext context) {
    // Six biggest, the rest folded into "Everything else".
    final shown = rows.take(6).toList();
    final rest = rows.skip(6).fold<int>(0, (s, r) => s + r.total);
    if (rest > 0) shown.add((name: 'Everything else', total: rest));
    final total = rows.fold<int>(0, (s, r) => s + r.total);

    return HubCard(
      icon: icon,
      tone: tone,
      title: title,
      subtitle: subtitle,
      trailing: link,
      child: shown.isEmpty
          ? HubEmpty(empty)
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(
                children: [
                  for (final r in shown)
                    HubShareRow(
                      label: r.name,
                      amount: r.total,
                      fraction: total == 0 ? 0 : r.total / total,
                      color: color,
                      note: total == 0
                          ? null
                          : '${(r.total / total * 100).round()}%',
                    ),
                ],
              ),
            ),
    );
  }
}

class _OwedCard extends StatelessWidget {
  const _OwedCard({required this.money});
  final HubMoney money;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final total = money.owedBuckets.fold<int>(0, (s, v) => s + v);
    const labels = ['0–30 days', '31–60 days', '61–90 days', 'Over 90 days'];
    final tones = [d.teal, d.warn, const Color(0xFFF08A4B), d.alert];

    return HubCard(
      icon: Icons.account_balance_wallet_outlined,
      tone: d.warn,
      title: 'Still owed to you',
      subtitle: 'Every unpaid invoice, by how long it has been waiting',
      trailing: const HubGoLink('Billing', HubGo.billing),
      child: total == 0
          ? const HubEmpty(
              'Nobody owes the clinic anything.',
              icon: Icons.verified_outlined,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HubSegBar([
                    for (var i = 0; i < 4; i++)
                      (money.owedBuckets[i].toDouble(), tones[i]),
                  ], height: 10),
                  const SizedBox(height: 14),
                  HubGrid(
                    minWidth: 170,
                    maxColumns: 4,
                    gap: 12,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: d.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(color: tones[i], width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labels[i],
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 9.2.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              HubAmount(
                                money.owedBuckets[i],
                                style: TextStyle(
                                  fontFamily: AppFonts.display,
                                  color: d.text1,
                                  fontSize: 12.5.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${money.owedBucketCounts[i]} invoice'
                                '${money.owedBucketCounts[i] == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'WHO OWES THE MOST',
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final o in money.topOwing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.patient,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: d.text1,
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${o.code} · ${o.invoices} invoice'
                                  '${o.invoices == 1 ? '' : 's'} · oldest '
                                  '${o.oldestDays} day${o.oldestDays == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    color: d.text3,
                                    fontSize: 9.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          HubPill(
                            o.oldestDays > 90
                                ? 'Over 90 days'
                                : o.oldestDays > 60
                                ? 'Over 60 days'
                                : o.oldestDays > 30
                                ? 'Over 30 days'
                                : 'Recent',
                            o.oldestDays > 60
                                ? d.alert
                                : o.oldestDays > 30
                                ? d.warn
                                : d.teal,
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 130,
                            child: HubAmount(
                              o.amount,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 10.4.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
