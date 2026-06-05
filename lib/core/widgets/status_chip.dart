import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_radii.dart';
import '../theme/dent_colors.dart';

enum ChipKind { inProgress, waiting, done, upcoming, overdue }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.kind});
  final String label;
  final ChipKind kind;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final d = context.dent;
    final (Color bg, Color fg) = switch (kind) {
      ChipKind.inProgress => (d.ice.withValues(alpha: .14), dark ? d.ice : const Color(0xFF0284C7)),
      ChipKind.waiting => (d.warn.withValues(alpha: .14), dark ? d.warn : const Color(0xFFD97706)),
      ChipKind.done => (d.ok.withValues(alpha: .13), dark ? const Color(0xFF34D399) : const Color(0xFF15803D)),
      ChipKind.upcoming => (d.text3.withValues(alpha: .13), d.text2),
      ChipKind.overdue => (d.alert.withValues(alpha: .14), dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 7.5.sp, fontWeight: FontWeight.w600)),
    );
  }
}
