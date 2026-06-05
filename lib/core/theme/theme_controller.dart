import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Active ThemeMode. Defaults to light. TODO(Settings/Phase): persist to Drift.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void toggle() => state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  void set(ThemeMode m) => state = m;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
