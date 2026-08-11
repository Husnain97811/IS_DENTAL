import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import 'widgets/appointment_tile.dart';
import 'widgets/mini_calendar.dart';

final billedAppointmentIdsProvider = StreamProvider<Set<int>>((ref) {
  return ref.watch(appDatabaseProvider).watchBilledAppointmentIds();
});

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
    final dentistFilter = ref.watch(dentistFilterProvider);
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

              Container(
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: d.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: d.line),
                ),
                child: DropdownButton<String?>(
                  value: dentistFilter,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'All doctors',
                        style: TextStyle(fontSize: 8.5.sp, color: d.text1),
                      ),
                    ),
                    for (final doc in ref.watch(dentistsProvider).value ?? [])
                      DropdownMenuItem<String?>(
                        value: doc,
                        child: Text(
                          doc,
                          style: TextStyle(fontSize: 8.5.sp, color: d.text1),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      ref.read(dentistFilterProvider.notifier).state = v,
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
                    padding: EdgeInsets.all(10),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text('$e', style: TextStyle(color: d.alert)),
                  ),
                  data: (list) {
                    final filtered = dentistFilter == null
                        ? list
                        : list
                              .where((a) => a.dentist == dentistFilter)
                              .toList();
                    return filtered.isEmpty
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
                                for (final a in filtered)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: AppointmentTile(appt: a),
                                        ),
                                        const SizedBox(width: 10),
                                        _ApptActions(appt: a),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                  },
                ),
              );
              final side = Column(
                children: [
                  DentPanel(title: 'Calendar', child: const MiniCalendar()),
                  const SizedBox(height: 18),
                  _countsPanel(d, apptsAsync.value ?? const []),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: agenda),
                  SizedBox(width: 8.sp),
                  Expanded(flex: 1, child: side),
                ],
              );
              // if (c.maxWidth < 920)
              //   return Column(
              //     children: [agenda, const SizedBox(height: 18), side],
              //   );
              // return Row(
              //   crossAxisAlignment: CrossAxisAlignment.start,
              //   children: [
              //     Expanded(child: agenda),
              //     const SizedBox(width: 18),
              //     SizedBox(width: 320, child: side),
              //   ],
              // );
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

class _ApptActions extends ConsumerWidget {
  const _ApptActions({required this.appt});
  final Appointment appt;

  Future<void> _confirmArrived(BuildContext context, WidgetRef ref) async {
    final d = context.dent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // ← named
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as arrived?'),
        content: Text('Confirm ${appt.patientName} has arrived at the clinic.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false), // ← use it
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
            ),
            onPressed: () => Navigator.pop(dialogContext, true), // ← use it
            child: const Text('Mark Arrived'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(appDatabaseProvider)
          .setAppointmentStatus(appt.id, AppointmentStatus.waiting.name);
    }
  }

  Future<void> _bill(BuildContext context, WidgetRef ref) async {
    final created = await showInvoiceEditor(
      context,
      patientId: appt.patientId,
      procedure: appt.procedure,
    );
    if (created == true) {
      await ref.read(appDatabaseProvider).setAppointmentBilled(appt.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final arrived = appt.status != AppointmentStatus.upcoming;
    final billed =
        ref.watch(billedAppointmentIdsProvider).value?.contains(appt.id) ??
        false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 92,
          child: OutlinedButton(
            onPressed: arrived ? null : () => _confirmArrived(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: arrived ? d.text4 : d.ok,
              side: BorderSide(color: arrived ? d.line : d.ok),
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              arrived ? 'Arrived ✓' : 'Arrived',
              style: TextStyle(fontSize: 8.5.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 92,
          child: billed
              ? OutlinedButton(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: d.ok,
                    side: BorderSide(color: d.line),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Billed ✓',
                    style: TextStyle(
                      fontSize: 8.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : FilledButton(
                  onPressed: () => _bill(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice,
                    foregroundColor: AppPalette.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Bill',
                    style: TextStyle(
                      fontSize: 8.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
