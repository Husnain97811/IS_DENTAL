import 'package:go_router/go_router.dart';

import '../shell/app_shell.dart';
import 'app_routes.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/appointments/presentation/appointments_screen.dart';
import '../../features/patients/presentation/patients_screen.dart';
import '../../features/treatments/presentation/treatments_screen.dart';
import '../../features/billing/presentation/billing_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navShell) => AppShell(navigationShell: navShell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.dashboard, builder: (c, s) => const DashboardScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.appointments, builder: (c, s) => const AppointmentsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.patients, builder: (c, s) => const PatientsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.treatments, builder: (c, s) => const TreatmentsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.billing, builder: (c, s) => const BillingScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.inventory, builder: (c, s) => const InventoryScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.reports, builder: (c, s) => const ReportsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoutes.settings, builder: (c, s) => const SettingsScreen())]),
      ],
    ),
  ],
);
