import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud/data/cloud_service.dart';
import '../../cloud/data/sync_engine.dart';
import '../../core/db/app_database.dart';
import '../../core/utils/monotonic_clock.dart';

enum HeartbeatResult { ok, subscriptionInvalid, offline }

class ConnectivityService {
  ConnectivityService(this._db, this._clock, this._cloud, this._sync);
  final AppDatabase _db;
  final MonotonicClock _clock;
  final CloudService _cloud;
  final SyncEngine _sync;

  // static const window = Duration(hours: 48);
  static const window = Duration(seconds: 48);
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
      // 1) Reach the server (sign in if needed).
      // ensureSignedIn is a void method that throws on failure, so just await it
      await _cloud.ensureSignedIn();

      // 2) Validate the subscription server-side.
      final sub = await _cloud.subscription(clinicId);
      if (sub == null) return HeartbeatResult.offline; // unreachable
      final serverExpired =
          sub.expiresAt != null && DateTime.now().isAfter(sub.expiresAt!);
      if (sub.status != 'active' || serverExpired) {
        return HeartbeatResult.subscriptionInvalid;
      }

      // 3) Success → reset the 48h window, then sync (best-effort).
      await seedContact();
      try {
        await _sync.syncAll(clinicId);
      } catch (_) {
        // Sync failures don't block access; the data is safe locally.
      }
      return HeartbeatResult.ok;
    } catch (_) {
      return HeartbeatResult.offline;
    }
  }
}

final connectivityServiceProvider = Provider(
  (ref) => ConnectivityService(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
    ref.watch(cloudServiceProvider),
    ref.watch(syncEngineProvider),
  ),
);
