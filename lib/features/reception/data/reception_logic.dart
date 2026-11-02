import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/calls/data/patient_call.dart';
import 'package:is_dental/features/showcase/data/showcase_cases.dart';

/// Every consented Before & After case on this computer, all branches —
/// the owner's picks can come from any branch.
final allShowcaseCasesProvider = StreamProvider<List<ShowcaseCase>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchShowcasePhotos().map((rows) {
    final groups = <String, List<XrayRow>>{};
    for (final r in rows) {
      (groups[r.pairGroup ?? r.uuid] ??= <XrayRow>[]).add(r);
    }
    final out = <ShowcaseCase>[];
    for (final e in groups.entries) {
      final c = ShowcaseCase.from(e.key, e.value);
      if (c != null) out.add(c);
    }
    out.sort((a, b) => b.after.takenAt.compareTo(a.after.takenAt));
    return out;
  });
});

/// Which calls should be announced now. Pure, so it is unit-tested.
///
/// - A call never seen before, not taken back, made in the last 3 minutes.
///   (Calls already there when the screen starts are NOT announced.)
/// - A call whose Repeat time moved forward.
/// Previous (undone) is never announced.
class AnnounceTracker {
  final _seen = <String>{};
  final _repeat = <String, DateTime>{};
  bool _primed = false;

  /// Feed every new list of today's calls; returns those to announce,
  /// oldest first.
  List<PatientCall> update(List<PatientCall> calls, DateTime now) {
    if (!_primed) {
      for (final c in calls) {
        _seen.add(c.id);
        if (c.repeatAt != null) _repeat[c.id] = c.repeatAt!;
      }
      _primed = true;
      return const [];
    }
    final out = <PatientCall>[];
    for (final c in calls) {
      final isNew = _seen.add(c.id);
      final r = c.repeatAt;
      final repeated =
          r != null && (_repeat[c.id] == null || r.isAfter(_repeat[c.id]!));
      if (r != null) _repeat[c.id] = r;
      if (c.undone) continue;
      if (isNew && now.difference(c.calledAt) <= const Duration(minutes: 3)) {
        out.add(c);
      } else if (!isNew && repeated) {
        out.add(c);
      }
    }
    out.sort((a, b) => a.calledAt.compareTo(b.calledAt));
    return out;
  }

  /// A new day — start fresh (nothing from yesterday is announced).
  void reset() {
    _seen.clear();
    _repeat.clear();
    _primed = false;
  }
}

/// Picks the next Showcase case at random, never the same one twice in a
/// row (when there is more than one).
String? nextCase(List<String> ids, String? last, math.Random rnd) {
  if (ids.isEmpty) return null;
  if (ids.length == 1) return ids.first;
  final pool = ids.where((i) => i != last).toList();
  return pool[rnd.nextInt(pool.length)];
}

/// Automatic calling — who to call now, at most one per doctor.
///
/// A doctor is FREE when nobody is on their chair, or the patient on the
/// chair is no longer "arrived" (marked Complete, or the arrival undone).
/// The next waiting patient is called only once their appointment time has
/// come — an early arrival waits for their slot. Pure, so it is tested.
List<(DoctorQueue, WaitingPatient)> autoCalls({
  required List<DoctorQueue> queues,
  required Set<String> stillArrived, // appointment uuids still waiting/inChair
  required DateTime now,
  Map<String, DateTime> recentlyTried = const {},
}) {
  final out = <(DoctorQueue, WaitingPatient)>[];
  for (final q in queues) {
    final next = q.next;
    if (next == null || next.startsAt.isAfter(now)) continue;
    final cur = q.current;
    final busy =
        cur != null &&
        cur.appointmentUuid != null &&
        stillArrived.contains(cur.appointmentUuid);
    if (busy) continue;
    final tried = recentlyTried[next.appointmentUuid];
    if (tried != null && now.difference(tried) < const Duration(seconds: 30)) {
      continue; // a failed try — don't hammer the cloud
    }
    out.add((q, next));
  }
  return out;
}
