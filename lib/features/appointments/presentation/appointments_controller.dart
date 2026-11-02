import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/appointment_repository_impl.dart';
import '../domain/appointment.dart';
import '../domain/appointment_repository.dart';
import '../../branches/presentation/branch_controller.dart';
import 'package:drift/drift.dart'
    show OrderingTerm, OrderingMode, BooleanExpressionOperators, Constant;

// const kDentists = ['Dr. Ayesha Khan', 'Dr. Bilal Ahmed', 'Dr. Sara Malik'];
const kProcedures = [
  'Scaling & Polishing',
  'Composite Filling',
  'Root Canal Therapy',
  'Crown Fitting',
  'Implant Consultation',
  'Teeth Whitening',
  'Braces Adjustment',
];

final appointmentRepositoryProvider = Provider<AppointmentRepository>(
  (ref) => AppointmentRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final selectedDateProvider = StateProvider<DateTime>((_) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

final appointmentsForDayProvider =
    StreamProvider.autoDispose<List<Appointment>>(
      (ref) => ref
          .watch(appointmentRepositoryProvider)
          .watchAppointmentsForDay(
            ref.watch(selectedDateProvider),
            branchId: ref.watch(activeBranchProvider),
          ),
    );

final appointmentsForMonthProvider = StreamProvider.autoDispose
    .family<List<Appointment>, ({int year, int month})>(
      (ref, ym) => ref
          .watch(appointmentRepositoryProvider)
          .watchAppointmentsForMonth(
            ym.year,
            ym.month,
            branchId: ref.watch(activeBranchProvider),
          ),
    );

final markedDaysProvider = StreamProvider.autoDispose
    .family<Set<int>, ({int year, int month})>(
      (ref, ym) => ref
          .watch(appointmentRepositoryProvider)
          .watchMarkedDays(
            ym.year,
            ym.month,
            branchId: ref.watch(activeBranchProvider),
          ),
    );

final viewedMonthProvider = StateProvider<({int year, int month})>((ref) {
  final s = ref.read(selectedDateProvider);
  return (year: s.year, month: s.month);
});

final appointmentsForPatientProvider = StreamProvider.autoDispose
    .family<List<Appointment>, int>(
      (ref, patientId) => ref
          .watch(appointmentRepositoryProvider)
          .watchAppointmentsForPatient(patientId),
    );
// ─────────────────────────────────────────────────────────────
// Clinic schedule config + overlap-aware slots
// ─────────────────────────────────────────────────────────────

class ClinicSchedule {
  const ClinicSchedule({
    this.start = const TimeOfDay(hour: 10, minute: 0),
    this.end = const TimeOfDay(hour: 17, minute: 0),
    this.slotMinutes = 20,
  });
  final TimeOfDay start;
  final TimeOfDay end;
  final int slotMinutes;

  ClinicSchedule copyWith({
    TimeOfDay? start,
    TimeOfDay? end,
    int? slotMinutes,
  }) => ClinicSchedule(
    start: start ?? this.start,
    end: end ?? this.end,
    slotMinutes: slotMinutes ?? this.slotMinutes,
  );
}

final clinicScheduleProvider = Provider<ClinicSchedule>((ref) {
  final branches = ref.watch(branchesStreamProvider).value ?? const [];
  final active = ref.watch(activeBranchProvider);
  if (branches.isEmpty) return const ClinicSchedule();
  // Owner "all branches" (active null) → use primary branch's hours for the grid.
  final b = active == null
      ? (branches.where((x) => x.isPrimary).firstOrNull ?? branches.first)
      : (branches.where((x) => x.uuid == active).firstOrNull ?? branches.first);
  return ClinicSchedule(
    start: TimeOfDay(hour: b.openMinutes ~/ 60, minute: b.openMinutes % 60),
    end: TimeOfDay(hour: b.closeMinutes ~/ 60, minute: b.closeMinutes % 60),
    slotMinutes: b.slotMinutes,
  );
});

/// True only if the two time ranges actually overlap.
/// Back-to-back ranges (one ends exactly when the next starts) do NOT overlap.
bool rangesOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Appointments for any given day (family version — works for the editor's picked date).
final appointmentsForDayFamilyProvider = StreamProvider.autoDispose
    .family<List<Appointment>, DateTime>(
      (ref, day) => ref
          .watch(appointmentRepositoryProvider)
          .watchAppointmentsForDay(
            day,
            branchId: ref.watch(activeBranchProvider),
          ),
    );

/// Every appointment on [day] in ALL branches. Clashes are checked against
/// this: a doctor or a patient can't be in two places at once, whichever
/// branch happens to be open on screen.
final allAppointmentsForDayProvider = StreamProvider.autoDispose
    .family<List<Appointment>, DateTime>(
      (ref, day) =>
          ref.watch(appointmentRepositoryProvider).watchAppointmentsForDay(day),
    );

/// The open / closed / weekday rules of the branch in view, as a slot grid
/// for [day] with nothing booked yet. Empty on a closed day.
List<DateTime> _slotTimes(Ref ref, DateTime day) {
  final sched = ref.watch(clinicScheduleProvider);
  DateTime at(TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  // Closed-day check (weekday 1=Mon..7=Sun) from the active branch.
  final branches = ref.watch(branchesStreamProvider).value ?? const [];
  final active = ref.watch(activeBranchProvider);
  final b = active == null
      ? (branches.where((x) => x.isPrimary).firstOrNull ??
            (branches.isEmpty ? null : branches.first))
      : branches.where((x) => x.uuid == active).firstOrNull;
  final closed = (b?.closedDays ?? '')
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .map((s) => int.tryParse(s.trim()))
      .toSet();
  if (closed.contains(day.weekday)) return const [];

  final close = at(sched.end);
  final step = Duration(minutes: sched.slotMinutes);
  return [
    for (var t = at(sched.start); !t.add(step).isAfter(close); t = t.add(step))
      t,
  ];
}

/// OLD grid: a slot is busy if it overlaps ANY appointment of ANY doctor.
/// Kept only so older screens still compile — booking and rescheduling use
/// [dentistSlotsProvider], which checks one doctor at a time.
final daySlotsProvider = Provider.autoDispose
    .family<List<({DateTime time, bool busy})>, DateTime>((ref, day) {
      final sched = ref.watch(clinicScheduleProvider);
      final appts =
          ref.watch(appointmentsForDayFamilyProvider(day)).value ?? const [];
      final step = Duration(minutes: sched.slotMinutes);
      return [
        for (final t in _slotTimes(ref, day))
          (
            time: t,
            busy: appts.any(
              (a) => rangesOverlap(
                t,
                t.add(step),
                a.startsAt,
                a.startsAt.add(Duration(minutes: a.durationMin)),
              ),
            ),
          ),
      ];
    });

/// Which slots are free for ONE doctor on one day.
/// [exceptId] — the appointment being moved, so it doesn't block itself.
typedef SlotQuery = ({DateTime day, String? dentist, int? exceptId});

/// Slot grid for [SlotQuery.dentist]. A slot is busy only when THAT doctor
/// already has an appointment overlapping it — five doctors can each see a
/// patient at 8:50. With no doctor chosen yet, every slot is free.
final dentistSlotsProvider = Provider.autoDispose
    .family<List<({DateTime time, bool busy})>, SlotQuery>((ref, q) {
      final sched = ref.watch(clinicScheduleProvider);
      final all =
          ref.watch(allAppointmentsForDayProvider(q.day)).value ?? const [];
      final mine = [
        for (final a in all)
          if (a.dentist == q.dentist && a.id != q.exceptId) a,
      ];
      final step = Duration(minutes: sched.slotMinutes);
      return [
        for (final t in _slotTimes(ref, q.day))
          (
            time: t,
            busy: mine.any(
              (a) => rangesOverlap(
                t,
                t.add(step),
                a.startsAt,
                a.startsAt.add(Duration(minutes: a.durationMin)),
              ),
            ),
          ),
      ];
    });

/// A real clash for a new or moved appointment, or null:
///  • the SAME doctor already has someone in that time, or
///  • the SAME patient is already booked then (with any doctor).
/// Other doctors' patients at the same time are fine.
({Appointment appt, bool sameDoctor})? findBookingClash(
  List<Appointment> dayAppointments, {
  required DateTime start,
  required int durationMin,
  required String dentist,
  int? patientId,
  int? exceptId,
}) {
  final end = start.add(Duration(minutes: durationMin));
  for (final a in dayAppointments) {
    if (a.id == exceptId) continue;
    final sameDoctor = a.dentist == dentist;
    final samePatient = patientId != null && a.patientId == patientId;
    if (!sameDoctor && !samePatient) continue;
    final aEnd = a.startsAt.add(Duration(minutes: a.durationMin));
    if (rangesOverlap(start, end, a.startsAt, aEnd)) {
      return (appt: a, sameDoctor: sameDoctor);
    }
  }
  return null;
}

/// "8:50 AM"
String clashTime(DateTime t) {
  final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

/// The message for a clash from [findBookingClash].
String clashMessage(({Appointment appt, bool sameDoctor}) c) {
  final a = c.appt;
  final range =
      '${clashTime(a.startsAt)}–'
      '${clashTime(a.startsAt.add(Duration(minutes: a.durationMin)))}';
  return c.sameDoctor
      ? '${a.dentist} already has ${a.patientName} at $range. '
            'Choose another time.'
      : '${a.patientName} is already booked with ${a.dentist} at $range.';
}

/// Doctor filter for the appointments screen. null = All doctors.
final dentistFilterProvider = StateProvider<String?>((_) => null);

/// Must match the SHORT names stored in the DB by the booking code.
/// Live list of dentist full names from the Users table (owner + clinician roles).
final dentistsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final branchId = ref.watch(activeBranchProvider);
  return (db.select(db.users)
        ..where(
          (u) =>
              u.isDeleted.equals(false) &
              u.role.isIn(const ['clinician']) &
              (branchId == null
                  ? const Constant(true)
                  : u.branchId.equals(branchId)),
        )
        ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
      .watch()
      .map((rows) => rows.map((u) => u.fullName).toList());
});
// const kDentistsShort = ['Dr. Ayesha', 'Dr. Bilal', 'Dr. Sara'];
