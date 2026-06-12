import 'patient.dart';
import 'tooth_record.dart';
import 'treatment_plan.dart';

abstract interface class PatientRepository {
  Stream<List<Patient>> watchPatients({String? branchId});
  Future<void> upsertPatient(Patient p);
  Future<void> softDeletePatient(int id);
  Stream<Map<int, ToothRecord>> watchToothRecords(int patientId);
  Future<void> setToothState(int patientId, int fdi, ToothState state);
  Stream<TreatmentPlan?> watchActivePlan(int patientId);
  Future<void> seedDemoDataIfEmpty();
}
