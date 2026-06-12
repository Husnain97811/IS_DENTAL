import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../auth/presentation/auth_controller.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../licensing/presentation/license_providers.dart';
import '../branch_controller.dart';

class BranchSwitcher extends ConsumerWidget {
  const BranchSwitcher({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    if (!ref.watch(isPremiumProvider)) return const SizedBox.shrink();
    final branches = ref.watch(branchesStreamProvider).value ?? [];
    if (branches.isEmpty) return const SizedBox.shrink();
    final active = ref.watch(activeBranchProvider);
    final isAdmin = ref.watch(authControllerProvider)?.isAdmin ?? false;

    Widget shell(Widget child) => Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: child,
    );

    // Branch staff: pinned. Read-only label.
    if (!isAdmin) {
      final match = branches.where((b) => b.uuid == active);
      if (match.isEmpty) return const SizedBox.shrink();
      return shell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_mall_directory_rounded, size: 14, color: d.ice),
            const SizedBox(width: 7),
            Text(
              match.first.name,
              style: TextStyle(
                fontSize: 9.sp,
                color: d.text1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Owner/admin: free switching (only worth showing with 2+ branches).
    if (branches.length < 2) return const SizedBox.shrink();
    final exists = active != null && branches.any((b) => b.uuid == active);
    return shell(
      DropdownButton<String?>(
        value: exists ? active : null,
        underline: const SizedBox(),
        isDense: true,
        icon: Icon(Icons.expand_more_rounded, size: 18, color: d.text3),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.apps_rounded, size: 14, color: d.text3),
                const SizedBox(width: 7),
                Text(
                  'All branches',
                  style: TextStyle(
                    fontSize: 9.sp,
                    color: d.text1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (final b in branches)
            DropdownMenuItem<String?>(
              value: b.uuid,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store_mall_directory_rounded,
                    size: 14,
                    color: d.ice,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    b.name,
                    style: TextStyle(
                      fontSize: 9.sp,
                      color: d.text1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (v) => ref.read(activeBranchProvider.notifier).select(v),
      ),
    );
  }
}
