import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/settings/data/permission_repository.dart';

/// Everything an owner can grant or withhold.
class Perm {
  static const viewFinancials = 'viewFinancials';
  static const accessBilling = 'accessBilling';
  static const billAppointments = 'billAppointments';
  static const prescribe = 'prescribe';
  static const manageWhatsapp = 'manageWhatsapp';
  static const viewPatientStats = 'viewPatientStats';
  static const exportXrays = 'exportXrays';
  static const manageBackup = 'manageBackup';
  static const manageStaff = 'manageStaff';
  static const cancelInvoices = 'cancelInvoices';
  static const manageExpenses = 'manageExpenses';
  static const viewExpenses = 'viewExpenses';

  static const all = [
    viewFinancials,
    accessBilling,
    billAppointments,
    prescribe,
    manageWhatsapp,
    viewPatientStats,
    exportXrays,
    manageBackup,
    manageStaff,
    cancelInvoices,
    manageExpenses,
    viewExpenses,
  ];

  static String label(String key) => switch (key) {
    viewFinancials => 'View financials',
    accessBilling => 'Billing & Invoices',
    billAppointments => 'Bill appointments',
    prescribe => 'Prescribe from appointments',
    manageWhatsapp => 'WhatsApp & Reminders',
    viewPatientStats => 'View patient statistics',
    exportXrays => 'Export X-rays',
    manageBackup => 'Manage backup & restore',
    manageStaff => 'Manage staff',
    cancelInvoices => 'Cancel invoices',
    manageExpenses => 'Record expenses',
    viewExpenses => 'View expenses & profit',
    _ => key,
  };

  static String describe(String key) => switch (key) {
    viewFinancials => 'Revenue figures, billing totals, and the Reports screen',
    accessBilling => 'Open the Billing screen: invoices, payments and printing',
    billAppointments => 'Bill button on the Appointments screen',
    prescribe => 'Prescribe button on the Appointments screen',
    manageWhatsapp =>
      'WhatsApp screen: connections, reminder language and offers',
    viewPatientStats => 'Visit counts, last-visit dates and patient totals',
    exportXrays => 'Download all X-rays as a ZIP',
    manageBackup => 'Backup, restore from cloud, and data export',
    manageStaff => 'Add, edit and remove staff logins',
    cancelInvoices => 'Mark an invoice cancelled. Owner can always do this.',
    manageExpenses =>
      'Add, edit and delete expenses, and edit the category list',
    viewExpenses =>
      'Open the Expenses screen and see expense totals. Net profit also '
          'needs "View financials".',
    _ => '',
  };
}

/// Sensible starting point when a clinic has never configured anything.
bool defaultFor(AppRole role, String key) {
  // Open to everyone until the owner restricts them —
  // keeps existing clinics working exactly as before.
  if (key == Perm.accessBilling ||
      key == Perm.billAppointments ||
      key == Perm.prescribe) {
    return true;
  }

  return switch (role) {
    AppRole.owner => true,
    AppRole.admin => key != Perm.manageBackup && key != Perm.cancelInvoices,
    AppRole.clinician =>
      key == Perm.viewPatientStats || key == Perm.exportXrays,
    AppRole.receptionist => false,
  };
}

final permissionRepositoryProvider = Provider(
  (ref) => PermissionRepository(ref.watch(appDatabaseProvider)),
);

final permissionsProvider = StreamProvider<Map<String, bool>>(
  (ref) => ref.watch(permissionRepositoryProvider).watchAll(),
);

/// The one question every widget asks: may the current user do this?
final canProvider = Provider.family<bool, String>((ref, key) {
  final role = ref.watch(authControllerProvider)?.role;
  if (role == null) return false;
  if (role == AppRole.owner) return true;

  final map = ref.watch(permissionsProvider).value ?? const {};
  return map['${role.name}|$key'] ?? defaultFor(role, key);
});
