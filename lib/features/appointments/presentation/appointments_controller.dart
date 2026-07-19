import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/appointment_repository_impl.dart';
import '../domain/appointment.dart';
import '../domain/appointment_repository.dart';
import 'package:flutter/material.dart' show TimeOfDay;

const kDentists = ['Dr. Ayesha Khan', 'Dr. Bilal Ahmed', 'Dr. Sara Malik'];
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
          .watchAppointmentsForDay(ref.watch(selectedDateProvider)),
    );

final appointmentsForMonthProvider = StreamProvider.autoDispose
    .family<List<Appointment>, ({int year, int month})>(
      (ref, ym) => ref
          .watch(appointmentRepositoryProvider)
          .watchAppointmentsForMonth(ym.year, ym.month),
    );

final markedDaysProvider = StreamProvider.autoDispose
    .family<Set<int>, ({int year, int month})>(
      (ref, ym) => ref
          .watch(appointmentRepositoryProvider)
          .watchMarkedDays(ym.year, ym.month),
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
// NEW: Clinic schedule config + overlap-aware slots
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

final clinicScheduleProvider = StateProvider<ClinicSchedule>(
  (_) => const ClinicSchedule(),
);

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
      (ref, day) =>
          ref.watch(appointmentRepositoryProvider).watchAppointmentsForDay(day),
    );

/// Slot grid built from clinic schedule. A slot is busy if its range
/// overlaps ANY appointment's full range (start → start + duration).
final daySlotsProvider = Provider.autoDispose
    .family<List<({DateTime time, bool busy})>, DateTime>((ref, day) {
      final sched = ref.watch(clinicScheduleProvider);
      final appts =
          ref.watch(appointmentsForDayFamilyProvider(day)).value ?? const [];

      DateTime at(TimeOfDay t) =>
          DateTime(day.year, day.month, day.day, t.hour, t.minute);

      final open = at(sched.start);
      final close = at(sched.end);
      final step = Duration(minutes: sched.slotMinutes);
      final slots = <({DateTime time, bool busy})>[];

      for (var t = open; !t.add(step).isAfter(close); t = t.add(step)) {
        final slotEnd = t.add(step);
        final busy = appts.any(
          (a) => rangesOverlap(
            t,
            slotEnd,
            a.startsAt,
            a.startsAt.add(Duration(minutes: a.durationMin)),
          ),
        );
        slots.add((time: t, busy: busy));
      }
      return slots;
    });

/// Doctor filter for the appointments screen. null = All doctors.
final dentistFilterProvider = StateProvider<String?>((_) => null);

/// Must match the SHORT names stored in the DB by the booking code.

const kDentistsShort = ['Dr. Ayesha Khan', 'Dr. Bilal Ahmed', 'Dr. Sara Malik'];
