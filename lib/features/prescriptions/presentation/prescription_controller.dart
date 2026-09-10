import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:is_dental/features/prescriptions/data/domain/prescription.dart';
import 'package:is_dental/features/prescriptions/prescription_repository.dart';
import '../../../core/db/app_database.dart';

final medicineQueryProvider = StateProvider<String>((_) => '');
final prescriptionRepositoryProvider = Provider(
  (ref) => PrescriptionRepository(ref.watch(appDatabaseProvider)),
);

final medicinesProvider = StreamProvider<List<Medicine>>(
  (ref) => ref.watch(prescriptionRepositoryProvider).watchMedicines(),
);

final precautionSetsProvider = StreamProvider<List<PrecautionSet>>(
  (ref) => ref.watch(prescriptionRepositoryProvider).watchPrecautionSets(),
);

final patientPrescriptionsProvider =
    StreamProvider.family<List<Prescription>, int>(
      (ref, patientId) =>
          ref.watch(prescriptionRepositoryProvider).watchForPatient(patientId),
    );
