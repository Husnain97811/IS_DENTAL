/// Patient call — who each doctor has called today.
///
/// Calls live in the cloud only (Supabase `patient_calls`), never in the
/// local database: they matter for one day, and every computer and the
/// reception screen must see the same thing within a second or two.
///
/// One row per press of Next. Previous never deletes — it marks the
/// current call `undone`, so the patient before shows as on chair again
/// and the undone patient goes back to the waiting list. `seq` counts the
/// presses of one doctor on one day; a unique index on
/// (clinic, dentist, day, seq) means two people pressing Next for the same
/// doctor at the same moment can't both succeed.
class PatientCall {
  const PatientCall({
    required this.id,
    required this.clinicId,
    required this.branchId,
    required this.dentist,
    required this.day,
    required this.seq,
    required this.appointmentUuid,
    required this.patientName,
    required this.calledBy,
    required this.calledAt,
    required this.undone,
    required this.repeatAt,
  });

  final String id;
  final String clinicId;
  final String? branchId;
  final String dentist;
  final String day; // yyyy-mm-dd, clinic's local day
  final int seq;
  final String? appointmentUuid;
  final String patientName; // full name, as announced
  final String? calledBy;
  final DateTime calledAt; // local
  final bool undone;
  final DateTime? repeatAt; // last "Repeat" press, local

  factory PatientCall.fromRow(Map<String, dynamic> r) => PatientCall(
    id: '${r['id']}',
    clinicId: '${r['clinic_id']}',
    branchId: r['branch_id'] as String?,
    dentist: '${r['dentist'] ?? ''}',
    day: '${r['day'] ?? ''}',
    seq: (r['seq'] as num?)?.toInt() ?? 0,
    appointmentUuid: r['appointment_uuid'] as String?,
    patientName: '${r['patient_name'] ?? ''}',
    calledBy: r['called_by'] as String?,
    calledAt: _time(r['called_at']) ?? DateTime.now(),
    undone: r['undone'] == true,
    repeatAt: _time(r['repeat_at']),
  );

  static DateTime? _time(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();
}

/// An arrived patient who can be called — built from today's appointments
/// marked Arrived (status waiting / inChair).
class WaitingPatient {
  const WaitingPatient({
    required this.appointmentId,
    required this.appointmentUuid,
    required this.branchId,
    required this.dentist,
    required this.name,
    required this.procedure,
    required this.startsAt,
  });

  final int appointmentId;
  final String appointmentUuid;
  final String? branchId;
  final String dentist;
  final String name;
  final String procedure;
  final DateTime startsAt; // local
}

/// One doctor's queue right now.
class DoctorQueue {
  const DoctorQueue({
    required this.dentist,
    required this.current,
    required this.previous,
    required this.waiting,
    required this.nextSeq,
  });

  final String dentist;

  /// On chair — the last call that wasn't taken back. Null before the
  /// first call of the day, or after Previous on the first call.
  final PatientCall? current;

  /// The call before [current]; Previous puts this one back on chair.
  final PatientCall? previous;

  /// Arrived and not called yet, in appointment-time order. The first one
  /// is "Next".
  final List<WaitingPatient> waiting;

  /// seq the next press of Next must use.
  final int nextSeq;

  WaitingPatient? get next => waiting.isEmpty ? null : waiting.first;
}

/// Builds a doctor's queue from today's calls and today's arrivals.
///
/// Pure — no clock, no database — so it is unit-tested on its own.
DoctorQueue buildQueue({
  required String dentist,
  required Iterable<PatientCall> calls,
  required Iterable<WaitingPatient> arrived,
}) {
  final mine = calls.where((c) => c.dentist == dentist).toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));
  final live = mine.where((c) => !c.undone).toList();

  final called = {
    for (final c in live)
      if (c.appointmentUuid != null) c.appointmentUuid!,
  };
  final waiting =
      arrived
          .where(
            (p) => p.dentist == dentist && !called.contains(p.appointmentUuid),
          )
          .toList()
        ..sort((a, b) {
          final t = a.startsAt.compareTo(b.startsAt);
          return t != 0 ? t : a.appointmentId.compareTo(b.appointmentId);
        });

  return DoctorQueue(
    dentist: dentist,
    current: live.isEmpty ? null : live.last,
    previous: live.length < 2 ? null : live[live.length - 2],
    waiting: waiting,
    nextSeq: mine.isEmpty ? 1 : mine.last.seq + 1,
  );
}

/// appointment uuid → its live call (latest wins), for the "Called 10:42"
/// tag on the Appointments screen.
Map<String, PatientCall> liveCallsByAppointment(Iterable<PatientCall> calls) {
  final out = <String, PatientCall>{};
  final sorted = calls.where((c) => !c.undone).toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));
  for (final c in sorted) {
    final u = c.appointmentUuid;
    if (u != null) out[u] = c;
  }
  return out;
}

/// The clinic's local day as stored in `patient_calls.day`.
String callDay(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// "10:42 AM"
String callTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Two presses of the same arrow key within [window] count as one action;
/// a single press only shows a hint. Stops a stray key from calling the
/// wrong patient.
class DoubleTap {
  DoubleTap({this.window = const Duration(milliseconds: 700)});
  final Duration window;
  Object? _key;
  DateTime? _at;

  /// True on the second press of [key] inside the window.
  bool press(Object key, DateTime now) {
    final hit = _key == key && _at != null && now.difference(_at!) <= window;
    if (hit) {
      _key = null;
      _at = null;
    } else {
      _key = key;
      _at = now;
    }
    return hit;
  }

  void reset() {
    _key = null;
    _at = null;
  }
}
