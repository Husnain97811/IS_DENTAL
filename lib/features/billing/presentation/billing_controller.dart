import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/billing_repository_impl.dart';
import '../domain/billing_repository.dart';
import '../domain/invoice.dart';
import '../../branches/presentation/branch_controller.dart';

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final invoicesStreamProvider = StreamProvider.autoDispose<List<Invoice>>(
  (ref) => ref
      .watch(billingRepositoryProvider)
      .watchInvoices(branchId: ref.watch(activeBranchProvider)),
);
final selectedInvoiceIdProvider = StateProvider<int?>((_) => null);
final clinicNameProvider = FutureProvider<String>(
  (ref) async =>
      (await ref.watch(appDatabaseProvider).clinicName()) ??
      'Smile Dental Care',
);

final selectedInvoiceProvider = StreamProvider.autoDispose<Invoice?>((ref) {
  final id = ref.watch(selectedInvoiceIdProvider);
  final repo = ref.watch(billingRepositoryProvider);
  if (id != null) return repo.watchInvoice(id);
  final list = ref.watch(invoicesStreamProvider).value;
  if (list == null || list.isEmpty) return Stream.value(null);
  return repo.watchInvoice(list.first.id);
});
