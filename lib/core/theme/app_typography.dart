import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

class AppFonts {
  AppFonts._();
  static const display = 'Sora', body = 'Manrope', mono = 'JetBrains Mono';
}

class AppTypography {
  AppTypography._();

  /// Built inside the Sizer builder so `.sp` resolves. [c] = primary text color.
  static TextTheme textTheme(Color c) => TextTheme(
        displayLarge: TextStyle(fontFamily: AppFonts.display, fontSize: 16.sp, fontWeight: FontWeight.w600, color: c, letterSpacing: -.2),
        headlineSmall: TextStyle(fontFamily: AppFonts.display, fontSize: 13.sp, fontWeight: FontWeight.w600, color: c),
        titleLarge: TextStyle(fontFamily: AppFonts.display, fontSize: 11.sp, fontWeight: FontWeight.w600, color: c),
        titleMedium: TextStyle(fontFamily: AppFonts.body, fontSize: 10.5.sp, fontWeight: FontWeight.w600, color: c),
        bodyLarge: TextStyle(fontFamily: AppFonts.body, fontSize: 10.sp, fontWeight: FontWeight.w500, color: c),
        bodyMedium: TextStyle(fontFamily: AppFonts.body, fontSize: 9.5.sp, fontWeight: FontWeight.w400, color: c),
        bodySmall: TextStyle(fontFamily: AppFonts.body, fontSize: 9.sp, fontWeight: FontWeight.w400, color: c),
        labelLarge: TextStyle(fontFamily: AppFonts.body, fontSize: 9.5.sp, fontWeight: FontWeight.w600, color: c),
        labelSmall: TextStyle(fontFamily: AppFonts.body, fontSize: 7.5.sp, fontWeight: FontWeight.w700, color: c, letterSpacing: .7),
      );

  static TextStyle mono({double? size, FontWeight weight = FontWeight.w500, Color? color}) =>
      TextStyle(fontFamily: AppFonts.mono, fontSize: size ?? 9.sp, fontWeight: weight, color: color);
}
