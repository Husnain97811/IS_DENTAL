import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import '../../../core/constants/views.dart';

final clinicProfileProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.clinicProfile).getSingleOrNull();
});

/// Total active users across ALL branches (for seat counting).
final totalStaffCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)..where((t) => t.isDeleted.equals(false)))
      .watch()
      .map((rows) => rows.length);
});

final staffProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(appDatabaseProvider);
  final session = ref.watch(authControllerProvider);
  final active = ref.watch(activeBranchProvider);

  final query = db.select(db.users)..where((t) => t.isDeleted.equals(false));

  if (session != null && session.role == AppRole.admin) {
    // admin: always pinned to own branch
    query.where((t) => t.branchId.equals(session.branchId ?? ''));
  } else if (active != null) {
    // owner with a specific branch selected
    query.where((t) => t.branchId.equals(active));
  }

  return query.watch();
});
