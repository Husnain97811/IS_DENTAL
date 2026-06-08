import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/appointment_repository_impl.dart';
import '../domain/appointment.dart';
import '../domain/appointment_repository.dart';

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

final markedDaysProvider = StreamProvider.autoDispose
    .family<Set<int>, ({int year, int month})>(
      (ref, ym) => ref
          .watch(appointmentRepositoryProvider)
          .watchMarkedDays(ym.year, ym.month),
    );

final slotsProvider = FutureProvider.autoDispose
    .family<List<({DateTime time, bool busy})>, DateTime>(
      (ref, day) => ref.watch(appointmentRepositoryProvider).slotsFor(day),
    );
