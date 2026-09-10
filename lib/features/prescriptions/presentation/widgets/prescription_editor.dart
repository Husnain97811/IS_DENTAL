import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/prescriptions/data/prescription_pdf.dart';
import 'package:printing/printing.dart';
import 'package:sizer/sizer.dart';
import 'prescription_preview.dart';
import '../../../../core/constants/views.dart';
import '../prescription_controller.dart';

enum _SaveMode { none, pdf, print }

Future<void> showPrescriptionEditor(
  BuildContext context, {
  required int patientId,
  required String patientUuid,
  required String patientName,
  String? allergies,
  Prescription? existing,
  int? presetAppointmentId,
  String presetAppointmentLabel = '',
  String presetDoctorName = '',
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _Editor(
      patientId: patientId,
      patientUuid: patientUuid,
      patientName: patientName,
      allergies: allergies,
      existing: existing,
      presetAppointmentId: presetAppointmentId,
      presetAppointmentLabel: presetAppointmentLabel,
      presetDoctorName: presetDoctorName,
    ),
  ),
);

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
    this.allergies,
    this.existing,
    this.presetAppointmentId,
    this.presetAppointmentLabel = '',
    this.presetDoctorName = '',
  });
  final int patientId;
  final String patientUuid, patientName;
  final String? allergies;
  final Prescription? existing;
  final int? presetAppointmentId;
  final String presetAppointmentLabel, presetDoctorName;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _advice = TextEditingController();
  final List<_MedRow> _rows = [];
  final List<CareLine> _care = [];
  int? _appointmentId;
  String _appointmentLabel = '';
  String _doctorName = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _advice.text = e.advice;
      _appointmentId = e.appointmentId;
      _appointmentLabel = e.appointmentLabel;
      _doctorName = e.doctorName;
      _care.addAll(e.care);
      for (final m in e.items) _rows.add(_MedRow.from(m));
    } else if (widget.presetAppointmentId != null) {
      // opened from the Appointments screen — visit already known
      _appointmentId = widget.presetAppointmentId;
      _appointmentLabel = widget.presetAppointmentLabel;
      _doctorName = widget.presetDoctorName;
    }
    if (_rows.isEmpty) _rows.add(_MedRow());
  }

  @override
  void dispose() {
    _advice.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  bool _isAllergyRisk(String medicine) {
    final a = (widget.allergies ?? '').toLowerCase();
    if (a.isEmpty) return false;
    final m = medicine.toLowerCase();
    // crude but useful: penicillin family
    if (a.contains('penicillin') &&
        (m.contains('augmentin') ||
            m.contains('amoxil') ||
            m.contains('amoxic') ||
            m.contains('penicillin')))
      return true;
    // direct name match against the allergy text
    for (final w in a.split(RegExp(r'[,\s]+'))) {
      if (w.length > 3 && m.contains(w)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final meds = ref.watch(medicinesProvider).value ?? const <Medicine>[];
    final sets =
        ref.watch(precautionSetsProvider).value ?? const <PrecautionSet>[];
    final maxW = 100.w < 700 ? 94.w : 66.w;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 90.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
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
                      color: d.teal.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      size: 17,
                      color: d.tealDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.existing == null
                              ? 'New Prescription'
                              : 'Prescription ${widget.existing!.rxNo}',
                          style: TextStyle(
                            fontSize: 12.5.sp,
                            color: d.text1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.patientName,
                          style: TextStyle(fontSize: 9.5.sp, color: d.text3),
                        ),
                      ],
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
                    // allergy banner
                    if ((widget.allergies ?? '').trim().isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: d.alert.withValues(alpha: .08),
                          border: Border.all(
                            color: d.alert.withValues(alpha: .35),
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          'ALLERGY:  ${widget.allergies}',
                          style: TextStyle(
                            color: d.alert,
                            fontSize: 10.5.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                    // linked visit
                    _lbl(d, 'Linked visit'),
                    _VisitPicker(
                      patientId: widget.patientId,
                      selectedId: _appointmentId,
                      onPicked: (id, label, doctor) => setState(() {
                        _appointmentId = id;
                        _appointmentLabel = label;
                        _doctorName = doctor;
                      }),
                    ),
                    if (_doctorName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Prescribed by  ·  $_doctorName',
                          style: TextStyle(
                            color: d.text2,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                    _lbl(d, 'Medicines'),
                    for (var i = 0; i < _rows.length; i++) _medRow(d, meds, i),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _rows.add(_MedRow())),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: d.ice,
                        side: BorderSide(color: d.ice.withValues(alpha: .5)),
                      ),
                      label: Text(
                        'Add medicine',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),

                    _lbl(d, 'Precautions & aftercare'),
                    for (final s in sets) _setChips(d, s),
                    if (_care.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: d.surface2,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: d.line),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < _care.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (_care[i].urdu.isNotEmpty)
                                            Text(
                                              _care[i].urdu,
                                              textAlign: TextAlign.right,
                                              textDirection: TextDirection.rtl,
                                              style: TextStyle(
                                                fontFamily: 'NotoNaskhArabic',
                                                fontSize: 11.5.sp,
                                                color: d.text1,
                                                height: 1.7,
                                              ),
                                            ),
                                          if (_care[i].english.isNotEmpty)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                _care[i].english,
                                                style: TextStyle(
                                                  color: d.text3,
                                                  fontSize: 9.5.sp,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 15,
                                        color: d.alert,
                                      ),
                                      onPressed: () =>
                                          setState(() => _care.removeAt(i)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    _lbl(d, 'Advice (optional)'),
                    TextField(
                      controller: _advice,
                      maxLines: 2,
                      style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: d.surface2,
                        hintText: 'Review in 5 days…',
                        hintStyle: TextStyle(color: d.text4, fontSize: 10.5.sp),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(color: d.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(color: d.line),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // footer
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
                  OutlinedButton(
                    onPressed: _busy ? null : () => _save(mode: _SaveMode.none),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.text2,
                      side: BorderSide(color: d.line),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text('Save', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _save(mode: _SaveMode.pdf),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.text2,
                      side: BorderSide(color: d.line),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    label: Text(
                      'Save & PDF',
                      style: TextStyle(fontSize: 10.5.sp),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _save(mode: _SaveMode.print),
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded, size: 17),
                    label: Text(
                      'Save & Print',
                      style: TextStyle(fontSize: 10.5.sp),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lbl(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
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

  Widget _medRow(DentColors d, List<Medicine> meds, int i) {
    final r = _rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child: _MedicineField(
                  controller: r.medicine,
                  medicines: meds,
                  onPicked: (m) {
                    r.medicine.text = m.name;
                    if (r.dosage.text.isEmpty) r.dosage.text = m.defaultDosage;
                    if (r.frequency.text.isEmpty)
                      r.frequency.text = m.defaultFrequency;
                    setState(() {});
                    if (_isAllergyRisk(m.name)) {
                      showDentDialog(
                        context,
                        kind: DentDialogKind.warning,
                        title: 'Allergy warning',
                        message:
                            'This patient is allergic to ${widget.allergies}.\n\n'
                            '"${m.name}" may be unsuitable. Please confirm before prescribing.',
                        confirmLabel: 'I understand',
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _f(d, r.dosage, 'Dosage', '1 tab')),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _f(d, r.frequency, 'Frequency', 'TDS')),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _f(d, r.duration, 'Duration', '5 days')),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 17, color: d.alert),
                onPressed: _rows.length == 1
                    ? null
                    : () => setState(() {
                        _rows.removeAt(i).dispose();
                      }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _f(d, r.instructions, 'Instructions', 'After meals'),
        ],
      ),
    );
  }

  Widget _f(DentColors d, TextEditingController c, String label, String hint) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: d.text4,
              fontSize: 7.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 40,
            child: TextField(
              controller: c,
              style: TextStyle(fontSize: 10.sp, color: d.text1),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: d.surface,
                hintText: hint,
                hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: d.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: d.line),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _setChips(DentColors d, PrecautionSet s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.name,
                style: TextStyle(
                  color: d.text2,
                  fontSize: 9.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final l in s.lines) {
                  if (!_care.any(
                    (c) => c.urdu == l.urdu && c.english == l.english,
                  )) {
                    _care.add(l);
                  }
                }
              }),
              child: Text(
                '+ add all',
                style: TextStyle(fontSize: 9.sp, color: d.tealDeep),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final l in s.lines)
              _chip(
                d,
                l,
                _care.any((c) => c.urdu == l.urdu && c.english == l.english),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _chip(DentColors d, CareLine l, bool picked) => GestureDetector(
    onTap: () => setState(() {
      final idx = _care.indexWhere(
        (c) => c.urdu == l.urdu && c.english == l.english,
      );
      if (idx >= 0) {
        _care.removeAt(idx);
      } else {
        _care.add(l);
      }
    }),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: picked ? d.teal.withValues(alpha: .14) : d.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: picked ? d.tealDeep : d.line),
      ),
      child: Text(
        l.urdu.isNotEmpty ? l.urdu : l.english,
        textDirection: l.urdu.isNotEmpty
            ? TextDirection.rtl
            : TextDirection.ltr,
        style: TextStyle(
          fontFamily: l.urdu.isNotEmpty ? 'NotoNaskhArabic' : null,
          color: picked ? d.tealDeep : d.text2,
          fontSize: l.urdu.isNotEmpty ? 11.sp : 9.5.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Future<void> _save({required _SaveMode mode}) async {
    final items = _rows
        .map(
          (r) => MedicineItem(
            medicine: r.medicine.text.trim(),
            dosage: r.dosage.text.trim(),
            frequency: r.frequency.text.trim(),
            duration: r.duration.text.trim(),
            instructions: r.instructions.text.trim(),
          ),
        )
        .where((m) => m.medicine.isNotEmpty)
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine.')),
      );
      return;
    }

    var doctor = _doctorName;
    if (doctor.trim().isEmpty) {
      final session = ref.read(authControllerProvider);
      if (session?.role == AppRole.clinician) doctor = session?.fullName ?? '';
    }

    setState(() => _busy = true);
    try {
      final id = await ref
          .read(prescriptionRepositoryProvider)
          .save(
            id: widget.existing?.id,
            patientId: widget.patientId,
            patientUuid: widget.patientUuid,
            appointmentId: _appointmentId,
            appointmentLabel: _appointmentLabel,
            doctorName: doctor,
            advice: _advice.text.trim(),
            items: items,
            care: _care,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context);

      if (mode == _SaveMode.none) return;

      final saved = await ref.read(prescriptionRepositoryProvider).byId(id);
      if (saved == null || !context.mounted) return;

      if (mode == _SaveMode.print) {
        await printPrescription(context, ref, saved);
      } else {
        final data = await buildRxData(ref, saved);
        if (data == null) return;
        final bytes = await PrescriptionPdf.build(data);
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'Prescription_${saved.rxNo}.pdf',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }
}

/// Holds the controllers for one medicine row.
class _MedRow {
  _MedRow();
  factory _MedRow.from(MedicineItem m) {
    final r = _MedRow();
    r.medicine.text = m.medicine;
    r.dosage.text = m.dosage;
    r.frequency.text = m.frequency;
    r.duration.text = m.duration;
    r.instructions.text = m.instructions;
    return r;
  }
  final medicine = TextEditingController();
  final dosage = TextEditingController();
  final frequency = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();
  void dispose() {
    medicine.dispose();
    dosage.dispose();
    frequency.dispose();
    duration.dispose();
    instructions.dispose();
  }
}

/// Searchable medicine field backed by the catalog.
class _MedicineField extends StatelessWidget {
  const _MedicineField({
    required this.controller,
    required this.medicines,
    required this.onPicked,
  });
  final TextEditingController controller;
  final List<Medicine> medicines;
  final void Function(Medicine) onPicked;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MEDICINE',
          style: TextStyle(
            color: d.text4,
            fontSize: 7.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 40,
          child: RawAutocomplete<Medicine>(
            textEditingController: controller,
            focusNode: FocusNode(),
            optionsBuilder: (v) {
              final q = v.text.toLowerCase();
              if (q.isEmpty) return medicines;
              return medicines.where(
                (m) =>
                    m.name.toLowerCase().contains(q) ||
                    m.category.toLowerCase().contains(q),
              );
            },
            displayStringForOption: (m) => m.name,
            onSelected: onPicked,
            fieldViewBuilder: (ctx, ctl, fn, _) => TextField(
              controller: ctl,
              focusNode: fn,
              style: TextStyle(fontSize: 10.sp, color: d.text1),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: d.surface,
                hintText: 'Search catalog…',
                hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: d.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: d.line),
                ),
              ),
            ),
            optionsViewBuilder: (ctx, onSel, opts) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    maxWidth: 320,
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final m in opts)
                        ListTile(
                          dense: true,
                          title: Text(
                            m.name,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: d.text1,
                            ),
                          ),
                          subtitle: Text(
                            [
                              m.form,
                              m.defaultDosage,
                              m.defaultFrequency,
                              m.category,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 8.5.sp, color: d.text4),
                          ),
                          onTap: () => onSel(m),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dropdown of this patient's appointments. Picking one sets the linked visit
/// AND the prescribing doctor (the dentist on that appointment).
class _VisitPicker extends ConsumerWidget {
  const _VisitPicker({
    required this.patientId,
    required this.selectedId,
    required this.onPicked,
  });
  final int patientId;
  final int? selectedId;

  /// (appointmentId, label, doctorName) — all null/empty for "no visit".
  final void Function(int?, String, String) onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final appts =
        ref.watch(appointmentsForPatientProvider(patientId)).value ??
        const <Appointment>[];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          value: selectedId,
          hint: Text(
            'Select a visit (optional)',
            style: TextStyle(color: d.text4, fontSize: 10.5.sp),
          ),
          icon: Icon(Icons.expand_more_rounded, size: 19, color: d.text3),
          dropdownColor: d.surface,
          borderRadius: BorderRadius.circular(12),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(
                'No visit — standalone prescription',
                style: TextStyle(color: d.text3, fontSize: 10.5.sp),
              ),
            ),
            for (final a in appts)
              DropdownMenuItem<int?>(
                value: a.id,
                child: Text(
                  '${_fmt(a.startsAt)} · ${a.procedure}'
                  '${a.dentist.isEmpty ? '' : '  (${a.dentist})'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.text1, fontSize: 10.5.sp),
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) {
              onPicked(null, '', '');
              return;
            }
            final a = appts.firstWhere((x) => x.id == id);
            onPicked(a.id, '${_fmt(a.startsAt)} · ${a.procedure}', a.dentist);
          },
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} '
      '${dt.year}';
}
