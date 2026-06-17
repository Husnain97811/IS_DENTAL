import 'appointment.dart';

abstract interface class AppointmentRepository {
  Stream<List<Appointment>> watchAppointmentsForDay(DateTime day);
  Stream<Set<int>> watchMarkedDays(int year, int month);
  Future<List<({DateTime time, bool busy})>> slotsFor(DateTime day);
  Future<void> book({
    required int patientId,
    required String dentist,
    required int chair,
    required String procedure,
    required DateTime startsAt,
    int durationMin,
  });
  Future<void> seedDemoAppointmentsIfEmpty();
  Stream<List<Appointment>> watchAppointmentsForMonth(int year, int month);
  Stream<List<Appointment>> watchAppointmentsForPatient(int patientId);
}
