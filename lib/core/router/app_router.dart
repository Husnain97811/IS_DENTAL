import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/features/offers/presentation/offers_screen.dart';
import 'package:is_dental/features/requests/presentation/requests_screen.dart';
import '../constants/views.dart';
import 'app_routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(licenseControllerProvider, (_, __) => refresh.value++);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);

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
          return (loc == '/login' || gate.contains(loc))
              ? AppRoutes.dashboard
              : null;
        default: // notActivated, invalid, or active-but-not-yet-set-up
          return loc == '/setup' ? null : '/setup';
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const _Splash()),
      GoRoute(path: '/setup', builder: (c, s) => const SetupWizard()),
      GoRoute(path: '/locked', builder: (c, s) => const LockedScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),

      GoRoute(
        path: '/reconnect',
        builder: (c, s) => const ReconnectRequiredScreen(),
      ),

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
                path: AppRoutes.patients,
                builder: (c, s) => const PatientsScreen(),
                routes: [
                  GoRoute(
                    path: 'offers',
                    builder: (c, s) => const OffersScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (c, s) => PatientDetailScreen(
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
                path: AppRoutes.appointments,
                builder: (c, s) => const AppointmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.patients,
                builder: (c, s) => const PatientsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (c, s) => PatientDetailScreen(
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
                path: AppRoutes.inventory,
                builder: (c, s) => const InventoryScreen(),
              ),
            ],
          ),
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
