import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/shell/widgets/formatters.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';
import '../../domain/patient.dart';
import '../patients_controller.dart';

Future<void> showPatientEditor(BuildContext context, {Patient? existing}) =>
    showDialog(
      context: context,
      builder: (_) => PatientEditorDialog(existing: existing),
    );

class PatientEditorDialog extends ConsumerStatefulWidget {
  const PatientEditorDialog({super.key, this.existing});
  final Patient? existing;
  @override
  ConsumerState<PatientEditorDialog> createState() => _S();
}

class _S extends ConsumerState<PatientEditorDialog> {
  late final TextEditingController _name,
      _code,
      _phone,
      _cnic,
      _age,
      _allergies,
      _insurance;
  late Gender _gender;
  late PatientStatus _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.fullName ?? '');
    _code = TextEditingController(
      text: e?.code ?? 'PT-${10000 + Random().nextInt(89999)}',
    );
    _phone = TextEditingController(text: e?.phone ?? '');
    _cnic = TextEditingController(text: e?.cnic ?? '');
    _age = TextEditingController(text: e == null ? '' : '${e.age}');
    _allergies = TextEditingController(text: e?.allergies ?? '');
    _insurance = TextEditingController(text: e?.insurance ?? '');
    _gender = e?.gender ?? Gender.female;
    _status = e?.status ?? PatientStatus.active;
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _phone, _cnic, _age, _allergies, _insurance])
      c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final e = widget.existing;
    await ref
        .read(patientRepositoryProvider)
        .upsertPatient(
          Patient(
            id: e?.id ?? 0,
            uuid: e?.uuid ?? '',

            code: _code.text.trim(),
            fullName: _name.text.trim(),
            gender: _gender,
            age: int.tryParse(_age.text) ?? 0,
            phone: _phone.text.trim(),
            cnic: _cnic.text.trim(),
            allergies: _allergies.text.trim().isEmpty
                ? null
                : _allergies.text.trim(),
            insurance: _insurance.text.trim().isEmpty
                ? null
                : _insurance.text.trim(),
            lastVisit: e?.lastVisit,
            visitCount: e?.visitCount ?? 0,
            balance: e?.balance ?? 0,
            status: _status,
            treatmentSummary: e?.treatmentSummary ?? '',
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'Add Patient' : 'Edit Patient',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),
              DentField(label: 'Full name', controller: _name),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DentField(label: 'Patient ID', controller: _code),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DentField(
                      label: 'Phone',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Expanded(
                  //   child: DentField(label: 'Patient ID', controller: _code),
                  // ),
                  // const SizedBox(width: 12),
                  Expanded(
                    child: DentField(
                      label: 'CNIC',
                      controller: _cnic,
                      hint: '35202-1234567-1',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CnicInputFormatter(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DentField(
                      label: 'Age',
                      controller: _age,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dd<Gender>(
                      'Gender',
                      _gender,
                      Gender.values,
                      (v) => setState(() => _gender = v),
                      (g) => g.name,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _dd<PatientStatus>(
                'Status',
                _status,
                PatientStatus.values,
                (v) => setState(() => _status = v),
                (s) => s.name,
              ),
              const SizedBox(height: 12),
              DentField(label: 'Allergies (optional)', controller: _allergies),
              const SizedBox(height: 12),
              DentField(label: 'Insurance (optional)', controller: _insurance),
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

  Widget _dd<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T> onChanged,
    String Function(T) name,
  ) {
    final d = context.dent;
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    return Column(
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
            items: [
              for (final i in items)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    cap(name(i)),
                    style: TextStyle(fontSize: 9.sp, color: d.text1),
                  ),
                ),
            ],
            onChanged: (v) => onChanged(v as T),
          ),
        ),
      ],
    );
  }
}
