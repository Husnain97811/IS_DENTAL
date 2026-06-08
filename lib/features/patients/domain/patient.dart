import 'package:freezed_annotation/freezed_annotation.dart';
part 'patient.freezed.dart';

enum Gender { male, female, other }

enum PatientStatus {
  inTreatment,
  active,
  pendingPayment,
  newPatient,
  recallDue,
}

@freezed
abstract class Patient with _$Patient {
  const Patient._();
  const factory Patient({
    required int id,
    required String uuid,
    required String code,
    required String fullName,
    required Gender gender,
    @Default(0) int age,
    @Default('') String phone,
    String? allergies,
    String? insurance,
    DateTime? lastVisit,
    @Default(0) int visitCount,
    @Default(0) int balance,
    required PatientStatus status,
    @Default('') String treatmentSummary,
  }) = _Patient;

  String get initials => fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .take(2)
      .join()
      .toUpperCase();
}
