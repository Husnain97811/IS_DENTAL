import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import '../../../../core/constants/views.dart';
import '../../data/expense_repository.dart';
import '../expenses_controller.dart';

const _monShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _m(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (x) => '${x[1]},',
);

/// Previews last month's expenses, confirms, then copies them into [p].
/// Nothing is written until the user agrees — the manual alternative to
/// auto-generated recurring rows.
Future<void> copyLastMonthFlow(
  BuildContext context,
  WidgetRef ref,
  Period p,
) async {
  final repo = ref.read(expenseRepositoryProvider);
  final branch = ref.read(activeBranchProvider);
  final from = DateTime(p.anchor.year, p.anchor.month - 1);
  final preview = await repo.previewCopy(from, branch);
  if (!context.mounted) return;

  if (preview.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nothing to copy from ${_monShort[from.month - 1]} ${from.year}.',
        ),
      ),
    );
    return;
  }

  final sum = preview.fold<int>(0, (s, e) => s + e.amount);
  final ok = await showDentDialog(
    context,
    kind: DentDialogKind.warning,
    title: 'Copy ${preview.length} expenses?',
    message:
        '${preview.length} entries totalling Rs ${_m(sum)} from '
        '${_monShort[from.month - 1]} ${from.year} will be copied into '
        '${p.label}. Edit the amounts afterwards if they changed.',
    confirmLabel: 'Copy them',
    cancelLabel: 'Cancel',
  );
  if (ok != true) return;

  final who = ref.read(authControllerProvider)?.username ?? '';
  final n = await repo.copyMonth(
    from: from,
    into: p.anchor,
    branchId: branch,
    by: who,
  );
  syncInBackground(ref);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$n expenses copied.')));
  }
}
