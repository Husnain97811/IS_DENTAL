import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/utils/pdf_output.dart';
import 'package:printing/printing.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/features/patients/presentation/patients_controller.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/invoice_pdf.dart';
import '../../domain/invoice.dart';
import '../billing_controller.dart';

class InvoiceDrawer extends ConsumerWidget {
  const InvoiceDrawer({super.key});

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

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
          : ListView(
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
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '#${inv.invoiceNo}',
                        style: AppTypography.mono(
                          size: 7.5.sp,
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
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                    color: d.text1,
                                  ),
                                ),
                                Text(
                                  inv.issuedAt.toString().split(' ').first,
                                  style: AppTypography.mono(
                                    size: 7.5.sp,
                                    color: d.text4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusChip(
                            inv.status.name[0].toUpperCase() +
                                inv.status.name.substring(1),
                            kind: switch (inv.status) {
                              InvoiceStatus.paid => ChipKind.done,
                              InvoiceStatus.pending => ChipKind.waiting,
                              InvoiceStatus.overdue => ChipKind.overdue,
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 1.6.h),
                      for (final it in inv.items)
                        _line(d, it.description, 'Rs ${_m(it.amount)}'),
                      if (inv.adjustment != 0)
                        _line(
                          d,
                          'Insurance adjustment',
                          '– Rs ${_m(inv.adjustment)}',
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: d.line)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Due',
                              style: TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: d.text1,
                              ),
                            ),
                            Text(
                              'Rs ${_m(inv.total)}',
                              style: TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: d.text1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: Column(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: d.ice,
                          foregroundColor: AppPalette.onAccent,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () => showPdfOutput(
                          context,
                          build: () async {
                            final db = ref.read(appDatabaseProvider);
                            final name = await ref.read(
                              clinicNameProvider.future,
                            );
                            final clinicId = await db.currentClinicId() ?? '';
                            final patient = ref.read(
                              patientByIdProvider(inv.patientId),
                            );
                            final profile = await db
                                .select(db.clinicProfile)
                                .getSingleOrNull();
                            return buildInvoicePdf(
                              inv,
                              clinicName: name,
                              clinicId: clinicId,
                              patientUuid: patient?.uuid ?? '',
                              patientCode: patient?.code,
                              clinicBranch: profile?.branch,
                            );
                          },
                          filename: '${inv.invoiceNo}.pdf',
                        ),
                        icon: const Icon(Icons.print_rounded, size: 17),
                        label: const Text('Print / PDF'),
                      ),
                      const SizedBox(height: 9),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: d.text2,
                          side: BorderSide(color: d.line),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: inv.status == InvoiceStatus.paid
                            ? null
                            : () => ref
                                  .read(billingRepositoryProvider)
                                  .markPaid(inv.id),
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: const Text('Mark as Paid'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _line(DentColors d, String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: d.text2, fontSize: 8.5.sp),
          ),
        ),
        Text(
          amount,
          style: AppTypography.mono(size: 8.5.sp, color: d.text1),
        ),
      ],
    ),
  );
}
