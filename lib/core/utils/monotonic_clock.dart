import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';

/// Anti-rollback clock. Never reports earlier than the highest time it has
/// seen, so moving the system date back cannot extend a licence.
///
/// Two safeguards stop it becoming permanently poisoned:
///  • a single implausible jump forward is ignored rather than recorded
///  • [healTo] lets a freshly verified licence pull it back to reality
class MonotonicClock {
  MonotonicClock(this._db);
  final AppDatabase _db;
  static const _k = 'clock_high_ms';

  /// A real clock does not gain more than this between two readings.
  /// Anything beyond it is a date change, not the passage of time.
  static const _maxJump = Duration(days: 2);

  Future<DateTime> now() async {
    final sys = DateTime.now().millisecondsSinceEpoch;
    final high = int.tryParse(await _db.getSetting(_k) ?? '') ?? 0;

    // first ever run — seed from the system clock
    if (high == 0) {
      await _db.setSetting(_k, '$sys');
      return DateTime.fromMillisecondsSinceEpoch(sys);
    }

    // system behind the mark → rollback attempt, report the mark
    if (sys <= high) return DateTime.fromMillisecondsSinceEpoch(high);

    // system ahead, but implausibly so → don't record it.
    // Report the system time (so the app still works today) but leave the
    // stored mark alone, so one bad date change isn't permanent.
    if (sys - high > _maxJump.inMilliseconds) {
      return DateTime.fromMillisecondsSinceEpoch(sys);
    }

    // normal forward movement
    await _db.setSetting(_k, '$sys');
    return DateTime.fromMillisecondsSinceEpoch(sys);
  }

  /// Pull the high-water mark back to [t].
  ///
  /// Only called with a timestamp from a signature-verified licence. A licence
  /// cannot be issued in the future, so a mark later than its issue date is
  /// provably wrong — most often a system date change during testing.
  Future<void> healTo(DateTime t) async {
    final ms = t.millisecondsSinceEpoch;
    final high = int.tryParse(await _db.getSetting(_k) ?? '') ?? 0;
    if (high > ms) await _db.setSetting(_k, '$ms');
  }

  /// Vendor escape hatch — clears the mark entirely. Reserved for support.
  Future<void> reset() => _db.setSetting(_k, '');
}

final monotonicClockProvider = Provider(
  (ref) => MonotonicClock(ref.watch(appDatabaseProvider)),
);
