import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';
import '../../../patients/presentation/patients_controller.dart';
import '../billing_controller.dart';

Future<void> showInvoiceEditor(BuildContext context) =>
    showDialog(context: context, builder: (_) => const InvoiceEditorDialog());

class InvoiceEditorDialog extends ConsumerStatefulWidget {
  const InvoiceEditorDialog({super.key});
  @override
  ConsumerState<InvoiceEditorDialog> createState() => _S();
}

class _Line {
  _Line() : desc = TextEditingController(), amt = TextEditingController();
  final TextEditingController desc, amt;
}

class _S extends ConsumerState<InvoiceEditorDialog> {
  int? _patientId;
  String _status = 'pending';
  late final TextEditingController _no, _adjustment;
  final List<_Line> _lines = [_Line()];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _no = TextEditingController(text: 'INV-${1000 + Random().nextInt(9000)}');
    _adjustment = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _no.dispose();
    _adjustment.dispose();
    for (final l in _lines) {
      l.desc.dispose();
      l.amt.dispose();
    }
    super.dispose();
  }

  int get _subtotal =>
      _lines.fold(0, (s, l) => s + (int.tryParse(l.amt.text) ?? 0));
  int get _total => _subtotal - (int.tryParse(_adjustment.text) ?? 0);
  String _m(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (x) => '${x[1]},',
  );

  Future<void> _save() async {
    final items = [
      for (final l in _lines)
        if (l.desc.text.trim().isNotEmpty &&
            (int.tryParse(l.amt.text) ?? 0) > 0)
          (description: l.desc.text.trim(), amount: int.parse(l.amt.text)),
    ];
    if (_patientId == null || items.isEmpty) return;
    setState(() => _busy = true);
    await ref
        .read(billingRepositoryProvider)
        .createInvoice(
          patientId: _patientId!,
          invoiceNo: _no.text.trim(),
          issuedAt: DateTime.now(),
          status: _status,
          summary: items.first.description,
          adjustment: int.tryParse(_adjustment.text) ?? 0,
          items: items,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patients = ref.watch(patientsStreamProvider).value ?? [];
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New Invoice',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Expanded(
                      child: _dd<int>(
                        d,
                        'Patient',
                        patients
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  p.fullName,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        _patientId,
                        (v) => setState(() => _patientId = v),
                        hint: 'Select…',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DentField(label: 'Invoice no.', controller: _no),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _dd<String>(
                  d,
                  'Status',
                  const ['pending', 'paid', 'overdue']
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                        ),
                      )
                      .toList(),
                  _status,
                  (v) => setState(() => _status = v!),
                ),
                SizedBox(height: 1.6.h),
                Text(
                  'LINE ITEMS',
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 7.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _lines[i].desc,
                            style: TextStyle(fontSize: 9.sp, color: d.text1),
                            decoration: _dec(d, 'Description'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _lines[i].amt,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(fontSize: 9.sp, color: d.text1),
                            decoration: _dec(d, 'Amount'),
                          ),
                        ),
                        IconButton(
                          onPressed: _lines.length == 1
                              ? null
                              : () => setState(() {
                                  _lines[i].desc.dispose();
                                  _lines[i].amt.dispose();
                                  _lines.removeAt(i);
                                }),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: d.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_Line())),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add line'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DentField(
                        label: 'Insurance adjustment',
                        controller: _adjustment,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TOTAL',
                          style: TextStyle(
                            color: d.text4,
                            fontSize: 7.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Rs ${_m(_total)}',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: d.text1,
                          ),
                        ),
                      ],
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
                      onPressed: (_busy || _patientId == null) ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.onAccent,
                              ),
                            )
                          : const Text('Create Invoice'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(DentColors d, String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: d.surface2,
    hintStyle: TextStyle(color: d.text4, fontSize: 8.5.sp),
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: d.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: d.ice, width: 1.5),
    ),
  );

  Widget _dd<T>(
    DentColors d,
    String label,
    List<DropdownMenuItem<T>> items,
    T? value,
    ValueChanged<T?> onChanged, {
    String? hint,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: d.text4,
          fontSize: 7.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          underline: const SizedBox(),
          hint: hint == null
              ? null
              : Text(
                  hint,
                  style: TextStyle(color: d.text4, fontSize: 9.sp),
                ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}
