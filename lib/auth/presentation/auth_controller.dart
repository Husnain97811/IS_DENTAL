import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:is_dental/features/hub/data/activity_log.dart';
import '../../core/constants/views.dart';

class AuthController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  Future<String?> login(String username, String password) async {
    final r = await ref.read(authServiceProvider).login(username, password);
    final db = ref.read(appDatabaseProvider);
    if (r.session != null) {
      state = r.session;
      // owner/admin → null (all branches); branch staff → pinned to their branch
      await ref.read(activeBranchProvider.notifier).select(r.session!.branchId);
      // Reporting Hub → Watch list: who signed in, when, on which computer.
      unawaited(logActivity(db, 'sign_in', session: r.session));
    } else if (username.trim().isNotEmpty) {
      // Recorded under the person's name when the username exists, so
      // their failed and good sign-ins sit together in the Watch list.
      unawaited(() async {
        User? u;
        try {
          u = await db.findActiveUser(username.trim());
        } catch (_) {}
        await logActivity(
          db,
          'sign_in_failed',
          userName: u?.fullName ?? username.trim(),
          detail: r.error ?? '',
        );
      }());
    }
    return r.error;
  }

  /// [auto] — signed out by IdleLock after no activity.
  void logout({bool auto = false}) {
    final s = state;
    if (s != null) {
      unawaited(
        logActivity(
          ref.read(appDatabaseProvider),
          auto ? 'auto_sign_out' : 'sign_out',
          session: s,
        ),
      );
    }
    state = null;
    ref.read(activeBranchProvider.notifier).select(null);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

/// Idle auto-logout timeout, in minutes. 0 = never.
final idleTimeoutProvider = StateProvider<int>((_) => 10);
