import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/stat_bar.dart';
import 'reports_controller.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (x) => '${x[1]},',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final async = ref.watch(reportsSummaryProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reports & Analytics',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Practice performance overview.',
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          SizedBox(height: 2.2.h),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final c in [
                      (
                        'Total Revenue',
                        'Rs ${_m(s.totalRevenue)}',
                        KpiTone.teal,
                        Icons.payments_rounded,
                      ),
                      (
                        'Total Patients',
                        '${s.patientCount}',
                        KpiTone.blue,
                        Icons.people_alt_rounded,
                      ),
                      (
                        'Procedures',
                        '${s.procedureCount}',
                        KpiTone.slate,
                        Icons.medical_services_rounded,
                      ),
                      (
                        'Avg. Rating',
                        '4.8/5',
                        KpiTone.amber,
                        Icons.star_rounded,
                      ),
                    ])
                      SizedBox(
                        width: 240,
                        child: KpiCard(
                          icon: c.$4,
                          tone: c.$3,
                          label: c.$1,
                          value: c.$2,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 2.2.h),
                LayoutBuilder(
                  builder: (context, cns) {
                    final trend = DentPanel(
                      title: 'Revenue Trend',
                      subtitle: 'Rs (000) · 6 months',
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SizedBox(height: 200, child: _bars(context, s)),
                      ),
                    );
                    final mix = DentPanel(
                      title: 'Procedure Mix',
                      subtitle: 'By revenue share',
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: _donut(context, s),
                      ),
                    );
                    if (cns.maxWidth < 920)
                      return Column(
                        children: [trend, const SizedBox(height: 18), mix],
                      );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: trend),
                        const SizedBox(width: 18),
                        Expanded(child: mix),
                      ],
                    );
                  },
                ),
                SizedBox(height: 2.2.h),
                DentPanel(
                  title: 'Dentist Performance',
                  subtitle: 'Appointments this period',
                  child: Column(
                    children: [
                      for (final dperf in s.dentists)
                        StatBarRow(
                          label: dperf.name,
                          fraction: s.dentists.isEmpty
                              ? 0
                              : dperf.value / s.dentists.first.value,
                          trailing: '${dperf.value}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bars(BuildContext context, ReportsSummary s) {
    final d = context.dent;
    final maxV =
        (s.monthly.isEmpty ? 1.0 : s.monthly.reduce((a, b) => a > b ? a : b))
            .clamp(1.0, double.infinity);
    final peak = s.monthly.indexOf(maxV.toDouble());
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxV * 1.25,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    i >= 0 && i < s.monthLabels.length ? s.monthLabels[i] : '',
                    style: AppTypography.mono(size: 7.sp, color: d.text4),
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
              barRods: [
                BarChartRodData(
                  toY: s.monthly[i],
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: i == peak
                        ? [d.tealDeep, d.teal]
                        : [d.ice.withValues(alpha: .6), d.ice],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _donut(BuildContext context, ReportsSummary s) {
    final d = context.dent;
    final colors = [d.ice, d.teal, d.tealDeep, d.text4, d.warn];
    final total = s.mix.fold<double>(0, (a, b) => a + b.value);
    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              sections: [
                for (var i = 0; i < s.mix.length; i++)
                  PieChartSectionData(
                    value: s.mix[i].value,
                    color: colors[i % colors.length],
                    radius: 18,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < s.mix.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                          s.mix[i].label,
                          style: TextStyle(color: d.text2, fontSize: 9.sp),
                        ),
                      ),
                      Text(
                        total == 0
                            ? '0%'
                            : '${(s.mix[i].value / total * 100).round()}%',
                        style: AppTypography.mono(size: 8.5.sp, color: d.text1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
