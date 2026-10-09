import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/invoice_pdf.dart';
import '../../data/payment_repository.dart';
import 'payment_dialog.dart';

class InvoiceDrawer extends ConsumerWidget {
  const InvoiceDrawer({super.key});

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  String _day(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final inv = ref.watch(selectedInvoiceProvider).value;
    return Container(
      width: 332,
      decoration: BoxDecoration(
        color: d.surface,
        border: Border(left: BorderSide(color: d.line)),
      ),
      child: inv == null
          ? Center(
              child: Text(
                'Select an invoice.',
                style: TextStyle(color: d.text4, fontSize: 9.sp),
              ),
            )
          : _body(context, ref, d, inv),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, DentColors d, Invoice inv) {
    final payments = ref.watch(paymentsForInvoiceProvider(inv.id)).value ?? [];
    final cancelled = inv.status == InvoiceStatus.cancelled;
    final settled = inv.balance <= 0;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: d.text1,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '#${inv.invoiceNo}',
                style: AppTypography.mono(
                  size: 9.5.sp,
                  color: d.ice,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inv.patientName,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w600,
                            color: d.text1,
                          ),
                        ),
                        Text(
                          _day(inv.issuedAt),
                          style: AppTypography.mono(
                            size: 9.5.sp,
                            color: d.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(_label(inv), kind: _kind(inv)),
                ],
              ),
              SizedBox(height: 1.6.h),
              for (final it in inv.items)
                _line(d, it.description, _m(it.amount)),
              if (inv.adjustment != 0)
                _line(d, 'Insurance adjustment', '– ${_m(inv.adjustment)}'),

              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: d.line)),
                ),
                child: Column(
                  children: [
                    _totalRow(d, 'Total', 'Rs ${_m(inv.total)}'),
                    const SizedBox(height: 6),
                    _totalRow(
                      d,
                      'Paid',
                      'Rs ${_m(inv.amountPaid)}',
                      color: d.teal,
                    ),
                    const SizedBox(height: 6),
                    _totalRow(
                      d,
                      'Balance',
                      'Rs ${_m(inv.balance)}',
                      big: true,
                      color: inv.balance > 0 ? d.alert : d.teal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (payments.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Received Payments',
              style: TextStyle(
                color: d.text1,
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ),
          for (final p in payments) _paymentRow(context, ref, d, p),
        ],

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          child: Column(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: (cancelled || settled)
                    ? null
                    : () => showPaymentDialog(context, inv),
                icon: const Icon(Icons.payments_rounded, size: 17),
                label: Text(settled ? 'Fully Paid' : 'Take Payment'),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.text2,
                  side: BorderSide(color: d.line),
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: () => showPdfOutput(
                  context,
                  build: () async {
                    final db = ref.read(appDatabaseProvider);
                    final name = await ref.read(clinicNameProvider.future);
                    final clinicId = await db.currentClinicId() ?? '';
                    final patient = ref.read(
                      patientByIdProvider(inv.patientId),
                    );
                    final profile = await db
                        .select(db.clinicProfile)
                        .getSingleOrNull();
                    final pays = await db.paymentsForInvoice(inv.id);
                    final prev = await db.patientBalanceExcluding(
                      inv.patientId,
                      inv.id,
                    );
                    return buildInvoicePdf(
                      inv,
                      clinicName: name,
                      clinicId: clinicId,
                      patientUuid: patient?.uuid ?? '',
                      patientCode: patient?.code,
                      clinicBranch: profile?.branch,
                      payments: pays,
                      previousBalance: prev,
                    );
                  },
                  filename: '${inv.invoiceNo}.pdf',
                ),
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Print / PDF'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentRow(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    InvoicePaymentRow p,
  ) {
    final canCancel = ref.watch(canProvider(Perm.cancelInvoices));
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rs ${_m(p.amount)} · ${p.method}',
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    _day(p.paidAt),
                    if ((p.methodDetail ?? '').isNotEmpty) p.methodDetail!,
                    if ((p.reference ?? '').isNotEmpty) 'TID ${p.reference}',
                    if (p.receivedByName.isNotEmpty) 'by ${p.receivedByName}',
                  ].join(' · '),
                  style: TextStyle(color: d.text4, fontSize: 9.5.sp),
                ),
              ],
            ),
          ),
          if (canCancel)
            IconButton(
              tooltip: 'Remove payment',
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 12.sp,
                color: d.text4,
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: d.surface,
                    title: const Text('Remove this payment?'),
                    content: Text(
                      'Rs ${_m(p.amount)} received on ${_day(p.paidAt)} will '
                      'be removed. The balance goes back up.',
                      style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Keep it'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: d.alert,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                final who = ref.read(authControllerProvider)?.username ?? '';
                await ref.read(paymentRepositoryProvider).remove(p.id, by: who);
                syncInBackground(ref);
              },
            ),
        ],
      ),
    );
  }

  String _label(Invoice i) {
    if (i.status == InvoiceStatus.cancelled) return 'Cancelled';
    if (i.isPartial) return 'Partial';
    return i.status.name[0].toUpperCase() + i.status.name.substring(1);
  }

  ChipKind _kind(Invoice i) {
    if (i.status == InvoiceStatus.cancelled) return ChipKind.overdue;
    if (i.isPartial) return ChipKind.inProgress;
    return switch (i.status) {
      InvoiceStatus.paid => ChipKind.done,
      InvoiceStatus.pending => ChipKind.waiting,
      InvoiceStatus.overdue => ChipKind.overdue,
      InvoiceStatus.cancelled => ChipKind.overdue,
    };
  }

  Widget _totalRow(
    DentColors d,
    String label,
    String value, {
    bool big = false,
    Color? color,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: big ? 12.sp : 10.sp,
          fontWeight: FontWeight.w600,
          color: color ?? d.text2,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: big ? 12.sp : 10.sp,
          fontWeight: FontWeight.w600,
          color: color ?? d.text1,
        ),
      ),
    ],
  );

  Widget _line(DentColors d, String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: d.text2,
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          amount,
          style: AppTypography.mono(size: 11.sp, color: d.text1),
        ),
      ],
    ),
  );
}
