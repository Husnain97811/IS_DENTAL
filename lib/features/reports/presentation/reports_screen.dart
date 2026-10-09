import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../core/constants/views.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  /// null = the default last-12-months view.
  DateTimeRange? _range;

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (x) => '${x[1]},',
  );

  /// Rs 1,250,000 is unreadable in a card; Rs 12.5L is not.
  String _compact(int v) {
    final a = v.abs();
    if (a >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (a >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    return _m(v);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _pretty(DateTime d) {
    const mon = [
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
    return '${d.day} ${mon[d.month - 1]} ${d.year}';
  }

  // ── range ────────────────────────────────────────────────────────────────
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange:
          _range ??
          DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: now),
      helpText: 'Select report period',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: context.dent.ice,
            brightness: Theme.of(ctx).brightness,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  // ── export ───────────────────────────────────────────────────────────────
  /// Exports exactly what is on screen — no second "all or custom" prompt.
  /// A report you looked at and a report you printed should never differ.
  Future<void> _onExport() async {
    final r = _range;
    await showPdfOutput(
      context,
      build: () async {
        final s = r == null
            ? await ref.read(reportsSummaryProvider.future)
            : await ref.read(
                reportsSummaryRangeProvider((from: r.start, to: r.end)).future,
              );
        final name =
            (await ref.read(appDatabaseProvider).clinicName()) ?? 'Clinic';
        return buildReportsPdf(
          s,
          clinicName: name,
          rangeLabel: r == null ? null : '${_fmt(r.start)} – ${_fmt(r.end)}',
        );
      },
      filename: r == null
          ? 'dentos-report.pdf'
          : 'dentos-report-${_fmt(r.start)}-${_fmt(r.end)}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    // Reports are financial data — gated per role by the owner.
    if (!ref.watch(canProvider(Perm.viewFinancials))) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 34, color: d.text4),
              const SizedBox(height: 14),
              Text(
                'Reports are not available for your role.',
                style: TextStyle(color: d.text3, fontSize: 12.1.sp),
              ),
              const SizedBox(height: 4),
              Text(
                'Ask the clinic owner if you need access.',
                style: TextStyle(color: d.text4, fontSize: 10.5.sp),
              ),
            ],
          ),
        ),
      );
    }

    final showExp = ref.watch(canProvider(Perm.viewExpenses));
    final async = _range == null
        ? ref.watch(reportsSummaryProvider)
        : ref.watch(
            reportsSummaryRangeProvider((from: _range!.start, to: _range!.end)),
          );

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 820;
        final pad = narrow ? 16.0 : 26.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 22, pad, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(d, narrow),
              const SizedBox(height: 18),
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(60),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('$e', style: TextStyle(color: d.alert)),
                ),
                data: (s) => _body(d, s, showExp, narrow, c.maxWidth),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _header(DentColors d, bool narrow) {
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _rangeChip(d, 'Last 12 months', _range == null, () {
          setState(() => _range = null);
        }),
        _rangeChip(
          d,
          _range == null
              ? 'Custom range'
              : '${_pretty(_range!.start)} – ${_pretty(_range!.end)}',
          _range != null,
          _pickRange,
        ),
      ],
    );

    // final export = OutlinedButton.icon(
    //   style: OutlinedButton.styleFrom(
    //     foregroundColor: d.text2,
    //     side: BorderSide(color: d.line),
    //     minimumSize: const Size(0, 42),
    //     padding: const EdgeInsets.symmetric(horizontal: 16),
    //   ),
    //   onPressed: _onExport,
    //   icon: const Icon(Icons.download_rounded, size: 18),
    //   label: const Text('Export PDF'),
    // );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   'Reports & Analytics',
        //   style: Theme.of(context).textTheme.displayLarge,
        // ),
        // const SizedBox(height: 4),
        Text(
          _range == null
              ? 'Practice performance · last 12 months'
              : 'Practice performance · ${_pretty(_range!.start)} to '
                    '${_pretty(_range!.end)}',
          style: TextStyle(color: d.text3, fontSize: 10.5.sp),
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 14),
          chips,
          // const SizedBox(height: 10),
          // export,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        // const SizedBox(width: 16),
        Column(
          // mainAxisAlignment: MainAxisAlignment.center,
          // crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // export,
            chips,
          ],
        ),
      ],
    );
  }

  Widget _rangeChip(DentColors d, String label, bool on, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? d.ice.withValues(alpha: .13) : d.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? d.ice : d.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? d.ice : d.text3,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  // ── body ─────────────────────────────────────────────────────────────────
  Widget _body(
    DentColors d,
    ReportsSummary s,
    bool showExp,
    bool narrow,
    double width,
  ) {
    final cols = width < 620
        ? 1
        : width < 980
        ? 2
        : 3;
    const gap = 16.0;
    final cardW = (width - (narrow ? 32 : 52) - gap * (cols - 1)) / cols;

    final secondary = <Widget>[
      KpiCard(
        icon: Icons.payments_rounded,
        tone: KpiTone.teal,
        label: 'Collected',
        value: 'Rs ${_m(s.totalRevenue)}',
      ),
      if (showExp)
        KpiCard(
          icon: Icons.account_balance_wallet_rounded,
          tone: KpiTone.amber,
          label: 'Expenses',
          value: 'Rs ${_m(s.totalExpenses)}',
        ),
      KpiCard(
        icon: Icons.pending_actions_rounded,
        tone: KpiTone.slate,
        label: 'Outstanding',
        value: 'Rs ${_m(s.outstanding)}',
      ),
      KpiCard(
        icon: Icons.people_alt_rounded,
        tone: KpiTone.blue,
        label: 'Patients',
        value: '${s.patientCount}',
      ),
      KpiCard(
        icon: Icons.medical_services_rounded,
        tone: KpiTone.slate,
        label: 'Procedures',
        value: '${s.procedureCount}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showExp) ...[_profitHero(d, s, narrow), const SizedBox(height: 16)],
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final w in secondary) SizedBox(width: cardW, child: w),
          ],
        ),
        const SizedBox(height: 18),

        // charts
        if (width < 980) ...[
          _trendPanel(d, s, showExp),
          const SizedBox(height: 18),
          _mixPanel(d, s, showExp),
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _trendPanel(d, s, showExp)),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: _mixPanel(d, s, showExp)),
              ],
            ),
          ),
        const SizedBox(height: 18),

        if (width < 980) ...[
          if (showExp) ...[_expensePanel(d, s), const SizedBox(height: 18)],
          _dentistPanel(d, s),
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showExp) ...[
                  Expanded(child: _expensePanel(d, s)),
                  const SizedBox(width: 18),
                ],
                Expanded(child: _dentistPanel(d, s)),
              ],
            ),
          ),
      ],
    );
  }

  // ── profit hero ──────────────────────────────────────────────────────────
  /// The number the owner opens this screen for. Six equal cards bury it
  /// among the patient count; this gives it the weight it deserves.
  Widget _profitHero(DentColors d, ReportsSummary s, bool narrow) {
    final up = s.netProfit >= 0;
    final spent = s.totalRevenue == 0
        ? 0.0
        : (s.totalExpenses / s.totalRevenue).clamp(0.0, 1.0);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'NET PROFIT',
          style: TextStyle(
            color: d.text4,
            fontSize: 9.4.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              up ? '+ ' : '– ',
              style: TextStyle(
                color: d.text3,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _m(s.netProfit.abs()),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: up ? d.text1 : d.alert,
                    fontSize: 22.4.sp,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: (up ? d.ok : d.alert).withValues(alpha: .11),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 15,
                color: up ? d.ok : d.alert,
              ),
              const SizedBox(width: 6),
              Text(
                '${(s.margin * 100).toStringAsFixed(1)}% margin',
                style: TextStyle(
                  color: up ? d.ok : d.alert,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _flow(d, 'Money in', s.totalRevenue, d.teal, Icons.south_west_rounded),
        const SizedBox(height: 14),
        _flow(
          d,
          'Money out',
          s.totalExpenses,
          d.warn,
          Icons.north_east_rounded,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: spent,
            minHeight: 8,
            backgroundColor: d.teal.withValues(alpha: .18),
            valueColor: AlwaysStoppedAnimation(d.warn),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          s.totalRevenue == 0
              ? 'Nothing collected in this period.'
              : '${(spent * 100).round()}% of what you collected went back out.',
          style: TextStyle(color: d.text4, fontSize: 9.6.sp),
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
                left,
                const SizedBox(height: 22),
                Divider(color: d.line, height: 1),
                const SizedBox(height: 18),
                right,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: left),
                  const SizedBox(width: 22),
                  VerticalDivider(color: d.line, width: 1),
                  const SizedBox(width: 22),
                  Expanded(flex: 5, child: right),
                ],
              ),
            ),
    );
  }

  Widget _flow(
    DentColors d,
    String label,
    int value,
    Color tone,
    IconData icon,
  ) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: tone),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: d.text3,
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Text(
        'Rs ${_m(value)}',
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: d.text1,
          fontSize: 13.2.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  // ── trend ────────────────────────────────────────────────────────────────
  Widget _trendPanel(DentColors d, ReportsSummary s, bool showExp) {
    final empty = s.monthly.every((v) => v == 0);
    return DentPanel(
      title: showExp ? 'Collected vs Expenses' : 'Collected Revenue',
      subtitle: 'Rs (000) · by month · hover a bar for the exact figure',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: empty
            ? _empty(d, Icons.bar_chart_rounded, 'Nothing collected yet')
            : Column(
                children: [
                  Row(
                    children: [
                      _legend(d, d.teal, 'Collected'),
                      if (showExp) ...[
                        const SizedBox(width: 18),
                        _legend(d, d.warn, 'Expenses'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(height: 210, child: _bars(context, s, showExp)),
                ],
              ),
      ),
    );
  }

  Widget _mixPanel(DentColors d, ReportsSummary s, bool showExp) {
    final data = showExp ? s.expenseMix : s.mix;
    return DentPanel(
      title: showExp ? 'Where the money went' : 'Procedure Mix',
      subtitle: showExp ? 'Expenses by category' : 'By revenue share',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: data.isEmpty
            ? _empty(d, Icons.donut_large_rounded, 'Nothing to show yet')
            : _donut(context, data),
      ),
    );
  }

  Widget _expensePanel(DentColors d, ReportsSummary s) => DentPanel(
    title: 'Expenses by Category',
    subtitle: 'Rs ${_m(s.totalExpenses)} total',
    child: s.expenseMix.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(30),
            child: _empty(
              d,
              Icons.account_balance_wallet_outlined,
              'No expenses recorded in this period',
            ),
          )
        : Column(
            children: [
              for (final e in s.expenseMix)
                StatBarRow(
                  label: e.label,
                  fraction: s.expenseMix.first.value == 0
                      ? 0
                      : e.value / s.expenseMix.first.value,
                  trailing: 'Rs ${_compact(e.value.round())}',
                ),
            ],
          ),
  );

  Widget _dentistPanel(DentColors d, ReportsSummary s) => DentPanel(
    title: 'Dentist Performance',
    subtitle: 'Appointments this period',
    child: s.dentists.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(30),
            child: _empty(
              d,
              Icons.people_outline_rounded,
              'No appointments in this period',
            ),
          )
        : Column(
            children: [
              for (final dp in s.dentists)
                StatBarRow(
                  label: dp.name.isEmpty ? 'Unassigned' : dp.name,
                  fraction: s.dentists.first.value == 0
                      ? 0
                      : dp.value / s.dentists.first.value,
                  trailing: '${dp.value}',
                ),
            ],
          ),
  );

  Widget _empty(DentColors d, IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
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

  Widget _legend(DentColors d, Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: d.text3,
          fontSize: 10.2.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  // ── charts ───────────────────────────────────────────────────────────────
  Widget _bars(BuildContext context, ReportsSummary s, bool showExpenses) {
    final d = context.dent;
    final all = [...s.monthly, if (showExpenses) ...s.monthlyExpenses];
    final maxV = (all.isEmpty ? 1.0 : all.reduce((a, b) => a > b ? a : b))
        .clamp(1.0, double.infinity);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxV * 1.25,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxV / 3,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: d.line, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => d.surface,
            tooltipBorder: BorderSide(color: d.line),
            getTooltipItem: (group, _, rod, rodIndex) {
              final label = rodIndex == 0 ? 'Collected' : 'Expenses';
              final month = group.x >= 0 && group.x < s.monthLabels.length
                  ? s.monthLabels[group.x]
                  : '';
              return BarTooltipItem(
                '$month · $label\nRs ${_m((rod.toY * 1000).round())}',
                TextStyle(
                  color: d.text1,
                  fontSize: 10.2.sp,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
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
              // widened for the larger axis labels
              reservedSize: 46,
              interval: maxV / 3,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  v == 0 ? '0' : v.round().toString(),
                  textAlign: TextAlign.right,
                  style: AppTypography.mono(size: 7.8.sp, color: d.text4),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    i >= 0 && i < s.monthLabels.length ? s.monthLabels[i] : '',
                    style: AppTypography.mono(size: 8.4.sp, color: d.text4),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < s.monthly.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: s.monthly[i],
                  width: showExpenses ? 9 : 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [d.tealDeep, d.teal],
                  ),
                ),
                if (showExpenses)
                  BarChartRodData(
                    toY: i < s.monthlyExpenses.length
                        ? s.monthlyExpenses[i]
                        : 0,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [d.warn.withValues(alpha: .6), d.warn],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _donut(
    BuildContext context,
    List<({String label, double value})> data,
  ) {
    final d = context.dent;
    final colors = [d.ice, d.teal, d.tealDeep, d.warn, d.text4];
    final total = data.fold<double>(0, (a, b) => a + b.value);

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  // widened so the larger centre text fits the hole
                  centerSpaceRadius: 50,
                  sections: [
                    for (var i = 0; i < data.length; i++)
                      PieChartSectionData(
                        value: data[i].value,
                        color: colors[i % colors.length],
                        radius: 20,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              // The hole was empty space; the total belongs in it.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rs ${_compact(total.round())}',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: d.text1,
                      fontSize: 13.2.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'TOTAL',
                    style: TextStyle(
                      color: d.text4,
                      fontSize: 7.8.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < data.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data[i].label,
                    style: TextStyle(color: d.text2, fontSize: 10.5.sp),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Rs ${_compact(data[i].value.round())}',
                  style: AppTypography.mono(size: 10.2.sp, color: d.text1),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    total == 0
                        ? '0%'
                        : '${(data[i].value / total * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: AppTypography.mono(size: 9.6.sp, color: d.text4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
