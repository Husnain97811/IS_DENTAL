import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';

final clinicProfileProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.clinicProfile).getSingleOrNull();
});

final staffProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)..where((t) => t.isDeleted.equals(false))).watch();
});
