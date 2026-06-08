import 'package:freezed_annotation/freezed_annotation.dart';
part 'appointment.freezed.dart';

enum AppointmentStatus { inChair, waiting, completed, upcoming, noShow }

@freezed
abstract class Appointment with _$Appointment {
  const Appointment._();
  const factory Appointment({
    required int id,
    required String uuid,
    required int patientId,
    required String patientName,
    required String dentist,
    @Default(1) int chair,
    required String procedure,
    required DateTime startsAt,
    @Default(30) int durationMin,
    required AppointmentStatus status,
  }) = _Appointment;

  String get patientInitials => patientName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .take(2)
      .join()
      .toUpperCase();
}
