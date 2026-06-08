import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../patients/presentation/patients_controller.dart';
import '../domain/invoice.dart';
import 'billing_controller.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});
  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
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
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(invoicesStreamProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Billing & Invoices',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Click an invoice to preview & print.',
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          SizedBox(height: 2.2.h),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
            data: (list) {
              final paidMtd = list
                  .where((i) => i.status == InvoiceStatus.paid)
                  .fold<int>(0, (s, i) => s + i.total);
              final pending = list
                  .where((i) => i.status != InvoiceStatus.paid)
                  .fold<int>(0, (s, i) => s + i.total);
              final avg = list.isEmpty
                  ? 0
                  : (list.fold<int>(0, (s, i) => s + i.total) / list.length)
                        .round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final c in [
                        (
                          'Collected',
                          'Rs ${_m(paidMtd)}',
                          KpiTone.teal,
                          Icons.payments_rounded,
                        ),
                        (
                          'Pending',
                          'Rs ${_m(pending)}',
                          KpiTone.amber,
                          Icons.schedule_rounded,
                        ),
                        (
                          'Invoices',
                          '${list.length}',
                          KpiTone.blue,
                          Icons.receipt_long_rounded,
                        ),
                        (
                          'Avg. Invoice',
                          'Rs ${_m(avg)}',
                          KpiTone.slate,
                          Icons.trending_up_rounded,
                        ),
                      ])
                        SizedBox(
                          width: 240,
                          child: KpiCard(
                            icon: c.$4,
                            tone: c.$3,
                            label: c.$1,
                            value: c.$2,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 2.2.h),
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
                        for (final inv in list) _row(d, inv),
                      ],
                    ),
                  ),
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
      color: d.text4,
      fontSize: 7.sp,
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
          Expanded(flex: 3, child: Text('PROCEDURE', style: h())),
          Expanded(flex: 2, child: Text('AMOUNT', style: h())),
          Expanded(flex: 2, child: Text('STATUS', style: h())),
        ],
      ),
    );
  }

  Widget _row(DentColors d, Invoice inv) {
    final selected = ref.watch(selectedInvoiceIdProvider) == inv.id;
    final (chip, label) = _st(inv.status);
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
                  size: 8.5.sp,
                  weight: FontWeight.w600,
                  color: d.text1,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                inv.patientName,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                inv.issuedAt.toString().split(' ').first,
                style: TextStyle(color: d.text2, fontSize: 8.5.sp),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                inv.summary,
                style: TextStyle(color: d.text2, fontSize: 8.5.sp),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Rs ${_m(inv.total)}',
                style: AppTypography.mono(size: 8.5.sp, color: d.text1),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(label, kind: chip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
