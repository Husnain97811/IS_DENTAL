import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../data/branch_repository_impl.dart';
import '../domain/branch.dart';
import '../domain/branch_repository.dart';

final branchRepositoryProvider = Provider<BranchRepository>(
  (ref) => BranchRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final branchesStreamProvider = StreamProvider.autoDispose<List<Branch>>(
  (ref) => ref.watch(branchRepositoryProvider).watchBranches(),
);

/// Active branch uuid, persisted to settings so it survives restarts.
class ActiveBranchController extends Notifier<String?> {
  @override
  String? build() {
    ref.read(appDatabaseProvider).getSetting('active_branch').then((v) {
      if (v != null && v.isNotEmpty) state = v;
    });
    return null;
  }

  Future<void> select(String? uuid) async {
    state = uuid;
    await ref.read(appDatabaseProvider).setSetting('active_branch', uuid ?? '');
  }
}

final activeBranchProvider = NotifierProvider<ActiveBranchController, String?>(
  ActiveBranchController.new,
);
