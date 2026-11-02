import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';

// ═════════════════════════════════════════════════════════════════════
//  Double bookings — two appointments that should never both happen:
//  the SAME doctor, or the SAME patient, at overlapping times (the same
//  rule the booking editor and the owner phone use).
//
//  Booking is checked when it is made, so this normally finds nothing. It
//  catches the one case no check can stop: a computer that was OFFLINE
//  booked a time that was taken meanwhile (from another computer, the
//  owner phone, or an approved patient-app request). When it syncs, both
//  appointments show a warning until reception moves one.
//
//  Read-only: nothing here changes an appointment.
// ═════════════════════════════════════════════════════════════════════

/// Statuses that still need the doctor's time. Completed, no-show and
/// cancelled visits can't clash any more.
const kLiveStatuses = {'upcoming', 'waiting', 'inChair'};

/// What the conflict check needs to know about one appointment.
class ConflictItem {
  const ConflictItem({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.dentist,
    required this.start,
    required this.minutes,
    required this.status,
    this.branchId,
  });

  final int id, patientId, minutes;
  final String patientName, dentist, status;
  final DateTime start;
  final String? branchId;

  DateTime get end => start.add(Duration(minutes: minutes <= 0 ? 30 : minutes));

  factory ConflictItem.fromAppointment(Appointment a) => ConflictItem(
    id: a.id,
    patientId: a.patientId,
    patientName: a.patientName,
    dentist: a.dentist,
    start: a.startsAt,
    minutes: a.durationMin,
    status: a.status.name,
  );
}

/// One appointment's clash: the OTHER appointment it overlaps.
class BookingConflict {
  const BookingConflict({required this.other, required this.sameDoctor});
  final ConflictItem other;

  /// true = the doctor is double-booked; false = the patient is booked
  /// twice (with another doctor).
  final bool sameDoctor;
}

/// A pair that clash, for the banner.
class ConflictPair {
  const ConflictPair(this.a, this.b, {required this.sameDoctor});
  final ConflictItem a, b;
  final bool sameDoctor;
}

bool _overlap(ConflictItem a, ConflictItem b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

/// Every clashing pair among [items], earliest first. Only appointments
/// that still need the time ([kLiveStatuses]) and start at or after
/// [from] count — yesterday's mix-ups can't be fixed any more.
List<ConflictPair> findConflictPairs(
  List<ConflictItem> items, {
  required DateTime from,
}) {
  final live =
      items
          .where(
            (a) => kLiveStatuses.contains(a.status) && !a.start.isBefore(from),
          )
          .toList()
        ..sort((x, y) => x.start.compareTo(y.start));
  final pairs = <ConflictPair>[];
  for (var i = 0; i < live.length; i++) {
    final a = live[i];
    for (var j = i + 1; j < live.length; j++) {
      final b = live[j];
      // sorted by start: once b starts after a ends, nothing later overlaps a
      if (!b.start.isBefore(a.end)) break;
      final sameDoctor =
          a.dentist.trim().isNotEmpty && a.dentist.trim() == b.dentist.trim();
      final samePatient = a.patientId == b.patientId;
      if ((sameDoctor || samePatient) && _overlap(a, b)) {
        pairs.add(ConflictPair(a, b, sameDoctor: sameDoctor));
      }
    }
  }
  return pairs;
}

/// Appointment id → its first clash (for the warning on each card).
Map<int, BookingConflict> conflictsById(List<ConflictPair> pairs) {
  final out = <int, BookingConflict>{};
  for (final p in pairs) {
    out.putIfAbsent(
      p.a.id,
      () => BookingConflict(other: p.b, sameDoctor: p.sameDoctor),
    );
    out.putIfAbsent(
      p.b.id,
      () => BookingConflict(other: p.a, sameDoctor: p.sameDoctor),
    );
  }
  return out;
}

DateTime _todayStart() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Clashes from today on (120 days ahead), across ALL branches — a doctor
/// or a patient can't be in two branches at once either. Live: updates the
/// moment a sync or the live channel brings a new appointment.
final upcomingConflictsProvider =
    StreamProvider.autoDispose<List<ConflictPair>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      final from = _todayStart();
      final to = from.add(const Duration(days: 120));
      final q =
          db.select(db.appointments).join([
              innerJoin(
                db.patients,
                db.patients.id.equalsExp(db.appointments.patientId),
              ),
            ])
            ..where(
              db.appointments.isDeleted.equals(false) &
                  db.appointments.status.isIn(kLiveStatuses) &
                  db.appointments.startsAt.isBiggerOrEqualValue(from) &
                  db.appointments.startsAt.isSmallerThanValue(to),
            )
            ..orderBy([OrderingTerm.asc(db.appointments.startsAt)]);
      return q.watch().map((rows) {
        final items = rows.map((r) {
          final a = r.readTable(db.appointments);
          final p = r.readTable(db.patients);
          return ConflictItem(
            id: a.id,
            patientId: a.patientId,
            patientName: p.fullName,
            dentist: a.dentist,
            start: a.startsAt,
            minutes: a.durationMin,
            status: a.status,
            branchId: a.branchId,
          );
        }).toList();
        return findConflictPairs(items, from: from);
      });
    });

/// Appointments booked from the owner phone. The server writes one synced
/// activity line per booking: kind `appt_booked_phone`, detail
/// `<appointment uuid>|<phone model>|…`. Read-only, last 200 days.
final phoneBookedUuidsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final since = DateTime.now().subtract(const Duration(days: 200));
  return (db.select(db.activityEvents)..where(
        (t) =>
            t.kind.equals('appt_booked_phone') &
            t.isDeleted.equals(false) &
            t.happenedAt.isBiggerOrEqualValue(since),
      ))
      .watch()
      .map(
        (rows) => {
          for (final r in rows)
            if (r.detail.split('|').first.trim().isNotEmpty)
              r.detail.split('|').first.trim(),
        },
      );
});

/// "5:00 PM"
String conflictTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Tue 4 Nov"
String conflictDay(DateTime t) =>
    '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
