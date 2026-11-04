import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:is_dental/features/hub/data/activity_log.dart';
import '../../core/constants/views.dart';

/// Why this computer signed someone out by itself — shown once on the
/// sign-in screen ("You have been logged out"), cleared by the next
/// successful sign-in or the close button.
final signOutNoticeProvider = StateProvider<String?>((_) => null);

class AuthController extends Notifier<AuthSession?> {
  /// Watches the signed-in person's own login row while they are signed in.
  StreamSubscription<User?>? _self;

  @override
  AuthSession? build() {
    ref.onDispose(() => _self?.cancel());
    return null;
  }

  Future<String?> login(String username, String password) async {
    final r = await ref.read(authServiceProvider).login(username, password);
    final db = ref.read(appDatabaseProvider);
    if (r.session != null) {
      state = r.session;
      ref.read(signOutNoticeProvider.notifier).state = null;
      _watchOwnLogin(r.session!);
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
    _end();
  }

  /// Signs the person out the moment their own login changes in a way that
  /// must end the session — on THIS computer, or on another computer or the
  /// owner phone (the change arrives here live, within seconds):
  ///  • the login was deactivated / removed;
  ///  • the password was changed.
  /// A role or permission change does NOT sign anyone out.
  void _watchOwnLogin(AuthSession s) {
    _self?.cancel();
    final db = ref.read(appDatabaseProvider);
    String? password; // the password hash this session signed in with
    String? uuid; // and whose login it is
    _self = (db.select(db.users)..where((t) => t.id.equals(s.userId)))
        .watchSingleOrNull()
        .listen(
          (u) {
            final now = state;
            if (now == null || now.userId != s.userId) return;
            // The row is only ever GONE during Restore from cloud (it
            // empties and refills the table) — never sign out mid-restore.
            if (u == null) return;
            uuid ??= u.uuid;
            // after a restore the same local id can belong to someone else
            if (u.uuid != uuid) return;
            if (u.isDeleted) {
              _forceOut(
                now,
                'deactivated',
                'Your login was deactivated by the clinic. Ask the owner '
                    'if you need access again.',
              );
              return;
            }
            password ??= u.passwordHash;
            if (u.passwordHash != password) {
              _forceOut(
                now,
                'password_changed',
                'Your password was changed. Sign in with the new password.',
              );
            }
          },
          // never let a database hiccup end someone's session
          onError: (Object _) {},
        );
  }

  void _forceOut(AuthSession s, String why, String message) {
    unawaited(
      logActivity(
        ref.read(appDatabaseProvider),
        'forced_sign_out',
        session: s,
        detail: why,
      ),
    );
    ref.read(signOutNoticeProvider.notifier).state = message;
    _end();
  }

  void _end() {
    _self?.cancel();
    _self = null;
    state = null;
    ref.read(activeBranchProvider.notifier).select(null);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

/// Idle auto-logout timeout, in minutes. 0 = never.
final idleTimeoutProvider = StateProvider<int>((_) => 10);
