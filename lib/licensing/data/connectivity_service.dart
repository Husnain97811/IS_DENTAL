import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/app_database.dart';
import '../../core/utils/monotonic_clock.dart';

enum HeartbeatResult { ok, subscriptionInvalid, offline }

class ConnectivityService {
  ConnectivityService(this._db, this._clock);
  final AppDatabase _db;
  final MonotonicClock _clock;

  static const window = Duration(hours: 48);
  static const _kLastContact = 'last_contact_ms';

  Future<Duration?> sinceLastContact() async {
    final last = int.tryParse(await _db.getSetting(_kLastContact) ?? '');
    if (last == null) return null;
    final now = await _clock.now();
    return Duration(milliseconds: now.millisecondsSinceEpoch - last);
  }

  Future<bool> withinWindow() async {
    final s = await sinceLastContact();
    return s != null && s <= window;
  }

  /// Records a successful server contact (also called right after activation).
  Future<void> seedContact() async {
    final now = await _clock.now();
    await _db.setSetting(_kLastContact, '${now.millisecondsSinceEpoch}');
  }

  Future<HeartbeatResult> heartbeat({
    required String clinicId,
    required DateTime licenseExpiry,
  }) async {
    try {
      final active = await _serverSubscriptionActive(clinicId);
      if (active == null) return HeartbeatResult.offline; // unreachable
      if (!active)
        return HeartbeatResult
            .subscriptionInvalid; // suspended/expired server-side
      await seedContact();
      // TODO(Phase 5): SyncEngine.syncAll() — push/pull every table once they exist.
      return HeartbeatResult.ok;
    } catch (_) {
      return HeartbeatResult.offline;
    }
  }

  /// true = active, false = suspended/expired server-side, null = unreachable.
  Future<bool?> _serverSubscriptionActive(String clinicId) async {
    // TODO(Phase 5): Supabase RPC `subscription_status(clinic_id)` behind RLS,
    // returning {status, expiresAt}. Until wired this returns null (offline),
    // so the gate behaves honestly in dev. Flip to `true` to test the unlock path.
    return null;
  }
}

final connectivityServiceProvider = Provider(
  (ref) => ConnectivityService(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
  ),
);
