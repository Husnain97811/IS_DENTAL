import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/db/app_database.dart';

// change this import to wherever your appDatabaseProvider lives

/// Watches the language column straight from the DB row,
/// so the chips update the moment the value changes.
final branchWaLanguageProvider = StreamProvider.family<String, int>((
  ref,
  branchId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.branches)..where((t) => t.id.equals(branchId)))
      .watchSingle()
      .map((row) => row.waLanguage);
});
