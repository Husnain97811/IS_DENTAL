import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/booking_conflicts.dart';

/// Top of the Appointments screen: the next double booking from today on,
/// with a button that opens that day. Hidden when there is none (normally).
///
/// Shows clashes that touch the branch in view (all branches for the owner
/// view), because a doctor or a patient can't be in two branches at once.
class BookingConflictBanner extends ConsumerWidget {
  const BookingConflictBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final all = ref.watch(upcomingConflictsProvider).value ?? const [];
    final active = ref.watch(activeBranchProvider);
    final pairs = active == null
        ? all
        : all
              .where((p) => p.a.branchId == active || p.b.branchId == active)
              .toList();
    if (pairs.isEmpty) return const SizedBox.shrink();

    final first = pairs.first;
    final a = first.a, b = first.b;
    final when = '${conflictDay(a.start)}, ${conflictTime(a.start)}';
    final what = first.sameDoctor
        ? '${a.dentist} has ${a.patientName} and ${b.patientName} at the same time.'
        : '${a.patientName} is booked with ${a.dentist} and with '
              '${b.dentist} at the same time.';
    final title = pairs.length == 1
        ? 'Double booking · $when'
        : '${pairs.length} double bookings · the first on $when';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: d.alert.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.alert.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_rounded, color: d.alert, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: d.alert,
                    fontSize: 9.5.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$what Reschedule one of them.',
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 9.sp,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () {
              // open that day, with every doctor showing
              ref.read(dentistFilterProvider.notifier).state = null;
              ref.read(viewedMonthProvider.notifier).state = (
                year: a.start.year,
                month: a.start.month,
              );
              ref.read(selectedDateProvider.notifier).state = DateTime(
                a.start.year,
                a.start.month,
                a.start.day,
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: d.alert,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Show',
              style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
