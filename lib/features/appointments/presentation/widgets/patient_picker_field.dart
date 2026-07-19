import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import 'package:is_dental/core/theme/app_typography.dart';
import 'package:is_dental/core/theme/dent_colors.dart';
import 'package:is_dental/core/widgets/dent_avatar.dart';
import 'package:is_dental/features/patients/domain/patient.dart';

sealed class PatientChoice {
  const PatientChoice();
}

class ExistingPatientChoice extends PatientChoice {
  const ExistingPatientChoice(this.patient);
  final Patient patient;
}

class NewPatientChoice extends PatientChoice {
  const NewPatientChoice(this.name);
  final String name;
}

class PatientPickerField extends StatefulWidget {
  const PatientPickerField({
    super.key,
    required this.patients,
    required this.onChanged,
    this.initial,
    this.label = 'Patient',
    this.hint = 'Search or type a new name…',
  });

  final List<Patient> patients;
  final ValueChanged<PatientChoice?> onChanged;
  final Patient? initial;
  final String label;
  final String hint;

  @override
  State<PatientPickerField> createState() => _PatientPickerFieldState();
}

class _PatientPickerFieldState extends State<PatientPickerField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  PatientChoice? _choice;
  bool _dismissed = false; // true after an explicit tap → hide dropdown

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    final init = widget.initial;
    if (init != null) {
      _ctrl.text = init.fullName;
      _query = init.fullName;
      _choice = ExistingPatientChoice(init);
      _dismissed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_choice);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _trimmed => _query.trim();

  List<Patient> get _matches {
    final q = _trimmed.toLowerCase();
    if (q.isEmpty) return const [];
    return widget.patients
        .where(
          (p) => '${p.fullName} ${p.phone} ${p.code}'.toLowerCase().contains(q),
        )
        .take(6)
        .toList();
  }

  bool get _hasExactName => widget.patients.any(
    (p) => p.fullName.toLowerCase() == _trimmed.toLowerCase(),
  );

  bool get _showSuggestions =>
      _focus.hasFocus && _trimmed.isNotEmpty && !_dismissed;

  // Typing now commits a choice immediately, so the Confirm button enables.
  void _onTextChanged(String v) {
    setState(() {
      _query = v;
      _dismissed = false;
      final t = v.trim();
      if (t.isEmpty) {
        _choice = null;
      } else {
        Patient? exact;
        for (final p in widget.patients) {
          if (p.fullName.toLowerCase() == t.toLowerCase()) {
            exact = p;
            break;
          }
        }
        _choice = exact != null
            ? ExistingPatientChoice(exact)
            : NewPatientChoice(t);
      }
    });
    widget.onChanged(_choice);
  }

  void _selectExisting(Patient p) {
    setState(() {
      _choice = ExistingPatientChoice(p);
      _ctrl.text = p.fullName;
      _query = p.fullName;
      _dismissed = true;
    });
    _focus.unfocus();
    widget.onChanged(_choice);
  }

  void _createNew() {
    final name = _trimmed;
    if (name.isEmpty) return;
    setState(() {
      _choice = NewPatientChoice(name);
      _dismissed = true;
    });
    _focus.unfocus();
    widget.onChanged(_choice);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            fontSize: 7.5.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            color: d.text4,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onTextChanged,
          style: TextStyle(fontSize: 9.sp, color: d.text1),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
            prefixIcon: Icon(Icons.search_rounded, color: d.text4, size: 11.sp),
            suffixIcon: _choice == null
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 11.sp,
                      color: d.text4,
                    ),
                    onPressed: () {
                      setState(() {
                        _choice = null;
                        _ctrl.clear();
                        _query = '';
                        _dismissed = false;
                      });
                      widget.onChanged(null);
                    },
                  ),
            filled: true,
            fillColor: d.surface2,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.ice, width: 1.5),
            ),
          ),
        ),

        // confirmation hint (only when the dropdown isn't open)
        if (!_showSuggestions && _choice is NewPatientChoice)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              "New patient — “${(_choice as NewPatientChoice).name}” will be "
              'created when you confirm the booking.',
              style: TextStyle(fontSize: 7.5.sp, color: d.teal, height: 1.4),
            ),
          )
        else if (!_showSuggestions && _choice is ExistingPatientChoice)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              'Existing patient · #${(_choice as ExistingPatientChoice).patient.code}',
              style: AppTypography.mono(size: 7.5.sp, color: d.text4),
            ),
          ),

        // live suggestions
        // live suggestions
        if (_showSuggestions)
          TextFieldTapRegion(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: BoxConstraints(maxHeight: 30.h),
              decoration: BoxDecoration(
                color: d.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: d.line),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final p in _matches) _suggestionTile(d, p),
                  if (!_hasExactName) _createTile(d),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _suggestionTile(DentColors d, Patient p) => InkWell(
    onTap: () => _selectExisting(p),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          DentAvatar(
            p.initials,
            bg: const Color(0x2638BDF8),
            fg: const Color(0xFF38BDF8),
            size: 32,
            radius: 9,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  style: TextStyle(
                    color: d.text1,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.sp,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '#${p.code} · ${p.phone}',
                  style: AppTypography.mono(size: 7.sp, color: d.text4),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _createTile(DentColors d) => InkWell(
    onTap: _createNew,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: d.teal.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.person_add_alt_1_rounded,
              size: 11.sp,
              color: d.teal,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 9.sp, color: d.text2),
                children: [
                  const TextSpan(text: 'Create new patient  '),
                  TextSpan(
                    text: '“$_trimmed”',
                    style: TextStyle(
                      color: d.text1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
