import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';

class MonotonicClock {
  MonotonicClock(this._db);
  final AppDatabase _db;
  static const _k = 'clock_high_ms';

  /// Never decreases: returns max(systemNow, highestEverSeen) and persists it.
  Future<DateTime> now() async {
    final sys = DateTime.now().millisecondsSinceEpoch;
    final high = int.tryParse(await _db.getSetting(_k) ?? '') ?? 0;
    final eff = sys < high ? high : sys;
    if (eff > high) await _db.setSetting(_k, '$eff');
    return DateTime.fromMillisecondsSinceEpoch(eff);
  }
}

final monotonicClockProvider = Provider(
  (ref) => MonotonicClock(ref.watch(appDatabaseProvider)),
);
