import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../../licensing/presentation/license_providers.dart';
import '../branch_controller.dart';
import 'package:collection/collection.dart';

class BranchSwitcher extends ConsumerWidget {
  const BranchSwitcher({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    if (!ref.watch(isPremiumProvider)) return const SizedBox.shrink();
    final branches = ref.watch(branchesStreamProvider).value ?? [];
    if (branches.isEmpty) return const SizedBox.shrink();
    final active = ref.watch(activeBranchProvider);
    final role = ref.watch(authControllerProvider)?.role;
    final isOwner = role == AppRole.owner;
    Widget shell(Widget child) => Container(
      // height: 42,
      padding: EdgeInsets.all(6.sp),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: child,
    );

    // Branch staff: pinned. Read-only label.
    if (!isOwner) {
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
    // Owner/admin: free switching (only worth showing with 2+ branches).
    if (branches.length < 2) return const SizedBox.shrink();
    final exists = active != null && branches.any((b) => b.uuid == active);
    return shell(
      DropdownButton<String>(
        value: exists ? active : branches.first.uuid,
        underline: const SizedBox(),
        isDense: true,
        icon: Icon(Icons.expand_more_rounded, size: 18, color: d.text3),
        items: [
          for (final b in branches)
            DropdownMenuItem<String>(
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
        onChanged: (v) async {
          if (v == null) return;
          final label =
              branches
                  .where((b) => b.uuid == v)
                  .map((b) => b.name)
                  .firstOrNull ??
              'this branch';
          final ok = await showDentDialog(
            context,
            kind: DentDialogKind.warning,
            title: 'Switch branch?',
            message:
                'The whole app will reload to show data for $label only. Continue?',
            confirmLabel: 'Switch',
            cancelLabel: 'Cancel',
          );
          if (ok == true) {
            await ref.read(activeBranchProvider.notifier).select(v);
          }
        },
      ),
    );
  }
}
