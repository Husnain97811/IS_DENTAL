import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/patient_repository_impl.dart';
import '../domain/patient.dart';
import '../domain/patient_repository.dart';
import '../domain/tooth_record.dart';
import '../domain/treatment_plan.dart';

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final patientsStreamProvider = StreamProvider.autoDispose<List<Patient>>(
  (ref) => ref.watch(patientRepositoryProvider).watchPatients(),
);

final selectedPatientIdProvider = StateProvider<int?>((_) => null);

/// Selected patient, defaulting to the first in the list (so the dashboard drawer is populated).
final selectedPatientProvider = Provider.autoDispose<Patient?>((ref) {
  final list = ref.watch(patientsStreamProvider).value;
  if (list == null || list.isEmpty) return null;
  final id = ref.watch(selectedPatientIdProvider);
  if (id == null) return list.first;
  for (final p in list) {
    if (p.id == id) return p;
  }
  return list.first;
});

final toothRecordsProvider = StreamProvider.autoDispose
    .family<Map<int, ToothRecord>, int>(
      (ref, patientId) =>
          ref.watch(patientRepositoryProvider).watchToothRecords(patientId),
    );

final activePlanProvider = StreamProvider.autoDispose
    .family<TreatmentPlan?, int>(
      (ref, patientId) =>
          ref.watch(patientRepositoryProvider).watchActivePlan(patientId),
    );
