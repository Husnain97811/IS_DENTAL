import 'invoice.dart';

abstract interface class BillingRepository {
  Stream<List<Invoice>> watchInvoices();
  Stream<Invoice?> watchInvoice(int id);
  Future<void> markPaid(int id);
  Future<void> seedDemoInvoicesIfEmpty();
}
