import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'app_typography.dart';
import 'dent_colors.dart';

class AppTheme {
  AppTheme._();
  static ThemeData get light => _build(Brightness.light, DentColors.light);
  static ThemeData get dark => _build(Brightness.dark, DentColors.dark);

  static ThemeData _build(Brightness b, DentColors d) => ThemeData(
        useMaterial3: true,
        brightness: b,
        colorScheme: ColorScheme(
          brightness: b,
          primary: d.ice, onPrimary: AppPalette.onAccent,
          secondary: d.teal, onSecondary: AppPalette.onAccent,
          surface: d.surface, onSurface: d.text1,
          error: d.alert, onError: Colors.white,
        ),
        scaffoldBackgroundColor: d.canvas,
        fontFamily: AppFonts.body,
        textTheme: AppTypography.textTheme(d.text1),
        dividerColor: d.line,
        splashFactory: InkSparkle.splashFactory,
        extensions: [d],
      );
}
