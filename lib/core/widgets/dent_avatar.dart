import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_typography.dart';

class DentAvatar extends StatelessWidget {
  const DentAvatar(
    this.initials, {
    super.key,
    required this.bg,
    required this.fg,
    this.size = 34,
    this.radius = 10,
  });
  final String initials;
  final Color bg, fg;
  final double size, radius;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(
      initials,
      style: TextStyle(
        fontFamily: AppFonts.display,
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: 10.sp,
      ),
    ),
  );
}
