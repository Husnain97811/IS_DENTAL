import 'invoice.dart';

abstract interface class BillingRepository {
  Stream<List<Invoice>> watchInvoices({String? branchId});
  Stream<Invoice?> watchInvoice(int id);
  Future<void> markPaid(int id);
  Future<void> seedDemoInvoicesIfEmpty();
  Future<void> createInvoice({
    required int patientId,
    required String invoiceNo,
    required DateTime issuedAt,
    required String status,
    required String summary,
    required int adjustment,
    required List<({String description, int amount})> items,
  });
}
