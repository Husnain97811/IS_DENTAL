import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_radii.dart';
import '../theme/app_typography.dart';
import '../theme/dent_colors.dart';

enum KpiTone { blue, teal, amber, slate }

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.icon, required this.tone, required this.label, required this.value, this.unit, this.delta, this.deltaUp = true});
  final IconData icon;
  final KpiTone tone;
  final String label, value;
  final String? unit, delta;
  final bool deltaUp;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color ibg, Color ifg) = switch (tone) {
      KpiTone.blue => (d.ice.withValues(alpha: .13), dark ? d.ice : const Color(0xFF0284C7)),
      KpiTone.teal => (d.teal.withValues(alpha: .14), d.tealDeep),
      KpiTone.amber => (d.warn.withValues(alpha: .13), dark ? d.warn : const Color(0xFFD97706)),
      KpiTone.slate => (d.text3.withValues(alpha: .13), d.text2),
    };
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: d.surface, borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: d.line), boxShadow: d.shadowCard,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(right: -30, top: -30, child: Container(width: 120, height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [d.ice.withValues(alpha: .13), d.ice.withValues(alpha: 0)])))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: ibg, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: ifg, size: 11.sp)),
            SizedBox(height: 1.6.h),
            Text(label, style: TextStyle(color: d.text3, fontSize: 8.5.sp, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            RichText(text: TextSpan(
              text: value,
              style: TextStyle(fontFamily: AppFonts.display, color: d.text1, fontSize: 14.sp, fontWeight: FontWeight.w600, letterSpacing: -.5),
              children: unit == null ? null : [
                TextSpan(text: ' $unit', style: TextStyle(fontFamily: AppFonts.display, color: d.text4, fontSize: 9.sp, fontWeight: FontWeight.w500)),
              ],
            )),
            if (delta != null) ...[
              const SizedBox(height: 9),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (deltaUp ? d.ok : d.alert).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadii.pill)),
                child: Text('${deltaUp ? '▲' : '▼'} ${delta!}',
                  style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.w600,
                    color: deltaUp ? (dark ? const Color(0xFF34D399) : const Color(0xFF15803D)) : (dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C))))),
            ],
          ]),
        ]),
      ),
    );
  }
}
