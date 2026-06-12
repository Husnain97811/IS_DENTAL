import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/views.dart';
import '../../features/branches/presentation/branch_controller.dart';

class AuthController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  Future<String?> login(String username, String password) async {
    final r = await ref.read(authServiceProvider).login(username, password);
    if (r.session != null) {
      state = r.session;
      // owner/admin → null (all branches); branch staff → pinned to their branch
      await ref.read(activeBranchProvider.notifier).select(r.session!.branchId);
    }
    return r.error;
  }

  void logout() {
    state = null;
    ref.read(activeBranchProvider.notifier).select(null);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);
