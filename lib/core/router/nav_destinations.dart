import 'package:flutter/material.dart';
import 'app_routes.dart';

enum DrawerKind { none, patient, booking, invoice }

enum NavGroup { clinical, operations, system }

class NavDestination {
  const NavDestination({
    required this.route,
    required this.icon,
    required this.label,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.primaryAction,
    required this.drawer,
    this.badge,
  });
  final String route, label, title, subtitle, primaryAction;
  final IconData icon;
  final NavGroup group;
  final DrawerKind drawer;
  final String? badge;
}

/// Order here defines the StatefulShellRoute branch indices.
const kNavDestinations = <NavDestination>[
  NavDestination(
    route: AppRoutes.dashboard,
    icon: Icons.grid_view_rounded,
    label: 'Dashboard',
    group: NavGroup.clinical,
    title: 'Clinical Dashboard',
    subtitle: 'Smile Dental Care · Rawalpindi Branch',
    primaryAction: 'New Appointment',
    drawer: DrawerKind.none,
  ),
  NavDestination(
    route: AppRoutes.appointments,
    icon: Icons.calendar_today_rounded,
    label: 'Appointments',
    group: NavGroup.clinical,
    title: 'Appointments',
    subtitle: 'Calendar & scheduling',
    primaryAction: 'New Appointment',
    drawer: DrawerKind.booking,
    badge: '18',
  ),
  NavDestination(
    route: AppRoutes.patients,
    icon: Icons.people_alt_rounded,
    label: 'Patients',
    group: NavGroup.clinical,
    title: 'Patient Records',
    subtitle: '',
    primaryAction: 'Add Patient',
    drawer: DrawerKind.patient,
  ),
  NavDestination(
    route: AppRoutes.treatments,
    icon: Icons.medical_services_rounded,
    label: 'Treatments',
    group: NavGroup.clinical,
    title: 'Treatment Catalog',
    subtitle: 'Procedures & pricing',
    primaryAction: 'New Procedure',
    drawer: DrawerKind.none,
  ),
  NavDestination(
    route: AppRoutes.billing,
    icon: Icons.receipt_long_rounded,
    label: 'Billing & Invoices',
    group: NavGroup.operations,
    title: 'Billing & Invoices',
    subtitle: 'Payments & receipts',
    primaryAction: 'New Invoice',
    drawer: DrawerKind.invoice,
  ),
  NavDestination(
    route: AppRoutes.inventory,
    icon: Icons.inventory_2_rounded,
    label: 'Inventory',
    group: NavGroup.operations,
    title: 'Inventory',
    subtitle: 'Supplies & stock control',
    primaryAction: 'Add Item',
    drawer: DrawerKind.none,
  ),
  NavDestination(
    route: AppRoutes.reports,
    icon: Icons.insights_rounded,
    label: 'Reports & Analytics',
    group: NavGroup.operations,
    title: 'Reports & Analytics',
    subtitle: 'Practice performance',
    primaryAction: 'Export Report',
    drawer: DrawerKind.none,
  ),
  NavDestination(
    route: AppRoutes.settings,
    icon: Icons.settings_rounded,
    label: 'Settings',
    group: NavGroup.system,
    title: 'Settings',
    subtitle: 'Clinic configuration',
    primaryAction: 'Save Changes',
    drawer: DrawerKind.none,
  ),
];
