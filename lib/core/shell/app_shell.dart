import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/app_database.dart';
import '../router/nav_destinations.dart';
import '../../features/requests/data/requests_realtime.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_topbar.dart';
import 'widgets/contextual_drawer.dart';
import '../theme/dent_colors.dart';

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
        final showDrawer = dest.drawer != DrawerKind.none && c.maxWidth >= 1280;
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
