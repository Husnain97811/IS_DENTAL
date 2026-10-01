import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/settings/data/permission_repository.dart';

/// Everything an owner can grant or withhold.
class Perm {
  static const viewFinancials = 'viewFinancials';
  static const viewPatientStats = 'viewPatientStats';
  static const exportXrays = 'exportXrays';
  static const manageBackup = 'manageBackup';
  static const manageStaff = 'manageStaff';
  static const cancelInvoices = 'cancelInvoices';

  static const all = [
    viewFinancials,
    viewPatientStats,
    exportXrays,
    manageBackup,
    manageStaff,
    cancelInvoices,
  ];

  static String label(String key) => switch (key) {
    viewFinancials => 'View financials',
    viewPatientStats => 'View patient statistics',
    exportXrays => 'Export X-rays',
    manageBackup => 'Manage backup & restore',
    manageStaff => 'Manage staff',
    cancelInvoices => 'Cancel invoices',

    _ => key,
  };

  static String describe(String key) => switch (key) {
    viewFinancials => 'Revenue figures, billing totals, and the Reports screen',
    viewPatientStats => 'Visit counts, last-visit dates and patient totals',
    exportXrays => 'Download all X-rays as a ZIP',
    manageBackup => 'Backup, restore from cloud, and data export',
    manageStaff => 'Add, edit and remove staff logins',
    cancelInvoices => 'Mark an invoice cancelled. Owner can always do this.',
    _ => '',
  };
}

/// Sensible starting point when a clinic has never configured anything.
bool defaultFor(AppRole role, String key) => switch (role) {
  AppRole.owner => true,
  AppRole.admin => key != Perm.manageBackup && key != Perm.cancelInvoices,
  AppRole.clinician => key == Perm.viewPatientStats || key == Perm.exportXrays,
  AppRole.receptionist => false,
};

final permissionRepositoryProvider = Provider(
  (ref) => PermissionRepository(ref.watch(appDatabaseProvider)),
);

final permissionsProvider = StreamProvider<Map<String, bool>>(
  (ref) => ref.watch(permissionRepositoryProvider).watchAll(),
);

/// The one question every widget asks: may the current user do this?
///
///   if (ref.watch(canProvider(Perm.viewFinancials))) ...
///
/// Owner is always allowed. Everyone else falls back to the role default
/// until the owner configures it.
final canProvider = Provider.family<bool, String>((ref, key) {
  final role = ref.watch(authControllerProvider)?.role;
  if (role == null) return false;
  if (role == AppRole.owner) return true;

  final map = ref.watch(permissionsProvider).value ?? const {};
  return map['${role.name}|$key'] ?? defaultFor(role, key);
});
