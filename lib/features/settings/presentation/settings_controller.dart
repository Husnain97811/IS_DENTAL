import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/views.dart';

final clinicProfileProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.clinicProfile).getSingleOrNull();
});

final staffProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(appDatabaseProvider);
  final session = ref.watch(authControllerProvider);

  final query = db.select(db.users)..where((t) => t.isDeleted.equals(false));

  // Admin sees only their own branch; owner sees everyone.
  if (session != null && session.role == AppRole.admin) {
    query.where((t) => t.branchId.equals(session.branchId ?? ''));
  }

  return query.watch();
});
