import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../../../cloud/data/quick_sync.dart';
import '../../domain/permissions.dart';

/// Owner-only. Controls what each role may see and do.
/// The owner is never listed — the owner can always do everything.
class PermissionsPanel extends ConsumerWidget {
  const PermissionsPanel({super.key});

  static const _roles = [
    AppRole.admin,
    AppRole.clinician,
    AppRole.receptionist,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    if (session?.role != AppRole.owner) return const SizedBox.shrink();

    final stored =
        ref.watch(permissionsProvider).value ?? const <String, bool>{};

    String roleLabel(AppRole r) => switch (r) {
      AppRole.owner => 'Owner',
      AppRole.admin => 'Admin',
      AppRole.clinician => 'Doctor',
      AppRole.receptionist => 'Reception',
    };

    return DentPanel(
      title: 'Role Permissions',
      subtitle: 'What each role can see. The owner always has full access.',
      child: Column(
        children: [
          // header row
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              color: d.surface2,
              border: Border(bottom: BorderSide(color: d.line)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 4, child: SizedBox()),
                for (final r in _roles)
                  Expanded(
                    flex: 2,
                    child: Text(
                      roleLabel(r),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: d.text3,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          for (final key in Perm.all)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Perm.label(key),
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Perm.describe(key),
                          style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                        ),
                      ],
                    ),
                  ),
                  for (final r in _roles)
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Switch(
                          value: stored['${r.name}|$key'] ?? defaultFor(r, key),
                          activeColor: d.ice,
                          onChanged: (v) async {
                            await ref
                                .read(permissionRepositoryProvider)
                                .set(role: r, key: key, allowed: v);
                            syncInBackground(ref);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Changes apply immediately on this computer, and on other '
              'computers after they sync.',
              style: TextStyle(color: d.text4, fontSize: 8.5.sp),
            ),
          ),
        ],
      ),
    );
  }
}
