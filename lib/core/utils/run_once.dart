import 'package:flutter/services.dart';

/// Actions currently running, by key.
final _running = <Object>{};

/// Runs [task] unless the same [key] is already running — a double click,
/// or a second click while a dialog is still opening, does nothing.
///
/// Use a key that names the thing being changed (`'bill:42'`,
/// `'payout:dr ali:2026-10'`), so two different actions never block each
/// other. Returns null when it was skipped.
Future<T?> runOnce<T>(Object key, Future<T> Function() task) async {
  if (!_running.add(key)) return null;
  try {
    return await task();
  } finally {
    _running.remove(key);
  }
}

/// Rupee amounts as people type them: "1500", "1,500", "Rs 1,500".
/// Returns null for anything that isn't a whole number, so a typo is
/// reported instead of being saved as 0.
int? parseRupees(String text) {
  // Dart's RegExp has no inline (?i) flag — case-insensitivity is a parameter
  final t = text
      .replaceAll(RegExp(r'rs\.?', caseSensitive: false), '')
      .replaceAll(',', '')
      .trim();
  if (t.isEmpty) return 0;
  return int.tryParse(t);
}

/// Lets only digits and commas into an amount field.
final rupeesInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
  LengthLimitingTextInputFormatter(12),
];

/// A percentage: digits and one decimal point, e.g. "40" or "37.5".
final percentInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?')),
];
