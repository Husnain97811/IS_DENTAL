import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/utils/monotonic_clock.dart';
import 'package:is_dental/licensing/data/license_verifier.dart';

import 'activity_log.dart';
import 'hub_pin.dart';

/// Who may open the Detailed Reporting Hub, and whether the plan has it.
///
/// [allowed]: the owner always; an admin only when the owner ticked
/// "Admins can open the Hub". [onPlan]: Standard or Premium.
/// A record, so listeners only fire when a value really changes.
typedef HubAccess = ({bool allowed, bool onPlan});

final hubAccessProvider = Provider<HubAccess>((ref) {
  final role = ref.watch(authControllerProvider.select((s) => s?.role));
  final onPlan = ref.watch(entitlementsProvider.select((e) => e.reportingHub));
  final adminOk =
      role == AppRole.admin && ref.watch(canProvider(Perm.viewReportingHub));
  return (allowed: role == AppRole.owner || adminOk, onPlan: onPlan);
});

enum HubCheckResult { ok, wrong, locked }

class HubCheck {
  const HubCheck.ok() : result = HubCheckResult.ok, triesLeft = 0, until = null;
  const HubCheck.wrong(this.triesLeft)
    : result = HubCheckResult.wrong,
      until = null;
  const HubCheck.locked(DateTime this.until)
    : result = HubCheckResult.locked,
      triesLeft = 0;

  final HubCheckResult result;
  final int triesLeft;
  final DateTime? until;

  bool get ok => result == HubCheckResult.ok;
}

/// PIN, lockout, reset codes and the activity record for the Hub.
///
/// Lockout counters live in this computer's settings (5 wrong → 5 minutes
/// here). The PIN hash lives on the user row and syncs, so one PIN works on
/// every computer.
class HubSecurity {
  HubSecurity(this._db, this._clock);

  final AppDatabase _db;
  final MonotonicClock _clock;
  final _verifier = LicenseVerifier();

  static const maxTries = 5;
  static const lockFor = Duration(minutes: 5);
  static const _kNonces = 'hub_reset_nonces';

  String _key(User u) => u.uuid.isEmpty ? 'id${u.id}' : u.uuid;

  /// Fresh copy of the signed-in user's row (PIN hash included).
  Future<User?> userFor(AuthSession s) => _db.findActiveUser(s.username);

  bool hasPin(User u) => (u.hubPinHash ?? '').isNotEmpty;

  /// When this computer's lockout ends, or null when not locked.
  Future<DateTime?> lockedUntil(User u) async {
    final ms = int.tryParse(
      await _db.getSetting('hub_pin_lock:${_key(u)}') ?? '',
    );
    if (ms == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return at.isAfter(DateTime.now()) ? at : null;
  }

  Future<HubCheck> checkPin(User u, AuthSession s, String pin) async {
    final until = await lockedUntil(u);
    if (until != null) return HubCheck.locked(until);
    final stored = u.hubPinHash ?? '';
    if (stored.isNotEmpty && await HubPin.verify(pin, stored)) {
      await _clearFails(u);
      return const HubCheck.ok();
    }
    return _fail(u, s, 'PIN');
  }

  /// The login password, asked once before the first PIN is set.
  Future<HubCheck> checkPassword(User u, AuthSession s, String password) async {
    final until = await lockedUntil(u);
    if (until != null) return HubCheck.locked(until);
    final hash = u.passwordHash;
    final ok = await Isolate.run(() {
      try {
        return BCrypt.checkpw(password, hash);
      } catch (_) {
        return false;
      }
    });
    if (ok) {
      await _clearFails(u);
      return const HubCheck.ok();
    }
    return _fail(u, s, 'password');
  }

  /// Saves a new PIN (hash only) and records [kind] in the activity log.
  Future<void> setPin(
    User u,
    AuthSession s,
    String pin, {
    required String kind,
    String detail = '',
  }) async {
    final hash = await HubPin.hash(pin);
    final now = DateTime.now();
    await (_db.update(_db.users)..where((t) => t.id.equals(u.id))).write(
      UsersCompanion(
        hubPinHash: Value(hash),
        hubPinSetAt: Value(now),
        updatedAt: Value(now), // → pushed on the next sync
      ),
    );
    await _clearFails(u);
    await _db.setSetting('hub_pin_lock:${_key(u)}', '');
    await log(s, kind, detail: detail);
  }

  /// Checks a pasted reset code without using it.
  Future<({HubResetCode? code, String? error})> checkResetCode(
    User u,
    String raw,
  ) async {
    if (raw.trim().isEmpty) {
      return (code: null, error: 'Paste the reset code first.');
    }
    final c = HubResetCode.parse(raw, _verifier.verifyCanonical);
    if (c == null) {
      return (
        code: null,
        error:
            'This is not a valid reset code. Copy the whole code and try again.',
      );
    }
    final clinicId = await _db.currentClinicId();
    if (clinicId == null || c.clinicId != clinicId) {
      return (code: null, error: 'This code was made for a different clinic.');
    }
    if (c.username.trim().toLowerCase() != u.username.trim().toLowerCase()) {
      return (
        code: null,
        error: 'This code was made for the user "${c.username}", not you.',
      );
    }
    // Monotonic clock — moving the computer's date back can't revive it.
    if ((await _clock.now()).isAfter(c.expiresAt)) {
      return (
        code: null,
        error: 'This code has expired. Ask Inover Studio for a new one.',
      );
    }
    if (await _nonceUsed(c.nonce)) {
      return (code: null, error: 'This code has already been used.');
    }
    return (code: c, error: null);
  }

  /// Uses a reset code and sets [newPin]. Returns an error message or null.
  Future<String?> redeemReset(
    User u,
    AuthSession s,
    String raw,
    String newPin,
  ) async {
    final r = await checkResetCode(u, raw);
    if (r.error != null) return r.error;
    final nonce = r.code!.nonce;
    final used =
        (await _db.getSetting(_kNonces) ?? '')
            .split(',')
            .where((e) => e.isNotEmpty)
            .toList()
          ..add(nonce);
    await _db.setSetting(
      _kNonces,
      used.sublist(used.length > 30 ? used.length - 30 : 0).join(','),
    );
    // The nonce also goes into the synced log, so the same code can't be
    // used again on another computer.
    await setPin(u, s, newPin, kind: 'hub_pin_reset', detail: 'code:$nonce');
    return null;
  }

  Future<bool> _nonceUsed(String nonce) async {
    final local = (await _db.getSetting(_kNonces) ?? '').split(',');
    if (local.contains(nonce)) return true;
    final row =
        await (_db.select(_db.activityEvents)
              ..where(
                (t) =>
                    t.kind.equals('hub_pin_reset') &
                    t.detail.equals('code:$nonce'),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<HubCheck> _fail(User u, AuthSession s, String what) async {
    final k = _key(u);
    final n =
        (int.tryParse(await _db.getSetting('hub_pin_fail:$k') ?? '') ?? 0) + 1;
    if (n >= maxTries) {
      final until = DateTime.now().add(lockFor);
      await _db.setSetting(
        'hub_pin_lock:$k',
        '${until.millisecondsSinceEpoch}',
      );
      await _db.setSetting('hub_pin_fail:$k', '0');
      await log(s, 'hub_pin_locked', detail: '$maxTries wrong tries ($what)');
      return HubCheck.locked(until);
    }
    await _db.setSetting('hub_pin_fail:$k', '$n');
    await log(s, 'hub_pin_wrong', detail: what);
    return HubCheck.wrong(maxTries - n);
  }

  Future<void> _clearFails(User u) =>
      _db.setSetting('hub_pin_fail:${_key(u)}', '0');

  /// Adds one line to the activity record. Never throws — a failed log line
  /// must not stop the owner using the Hub.
  Future<void> log(AuthSession? s, String kind, {String detail = ''}) =>
      logActivity(_db, kind, session: s, detail: detail);

  /// Latest Hub activity, newest first — Settings and System health.
  Stream<List<ActivityEventRow>> watchHubEvents({int limit = 12}) =>
      (_db.select(_db.activityEvents)
            ..where((t) => t.kind.like('hub_%') & t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)])
            ..limit(limit))
          .watch();
}

final hubSecurityProvider = Provider<HubSecurity>(
  (ref) => HubSecurity(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
  ),
);

final hubEventsProvider = StreamProvider.autoDispose<List<ActivityEventRow>>(
  (ref) => ref.watch(hubSecurityProvider).watchHubEvents(),
);

/// When the signed-in user's Hub PIN was set (null = not set yet).
final myHubPinSetAtProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  final username = ref.watch(authControllerProvider.select((s) => s?.username));
  if (username == null) return Stream.value(null);
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)
        ..where((t) => t.username.equals(username) & t.isDeleted.equals(false)))
      .watchSingleOrNull()
      .map((u) => (u?.hubPinHash ?? '').isEmpty ? null : u?.hubPinSetAt);
});

/// Human words for an activity kind.
String hubEventLabel(String kind) => switch (kind) {
  'hub_open' => 'Opened the Hub',
  'hub_exit' => 'Left the Hub',
  'hub_pin_wrong' => 'Wrong PIN or password',
  'hub_pin_locked' => 'Locked out for 5 minutes',
  'hub_pin_set' => 'Set a Hub PIN',
  'hub_pin_changed' => 'Changed the Hub PIN',
  'hub_pin_reset' => 'Reset the PIN with a code',
  'hub_idle_lock' => 'Hub locked',
  'hub_idle_exit' => 'Hub closed (no activity)',
  'hub_admins_on' => 'Allowed admins into the Hub',
  'hub_admins_off' => 'Stopped admins opening the Hub',
  'hub_export' => 'Downloaded the owner report',
  'sign_in' => 'Signed in',
  'sign_in_failed' => 'Failed sign-in',
  'sign_out' => 'Signed out',
  'auto_sign_out' => 'Signed out (no activity)',
  'discount_given' => 'Gave a discount',
  'price_changed' => 'Changed a price',
  'procedure_added' => 'Added a procedure',
  'procedure_removed' => 'Removed a procedure',
  'rate_changed' => 'Changed a commission rate',
  _ => kind,
};
