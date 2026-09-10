import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/utils/qr_payload.dart';
import 'package:printing/printing.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../data/prescription_pdf.dart';
import 'prescription_editor.dart';

/// Builds the PDF bytes for a prescription (pulls clinic + patient details).
Future<RxPdfData?> buildRxData(WidgetRef ref, Prescription rx) async {
  final db = ref.read(appDatabaseProvider);
  final profile = await db.select(db.clinicProfile).getSingleOrNull();
  final p = await (db.select(
    db.patients,
  )..where((t) => t.id.equals(rx.patientId))).getSingleOrNull();
  if (p == null) return null;

  final clinicId = await db.currentClinicId() ?? '';

  return RxPdfData(
    clinicName: profile?.name ?? 'Clinic',
    branchLine: await db.rxSetting('address', profile?.branch ?? ''),
    contactLine: await db.rxSetting('contact'),
    regLine: await db.rxSetting('reg'),
    footer: await db.rxSetting(
      'footer',
      'This prescription is valid for the named patient only. '
          'Please complete the full course of any antibiotic.',
    ),
    patientName: p.fullName,
    patientCode: p.code,
    age: p.age,
    gender: p.gender.isEmpty
        ? ''
        : p.gender[0].toUpperCase() + p.gender.substring(1),
    allergies: p.allergies,
    qrPayload: buildPatientQrPayload(clinicId: clinicId, patientUuid: p.uuid),
    rx: rx,
  );
}

/// Opens the system print dialog for a prescription.
Future<void> printPrescription(
  BuildContext context,
  WidgetRef ref,
  Prescription rx,
) async {
  final data = await buildRxData(ref, rx);
  if (data == null) return;
  final bytes = await PrescriptionPdf.build(data);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Prescription_${rx.rxNo}',
  );
}

Future<void> showPrescriptionPreview(
  BuildContext context, {
  required Prescription rx,
  required String patientName,
  required String patientUuid,
  String? allergies,
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _Preview(
      rx: rx,
      patientName: patientName,
      patientUuid: patientUuid,
      allergies: allergies,
    ),
  ),
);

class _Preview extends ConsumerStatefulWidget {
  const _Preview({
    required this.rx,
    required this.patientName,
    required this.patientUuid,
    this.allergies,
  });
  final Prescription rx;
  final String patientName, patientUuid;
  final String? allergies;
  @override
  ConsumerState<_Preview> createState() => _S();
}

class _S extends ConsumerState<_Preview> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final rx = widget.rx;
    final maxW = 100.w < 640 ? 94.w : 56.w;

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
            // header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.teal.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      size: 18,
                      color: d.tealDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rx.rxNo,
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12.sp,
                            color: d.text1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.patientName}  ·  ${_fmt(rx.issuedAt)}',
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rx.doctorName.isNotEmpty ||
                        rx.appointmentLabel.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: d.surface2,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: d.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rx.doctorName.isNotEmpty)
                              Text(
                                'Prescribed by  ·  ${rx.doctorName}',
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (rx.appointmentLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  'Visit  ·  ${rx.appointmentLabel}',
                                  style: TextStyle(
                                    color: d.text3,
                                    fontSize: 9.5.sp,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    if ((widget.allergies ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
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
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],

                    _h(d, 'Medicines'),
                    for (var i = 0; i < rx.items.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: d.line)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}.',
                                style: TextStyle(
                                  color: d.text4,
                                  fontSize: 10.sp,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rx.items[i].medicine,
                                    style: TextStyle(
                                      color: d.text1,
                                      fontSize: 10.5.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (rx.items[i].instructions.isNotEmpty)
                                    Text(
                                      rx.items[i].instructions,
                                      style: TextStyle(
                                        color: d.text4,
                                        fontSize: 9.sp,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                rx.items[i].dosage,
                                style: TextStyle(
                                  color: d.text2,
                                  fontSize: 10.sp,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                rx.items[i].frequency,
                                style: TextStyle(
                                  color: d.text2,
                                  fontSize: 10.sp,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                rx.items[i].duration,
                                style: TextStyle(
                                  color: d.text2,
                                  fontSize: 10.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (rx.care.isNotEmpty) ...[
                      _h(d, 'Precautions & aftercare'),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: d.teal.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: d.teal.withValues(alpha: .35),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (final c in rx.care)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (c.urdu.isNotEmpty)
                                      Text(
                                        c.urdu,
                                        textAlign: TextAlign.right,
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          fontFamily: 'NotoNaskhArabic',
                                          fontSize: 11.5.sp,
                                          color: d.text1,
                                          height: 1.8,
                                        ),
                                      ),
                                    if (c.english.isNotEmpty)
                                      Text(
                                        c.english,
                                        style: TextStyle(
                                          color: d.text3,
                                          fontSize: 9.5.sp,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    if (rx.advice.isNotEmpty) ...[
                      _h(d, 'Advice'),
                      Text(
                        rx.advice,
                        style: TextStyle(color: d.text2, fontSize: 10.sp),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showPrescriptionEditor(
                        context,
                        patientId: rx.patientId,
                        patientUuid: widget.patientUuid,
                        patientName: widget.patientName,
                        allergies: widget.allergies,
                        existing: rx,
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.text2,
                      side: BorderSide(color: d.line),
                      minimumSize: const Size(0, 44),
                    ),
                    label: Text('Edit', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _savePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: d.text2,
                      side: BorderSide(color: d.line),
                      minimumSize: const Size(0, 44),
                    ),
                    label: Text(
                      'Save PDF',
                      style: TextStyle(fontSize: 10.5.sp),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _print,
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded, size: 17),
                    label: Text('Print', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    await printPrescription(context, ref, widget.rx);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _savePdf() async {
    setState(() => _busy = true);
    final data = await buildRxData(ref, widget.rx);
    if (data == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final bytes = await PrescriptionPdf.build(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Prescription_${widget.rx.rxNo}.pdf',
    );
    if (mounted) setState(() => _busy = false);
  }

  Widget _h(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
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

  String _fmt(DateTime dt) =>
      '${dt.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} '
      '${dt.year}';
}
