import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../prescription_controller.dart';

Future<void> showMedicineEditor(BuildContext context, {Medicine? existing}) =>
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _MedicineEditor(existing: existing),
      ),
    );

const _kForms = [
  'Tablet',
  'Capsule',
  'Syrup',
  'Mouthwash',
  'Gel',
  'Injection',
  'Drops',
  'Ointment',
  'Other',
];
const _kCategories = [
  'Antibiotic',
  'Painkiller',
  'Antiseptic',
  'Gastro-protective',
  'Anti-inflammatory',
  'Supplement',
  'Topical',
  'Other',
];

class _MedicineEditor extends ConsumerStatefulWidget {
  const _MedicineEditor({this.existing});
  final Medicine? existing;
  @override
  ConsumerState<_MedicineEditor> createState() => _S();
}

class _S extends ConsumerState<_MedicineEditor> {
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _frequency = TextEditingController();
  String _form = 'Tablet';
  String _category = 'Antibiotic';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _dosage.text = e.defaultDosage;
      _frequency.text = e.defaultFrequency;
      if (_kForms.contains(e.form)) _form = e.form;
      if (_kCategories.contains(e.category)) _category = e.category;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _frequency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final maxW = 100.w < 520 ? 92.w : 46.w;
    final canSave = _name.text.trim().isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 88.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.ice.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.medication_liquid_rounded,
                      size: 17,
                      color: d.ice,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add Medicine'
                          : 'Edit Medicine',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: d.text1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(d, 'Medicine name'),
                    _tf(
                      d,
                      _name,
                      'e.g. Augmentin 625mg',
                      onChanged: (_) => setState(() {}),
                    ),

                    _lbl(d, 'Form'),
                    _dd(d, _form, _kForms, (v) => setState(() => _form = v!)),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _lbl(d, 'Default dosage'),
                              _tf(d, _dosage, '1 tab'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _lbl(d, 'Default frequency'),
                              _tf(d, _frequency, 'TDS (3× daily)'),
                            ],
                          ),
                        ),
                      ],
                    ),

                    _lbl(d, 'Category'),
                    _dd(
                      d,
                      _category,
                      _kCategories,
                      (v) => setState(() => _category = v!),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'Dosage and frequency are just defaults — they fill in '
                      'automatically when prescribing and can still be changed '
                      'for each patient.',
                      style: TextStyle(color: d.text4, fontSize: 9.5.sp),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: canSave ? d.ice : d.line,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    onPressed: (!canSave || _busy) ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Save', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref
        .read(prescriptionRepositoryProvider)
        .upsertMedicine(
          id: widget.existing?.id,
          name: _name.text.trim(),
          form: _form,
          defaultDosage: _dosage.text.trim(),
          defaultFrequency: _frequency.text.trim(),
          category: _category,
        );
    if (mounted) Navigator.pop(context);
  }

  Widget _lbl(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: 8.5.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _tf(
    DentColors d,
    TextEditingController c,
    String hint, {
    ValueChanged<String>? onChanged,
  }) => SizedBox(
    height: 44,
    child: TextField(
      controller: c,
      onChanged: onChanged,
      style: TextStyle(fontSize: 10.5.sp, color: d.text1),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: d.surface2,
        hintText: hint,
        hintStyle: TextStyle(color: d.text4, fontSize: 10.5.sp),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.ice),
        ),
      ),
    ),
  );

  Widget _dd(
    DentColors d,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: d.surface,
        borderRadius: BorderRadius.circular(12),
        icon: Icon(Icons.expand_more_rounded, size: 19, color: d.text3),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i,
              child: Text(
                i,
                style: TextStyle(fontSize: 10.5.sp, color: d.text1),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}
