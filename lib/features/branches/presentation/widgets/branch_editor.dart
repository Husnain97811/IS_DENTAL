import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';
import '../../domain/branch.dart';
import '../branch_controller.dart';

Future<void> showBranchEditor(BuildContext context, {Branch? existing}) =>
    showDialog(
      context: context,
      builder: (_) => BranchEditorDialog(existing: existing),
    );

class BranchEditorDialog extends ConsumerStatefulWidget {
  const BranchEditorDialog({super.key, this.existing});
  final Branch? existing;
  @override
  ConsumerState<BranchEditorDialog> createState() => _S();
}

class _S extends ConsumerState<BranchEditorDialog> {
  late final TextEditingController _name, _loc;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _loc = TextEditingController(text: e?.location ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _loc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final e = widget.existing;
    await ref
        .read(branchRepositoryProvider)
        .upsertBranch(
          Branch(
            id: e?.id ?? 0,
            uuid: e?.uuid ?? '',
            name: _name.text.trim(),
            location: _loc.text.trim(),
            isPrimary: e?.isPrimary ?? false,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'Add Branch' : 'Edit Branch',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),
              DentField(label: 'Branch name', controller: _name),
              const SizedBox(height: 12),
              DentField(
                label: 'Location',
                controller: _loc,
                hint: 'City / address',
              ),
              SizedBox(height: 2.4.h),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                    ),
                    onPressed: _busy ? null : _save,
                    child: _busy
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
            ],
          ),
        ),
      ),
    );
  }
}
