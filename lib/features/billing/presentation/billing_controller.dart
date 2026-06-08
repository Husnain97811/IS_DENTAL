import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../data/billing_repository_impl.dart';
import '../domain/billing_repository.dart';
import '../domain/invoice.dart';

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final invoicesStreamProvider = StreamProvider.autoDispose<List<Invoice>>(
  (ref) => ref.watch(billingRepositoryProvider).watchInvoices(),
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
