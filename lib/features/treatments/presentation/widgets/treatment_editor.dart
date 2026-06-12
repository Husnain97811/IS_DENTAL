import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';
import '../../domain/treatment.dart';
import '../treatments_controller.dart';

Future<void> showTreatmentEditor(BuildContext context, {Treatment? existing}) =>
    showDialog(
      context: context,
      builder: (_) => TreatmentEditorDialog(existing: existing),
    );

class TreatmentEditorDialog extends ConsumerStatefulWidget {
  const TreatmentEditorDialog({super.key, this.existing});
  final Treatment? existing;
  @override
  ConsumerState<TreatmentEditorDialog> createState() => _S();
}

class _S extends ConsumerState<TreatmentEditorDialog> {
  late final TextEditingController _name, _cat, _price, _dur;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _cat = TextEditingController(text: e?.category ?? '');
    _price = TextEditingController(text: e == null ? '' : '${e.price}');
    _dur = TextEditingController(text: e?.duration ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _cat, _price, _dur]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final e = widget.existing;
    await ref
        .read(treatmentRepositoryProvider)
        .upsertTreatment(
          Treatment(
            id: e?.id ?? 0,
            uuid: e?.uuid ?? '',
            name: _name.text.trim(),
            category: _cat.text.trim(),
            price: int.tryParse(_price.text) ?? 0,
            duration: _dur.text.trim(),
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    setState(() => _busy = true);
    await ref
        .read(treatmentRepositoryProvider)
        .softDeleteTreatment(widget.existing!.id);
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
                widget.existing == null ? 'New Procedure' : 'Edit Procedure',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),
              DentField(label: 'Procedure name', controller: _name),
              const SizedBox(height: 12),
              DentField(label: 'Category', controller: _cat),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DentField(
                      label: 'Price (Rs)',
                      controller: _price,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DentField(
                      label: 'Duration',
                      controller: _dur,
                      hint: 'e.g. 45 min',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2.4.h),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(foregroundColor: d.alert),
                      child: const Text('Delete'),
                    ),
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
