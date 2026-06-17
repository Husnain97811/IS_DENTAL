import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';

import '../../../core/db/app_database.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/mini_bar_chart.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/stat_bar.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointments_controller.dart';
import '../../appointments/presentation/widgets/appointment_tile.dart';
import '../../inventory/domain/inventory_item.dart';
import '../../inventory/presentation/inventory_controller.dart';

typedef _Range = ({DateTime start, DateTime end});

// today's appointments (independent of the Appointments screen's selected date)
final _todayApptsProvider = StreamProvider.autoDispose<List<Appointment>>((
  ref,
) {
  final n = DateTime.now();
  return ref
      .watch(appointmentRepositoryProvider)
      .watchAppointmentsForDay(DateTime(n.year, n.month, n.day));
});

final _clinicNameProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      (await ref.watch(appDatabaseProvider).clinicName()) ?? 'your clinic',
);

// DB-side aggregates
final _patientCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchPatientCount(),
);
final _inTreatmentProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(appDatabaseProvider).watchInTreatmentCount(),
);
final _unpaidProvider = StreamProvider.autoDispose<({int sum, int count})>(
  (ref) => ref.watch(appDatabaseProvider).watchUnpaidTotals(),
);
final _apptCountProvider = StreamProvider.autoDispose.family<int, _Range>(
  (ref, r) =>
      ref.watch(appDatabaseProvider).watchAppointmentCount(r.start, r.end),
);
final _revenueProvider = StreamProvider.autoDispose.family<int, _Range>(
  (ref, r) => ref.watch(appDatabaseProvider).watchPaidRevenue(r.start, r.end),
);
final _topProcProvider = StreamProvider.autoDispose
    .family<List<({String procedure, int count})>, _Range>(
      (ref, r) =>
          ref.watch(appDatabaseProvider).watchTopProcedures(r.start, r.end),
    );
final _weekPaidProvider = StreamProvider.autoDispose
    .family<List<({DateTime issuedAt, int total})>, _Range>(
      (ref, r) => ref
          .watch(appDatabaseProvider)
          .watchPaidInvoicesBetween(r.start, r.end),
    );

String _money(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _range = 0; // 0 = Today, 1 = Week, 2 = Month

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final now = DateTime.now();

    final today0 = DateTime(now.year, now.month, now.day);
    final monday = today0.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final _Range periodRange = switch (_range) {
      0 => (start: today0, end: today0.add(const Duration(days: 1))),
      1 => (start: monday, end: monday.add(const Duration(days: 7))),
      _ => (start: monthStart, end: monthEnd),
    };
    final _Range monthRange = (start: monthStart, end: monthEnd);
    final _Range weekRange = (
      start: monday,
      end: monday.add(const Duration(days: 7)),
    );

    final patientCount = ref.watch(_patientCountProvider).value ?? 0;
    final inTreatment = ref.watch(_inTreatmentProvider).value ?? 0;
    final unpaid = ref.watch(_unpaidProvider).value ?? (sum: 0, count: 0);
    final apptCount = ref.watch(_apptCountProvider(periodRange)).value ?? 0;
    final revenue = ref.watch(_revenueProvider(periodRange)).value ?? 0;
    final topRows =
        ref.watch(_topProcProvider(monthRange)).value ??
        const <({String procedure, int count})>[];
    final weekPaid =
        ref.watch(_weekPaidProvider(weekRange)).value ??
        const <({DateTime issuedAt, int total})>[];
    final today = ref.watch(_todayApptsProvider).value ?? const <Appointment>[];
    final inventory =
        ref.watch(inventoryStreamProvider).value ?? const <InventoryItem>[];
    final clinic = ref.watch(_clinicNameProvider).value ?? 'your clinic';

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final lowStock = inventory.where((i) => i.level != StockLevel.ok).length;

    final periodWord = switch (_range) {
      0 => 'Today',
      1 => 'This Week',
      _ => 'This Month',
    };

    // weekly revenue chart (this week's paid invoices, Mon–Sun)
    final weekDays = [
      for (var i = 0; i < 7; i++) monday.add(Duration(days: i)),
    ];
    final dayTotals = [
      for (final day in weekDays)
        weekPaid
            .where((e) => sameDay(e.issuedAt, day))
            .fold<int>(0, (s, e) => s + e.total),
    ];
    final weekTotal = dayTotals.fold<int>(0, (a, b) => a + b);
    final maxT = dayTotals.fold<int>(0, (m, v) => v > m ? v : m);
    final chartValues = [for (final v in dayTotals) maxT == 0 ? 0.0 : v / maxT];
    final peak = maxT == 0 ? null : dayTotals.indexOf(maxT);

    final maxC = topRows.isEmpty ? 1 : topRows.first.count;

    final inChair = today
        .where((a) => a.status == AppointmentStatus.inChair)
        .length;
    final waiting = today
        .where((a) => a.status == AppointmentStatus.waiting)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // greeting
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: d.text1,
                        ),
                        children: [
                          TextSpan(text: '${_greeting()}, '),
                          TextSpan(
                            text: clinic,
                            style: TextStyle(
                              foreground: Paint()
                                ..shader = d.accentGradient.createShader(
                                  const Rect.fromLTWH(0, 0, 260, 40),
                                ),
                            ),
                          ),
                          const TextSpan(text: ' 👋'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You have ${today.length} appointment${today.length == 1 ? '' : 's'} today · $inChair in chair · $waiting waiting.',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ],
                ),
              ),
              SegmentedControl(
                items: const ['Today', 'Week', 'Month'],
                selected: _range,
                onChanged: (i) => setState(() => _range = i),
              ),
            ],
          ),
          SizedBox(height: 2.4.h),

          // KPIs
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < 720 ? 2 : 4;
              const gap = 16.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              final cards = [
                KpiCard(
                  icon: Icons.calendar_today_rounded,
                  tone: KpiTone.blue,
                  label: "$periodWord's Appointments",
                  value: '$apptCount',
                ),
                KpiCard(
                  icon: Icons.attach_money_rounded,
                  tone: KpiTone.teal,
                  label: 'Revenue ($periodWord)',
                  value: 'Rs ${_money(revenue)}',
                ),
                KpiCard(
                  icon: Icons.schedule_rounded,
                  tone: KpiTone.amber,
                  label: 'Pending Payments',
                  value: 'Rs ${_money(unpaid.sum)}',
                  delta: '${unpaid.count} outstanding',
                  deltaUp: false,
                ),
                KpiCard(
                  icon: Icons.people_alt_rounded,
                  tone: KpiTone.slate,
                  label: 'Total Patients',
                  value: '$patientCount',
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: cards
                    .map((e) => SizedBox(width: w, child: e))
                    .toList(),
              );
            },
          ),
          SizedBox(height: 2.2.h),

          // schedule + revenue
          LayoutBuilder(
            builder: (context, c) {
              final stack = c.maxWidth < 920;
              final left = DentPanel(
                title: "Today's Schedule",
                subtitle: 'Live queue',
                trailing: PanelLink(
                  'Open Calendar',
                  onTap: () => context.go(AppRoutes.appointments),
                ),
                child: today.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(36),
                        child: Center(
                          child: Text(
                            'No appointments scheduled today.',
                            style: TextStyle(color: d.text4, fontSize: 9.sp),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            for (final a in today) AppointmentTile(appt: a),
                          ],
                        ),
                      ),
              );
              final right = DentPanel(
                title: 'Weekly Revenue',
                subtitle: 'Mon – Sun · collected',
                trailing: PanelLink(
                  'Details',
                  icon: Icons.chevron_right_rounded,
                  onTap: () => context.go(AppRoutes.reports),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: MiniBarChart(
                        values: chartValues,
                        labels: const [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun',
                        ],
                        peakIndex: peak,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: d.line)),
                      ),
                      child: Row(
                        children: [
                          _legendStat(
                            context,
                            'Rs ${_money(weekTotal)}',
                            'This week',
                            d.ok,
                          ),
                          const SizedBox(width: 24),
                          _legendStat(
                            context,
                            'Rs ${_money((weekTotal / 7).round())}',
                            'Daily average',
                            d.text3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              return stack
                  ? Column(children: [left, const SizedBox(height: 18), right])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 155, child: left),
                        const SizedBox(width: 18),
                        Expanded(flex: 100, child: right),
                      ],
                    );
            },
          ),
          SizedBox(height: 2.2.h),

          // top procedures + clinic status
          LayoutBuilder(
            builder: (context, c) {
              final stack = c.maxWidth < 920;
              final a = DentPanel(
                title: 'Top Procedures',
                subtitle: 'This month by volume',
                child: topRows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(36),
                        child: Center(
                          child: Text(
                            'No procedures yet.',
                            style: TextStyle(color: d.text4, fontSize: 9.sp),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (final e in topRows)
                            StatBarRow(
                              label: e.procedure,
                              fraction: e.count / maxC,
                              trailing: '${e.count}',
                            ),
                        ],
                      ),
              );
              final b = DentPanel(
                title: 'Clinic Status',
                subtitle: 'Real-time operations',
                child: Column(
                  children: [
                    StatBarRow(
                      label: '🦷  Total Patients',
                      fraction: 0,
                      trailing: '$patientCount',
                      showTrack: false,
                    ),
                    StatBarRow(
                      label: '📅  Appointments Today',
                      fraction: 0,
                      trailing: '${today.length}',
                      showTrack: false,
                    ),
                    StatBarRow(
                      label: '🩺  In Treatment',
                      fraction: 0,
                      trailing: '$inTreatment',
                      showTrack: false,
                    ),
                    StatBarRow(
                      label: '🧾  Unpaid Invoices',
                      fraction: 0,
                      trailing: '${unpaid.count}',
                      showTrack: false,
                    ),
                    StatBarRow(
                      label: '📦  Low Stock Alerts',
                      fraction: 0,
                      trailing: '$lowStock',
                      trailingColor: lowStock > 0 ? d.alert : null,
                      showTrack: false,
                    ),
                  ],
                ),
              );
              return stack
                  ? Column(children: [a, const SizedBox(height: 18), b])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: a),
                        const SizedBox(width: 18),
                        Expanded(child: b),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  Widget _legendStat(
    BuildContext context,
    String big,
    String sub,
    Color subColor,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        big,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: context.dent.text1,
        ),
      ),
      Text(
        sub,
        style: TextStyle(
          fontSize: 8.sp,
          fontWeight: FontWeight.w600,
          color: subColor,
        ),
      ),
    ],
  );
}
