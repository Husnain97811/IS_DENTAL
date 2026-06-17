import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/cloud_service.dart';
import 'package:is_dental/cloud/data/sync_engine.dart';
import 'package:sizer/sizer.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../licensing/presentation/license_providers.dart';
import '../../branches/domain/branch.dart';
import '../../branches/presentation/branch_controller.dart';
import '../../branches/presentation/widgets/branch_editor.dart';
import 'settings_controller.dart';
import 'widgets/staff_editor.dart';

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

  Future<String> syncNow(WidgetRef ref) async {
    try {
      debugPrint('SYNC: signing in…');
      await ref.read(cloudServiceProvider).ensureSignedIn();
      final clinicId = await ref.read(appDatabaseProvider).currentClinicId();
      debugPrint('SYNC: start for $clinicId');
      await ref.read(syncEngineProvider).syncAll(clinicId!);
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
            style: TextStyle(color: d.text3, fontSize: 9.sp),
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
              final right = Column(
                children: [
                  _staffPanel(d),
                  const SizedBox(height: 18),
                  if (premium) ...[
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
        _fieldRow(d, 'Clinic Name', 'Appears on invoices & reports', _name),
        _fieldRow(d, 'Branch', 'Primary location label', _branch),
        _fieldRow(d, 'Currency', 'Billing currency', _currency),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Row(
            children: [
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
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
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accent Colour',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Primary highlight',
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
                  ],
                ),
              ),
              for (final col in [d.ice, d.teal, const Color(0xFF8B5CF6)])
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: col,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _staffPanel(DentColors d) {
    final staff = ref.watch(staffProvider);
    final premium = ref.watch(isPremiumProvider);
    final maxUsers = ref.watch(maxUsersProvider);
    final count = staff.value?.length ?? 0;
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
        data: (rows) => Column(
          children: [
            for (final u in rows) _staffRow(d, u.id, u.fullName, u.role),
            if (premium && atLimit)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'All $maxUsers seats are in use. Remove a user or upgrade to add more.',
                  style: TextStyle(color: d.text4, fontSize: 8.sp),
                ),
              ),
          ],
        ),
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
                  fontSize: 9.sp,
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
            style: TextStyle(fontSize: 9.sp, color: d.text1),
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
                  fontSize: 9.sp,
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
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Export full database (.dentos)',
                      style: TextStyle(color: d.text3, fontSize: 8.sp),
                    ),
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
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Backup & export — coming soon.'),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.text2,
                  side: BorderSide(color: d.line),
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _staffRow(DentColors d, int id, String name, String role) => Container(
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
                name,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1),
                style: TextStyle(color: d.text3, fontSize: 8.sp),
              ),
            ],
          ),
        ),
        StatusChip(
          role == 'owner' ? 'Owner' : 'Active',
          kind: role == 'owner' ? ChipKind.inProgress : ChipKind.done,
        ),
        if (role != 'owner')
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 16, color: d.text4),
            onPressed: () => ref.read(appDatabaseProvider).softDeleteUser(id),
          ),
      ],
    ),
  );

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
                  fontSize: 9.sp,
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
          onPressed: () =>
              ref.read(branchRepositoryProvider).softDeleteBranch(b.id),
        ),
      ],
    ),
  );
}
