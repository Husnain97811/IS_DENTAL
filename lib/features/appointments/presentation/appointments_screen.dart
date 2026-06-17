import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../patients/presentation/patients_controller.dart';
import '../domain/appointment.dart';
import 'appointments_controller.dart';
import 'widgets/appointment_tile.dart';
import 'widgets/mini_calendar.dart';

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  int _view = 1;
  @override
  void initState() {
    super.initState();
    if (kDebugMode && kSeedDemoData) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(patientRepositoryProvider).seedDemoDataIfEmpty();
        await ref
            .read(appointmentRepositoryProvider)
            .seedDemoAppointmentsIfEmpty();
      });
    }
  }

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final day = ref.watch(selectedDateProvider);
    final apptsAsync = ref.watch(appointmentsForDayProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appointments',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.day} ${_months[day.month - 1]} ${day.year}',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ],
                ),
              ),
              SegmentedControl(
                items: const ['Day', 'Agenda', 'Week'],
                selected: _view,
                onChanged: (i) => setState(() => _view = i),
              ),
            ],
          ),
          SizedBox(height: 2.2.h),
          LayoutBuilder(
            builder: (context, c) {
              final agenda = DentPanel(
                title: "Today's Agenda",
                subtitle: 'Grouped by time',
                child: apptsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('$e', style: TextStyle(color: d.alert)),
                  ),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              'No appointments for this day.',
                              style: TextStyle(color: d.text4),
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              for (final a in list) AppointmentTile(appt: a),
                            ],
                          ),
                        ),
                ),
              );
              final side = Column(
                children: [
                  DentPanel(title: 'Calendar', child: const MiniCalendar()),
                  const SizedBox(height: 18),
                  _countsPanel(d, apptsAsync.value ?? const []),
                ],
              );
              if (c.maxWidth < 920)
                return Column(
                  children: [agenda, const SizedBox(height: 18), side],
                );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: agenda),
                  const SizedBox(width: 18),
                  SizedBox(width: 320, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _countsPanel(DentColors d, List<Appointment> list) {
    final noShow = list
        .where((a) => a.status == AppointmentStatus.noShow)
        .length;
    final pending = list
        .where((a) => a.status == AppointmentStatus.waiting)
        .length;
    final confirmed = list.length - noShow - pending;
    Widget row(String dot, String label, String value, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            dot,
            style: TextStyle(color: color, fontSize: 9.sp),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: d.text2, fontSize: 9.sp),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: d.text1,
              fontSize: 9.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return DentPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            row('●', 'Confirmed', '$confirmed', d.ok),
            row('●', 'Pending', '$pending', d.warn),
            row('●', 'No-show', '$noShow', d.alert),
          ],
        ),
      ),
    );
  }
}
