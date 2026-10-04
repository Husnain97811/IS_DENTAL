import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:is_dental/features/appointments/presentation/widgets/appointment_actions_dialog.dart';
import 'package:is_dental/features/prescriptions/presentation/widgets/prescription_editor.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import 'widgets/appointment_tile.dart';
import 'widgets/mini_calendar.dart';

final billedAppointmentIdsProvider = StreamProvider<Set<int>>((ref) {
  return ref.watch(appDatabaseProvider).watchBilledAppointmentIds();
});

final prescribedAppointmentIdsProvider = StreamProvider<Set<int>>((ref) {
  return ref.watch(appDatabaseProvider).watchPrescribedAppointmentIds();
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
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: d.surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: d.line),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          AppointmentTile(appt: a),
                                          Divider(height: 1, color: d.line),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              10,
                                              12,
                                              10,
                                            ),
                                            child: _ApptActions(appt: a),
                                          ),
                                        ],
                                      ),
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

  // ── mark arrived ──
  Future<void> _confirmArrived(BuildContext context, WidgetRef ref) async {
    final d = context.dent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as arrived?'),
        content: Text('Confirm ${appt.patientName} has arrived at the clinic.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ok,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
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

  /// Arrived → Complete, or undo the arrival if nothing has been done yet.
  Future<void> _stageAction(
    BuildContext context,
    WidgetRef ref,
    bool canUndo,
  ) async {
    final d = context.dent;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Finish this visit?'),
        content: Text(
          canUndo
              ? '${appt.patientName}\'s visit is finished — or undo the arrival '
                    'if they were marked by mistake.'
              : '${appt.patientName}\'s visit is finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
            child: const Text('Cancel'),
          ),
          if (canUndo)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: d.alert),
              onPressed: () => Navigator.pop(dialogCtx, 'undo'),
              child: const Text('Undo arrival'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ok,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, 'complete'),
            child: const Text('Mark Completed'),
          ),
        ],
      ),
    );

    final db = ref.read(appDatabaseProvider);
    if (choice == 'complete') {
      await db.setAppointmentStatus(appt.id, AppointmentStatus.completed.name);
    } else if (choice == 'undo') {
      await db.setAppointmentStatus(appt.id, AppointmentStatus.upcoming.name);
    }
  }

  // ── bill ──
  Future<void> _bill(BuildContext context, WidgetRef ref) async {
    final created = await showInvoiceEditor(
      context,
      patientId: appt.patientId,
      procedure: appt.procedure,
    );
    if (created == true) {
      final db = ref.read(appDatabaseProvider);
      await db.setAppointmentBilled(appt.id);
      // billing means the visit is done
      await db.setAppointmentStatus(appt.id, AppointmentStatus.completed.name);
    }
  }

  // ── prescribe ──
  Future<void> _prescribe(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final p = await (db.select(
      db.patients,
    )..where((t) => t.id.equals(appt.patientId))).getSingleOrNull();
    if (p == null || !context.mounted) return;

    await showPrescriptionEditor(
      context,
      patientId: p.id,
      patientUuid: p.uuid,
      patientName: p.fullName,
      allergies: p.allergies,
      presetAppointmentId: appt.id,
      presetAppointmentLabel:
          '${appt.startsAt.day}/${appt.startsAt.month}/${appt.startsAt.year} · ${appt.procedure}',
      presetDoctorName: appt.dentist,
    );
  }

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final billed =
        ref.watch(billedAppointmentIdsProvider).value?.contains(appt.id) ??
        false;
    final prescribed =
        ref.watch(prescribedAppointmentIdsProvider).value?.contains(appt.id) ??
        false;

    // role permissions
    final canBill = ref.watch(canProvider(Perm.billAppointments));
    final canPrescribe = ref.watch(canProvider(Perm.prescribe));

    final isDone = appt.status == AppointmentStatus.completed;
    final hasArrived =
        appt.status == AppointmentStatus.waiting ||
        appt.status == AppointmentStatus.inChair;

    // the visit has begun — no rescheduling or cancelling from here
    final started = isDone || hasArrived || billed || prescribed;
    // arrival can only be undone while nothing else has happened
    final canUndoArrival = hasArrived && !billed && !prescribed;

    final labelStyle = TextStyle(fontSize: 9.5.sp, fontWeight: FontWeight.w600);
    final pad = const EdgeInsets.symmetric(vertical: 10);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    // ── stage: Mark Arrived → Complete → Completed ──
    final Widget stage = isDone
        ? OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.task_alt_rounded, size: 15),
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: d.ok,
              side: BorderSide(color: d.line),
              padding: pad,
              shape: shape,
            ),
            label: Text('Completed', style: labelStyle),
          )
        : hasArrived
        ? FilledButton.icon(
            onPressed: () => _stageAction(context, ref, canUndoArrival),
            icon: const Icon(Icons.task_alt_rounded, size: 15),
            style: FilledButton.styleFrom(
              backgroundColor: d.ok,
              foregroundColor: Colors.white,
              padding: pad,
              shape: shape,
            ),
            label: Text('Complete', style: labelStyle),
          )
        : OutlinedButton.icon(
            onPressed: () => _confirmArrived(context, ref),
            icon: const Icon(Icons.how_to_reg_rounded, size: 15),
            style: OutlinedButton.styleFrom(
              foregroundColor: d.ok,
              side: BorderSide(color: d.ok),
              padding: pad,
              shape: shape,
            ),
            label: Text('Mark Arrived', style: labelStyle),
          );

    // ── prescribe ──
    final Widget prescribedDone = OutlinedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.check_circle_rounded, size: 15),
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: d.tealDeep,
        side: BorderSide(color: d.line),
        padding: pad,
        shape: shape,
      ),
      label: Text('Prescribed', style: labelStyle),
    );
    final Widget prescribeBtn = OutlinedButton.icon(
      onPressed: () => _prescribe(context, ref),
      icon: const Icon(Icons.medication_rounded, size: 15),
      style: OutlinedButton.styleFrom(
        foregroundColor: d.tealDeep,
        side: BorderSide(color: d.tealDeep.withValues(alpha: .55)),
        padding: pad,
        shape: shape,
      ),
      label: Text('Prescribe', style: labelStyle),
    );

    // ── bill ──
    final Widget billedDone = OutlinedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.check_circle_rounded, size: 15),
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: d.ok,
        side: BorderSide(color: d.line),
        padding: pad,
        shape: shape,
      ),
      label: Text('Billed', style: labelStyle),
    );
    final Widget billBtn = FilledButton.icon(
      onPressed: () => _bill(context, ref),
      icon: const Icon(Icons.receipt_long_rounded, size: 15),
      style: FilledButton.styleFrom(
        backgroundColor: d.ice,
        foregroundColor: AppPalette.onAccent,
        padding: pad,
        shape: shape,
      ),
      label: Text('Bill', style: labelStyle),
    );

    // ── manage: only before the visit begins ──
    final Widget manage = OutlinedButton.icon(
      onPressed: () => showAppointmentActions(context, appt),
      icon: const Icon(Icons.more_horiz_rounded, size: 15),
      style: OutlinedButton.styleFrom(
        foregroundColor: d.text2,
        side: BorderSide(color: d.line),
        padding: pad,
        shape: shape,
      ),
      label: Text('Manage', style: labelStyle),
    );

    // Done states always show (staff can see what happened);
    // action buttons only show with permission.
    final buttons = <Widget>[
      stage,
      if (prescribed) prescribedDone else if (canPrescribe) prescribeBtn,
      if (billed) billedDone else if (canBill) billBtn,
      if (!started) manage,
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}
