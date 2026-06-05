import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../domain/auth_session.dart';

class AuthService {
  AuthService(this._db);
  final AppDatabase _db;

  static const _failKey = 'login_fail_count';
  static const _lockKey = 'login_locked_until_ms';
  static const _maxFails = 5;
  static const _lockFor = Duration(minutes: 5);

  Future<({AuthSession? session, String? error})> login(
    String username,
    String password,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lockedUntil = int.tryParse(await _db.getSetting(_lockKey) ?? '');
    if (lockedUntil != null && nowMs < lockedUntil) {
      final mins = ((lockedUntil - nowMs) / 60000).ceil();
      return (
        session: null,
        error: 'Too many attempts — try again in $mins min.',
      );
    }

    final user = await _db.findActiveUser(username.trim());
    final ok = user != null && BCrypt.checkpw(password, user.passwordHash);
    if (!ok) {
      final fails =
          (int.tryParse(await _db.getSetting(_failKey) ?? '') ?? 0) + 1;
      if (fails >= _maxFails) {
        await _db.setSetting(_lockKey, '${nowMs + _lockFor.inMilliseconds}');
        await _db.setSetting(_failKey, '0');
        return (
          session: null,
          error: 'Too many attempts — locked for ${_lockFor.inMinutes} min.',
        );
      }
      await _db.setSetting(_failKey, '$fails');
      return (session: null, error: 'Incorrect username or password.');
    }

    await _db.setSetting(_failKey, '0');
    await _db.setSetting(_lockKey, '0');
    return (
      session: AuthSession(
        userId: user.id,
        fullName: user.fullName,
        username: user.username,
        role: roleFromString(user.role),
      ),
      error: null,
    );
  }
}

final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(appDatabaseProvider)),
);
