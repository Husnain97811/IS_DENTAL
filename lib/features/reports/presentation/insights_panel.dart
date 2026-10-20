import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/router/app_routes.dart';
import 'package:sizer/sizer.dart';

import 'insights_controller.dart';

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

String _m(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (x) => '${x[1]},',
);

/// Rs 1,250,000 → 12.50L, for tight spots.
String _compact(int v) {
  final a = v.abs();
  if (a >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
  if (a >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
  return _m(v);
}

String _pct(double v) => '${(v * 100).round()}%';

String _ago(int days) {
  if (days < 45) return '$days days';
  final months = (days / 30.4).round();
  return months < 12
      ? '$months months'
      : '${(days / 365).toStringAsFixed(1)} years';
}

// ═════════════════════════════════════════════════════════════════════════════
//  1. Small "at a glance" card on the Reports overview
// ═════════════════════════════════════════════════════════════════════════════

/// Four headline numbers and a way into the Insights tab. Keeps the
/// overview clean — the detail lives one click away.
class InsightsTeaser extends ConsumerWidget {
  const InsightsTeaser({super.key, required this.range, required this.onOpen});
  final InsightsRange range;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final s = ref.watch(insightsProvider(range)).value;

    Widget tile(IconData icon, Color tone, String label, String value) =>
        Container(
          constraints: const BoxConstraints(minWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: d.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: d.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: tone),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 10.6.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: d.text1,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Material(
      color: d.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: d.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_graph_rounded, size: 18, color: d.ice),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Insights at a glance',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: d.text1,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Open Insights',
                    style: TextStyle(
                      color: d.ice,
                      fontSize: 10.6.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: d.ice),
                ],
              ),
              const SizedBox(height: 14),
              if (s == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    tile(
                      Icons.insights_rounded,
                      d.ice,
                      'Expected by end of ${s.forecast.year}',
                      s.forecast.locked
                          ? 'Needs 1 month'
                          : 'Rs ${_compact(s.forecast.forecast)}',
                    ),
                    tile(
                      Icons.replay_rounded,
                      d.teal,
                      'Patients who come back',
                      s.visitedPatients == 0 ? '—' : _pct(s.returnRate),
                    ),
                    tile(
                      Icons.workspace_premium_rounded,
                      d.warn,
                      'Top earning service',
                      s.topServices.isEmpty ? '—' : s.topServices.first.name,
                    ),
                    tile(
                      Icons.warning_amber_rounded,
                      s.atRisk.isEmpty ? d.ok : d.alert,
                      'At-risk patients',
                      '${s.atRisk.length}',
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  2. The Insights tab: three clean pages
// ═════════════════════════════════════════════════════════════════════════════

class InsightsView extends ConsumerStatefulWidget {
  const InsightsView({
    super.key,
    required this.range,
    required this.showExpenses,
  });

  /// Period for "top services" — the same one the Overview uses.
  final InsightsRange range;
  final bool showExpenses;

  @override
  ConsumerState<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends ConsumerState<InsightsView> {
  int _page = 0; // 0 Income · 1 Patients · 2 Retention

  static const _pages = ['Income', 'Patients', 'Retention'];
  static const _hints = [
    'What you will earn this year, and which services bring the money.',
    'How often patients come back, and who your most valuable patients are.',
    'Who is slipping away, and how well new patients stay with you.',
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(insightsProvider(widget.range));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedControl(
              items: _pages,
              selected: _page,
              onChanged: (i) => setState(() => _page = i),
            ),
            Text(
              _hints[_page],
              style: TextStyle(color: d.text3, fontSize: 10.6.sp),
            ),
          ],
        ),
        const SizedBox(height: 18),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
          data: (s) => LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 980;

              Widget pair(Widget a, Widget b) => wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: a),
                        const SizedBox(width: 18),
                        Expanded(child: b),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [a, const SizedBox(height: 18), b],
                    );

              return switch (_page) {
                0 => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ForecastPanel(
                      f: s.forecast,
                      showExpenses: widget.showExpenses,
                    ),
                    const SizedBox(height: 18),
                    _TopServicesPanel(services: s.topServices),
                  ],
                ),
                1 => pair(_ReturningPanel(s: s), _LifetimePanel(s: s)),
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AtRiskPanel(list: s.atRisk),
                    const SizedBox(height: 18),
                    _RetentionPanel(cohorts: s.cohorts),
                  ],
                ),
              };
            },
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared bits
// ═════════════════════════════════════════════════════════════════════════════

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Column(
        children: [
          Icon(icon, size: 28, color: d.text4),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: d.text4, fontSize: 10.5.sp),
          ),
        ],
      ),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value, {this.color});
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      value,
      style: TextStyle(
        fontFamily: AppFonts.display,
        color: color ?? context.dent.text1,
        fontSize: 22.sp,
        fontWeight: FontWeight.w700,
        height: 1.05,
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: d.text4,
              fontSize: 10.6.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.display,
              color: d.text1,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, {this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 8.8.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

void _openPatient(BuildContext context, int id) =>
    context.push('${AppRoutes.patients}/$id');

// ═════════════════════════════════════════════════════════════════════════════
//  Year-end forecast
// ═════════════════════════════════════════════════════════════════════════════

class _ForecastPanel extends StatelessWidget {
  const _ForecastPanel({required this.f, required this.showExpenses});
  final YearForecast f;
  final bool showExpenses;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    final badge = f.locked
        ? _Badge(
            'Needs 1 month of data',
            d.text4,
            icon: Icons.lock_outline_rounded,
          )
        : f.reliable
        ? _Badge('Reliable', d.ok, icon: Icons.verified_rounded)
        : _Badge('Early estimate', d.warn, icon: Icons.schedule_rounded);

    return DentPanel(
      title: 'Expected Income by End of ${f.year}',
      subtitle: 'Based on money actually collected · latest months count most',
      trailing: badge,
      child: f.locked
          ? const _Empty(
              Icons.insights_rounded,
              'The forecast appears after one full month of payments.\n'
              'It becomes reliable after three months.',
            )
          : LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 760;
                final summary = _summary(d);
                final chart = SizedBox(height: 200, child: _chart(d));
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summary,
                            const SizedBox(height: 20),
                            chart,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(width: 280, child: summary),
                            const SizedBox(width: 24),
                            Expanded(child: chart),
                          ],
                        ),
                );
              },
            ),
    );
  }

  Widget _summary(DentColors d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _BigNumber('Rs ${_m(f.forecast)}'),
      const SizedBox(height: 6),
      Text(
        'Likely between Rs ${_compact(f.low)} and Rs ${_compact(f.high)}',
        style: TextStyle(color: d.text3, fontSize: 9.8.sp),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MiniStat('Collected so far', 'Rs ${_compact(f.ytdCollected)}'),
          if (showExpenses && f.forecastProfit != null)
            _MiniStat('Expected profit', 'Rs ${_compact(f.forecastProfit!)}'),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        f.reliable
            ? 'Uses your last 3 months.'
            : 'Uses ${f.monthsUsed} month${f.monthsUsed == 1 ? '' : 's'} of data — '
                  'gets more accurate after 3 months.',
        style: TextStyle(color: d.text4, fontSize: 8.8.sp),
      ),
    ],
  );

  Widget _chart(DentColors d) {
    final values = [
      for (final v in f.actual)
        if (v != null) v,
      for (final v in f.projected)
        if (v != null) v,
    ];
    final maxV = (values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b))
        .clamp(1.0, double.infinity);

    List<FlSpot> spots(List<double?> xs) => [
      for (var i = 0; i < 12; i++)
        xs[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), xs[i]!),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 11,
        minY: 0,
        maxY: maxV * 1.25,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxV / 3,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: d.line, strokeWidth: 1, dashArray: [4, 4]),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => d.surface,
            tooltipBorder: BorderSide(color: d.line),
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${_mon[t.x.toInt()]} · ${t.barIndex == 0 ? 'Collected' : 'Expected'}\n'
                  'Rs ${_m((t.y * 1000).round())}',
                  TextStyle(
                    color: d.text1,
                    fontSize: 9.6.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: maxV / 3,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  v == 0 ? '0' : '${v.round()}k',
                  textAlign: TextAlign.right,
                  style: AppTypography.mono(size: 7.8.sp, color: d.text4),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i > 11 || v != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _mon[i],
                    style: AppTypography.mono(size: 7.8.sp, color: d.text4),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          // What actually came in — solid.
          LineChartBarData(
            spots: spots(f.actual),
            color: d.teal,
            barWidth: 3,
            isCurved: false,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: d.teal.withValues(alpha: .12),
            ),
          ),
          // What we expect — dashed.
          LineChartBarData(
            spots: spots(f.projected),
            color: d.ice,
            barWidth: 2.5,
            isCurved: false,
            dashArray: const [6, 5],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Returning patients
// ═════════════════════════════════════════════════════════════════════════════

class _ReturningPanel extends StatelessWidget {
  const _ReturningPanel({required this.s});
  final Insights s;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    if (s.visitedPatients == 0) {
      return DentPanel(
        title: 'Returning Patients',
        subtitle: 'All time',
        child: _Empty(Icons.people_outline_rounded, 'No visits recorded yet'),
      );
    }
    final maxBucket = s.visitBuckets
        .map((b) => b.count)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return DentPanel(
      title: 'Returning Patients',
      subtitle: 'All time · sessions within 2 weeks count as one visit',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _BigNumber(_pct(s.returnRate), color: d.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${s.returningPatients} of ${s.visitedPatients} patients came back',
                      style: TextStyle(color: d.text3, fontSize: 10.sp),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniStat(
                  'Typical time between visits',
                  s.typicalGapDays == null ? '—' : _ago(s.typicalGapDays!),
                ),
                _MiniStat(
                  'Visits per returning patient',
                  s.returningPatients == 0
                      ? '—'
                      : s.avgVisitsReturning.toStringAsFixed(1),
                ),
                _MiniStat(
                  'Back within 6 months',
                  s.sixMonthReturn == null
                      ? 'Needs 6 months'
                      : _pct(s.sixMonthReturn!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'HOW MANY TIMES THEY VISITED',
              style: TextStyle(
                color: d.text4,
                fontSize: 10.4.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 4),
            // Each group is clickable: shows exactly who is in it.
            for (final b in s.visitBuckets)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: b.count == 0 ? null : () => _showBucket(context, b),
                child: Row(
                  children: [
                    Expanded(
                      child: StatBarRow(
                        label: b.label,
                        fraction: maxBucket == 0 ? 0 : b.count / maxBucket,
                        trailing: '${b.count}',
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: b.count == 0 ? Colors.transparent : d.text4,
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

/// The patients behind one "how many visits" group, with a search box.
void _showBucket(BuildContext context, VisitBucket b) {
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => _BucketDialog(bucket: b, parentContext: context),
  );
}

class _BucketDialog extends StatefulWidget {
  const _BucketDialog({required this.bucket, required this.parentContext});
  final VisitBucket bucket;

  /// The screen behind the dialog — used to open a patient after closing.
  final BuildContext parentContext;

  @override
  State<_BucketDialog> createState() => _BucketDialogState();
}

class _BucketDialogState extends State<_BucketDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final b = widget.bucket;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? b.patients
        : b.patients
              .where(
                (p) => p.name.toLowerCase().contains(q) || p.phone.contains(q),
              )
              .toList();

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patients with ${b.label}',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${b.count} patient${b.count == 1 ? '' : 's'} · most recent visit first',
                          style: TextStyle(color: d.text3, fontSize: 10.4.sp),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: d.text3),
                  ),
                ],
              ),
            ),
            if (b.count > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  style: TextStyle(color: d.text1, fontSize: 10.6.sp),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, color: d.text4),
                    hintText: 'Search name or phone',
                    hintStyle: TextStyle(color: d.text4, fontSize: 10.6.sp),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

            // ── list ──
            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        'No patient matches "$_q".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        return _PatientRow(
                          rank: i + 1,
                          name: p.name,
                          sub:
                              '${p.visits} visit${p.visits == 1 ? '' : 's'}'
                              ' · last ${_dateOf(p.lastVisit)}'
                              '${p.phone.isEmpty ? '' : ' · ${p.phone}'}',
                          amount: p.paid,
                          onTap: () {
                            Navigator.pop(context);
                            _openPatient(widget.parentContext, p.patientId);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Top earning services
// ═════════════════════════════════════════════════════════════════════════════

class _TopServicesPanel extends StatelessWidget {
  const _TopServicesPanel({required this.services});
  final List<ServiceEarning> services;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final medals = [d.warn, d.text3, d.tealDeep];

    return DentPanel(
      title: 'Top Earning Services',
      subtitle: 'Invoiced in this period · after discounts',
      child: services.isEmpty
          ? const _Empty(
              Icons.medical_services_outlined,
              'No invoiced services in this period',
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                children: [
                  for (var i = 0; i < services.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: medals[i].withValues(alpha: .15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: medals[i],
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5.sp,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                services[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${services[i].count} time${services[i].count == 1 ? '' : 's'}'
                                ' · ${_pct(services[i].share)} of service income',
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 10.4.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Rs ${_compact(services[i].amount)}',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: services[i].share.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: d.line,
                        valueColor: AlwaysStoppedAnimation(medals[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Lifetime value + top 10
// ═════════════════════════════════════════════════════════════════════════════

class _LifetimePanel extends StatelessWidget {
  const _LifetimePanel({required this.s});
  final Insights s;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return DentPanel(
      title: 'Patient Lifetime Value',
      subtitle: 'Average a patient has paid you, all time',
      child: s.payingPatients == 0
          ? const _Empty(Icons.savings_outlined, 'No payments recorded yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BigNumber('Rs ${_m(s.avgLifetimeValue)}'),
                      const SizedBox(height: 4),
                      Text(
                        'per patient · across ${s.payingPatients} paying patients',
                        style: TextStyle(color: d.text3, fontSize: 9.8.sp),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'TOP ${s.topPatients.length} PATIENTS BY SPEND',
                        style: TextStyle(
                          color: d.text4,
                          fontSize: 8.4.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .8,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < s.topPatients.length; i++)
                  _PatientRow(
                    rank: i + 1,
                    name: s.topPatients[i].name,
                    sub:
                        '${s.topPatients[i].visits} visit${s.topPatients[i].visits == 1 ? '' : 's'}'
                        '${s.topPatients[i].lastVisit == null ? '' : ' · last ${_dateOf(s.topPatients[i].lastVisit!)}'}',
                    amount: s.topPatients[i].paid,
                    onTap: () =>
                        _openPatient(context, s.topPatients[i].patientId),
                  ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

String _dateOf(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.name,
    required this.sub,
    required this.amount,
    required this.onTap,
    this.rank,
    this.warn = false,
  });
  final int? rank;
  final String name, sub;
  final int amount;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  style: AppTypography.mono(size: 9.6.sp, color: d.text4),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: warn ? d.warn : d.text4,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: d.text3, fontSize: 8.8.sp),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Rs ${_compact(amount)}',
              style: AppTypography.mono(size: 9.8.sp, color: d.text1),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: d.text4),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  At-risk patients
// ═════════════════════════════════════════════════════════════════════════════

class _AtRiskPanel extends StatefulWidget {
  const _AtRiskPanel({required this.list});
  final List<AtRiskPatient> list;

  @override
  State<_AtRiskPanel> createState() => _AtRiskPanelState();
}

class _AtRiskPanelState extends State<_AtRiskPanel> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final list = widget.list;
    final shown = _all ? list : list.take(8).toList();

    return DentPanel(
      title: 'At-Risk Patients',
      subtitle: list.isEmpty
          ? 'Regulars who are late for their usual visit'
          : '${list.length} regular${list.length == 1 ? ' is' : 's are'} late for their usual visit',
      child: list.isEmpty
          ? const _Empty(
              Icons.favorite_border_rounded,
              'No regular patients are overdue right now.\n'
              'Patients with 3+ visits appear here when they are late.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                for (final p in shown)
                  _PatientRow(
                    name: p.name,
                    warn: p.daysSinceLast > p.usualGapDays * 2,
                    sub:
                        'Usually every ${_ago(p.usualGapDays)} · last seen ${_ago(p.daysSinceLast)} ago'
                        '${p.phone.isEmpty ? '' : ' · ${p.phone}'}',
                    amount: p.paid,
                    onTap: () => _openPatient(context, p.patientId),
                  ),
                if (list.length > 8)
                  TextButton(
                    onPressed: () => setState(() => _all = !_all),
                    child: Text(
                      _all ? 'Show less' : 'Show all ${list.length}',
                      style: TextStyle(color: d.ice, fontSize: 9.6.sp),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Retention grid
// ═════════════════════════════════════════════════════════════════════════════

class _RetentionPanel extends StatelessWidget {
  const _RetentionPanel({required this.cohorts});
  final List<RetentionCohort> cohorts;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    Widget head(String t, {bool left = false}) => Text(
      t.toUpperCase(),
      textAlign: left ? TextAlign.left : TextAlign.center,
      style: TextStyle(
        color: d.text4,
        fontSize: 8.4.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    );

    Widget cell(double? v) {
      if (v == null) {
        return Container(
          height: 38,
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: d.line),
          ),
          child: Text(
            '—',
            style: TextStyle(color: d.text4, fontSize: 9.6.sp),
          ),
        );
      }
      // Stronger colour = more patients came back.
      final strong = v >= .5;
      return Container(
        height: 38,
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: d.teal.withValues(alpha: 0.08 + 0.72 * v.clamp(0.0, 1.0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _pct(v),
          style: TextStyle(
            color: strong ? Colors.white : d.text1,
            fontSize: 10.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return DentPanel(
      title: 'Retention by Joining Month',
      subtitle: 'Share of new patients who came back within 1, 3 and 6 months',
      child: cohorts.isEmpty
          ? const _Empty(
              Icons.grid_view_rounded,
              'No new patients in the last 12 months',
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: head('Joined', left: true)),
                      Expanded(flex: 2, child: head('New')),
                      Expanded(flex: 3, child: head('1 month')),
                      Expanded(flex: 3, child: head('3 months')),
                      Expanded(flex: 3, child: head('6 months')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final c in cohorts)
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${_mon[c.month.month - 1]} ${c.month.year}',
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${c.size}',
                            textAlign: TextAlign.center,
                            style: AppTypography.mono(
                              size: 10.sp,
                              color: d.text2,
                            ),
                          ),
                        ),
                        Expanded(flex: 3, child: cell(c.m1)),
                        Expanded(flex: 3, child: cell(c.m3)),
                        Expanded(flex: 3, child: cell(c.m6)),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '— means not enough time has passed yet to know.',
                    style: TextStyle(color: d.text4, fontSize: 8.8.sp),
                  ),
                ],
              ),
            ),
    );
  }
}
