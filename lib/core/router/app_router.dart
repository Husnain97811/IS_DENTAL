import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/views.dart';
import 'app_routes.dart';
import 'package:is_dental/features/patients/presentation/patient_detail_route.dart';
import 'package:is_dental/features/hub/data/hub_security.dart';
import 'package:is_dental/features/hub/presentation/hub_entry.dart';
import 'package:is_dental/features/hub/presentation/reporting_hub_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(licenseControllerProvider, (_, __) => refresh.value++);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  // Losing Hub access (plan downgrade, owner switches admins off) moves
  // anyone inside it straight back to the Dashboard.
  ref.listen(hubAccessProvider, (_, __) => refresh.value++);

  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) {
      final ls = ref.read(licenseControllerProvider).value;
      final loc = state.matchedLocation;
      if (ls == null) return loc == '/splash' ? null : '/splash';
      switch (ls.status) {
        case LicenseStatus.expired:
          return loc == '/locked' ? null : '/locked';

        case LicenseStatus.reconnectRequired:
          return loc == '/reconnect' ? null : '/reconnect';
        // and extend the active cleanup list to include '/reconnect':
        case LicenseStatus.active when ls.setupComplete:
          final authed = ref.read(authControllerProvider) != null;
          const gate = {'/splash', '/setup', '/locked', '/reconnect'};
          if (!authed) return loc == '/login' ? null : '/login';

          // ── licence gating ──
          final lic = ls.license;
          final cloud = lic?.cloudPackage == CloudPackage.cloud;
          final std =
              cloud &&
              (lic!.tier == LicenseTier.standard ||
                  lic.tier == LicenseTier.premium);
          if (!std && loc.startsWith(AppRoutes.whatsapp)) {
            return AppRoutes.dashboard;
          }
          if (!std && loc.startsWith('${AppRoutes.dashboard}/requests')) {
            return AppRoutes.dashboard;
          }
          if (loc.startsWith(kHubRoute)) {
            final hub = ref.read(hubAccessProvider);
            if (!hub.allowed || !hub.onPlan) return AppRoutes.dashboard;
          }

          return (loc == '/login' || gate.contains(loc))
              ? AppRoutes.dashboard
              : null;
        default: // notActivated, invalid, or active-but-not-yet-set-up
          return loc == '/setup' ? null : '/setup';
      }
    },
    routes: [
      // Bare "/" (the error page's Home button, an old link) → Dashboard.
      GoRoute(path: '/', redirect: (c, s) => AppRoutes.dashboard),
      GoRoute(path: '/splash', builder: (c, s) => const _Splash()),
      GoRoute(path: '/setup', builder: (c, s) => const SetupWizard()),
      GoRoute(path: '/locked', builder: (c, s) => const LockedScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),

      GoRoute(
        path: '/reconnect',
        builder: (c, s) => const ReconnectRequiredScreen(),
      ),

      // Detailed Reporting Hub — outside the shell, so it replaces the
      // sidebar and every clinic screen while it is open.
      GoRoute(path: kHubRoute, builder: (c, s) => const ReportingHubScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) =>
            AppShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (c, s) => const DashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'requests',
                    builder: (c, s) => const RequestsScreen(),
                  ),
                ],
              ),
            ],
          ),

          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.appointments,
                builder: (c, s) => const AppointmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.prescriptions,
                builder: (c, s) => const PrescriptionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.patients,
                builder: (c, s) => const PatientsScreen(),
                routes: [
                  // GoRoute(
                  //   path: 'offers',
                  //   builder: (c, s) => const OffersScreen(),
                  // ),
                  GoRoute(
                    path: ':id',
                    builder: (c, s) => PatientDetailRoute(
                      patientId: int.parse(s.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.whatsapp,
                builder: (c, s) => const WhatsAppScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.treatments,
                builder: (c, s) => const TreatmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.billing,
                builder: (c, s) => const BillingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.expenses,
                builder: (c, s) => const ExpensesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.showcase,
                builder: (c, s) => const ShowcaseScreen(),
              ),
            ],
          ),
          // StatefulShellBranch(
          //   routes: [
          //     GoRoute(
          //       path: AppRoutes.inventory,
          //       builder: (c, s) => const InventoryScreen(),
          //     ),
          //   ],
          // ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                builder: (c, s) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (c, s) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _Splash extends ConsumerWidget {
  const _Splash();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(licenseControllerProvider);
    return Scaffold(
      body: Center(
        child: s.hasError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Startup error:\n\n${s.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.dent.alert, fontSize: 13),
                ),
              )
            : CircularProgressIndicator(color: context.dent.ice),
      ),
    );
  }
}
