import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_radii.dart';
import '../theme/dent_colors.dart';

class StatBarRow extends StatelessWidget {
  const StatBarRow({super.key, required this.label, required this.fraction, required this.trailing, this.trailingColor, this.showTrack = true});
  final String label;
  final double fraction; // 0..1
  final String trailing;
  final Color? trailingColor;
  final bool showTrack;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.line))),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: d.text2, fontSize: 9.sp, fontWeight: FontWeight.w500))),
        if (showTrack) ...[
          Container(width: 110, height: 7,
            decoration: BoxDecoration(color: d.surface2, borderRadius: BorderRadius.circular(AppRadii.pill)),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
              builder: (_, t, __) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: t,
                child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [d.ice, d.teal]), borderRadius: BorderRadius.circular(AppRadii.pill)))),
            )),
          const SizedBox(width: 12),
        ],
        Text(trailing, style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 8.5.sp, fontWeight: FontWeight.w600, color: trailingColor ?? d.text1)),
      ]),
    );
  }
}
