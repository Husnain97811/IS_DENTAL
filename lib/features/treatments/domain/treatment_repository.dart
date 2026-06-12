import 'treatment.dart';

abstract interface class TreatmentRepository {
  Stream<List<Treatment>> watchTreatments();
  Future<void> upsertTreatment(Treatment t);
  Future<void> softDeleteTreatment(int id);
  Future<void> seedDemoIfEmpty();
}
