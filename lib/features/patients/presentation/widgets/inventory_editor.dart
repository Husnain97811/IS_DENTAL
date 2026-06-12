import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/inventory/domain/inventory_item.dart';
import 'package:is_dental/features/inventory/presentation/inventory_controller.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';

Future<void> showInventoryEditor(
  BuildContext context, {
  InventoryItem? existing,
}) => showDialog(
  context: context,
  builder: (_) => InventoryEditorDialog(existing: existing),
);

class InventoryEditorDialog extends ConsumerStatefulWidget {
  const InventoryEditorDialog({super.key, this.existing});
  final InventoryItem? existing;
  @override
  ConsumerState<InventoryEditorDialog> createState() => _S();
}

class _S extends ConsumerState<InventoryEditorDialog> {
  late final TextEditingController _name, _cat, _stock, _par, _reorder, _unit;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _cat = TextEditingController(text: e?.category ?? '');
    _stock = TextEditingController(text: e == null ? '' : '${e.inStock}');
    _par = TextEditingController(text: e == null ? '' : '${e.parLevel}');
    _reorder = TextEditingController(text: e == null ? '' : '${e.reorderAt}');
    _unit = TextEditingController(text: e?.unit ?? 'units');
  }

  @override
  void dispose() {
    for (final c in [_name, _cat, _stock, _par, _reorder, _unit]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final e = widget.existing;
    await ref
        .read(inventoryRepositoryProvider)
        .upsertItem(
          InventoryItem(
            id: e?.id ?? 0,
            uuid: e?.uuid ?? '',
            name: _name.text.trim(),
            category: _cat.text.trim(),
            inStock: int.tryParse(_stock.text) ?? 0,
            parLevel: int.tryParse(_par.text) ?? 0,
            reorderAt: int.tryParse(_reorder.text) ?? 0,
            unit: _unit.text.trim().isEmpty ? 'units' : _unit.text.trim(),
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'Add Item' : 'Edit Item',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),
              DentField(label: 'Item name', controller: _name),
              const SizedBox(height: 12),
              DentField(label: 'Category', controller: _cat),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DentField(
                      label: 'In stock',
                      controller: _stock,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DentField(label: 'Unit', controller: _unit),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DentField(
                      label: 'Par (full) level',
                      controller: _par,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DentField(
                      label: 'Reorder at',
                      controller: _reorder,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
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
