import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../data/treatment_repository_impl.dart';
import '../domain/treatment.dart';
import '../domain/treatment_repository.dart';

final treatmentRepositoryProvider = Provider<TreatmentRepository>(
  (ref) => TreatmentRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final treatmentsStreamProvider = StreamProvider.autoDispose<List<Treatment>>(
  (ref) => ref.watch(treatmentRepositoryProvider).watchTreatments(),
);
