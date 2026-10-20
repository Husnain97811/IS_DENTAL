import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';

import '../constants/views.dart';
import '../router/app_routes.dart';
import '../router/nav_destinations.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_topbar.dart';
import 'widgets/contextual_drawer.dart';
import 'package:is_dental/features/patients/presentation/patient_detail_route.dart';

/// Below this window width there is no room for the side panel. Screens
/// that depend on it (Billing) slide it in as an overlay instead.
const double kDrawerMinWidth = 1280;

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _collapsed = false;
  void _toggleSidebar() => setState(() => _collapsed = !_collapsed);

  @override
  void initState() {
    super.initState();
    // Subscribe to booking-request realtime once the shell mounts
    // (only reached when authed + inside the app).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final clinicId = await ref.read(appDatabaseProvider).currentClinicId();
      if (clinicId != null && clinicId.isNotEmpty) {
        await ref
            .read(deviceServiceProvider)
            .ensureRegistered(
              byUsername: ref.read(authControllerProvider)?.username,
            );
        await ref.read(appDatabaseProvider).seedLookupsIfEmpty();
        await ref.read(appDatabaseProvider).dedupeLookups();
        // Copy the old chart into the new one, once per patient. On a cloud
        // computer this waits until findings have been pulled at least once.
        try {
          final db = ref.read(appDatabaseProvider);
          final pulled = await db.getSetting('tooth_findings_pulled') == '1';
          final everSynced =
              (await db.getSetting('sync_pull_patients') ?? '').isNotEmpty;
          if (pulled || !everSynced)
            await ToothChartRepository(db).importLegacy();
        } catch (_) {}
        // Encrypts any X-ray still stored as a plain image. Background,
        // verified per file, and safe to interrupt.
        unawaited(ref.read(xrayVaultProvider).encryptPending());
        await ref.read(requestsRealtimeProvider).start(clinicId);
      }
    });
  }

  @override
  void dispose() {
    ref.read(requestsRealtimeProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dest = kNavDestinations[widget.navigationShell.currentIndex];
    return LayoutBuilder(
      builder: (context, c) {
        // Desktop-first breakpoints: auto-collapse below 1100, hide drawer below 1280.
        final autoCollapse = c.maxWidth < 1100;
        final collapsed = _collapsed || autoCollapse;
        // Billing's Day close tab has nothing to do with one invoice, so the
        // invoice preview drawer hides while it's open.
        final dayCloseOpen =
            dest.drawer == DrawerKind.invoice &&
            ref.watch(billingTabProvider) == 1;
        // A full patient file is open — the drawer's patient preview would
        // only repeat it. It comes back on the Patients list.
        final patientFileOpen =
            dest.route == AppRoutes.patients &&
            ref.watch(patientDetailDepthProvider) > 0;
        final showDrawer =
            dest.drawer != DrawerKind.none &&
            !dayCloseOpen &&
            !patientFileOpen &&
            c.maxWidth >= kDrawerMinWidth;
        return Scaffold(
          body: Row(
            children: [
              AppSidebar(
                collapsed: collapsed,
                currentIndex: widget.navigationShell.currentIndex,
                onSelect: (i) => widget.navigationShell.goBranch(
                  i,
                  initialLocation: i == widget.navigationShell.currentIndex,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    AppTopbar(
                      destination: dest,
                      onToggleSidebar: _toggleSidebar,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: context.dent.canvas,
                              child: widget.navigationShell,
                            ),
                          ),
                          if (showDrawer) ContextualDrawer(kind: dest.drawer),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
