import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/cloud_service.dart';
import 'package:is_dental/cloud/data/sync_engine.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import '../../../licensing/presentation/license_providers.dart';
import '../../branches/domain/branch.dart';
import '../../branches/presentation/branch_controller.dart';
import '../../branches/presentation/widgets/branch_editor.dart';
import 'settings_controller.dart';
import 'widgets/staff_editor.dart';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:is_dental/core/utils/pdf_output.dart';
import 'package:is_dental/features/reports/data/reports_pdf.dart';
import 'package:is_dental/features/reports/presentation/reports_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _S();
}

class _S extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController(),
      _branch = TextEditingController(),
      _currency = TextEditingController();
  bool _loaded = false, _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _branch.dispose();
    _currency.dispose();
    super.dispose();
  }

  //temporary init

  // @override
  // void initState() {
  //   super.initState();
  //   // TEMP — run once to stamp legacy rows, then remove
  //   WidgetsBinding.instance.addPostFrameCallback((_) async {
  //     final n = await ref.read(appDatabaseProvider).backfillBranchIds();
  //     debugPrint('Backfilled $n rows with branch');
  //   });
  // }

  Widget _myProfileCard(DentColors d, AuthSession? session) {
    final branches = ref.watch(branchesStreamProvider).value ?? [];
    final branchName = session?.branchId == null
        ? 'All branches'
        : (branches
                  .where((b) => b.uuid == session?.branchId)
                  .map((b) => b.name)
                  .firstOrNull ??
              '—');
    String roleLabel(AppRole r) => switch (r) {
      AppRole.owner => 'Owner',
      AppRole.admin => 'Admin',
      AppRole.clinician => 'Clinician',
      AppRole.receptionist => 'Receptionist',
    };
    final roleName = session == null ? '' : roleLabel(session.role);
    Widget infoRow(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: d.text3,
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: d.text1,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return DentPanel(
      title: 'My Profile',
      subtitle: 'Your account details',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.ice.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    session?.initials ?? '?',
                    style: TextStyle(
                      color: d.ice,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session?.fullName ?? '—',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '@${session?.username ?? ''}',
                      style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),
          infoRow('Role', roleName),
          infoRow('Branch', branchName),
        ],
      ),
    );
  }

  Future<String> syncNow(WidgetRef ref) async {
    try {
      debugPrint('SYNC: signing in…');
      await ref.read(cloudServiceProvider).ensureSignedIn();
      final clinicId = await ref.read(appDatabaseProvider).currentClinicId();
      debugPrint('SYNC: start for $clinicId');
      await ref.read(syncEngineProvider).syncAll(clinicId!);
      await ref.read(appDatabaseProvider).recordSyncNow(); // ← add this
      debugPrint('SYNC: done');
      return 'Synced';
    } catch (e) {
      debugPrint('SYNC: FAILED $e');
      return 'Sync failed: $e';
    }
  }

  Future<void> _save() async {
    final db = ref.read(appDatabaseProvider);
    final existing = await db.select(db.clinicProfile).getSingleOrNull();
    setState(() => _saving = true);
    await db.saveProfile(
      clinicId: existing?.clinicId ?? '',
      name: _name.text.trim(),
      branch: _branch.text.trim(),
      currency: _currency.text.trim(),
      tier: existing?.tier ?? 'standard',
    );
    if (mounted) {
      setState(() => _saving = false);
      ref.invalidate(clinicProfileProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clinic profile saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final premium = ref.watch(isPremiumProvider);
    ref.watch(clinicProfileProvider).whenData((p) {
      if (!_loaded && p != null) {
        _name.text = p.name;
        _branch.text = p.branch;
        _currency.text = p.currency;
        _loaded = true;
      }
    });
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 4),
          Text(
            'Clinic profile, appearance, staff & data.',
            style: TextStyle(color: d.text3, fontSize: 10.sp),
          ),
          SizedBox(height: 2.2.h),
          LayoutBuilder(
            builder: (context, c) {
              final left = Column(
                children: [
                  _profilePanel(d),
                  const SizedBox(height: 18),
                  _appearancePanel(d, isDark),
                ],
              );
              final session = ref.watch(authControllerProvider);
              final role = session?.role;
              final isOwner = role == AppRole.owner;
              final isAdmin = role == AppRole.admin;
              final canManageStaff = isOwner || isAdmin;

              final right = Column(
                children: [
                  // Everyone except owner sees their own profile card
                  if (!isOwner) ...[
                    _myProfileCard(d, session),
                    const SizedBox(height: 18),
                  ],
                  // Owner/admin: staff management
                  if (canManageStaff) ...[
                    _staffPanel(d),
                    const SizedBox(height: 18),
                  ],
                  // Owner only: branches
                  if (premium && isOwner) ...[
                    _branchesPanel(d),
                    const SizedBox(height: 18),
                  ],
                  _dataPanel(d),
                ],
              );
              if (c.maxWidth < 900)
                return Column(
                  children: [left, const SizedBox(height: 18), right],
                );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 18),
                  Expanded(child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _profilePanel(DentColors d) => DentPanel(
    title: 'Clinic Profile',
    child: Column(
      children: [
        _fieldRowLocked(d, 'Clinic Name', 'Set during clinic setup', _name),
        _fieldRowLocked(d, 'Branch', 'Set during clinic setup', _branch),
        _fieldRowLocked(d, 'Currency', 'Billing currency', _currency),
        // Padding(
        //   padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
        //   child: Row(
        //     children: [
        //       const Spacer(),
        //       FilledButton(
        //         style: FilledButton.styleFrom(
        //           backgroundColor: d.ice,
        //           foregroundColor: AppPalette.onAccent,
        //         ),
        //         onPressed: _saving ? null : _save,
        //         child: _saving
        //             ? const SizedBox(
        //                 width: 16,
        //                 height: 16,
        //                 child: CircularProgressIndicator(
        //                   strokeWidth: 2,
        //                   color: AppPalette.onAccent,
        //                 ),
        //               )
        //             : const Text('Save'),
        //       ),
        //     ],
        //   ),
        // ),
      ],
    ),
  );

  Widget _appearancePanel(DentColors d, bool isDark) => DentPanel(
    title: 'Appearance',
    child: Column(
      children: [
        _toggleRow(
          d,
          'Dark Mode',
          'Switch the entire interface theme',
          isDark,
          (v) => ref
              .read(themeModeProvider.notifier)
              .set(v ? ThemeMode.dark : ThemeMode.light),
        ),
        // Padding(
        //   padding: const EdgeInsets.all(18),
        //   child: Row(
        //     children: [
        //       Expanded(
        //         child: Column(
        //           crossAxisAlignment: CrossAxisAlignment.start,
        //           children: [
        //             Text(
        //               'Accent Colour',
        //               style: TextStyle(
        //                 color: d.text1,
        //                 fontSize: 9.sp,
        //                 fontWeight: FontWeight.w600,
        //               ),
        //             ),
        //             Text(
        //               'Primary highlight',
        //               style: TextStyle(color: d.text3, fontSize: 8.sp),
        //             ),
        //           ],
        //         ),
        //       ),
        //       for (final col in [d.ice, d.teal, const Color(0xFF8B5CF6)])
        //         Container(
        //           width: 24,
        //           height: 24,
        //           margin: const EdgeInsets.only(left: 8),
        //           decoration: BoxDecoration(
        //             color: col,
        //             borderRadius: BorderRadius.circular(7),
        //           ),
        //         ),
        //     ],
        //   ),
        // ),
      ],
    ),
  );

  Widget _staffPanel(DentColors d) {
    final staff = ref.watch(staffProvider);
    final premium = ref.watch(isPremiumProvider);
    final maxUsers = ref.watch(maxUsersProvider);
    final count = ref.watch(totalStaffCountProvider).value ?? 0;
    final atLimit = count >= maxUsers;
    return DentPanel(
      title: 'Staff & Roles',
      subtitle: premium ? '$count / $maxUsers seats used' : 'Single-user plan',
      trailing: !premium
          ? null
          : OutlinedButton.icon(
              onPressed: atLimit ? null : () => showStaffEditor(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: d.ice,
                side: BorderSide(color: d.line),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add user'),
            ),
      child: staff.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: Text('$e', style: TextStyle(color: d.alert)),
        ),
        data: (allRows) {
          final active = ref.watch(activeBranchProvider);
          final rows = active == null
              ? allRows
              : allRows.where((u) => u.branchId == active).toList();
          return Column(
            children: [
              for (final u in rows) _staffRow(d, u),
              if (premium && atLimit)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'All $maxUsers seats are in use. Remove a user or upgrade to add more.',
                    style: TextStyle(color: d.text4, fontSize: 8.sp),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _branchesPanel(DentColors d) {
    final branches = ref.watch(branchesStreamProvider);
    final maxBranches = ref.watch(maxBranchesProvider);
    final count = branches.value?.length ?? 0;
    final atLimit = count >= maxBranches;
    return DentPanel(
      title: 'Branches',
      subtitle: '$count / $maxBranches locations',
      trailing: OutlinedButton.icon(
        onPressed: atLimit ? null : () => showBranchEditor(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: d.ice,
          side: BorderSide(color: d.line),
        ),
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add branch'),
      ),
      child: branches.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: Text('$e', style: TextStyle(color: d.alert)),
        ),
        data: (rows) => Column(
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No branches yet. Add your first location.',
                  style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                ),
              ),
            for (final b in rows) _branchRow(d, b),
            if (atLimit)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Your plan allows $maxBranches branches. Upgrade to add more.',
                  style: TextStyle(color: d.text4, fontSize: 8.sp),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRowLocked(
    DentColors d,
    String title,
    String sub,
    TextEditingController c,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.lock_outline_rounded, size: 12, color: d.text4),
                ],
              ),
              Text(
                sub,
                style: TextStyle(color: d.text3, fontSize: 8.sp),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: c,
            enabled: false,
            style: TextStyle(fontSize: 10.sp, color: d.text3),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: d.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.line),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _fieldRow(
    DentColors d,
    String title,
    String sub,
    TextEditingController c,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sub,
                style: TextStyle(color: d.text3, fontSize: 8.sp),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: c,
            style: TextStyle(fontSize: 10.sp, color: d.text1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: d.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.ice, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _toggleRow(
    DentColors d,
    String title,
    String sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sub,
                style: TextStyle(color: d.text3, fontSize: 8.sp),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: d.ice),
      ],
    ),
  );

  Widget _dataPanel(DentColors d) => DentPanel(
    title: 'Data & Backup',
    child: Column(
      children: [
        _toggleRow(d, 'Auto Backup', 'Encrypted local backup', true, (_) {}),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Sync',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Push all local data to Supabase',
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                ),
                onPressed: () async {
                  final msg = await syncNow(ref);
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
                icon: const Icon(Icons.cloud_sync_rounded, size: 16),
                label: const Text('Sync now'),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restore / Export',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Export reports PDF or patient data CSV',
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _showManageSheet(d),
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.text2,
                  side: BorderSide(color: d.line),
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: d.alert,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Returns to the login screen',
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDentDialog(
                    context,
                    kind: DentDialogKind.warning,
                    title: 'Sign out?',
                    message:
                        'You will be returned to the login screen. Local data stays safe.',
                    confirmLabel: 'Sign out',
                    cancelLabel: 'Cancel',
                  );
                  if (ok == true && context.mounted) {
                    ref.read(authControllerProvider.notifier).logout();
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.alert,
                  side: BorderSide(color: d.alert.withValues(alpha: .4)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _showManageSheet(DentColors d) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: d.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ManageSheet(parentRef: ref),
    );
  }

  // CSV helper used by the sheet
  static String _buildPatientCsv(List<dynamic> patients) {
    final buf = StringBuffer();
    buf.writeln('Code,Name,Phone,Status,Balance,Last Visit');
    for (final p in patients) {
      buf.writeln(
        '${p.code},"${p.fullName}",${p.phone},${p.status.name},${p.balance},${p.lastVisit ?? "—"}',
      );
    }
    return buf.toString();
  }

  Widget _staffRow(DentColors d, User u) {
    final isOwnerViewing =
        ref.watch(authControllerProvider)?.role == AppRole.owner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  u.role.isEmpty
                      ? ''
                      : u.role[0].toUpperCase() + u.role.substring(1),
                  style: TextStyle(color: d.text3, fontSize: 8.sp),
                ),
              ],
            ),
          ),
          StatusChip(
            u.role == 'owner' ? 'Owner' : 'Active',
            kind: u.role == 'owner' ? ChipKind.inProgress : ChipKind.done,
          ),
          // Owner can edit any non-owner user
          if (isOwnerViewing && u.role != 'owner')
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 16, color: d.text4),
              onPressed: () => showStaffEditor(context, existing: u),
            ),
          if (u.role != 'owner')
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: d.text4,
              ),
              onPressed: () async {
                final ok = await showDentDialog(
                  context,
                  kind: DentDialogKind.warning,
                  title: 'Delete user?',
                  message:
                      'Remove ${u.fullName}\'s login. They will no longer be able to sign in. This cannot be undone.',
                  confirmLabel: 'Delete',
                  cancelLabel: 'Cancel',
                );
                if (ok == true) {
                  await ref.read(appDatabaseProvider).softDeleteUser(u.id);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _branchRow(DentColors d, Branch b) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Icon(Icons.store_mall_directory_rounded, size: 18, color: d.ice),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b.name,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (b.location.isNotEmpty)
                Text(
                  b.location,
                  style: TextStyle(color: d.text3, fontSize: 8.sp),
                ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 16, color: d.text4),
          onPressed: () => showBranchEditor(context, existing: b),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 16, color: d.text4),
          onPressed: () async {
            final ok = await showDentDialog(
              context,
              kind: DentDialogKind.warning,
              title: 'Delete branch?',
              message:
                  'Remove ${b.name}. Staff assigned to this branch will lose their location. This cannot be undone.',
              confirmLabel: 'Delete',
              cancelLabel: 'Cancel',
            );
            if (ok == true) {
              await ref.read(branchRepositoryProvider).softDeleteBranch(b.id);
            }
          },
        ),
      ],
    ),
  );
}

class _ManageSheet extends ConsumerStatefulWidget {
  const _ManageSheet({required this.parentRef});
  final WidgetRef parentRef;

  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  bool _exportingCsv = false;
  bool _exportingPdf = false;

  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: d.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Text(
            'Data & Export',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: d.text1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Export your clinic data or run a manual backup.',
            style: TextStyle(color: d.text3, fontSize: 10.sp),
          ),
          const SizedBox(height: 24),

          // Export reports PDF
          _SheetTile(
            d: d,
            icon: Icons.picture_as_pdf_rounded,
            iconColor: d.ice,
            title: 'Export Reports PDF',
            subtitle:
                'Revenue, procedures, dentist performance · last 12 months',
            loading: _exportingPdf,
            onTap: () async {
              setState(() => _exportingPdf = true);
              try {
                final s = await ref.read(reportsSummaryProvider.future);
                final name =
                    await ref.read(appDatabaseProvider).clinicName() ??
                    'Clinic';
                if (!context.mounted) return;
                await showPdfOutput(
                  context,
                  build: () => buildReportsPdf(s, clinicName: name),
                  filename: 'dentos-report.pdf',
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              } finally {
                if (mounted) setState(() => _exportingPdf = false);
              }
            },
          ),
          const SizedBox(height: 12),

          // Export patient CSV
          _SheetTile(
            d: d,
            icon: Icons.table_chart_rounded,
            iconColor: d.teal,
            title: 'Export Patient List (CSV)',
            subtitle: 'All active patients · name, phone, status, balance',
            loading: _exportingCsv,
            onTap: () async {
              setState(() => _exportingCsv = true);
              try {
                final db = ref.read(appDatabaseProvider);
                final rows = await (db.select(
                  db.patients,
                )..where((t) => t.isDeleted.equals(false))).get();
                final csv = StringBuffer();
                csv.writeln('Code,Name,Phone,Status,Balance');
                for (final p in rows) {
                  csv.writeln(
                    '${p.code},"${p.fullName}",${p.phone},${p.status},${p.balance}',
                  );
                }
                final bytes = csv.toString().codeUnits;
                await Printing.sharePdf(
                  bytes: Uint8List.fromList(bytes),
                  filename: 'dentos-patients.csv',
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CSV export failed: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _exportingCsv = false);
              }
            },
          ),
          const SizedBox(height: 12),

          // Sync now
          // _SheetTile(
          //   d: d,
          //   icon: Icons.cloud_sync_rounded,
          //   iconColor: d.warn,
          //   title: 'Sync to Cloud Now',
          //   subtitle: 'Push all local changes to Supabase immediately',
          //   loading: false,
          //   onTap: () async {
          //     Navigator.pop(context);
          //     final msg = await syncNow(widget.parentRef);
          //     if (context.mounted) {
          //       ScaffoldMessenger.of(
          //         context,
          //       ).showSnackBar(SnackBar(content: Text(msg)));
          //     }
          //   },
          // ),
          FilledButton.icon(
            onPressed: () async {
              final msg = await syncNow(ref);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
            icon: const Icon(Icons.cloud_sync_rounded),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 20),

          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: d.text2,
              side: BorderSide(color: d.line),
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.d,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });
  final DentColors d;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: d.surface2,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: iconColor,
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 9.5.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: d.text4, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String> syncNow(WidgetRef ref) async {
  try {
    debugPrint('SYNC: signing in…');
    await ref.read(cloudServiceProvider).ensureSignedIn();
    final clinicId = await ref.read(appDatabaseProvider).currentClinicId();
    debugPrint('SYNC: start for $clinicId');
    await ref.read(syncEngineProvider).syncAll(clinicId!);
    await ref.read(appDatabaseProvider).recordSyncNow(); // ← add this
    debugPrint('SYNC: done');
    return 'Synced';
  } catch (e) {
    debugPrint('SYNC: FAILED $e');
    return 'Sync failed: $e';
  }
}
