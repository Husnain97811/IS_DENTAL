import 'package:flutter/material.dart';
import 'package:is_dental/features/billing/presentation/widgets/invoice_drawer.dart';
import 'package:sizer/sizer.dart';

import '../../../features/appointments/presentation/widgets/quick_book_drawer.dart';
import '../../../features/patients/presentation/widgets/patient_snapshot_drawer.dart';
import '../../router/nav_destinations.dart';
import '../../theme/dent_colors.dart';

class ContextualDrawer extends StatelessWidget {
  const ContextualDrawer({super.key, required this.kind});
  final DrawerKind kind;

  @override
  Widget build(BuildContext context) {
    if (kind == DrawerKind.patient) return const PatientSnapshotDrawer();
    if (kind == DrawerKind.booking) return const QuickBookDrawer();
    if (kind == DrawerKind.patient) return const PatientSnapshotDrawer();
    if (kind == DrawerKind.booking) return const QuickBookDrawer();
    if (kind == DrawerKind.invoice) return const InvoiceDrawer();

    // invoice pane is wired in Phase 4.
    final d = context.dent;
    return Container(
      width: 332,
      decoration: BoxDecoration(
        color: d.surface,
        border: Border(left: BorderSide(color: d.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  'PINNED',
                  style: TextStyle(
                    color: d.ice,
                    fontSize: 7.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(6.w),
                child: Text(
                  'Wired up in Phase 4.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: d.text4, fontSize: 9.sp, height: 1.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
