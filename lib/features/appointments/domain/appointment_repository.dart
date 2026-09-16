import 'appointment.dart';

abstract interface class AppointmentRepository {
  Future<List<({DateTime time, bool busy})>> slotsFor(DateTime day);
  Future<void> book({
    required int patientId,
    required String dentist,
    required int chair,
    required String procedure,
    required DateTime startsAt,
    int durationMin,
  });

  /// Cancel — soft-delete so the row still syncs and history survives.
  Future<void> cancel(int id, {String? reason});

  /// Reschedule — move to a new time, keeping the same row.
  Future<void> reschedule({
    required int id,
    required DateTime startsAt,
    String? dentist,
    int? durationMin,
  });

  Future<void> seedDemoAppointmentsIfEmpty();
  Stream<List<Appointment>> watchAppointmentsForPatient(int patientId);
  Stream<List<Appointment>> watchAppointmentsForDay(
    DateTime day, {
    String? branchId,
  });

  Stream<Set<int>> watchMarkedDays(int year, int month, {String? branchId});
  Stream<List<Appointment>> watchAppointmentsForMonth(
    int year,
    int month, {
    String? branchId,
  });
  Future<void> setStatus(int id, AppointmentStatus status);
}
