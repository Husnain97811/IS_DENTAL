import 'package:flutter/material.dart';
import 'package:is_dental/features/billing/presentation/widgets/invoice_drawer.dart';

import '../../../features/appointments/presentation/widgets/quick_book_drawer.dart';
import '../../../features/patients/presentation/widgets/patient_snapshot_drawer.dart';
import '../../router/nav_destinations.dart';

class ContextualDrawer extends StatelessWidget {
  const ContextualDrawer({super.key, required this.kind});
  final DrawerKind kind;

  @override
  Widget build(BuildContext context) {
    if (kind == DrawerKind.patient) return const PatientSnapshotDrawer();
    // if (kind == DrawerKind.booking ) return const QuickBookDrawer();
    if (kind == DrawerKind.booking) {
      final width = MediaQuery.sizeOf(context).width;
      // Hide on normal laptop widths and below (tweak breakpoint as needed)
      if (width < 1540) return const SizedBox.shrink();
      return const QuickBookDrawer();
    }

    if (kind == DrawerKind.invoice) return const InvoiceDrawer();
    return const SizedBox.shrink();
  }
}
