import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';

class PaymentRepository {
  PaymentRepository(this._db);
  final AppDatabase _db;

  Future<void> add({
    required int invoiceId,
    required int amount,
    required DateTime paidAt,
    required String method,
    String? methodDetail,
    String? reference,
    String note = '',
    String by = '',
  }) => _db.insertPayment(
    invoiceId: invoiceId,
    amount: amount,
    paidAt: paidAt,
    method: method,
    methodDetail: methodDetail,
    reference: reference,
    note: note,
    receivedByName: by,
  );

  Future<void> remove(int paymentId, {String by = ''}) =>
      _db.softDeletePayment(paymentId, by: by);
}

final paymentRepositoryProvider = Provider(
  (ref) => PaymentRepository(ref.watch(appDatabaseProvider)),
);

final paymentsForInvoiceProvider = StreamProvider.autoDispose
    .family<List<InvoicePaymentRow>, int>(
      (ref, invoiceId) =>
          ref.watch(appDatabaseProvider).watchPaymentsForInvoice(invoiceId),
    );
