import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/db/lookup_providers.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../expenses/data/expense_repository.dart';

/// Owner-editable dropdown lists: expense categories and payment methods.
class LookupPanel extends ConsumerStatefulWidget {
  const LookupPanel({super.key});
  @override
  ConsumerState<LookupPanel> createState() => _LookupPanelState();
}

class _LookupPanelState extends ConsumerState<LookupPanel> {
  int _tab = 0;

  String get _kind => _tab == 0 ? 'expense_category' : 'payment_method';

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final rows =
        ref
            .watch(
              _tab == 0 ? expenseCategoriesProvider : paymentMethodsProvider,
            )
            .value ??
        const <LookupRow>[];

    return DentPanel(
      title: 'Expense Lists',
      subtitle: 'Categories and payment methods',
      trailing: SegmentedControl(
        items: const ['Categories', 'Methods'],
        selected: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
      child: Column(
        children: [
          for (final r in rows)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename',
                    icon: Icon(Icons.edit_outlined, size: 15, color: d.text4),
                    onPressed: () => _rename(r),
                  ),
                  IconButton(
                    tooltip: 'Hide',
                    icon: Icon(
                      Icons.visibility_off_outlined,
                      size: 15,
                      color: d.text4,
                    ),
                    onPressed: () => _hide(r),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: d.ice,
                side: BorderSide(color: d.line),
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(_tab == 0 ? 'Add category' : 'Add method'),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _prompt(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    final d = context.dent;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          style: TextStyle(color: d.text1, fontSize: 10.sp),
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(dialogCtx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
            ),
            onPressed: () => Navigator.pop(dialogCtx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _prompt(_tab == 0 ? 'New category' : 'New method');
    if (name == null || name.isEmpty) return;
    await ref.read(expenseRepositoryProvider).addLookup(_kind, name);
    syncInBackground(ref);
  }

  Future<void> _rename(LookupRow r) async {
    final name = await _prompt('Rename', initial: r.name);
    if (name == null || name.isEmpty || name == r.name) return;
    await ref.read(expenseRepositoryProvider).renameLookup(r.id, name);
    syncInBackground(ref);
  }

  Future<void> _hide(LookupRow r) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Hide "${r.name}"?',
      message:
          'It disappears from the dropdown. Expenses already using it keep '
          'their category and still appear in reports.',
      confirmLabel: 'Hide',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;
    await ref.read(expenseRepositoryProvider).hideLookup(r.id);
    syncInBackground(ref);
  }
}
