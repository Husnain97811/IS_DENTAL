import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/app_flags.dart';
import 'package:sizer/sizer.dart';
import '../../../core/constants/views.dart';
import '../../../core/widgets/kpi_card.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});
  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode && kSeedDemoData) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(patientRepositoryProvider).seedDemoDataIfEmpty();
        await ref.read(billingRepositoryProvider).seedDemoInvoicesIfEmpty();
      });
    }
  }

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  (ChipKind, String) _st(InvoiceStatus s) => switch (s) {
    InvoiceStatus.paid => (ChipKind.done, 'Paid'),
    InvoiceStatus.pending => (ChipKind.waiting, 'Pending'),
    InvoiceStatus.overdue => (ChipKind.overdue, 'Overdue'),
    InvoiceStatus.cancelled => (ChipKind.overdue, 'Cancelled'),
  };

  /// Partial is display only — no new InvoiceStatus value.
  (ChipKind, String) _stInv(Invoice i) =>
      i.isPartial ? (ChipKind.inProgress, 'Partial') : _st(i.status);

  Future<void> _cancel(Invoice inv) async {
    final d = context.dent;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this invoice?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${inv.invoiceNo} · ${inv.patientName} · Rs ${_m(inv.total)}',
              style: TextStyle(color: d.text2, fontSize: 11.sp),
            ),
            if (inv.amountPaid > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Rs ${_m(inv.amountPaid)} has already been received on this '
                'invoice. That money stays in your revenue — refund it '
                'separately if you are giving it back.',
                style: TextStyle(color: d.alert, fontSize: 9.5.sp),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'The invoice is kept for your records and excluded from totals. '
              'Only the owner can see cancelled invoices.',
              style: TextStyle(color: d.text4, fontSize: 9.5.sp),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.alert,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel invoice'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final who = ref.read(authControllerProvider)?.username ?? 'unknown';
    await ref.read(billingRepositoryProvider).cancelInvoice(inv.id, by: who);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    // No billing access → nothing on this screen renders.
    if (!ref.watch(canProvider(Perm.accessBilling))) {
      return Center(
        child: Text(
          'You don\'t have access to this screen.',
          style: TextStyle(color: d.text4, fontSize: 10.sp),
        ),
      );
    }

    final canFin = ref.watch(canProvider(Perm.viewFinancials));
    final canCancel = ref.watch(canProvider(Perm.cancelInvoices));
    final isOwner = ref.watch(authControllerProvider)?.role == AppRole.owner;
    final async = ref.watch(invoicesStreamProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 2.h),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
            data: (list) {
              // Collected = money actually received, including partials.
              final paidMtd = list.fold<int>(0, (s, i) => s + i.amountPaid);
              // Pending = what is still owed, not the full invoice value.
              final pending = list.fold<int>(
                0,
                (s, i) => s + (i.balance > 0 ? i.balance : 0),
              );
              final avg = list.isEmpty
                  ? 0
                  : (list.fold<int>(0, (s, i) => s + i.total) / list.length)
                        .round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canFin) ...[
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final c in [
                          ('Collected', 'Rs ${_m(paidMtd)}', KpiTone.teal),
                          ('Pending', 'Rs ${_m(pending)}', KpiTone.amber),
                          ('Invoices', '${list.length}', KpiTone.blue),
                          ('Avg. Invoice', 'Rs ${_m(avg)}', KpiTone.slate),
                        ])
                          SizedBox(
                            width: 12.w,
                            child: KpiCard(
                              tone: c.$3,
                              label: c.$1,
                              value: c.$2,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 2.2.h),
                  ],
                  DentPanel(
                    title: 'Recent Invoices',
                    subtitle: 'Click to preview',
                    child: Column(
                      children: [
                        _header(d),
                        if (list.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(
                              'No invoices yet.',
                              style: TextStyle(color: d.text4),
                            ),
                          ),
                        for (final inv in list) _row(d, inv, canCancel),
                      ],
                    ),
                  ),

                  if (isOwner) ...[SizedBox(height: 2.2.h), _cancelledPanel(d)],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _header(DentColors d) {
    TextStyle h() => TextStyle(
      color: d.text1,
      fontSize: 12.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .7,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('INVOICE', style: h())),
          Expanded(flex: 3, child: Text('PATIENT', style: h())),
          Expanded(flex: 2, child: Text('DATE', style: h())),
          // Expanded(flex: 3, child: Text('PROCEDURE', style: h())),
          Expanded(flex: 2, child: Text('AMOUNT', style: h())),
          Expanded(flex: 1, child: Text('STATUS', style: h())),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _row(DentColors d, Invoice inv, bool canCancel) {
    final selected = ref.watch(selectedInvoiceIdProvider) == inv.id;
    final (chip, label) = _stInv(inv);
    return InkWell(
      onTap: () => ref.read(selectedInvoiceIdProvider.notifier).state = inv.id,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? d.surface2 : null,
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '#${inv.invoiceNo}',
                style: AppTypography.mono(
                  size: 11.sp,
                  // weight: FontWeight.w600,
                  color: d.text2,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                inv.patientName,
                style: TextStyle(
                  color: d.text2,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                inv.issuedAt.toString().split(' ').first,
                style: TextStyle(color: d.text2, fontSize: 11.sp),
              ),
            ),
            // Expanded(
            //   flex: 3,
            //   child: Text(
            //     inv.summary,
            //     style: TextStyle(color: d.text2, fontSize: 11.sp),
            //     overflow: TextOverflow.ellipsis,
            //   ),
            // ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rs ${_m(inv.total)}',
                    style: AppTypography.mono(size: 11.sp, color: d.text2),
                  ),
                  if (inv.balance > 0 && inv.amountPaid > 0)
                    Text(
                      'Rs ${_m(inv.balance)} due',
                      style: AppTypography.mono(size: 8.sp, color: d.alert),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(label, kind: chip),
              ),
            ),
            SizedBox(
              width: 40,
              child: canCancel && inv.status != InvoiceStatus.cancelled
                  ? IconButton(
                      tooltip: 'Cancel invoice',
                      icon: Icon(Icons.block_rounded, size: 16, color: d.text4),
                      onPressed: () => _cancel(inv),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cancelledPanel(DentColors d) {
    final async = ref.watch(cancelledInvoicesProvider);
    final list = async.value ?? const <Invoice>[];
    if (list.isEmpty) return const SizedBox.shrink();

    return DentPanel(
      title: 'Cancelled Invoices',
      subtitle: 'Visible to the owner only · excluded from all totals',
      child: Column(
        children: [
          for (final inv in list)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      '#${inv.invoiceNo}',
                      style: AppTypography.mono(
                        size: 11.sp,
                        color: d.text3,
                      ).copyWith(decoration: TextDecoration.lineThrough),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      inv.patientName,
                      style: TextStyle(color: d.text3, fontSize: 11.sp),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Rs ${_m(inv.total)}',
                      style: AppTypography.mono(size: 11.sp, color: d.text3),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'by ${inv.cancelledBy ?? "—"}'
                      '${inv.cancelledAt == null ? "" : " · ${inv.cancelledAt!.day}/${inv.cancelledAt!.month}/${inv.cancelledAt!.year}"}',
                      style: TextStyle(color: d.text4, fontSize: 9.5.sp),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
