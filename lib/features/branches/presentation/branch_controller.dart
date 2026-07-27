import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
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

/// Active branch uuid, persisted to settings. NEVER "all"/null once branches
/// exist — always resolves to a real branch (primary, else first).
class ActiveBranchController extends Notifier<String?> {
  @override
  String? build() {
    final branches = ref.watch(branchesStreamProvider).value ?? const [];

    ref.read(appDatabaseProvider).getSetting('active_branch').then((saved) {
      if (branches.isEmpty) return;
      final validSaved =
          (saved != null &&
              saved.isNotEmpty &&
              branches.any((b) => b.uuid == saved))
          ? saved
          : null;
      final resolved =
          validSaved ??
          (branches.where((b) => b.isPrimary).firstOrNull?.uuid ??
              branches.first.uuid);
      state = resolved;
      ref.read(appDatabaseProvider).setSetting('active_branch', resolved);
    });

    if (branches.isEmpty) return null;
    return branches.where((b) => b.isPrimary).firstOrNull?.uuid ??
        branches.first.uuid;
  }

  Future<void> select(String? uuid) async {
    if (uuid == null || uuid.isEmpty) return;
    state = uuid;
    await ref.read(appDatabaseProvider).setSetting('active_branch', uuid);
  }
}

final activeBranchProvider = NotifierProvider<ActiveBranchController, String?>(
  ActiveBranchController.new,
);
