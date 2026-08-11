import 'patient.dart';
import 'tooth_record.dart';
import 'treatment_plan.dart';

abstract interface class PatientRepository {
  Stream<List<Patient>> watchPatients({String? branchId});
  Future<void> upsertPatient(Patient p);
  Future<void> softDeletePatient(int id);
  Stream<Map<int, ToothRecord>> watchToothRecords(int patientId);
  Future<void> setToothState(int patientId, int fdi, ToothState state);
  Stream<TreatmentPlan?> watchActivePlan(int patientId); // kept, unchanged

  // ── NEW: multiple-plan support ──
  Stream<List<TreatmentPlan>> watchPlans(int patientId);
  Future<void> createPlan(
    int patientId,
    String title,
    List<TreatmentStep> steps,
  );
  Future<void> updatePlan(int planId, String title, List<TreatmentStep> steps);
  Future<void> deletePlan(int planId);
  Future<void> setStepStatus(int stepId, StepStatus status);

  Future<void> seedDemoDataIfEmpty();
}
