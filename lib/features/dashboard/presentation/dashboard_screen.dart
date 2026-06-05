import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_avatar.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/mini_bar_chart.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/stat_bar.dart';
import '../../../core/widgets/status_chip.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _hello(context),
        SizedBox(height: 2.4.h),
        _kpis(),
        SizedBox(height: 2.2.h),
        LayoutBuilder(builder: (context, c) {
          final stack = c.maxWidth < 920;
          final left = _schedulePanel(context);
          final right = _revenuePanel(context);
          return stack
              ? Column(children: [left, const SizedBox(height: 18), right])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 155, child: left), const SizedBox(width: 18), Expanded(flex: 100, child: right)]);
        }),
        SizedBox(height: 2.2.h),
        LayoutBuilder(builder: (context, c) {
          final stack = c.maxWidth < 920;
          final a = _topProcedures(context), b = _clinicStatus(context);
          return stack
              ? Column(children: [a, const SizedBox(height: 18), b])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 18), Expanded(child: b)]);
        }),
      ]),
    );
  }

  Widget _hello(BuildContext context) {
    final d = context.dent;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          style: TextStyle(fontFamily: AppFonts.display, fontSize: 16.sp, fontWeight: FontWeight.w600, color: d.text1),
          children: [
            const TextSpan(text: 'Good morning, '),
            TextSpan(text: 'Dr. Khan', style: TextStyle(foreground: Paint()..shader = d.accentGradient.createShader(const Rect.fromLTWH(0, 0, 200, 40)))),
            const TextSpan(text: ' 👋'),
          ],
        )),
        const SizedBox(height: 4),
        Text('You have 18 appointments today · 4 chairs active · 2 patients waiting in the lobby.',
            style: TextStyle(color: d.text3, fontSize: 9.sp)),
      ])),
      SegmentedControl(items: const ['Today', 'Week', 'Month'], selected: _range, onChanged: (i) => setState(() => _range = i)),
    ]);
  }

  Widget _kpis() => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 720 ? 2 : 4;
        const gap = 16.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        final cards = const [
          KpiCard(icon: Icons.calendar_today_rounded, tone: KpiTone.blue, label: "Today's Appointments", value: '18', unit: '/ 24 slots', delta: '12% vs last Tue'),
          KpiCard(icon: Icons.attach_money_rounded, tone: KpiTone.teal, label: 'Revenue Today', value: 'Rs 184,500', delta: '8.4% vs avg'),
          KpiCard(icon: Icons.schedule_rounded, tone: KpiTone.amber, label: 'Pending Payments', value: 'Rs 42,300', delta: '7 outstanding invoices', deltaUp: false),
          KpiCard(icon: Icons.donut_large_rounded, tone: KpiTone.slate, label: 'Chair Utilization', value: '78', unit: '%', delta: 'Optimal range'),
        ];
        return Wrap(spacing: gap, runSpacing: gap, children: cards.map((e) => SizedBox(width: w, child: e)).toList());
      });

  Widget _schedulePanel(BuildContext context) => DentPanel(
        title: "Today's Schedule",
        subtitle: 'Live queue · auto-refresh',
        trailing: PanelLink('Open Calendar', onTap: () {}),
        child: const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Column(children: [
          _ApptRow(time: '09:00', tone: _Tone.ice, initials: 'FA', name: 'Fatima Aslam', chip: ChipKind.inProgress, chipText: 'In Chair', detail: 'Root Canal Therapy · Molar #36 · Session 2/3', doctor: 'Dr. Khan', chair: 'Chair 01'),
          _ApptRow(time: '09:45', tone: _Tone.warn, initials: 'UR', name: 'Usman Raza', chip: ChipKind.waiting, chipText: 'Waiting', detail: 'Scaling & Polishing · Routine cleaning', doctor: 'Dr. Bilal', chair: 'Chair 02'),
          _ApptRow(time: '10:30', tone: _Tone.ok, initials: 'HN', name: 'Hira Nadeem', chip: ChipKind.done, chipText: 'Completed', detail: 'Composite Filling · Pre-molar #14', doctor: 'Dr. Sara', chair: 'Chair 03'),
          _ApptRow(time: '11:15', tone: _Tone.slate, initials: 'TM', name: 'Tariq Mehmood', chip: ChipKind.upcoming, chipText: 'Upcoming', detail: 'Crown Fitting · Zirconia · Tooth #46', doctor: 'Dr. Khan', chair: 'Chair 01'),
          _ApptRow(time: '12:00', tone: _Tone.slate, initials: 'AZ', name: 'Ayesha Zubair', chip: ChipKind.upcoming, chipText: 'Upcoming', detail: 'Braces Adjustment · Monthly ortho review', doctor: 'Dr. Sara', chair: 'Chair 03'),
        ])),
      );

  Widget _revenuePanel(BuildContext context) {
    final d = context.dent;
    return DentPanel(
      title: 'Weekly Revenue',
      subtitle: 'Mon – Sun · Rs (000)',
      trailing: PanelLink('Details', icon: Icons.chevron_right_rounded, onTap: () {}),
      child: Column(children: [
        const Padding(padding: EdgeInsets.all(18),
            child: MiniBarChart(values: [.55, .72, .48, .95, .80, .64, .30], labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], peakIndex: 3)),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: d.line))),
          child: Row(children: [
            _legendStat(context, 'Rs 1.12M', '▲ 14% this week', d.ok),
            const SizedBox(width: 24),
            _legendStat(context, 'Rs 160K', 'Daily average', d.text3),
          ]),
        ),
      ]),
    );
  }

  Widget _legendStat(BuildContext context, String big, String sub, Color subColor) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(big, style: TextStyle(fontFamily: AppFonts.display, fontSize: 11.sp, fontWeight: FontWeight.w600, color: context.dent.text1)),
        Text(sub, style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.w600, color: subColor)),
      ]);

  Widget _topProcedures(BuildContext context) => const DentPanel(
        title: 'Top Procedures', subtitle: 'This month by volume',
        child: Column(children: [
          StatBarRow(label: 'Scaling & Polishing', fraction: .88, trailing: '88'),
          StatBarRow(label: 'Composite Fillings', fraction: .64, trailing: '64'),
          StatBarRow(label: 'Root Canal Therapy', fraction: .41, trailing: '41'),
          StatBarRow(label: 'Tooth Extraction', fraction: .33, trailing: '33'),
          StatBarRow(label: 'Crowns & Bridges', fraction: .22, trailing: '22'),
        ]),
      );

  Widget _clinicStatus(BuildContext context) {
    final d = context.dent;
    Widget row(String label, String value, {Color? color}) =>
        StatBarRow(label: label, fraction: 0, trailing: value, trailingColor: color, showTrack: false);
    return DentPanel(title: 'Clinic Status', subtitle: 'Real-time operations', child: Column(children: [
      row('🟢  Chairs Active', '3 / 4'),
      row('⏳  Avg. Wait Time', '12 min'),
      row('🦷  New Patients (MTD)', '47'),
      row('📦  Low Stock Alerts', '3 items', color: d.alert),
      row('🔁  Recall Due (7d)', '14'),
    ]));
  }
}

enum _Tone { ice, warn, ok, slate }

class _ApptRow extends StatelessWidget {
  const _ApptRow({required this.time, required this.tone, required this.initials, required this.name, required this.chip, required this.chipText, required this.detail, required this.doctor, required this.chair});
  final String time, initials, name, chipText, detail, doctor, chair;
  final _Tone tone;
  final ChipKind chip;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color bar, Color avBg, Color avFg) = switch (tone) {
      _Tone.ice => (d.ice, d.ice.withValues(alpha: .15), dark ? d.ice : const Color(0xFF0284C7)),
      _Tone.warn => (d.warn, d.warn.withValues(alpha: .14), dark ? d.warn : const Color(0xFFD97706)),
      _Tone.ok => (d.ok, d.ok.withValues(alpha: .13), dark ? const Color(0xFF34D399) : const Color(0xFF15803D)),
      _Tone.slate => (d.text4, d.text3.withValues(alpha: .13), d.text2),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          SizedBox(width: 50, child: Text(time, style: TextStyle(fontFamily: AppFonts.mono, fontSize: 8.sp, color: d.text3, fontWeight: FontWeight.w500))),
          Container(width: 4, height: 40, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4))),
          DentAvatar(initials, bg: avBg, fg: avFg, size: 38, radius: 11),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, style: TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.w600, color: d.text1), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 7),
              StatusChip(chipText, kind: chip),
            ]),
            const SizedBox(height: 2),
            Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: d.text3, fontSize: 8.5.sp)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(doctor, style: TextStyle(color: d.text2, fontSize: 8.5.sp, fontWeight: FontWeight.w600)),
            Text(chair, style: TextStyle(color: d.text4, fontSize: 8.sp)),
          ]),
        ]),
      ),
    );
  }
}
