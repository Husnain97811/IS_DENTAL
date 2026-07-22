import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import '../../../core/db/app_database.dart';
import '../data/treatment_repository_impl.dart';
import '../domain/treatment.dart';
import '../domain/treatment_repository.dart';

final treatmentRepositoryProvider = Provider<TreatmentRepository>(
  (ref) => TreatmentRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final treatmentsStreamProvider = StreamProvider.autoDispose<List<Treatment>>(
  (ref) => ref
      .watch(treatmentRepositoryProvider)
      .watchTreatments(branchId: ref.watch(activeBranchProvider)),
);

// /// Live procedure names from the treatments catalog.
// final proceduresProvider = StreamProvider<List<String>>((ref) {
//   final list = ref.watch(treatmentsStreamProvider).value ?? const [];
//   return Stream.value(list.map((t) => t.name).toList());
// });

final proceduresProvider = Provider.autoDispose<List<String>>((ref) {
  final list = ref.watch(treatmentsStreamProvider).value ?? const [];
  return list.map((t) => t.name).toList();
});

final procedurePriceProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final list = ref.watch(treatmentsStreamProvider).value ?? const [];
  return {for (final t in list) t.name: t.price};
});
