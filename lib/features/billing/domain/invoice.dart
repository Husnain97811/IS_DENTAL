import 'package:freezed_annotation/freezed_annotation.dart';
part 'invoice.freezed.dart';

enum InvoiceStatus { paid, pending, overdue, cancelled }

@freezed
abstract class InvoiceItem with _$InvoiceItem {
  const factory InvoiceItem({
    required int id,
    required String description,
    required int amount,
    @Default(1) int qty,
  }) = _InvoiceItem;
}

@freezed
abstract class Invoice with _$Invoice {
  const factory Invoice({
    required int id,
    required String uuid,
    required int patientId,
    required String patientName,
    required String invoiceNo,
    required DateTime issuedAt,
    required InvoiceStatus status,
    @Default('') String summary,
    @Default(0) int subtotal,
    @Default(0) int adjustment,
    @Default(0) int total,
    @Default(0) int amountPaid,
    @Default([]) List<InvoiceItem> items,
    String? cancelledBy,
    DateTime? cancelledAt,
  }) = _Invoice;

  const Invoice._();

  int get balance => total - amountPaid;

  /// Display only — no new InvoiceStatus value, so every exhaustive
  /// switch in the app keeps compiling.
  bool get isPartial =>
      amountPaid > 0 && amountPaid < total && status != InvoiceStatus.cancelled;
}
