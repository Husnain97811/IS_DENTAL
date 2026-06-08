import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_avatar.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/appointment.dart';

class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appt});
  final Appointment appt;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (
      Color bar,
      Color avBg,
      Color avFg,
      ChipKind chip,
      String label,
    ) = switch (appt.status) {
      AppointmentStatus.inChair => (
        d.ice,
        d.ice.withValues(alpha: .15),
        dark ? d.ice : const Color(0xFF0284C7),
        ChipKind.inProgress,
        'In Chair',
      ),
      AppointmentStatus.waiting => (
        d.warn,
        d.warn.withValues(alpha: .14),
        dark ? d.warn : const Color(0xFFD97706),
        ChipKind.waiting,
        'Waiting',
      ),
      AppointmentStatus.completed => (
        d.ok,
        d.ok.withValues(alpha: .13),
        dark ? const Color(0xFF34D399) : const Color(0xFF15803D),
        ChipKind.done,
        'Completed',
      ),
      AppointmentStatus.upcoming => (
        d.text4,
        d.text3.withValues(alpha: .13),
        d.text2,
        ChipKind.upcoming,
        'Upcoming',
      ),
      AppointmentStatus.noShow => (
        d.alert,
        d.alert.withValues(alpha: .14),
        dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C),
        ChipKind.overdue,
        'No-show',
      ),
    };
    String two(int v) => v.toString().padLeft(2, '0');
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              child: Text(
                '${two(appt.startsAt.hour)}:${two(appt.startsAt.minute)}',
                style: AppTypography.mono(
                  size: 8.sp,
                  color: d.text3,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 4,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: bar,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            DentAvatar(
              appt.patientInitials,
              bg: avBg,
              fg: avFg,
              size: 38,
              radius: 11,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          appt.patientName,
                          style: TextStyle(
                            fontSize: 9.5.sp,
                            fontWeight: FontWeight.w600,
                            color: d.text1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 7),
                      StatusChip(label, kind: chip),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${appt.procedure} · ${appt.durationMin} min',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  appt.dentist,
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 8.5.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Chair ${two(appt.chair)}',
                  style: TextStyle(color: d.text4, fontSize: 8.sp),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
