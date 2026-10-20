import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/prescription_pdf.dart';
import 'prescription_editor.dart';
import 'package:is_dental/features/whatsapp/data/wa_outbox.dart';
import 'package:is_dental/core/utils/save_to_downloads.dart';
import 'package:is_dental/core/widgets/busy_dialog.dart';

/// Builds the PDF bytes for a prescription (pulls clinic + patient details).
Future<RxPdfData?> buildRxData(WidgetRef ref, Prescription rx) =>
    buildRxDataFrom(ref.read(appDatabaseProvider), rx);

/// Same as [buildRxData] but without a WidgetRef — used by the WhatsApp
/// sender, which runs after the editor dialog has closed.
Future<RxPdfData?> buildRxDataFrom(AppDatabase db, Prescription rx) async {
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

/// Builds the prescription PDF and writes it straight into Downloads
/// ("Prescription_RX-0000012_Ali.pdf"), with "Saving…" while it works and a
/// ✓ message with Show — or the reason it failed. Works with no internet.
Future<void> savePrescriptionToDownloads(
  BuildContext context,
  AppDatabase db,
  Prescription rx,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final saved = await runBusy(context, 'Saving prescription to Downloads…', (
      _,
    ) async {
      final data = await buildRxDataFrom(db, rx);
      if (data == null) throw StateError('The patient record was not found.');
      final bytes = await PrescriptionPdf.build(data);
      final first = data.patientName.trim().split(RegExp(r'\s+')).first;
      return saveToDownloads(
        bytes,
        'Prescription_${rx.rxNo}${first.isEmpty ? '' : '_$first'}.pdf',
      );
    });
    showSavedToDownloads(messenger, saved);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not save the prescription: ${'$e'.replaceFirst('Bad state: ', '')}',
        ),
      ),
    );
  }
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

            // WhatsApp status + send / resend
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _WaRxBar(rx: rx),
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
                      'Download PDF',
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
    await savePrescriptionToDownloads(
      context,
      ref.read(appDatabaseProvider),
      widget.rx,
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

/// One line under the prescription: has it gone on WhatsApp, plus Send / Resend.
class _WaRxBar extends ConsumerStatefulWidget {
  const _WaRxBar({required this.rx});
  final Prescription rx;
  @override
  ConsumerState<_WaRxBar> createState() => _WaRxBarState();
}

class _WaRxBarState extends ConsumerState<_WaRxBar> {
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // anything left waiting for internet (even from before a restart) is
    // retried now
    resumePendingWhatsApp(ProviderScope.containerOf(context, listen: false));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(rxWaStatusProvider(widget.rx.uuid));
    ref.invalidate(rxWaPendingProvider(widget.rx.id));
  }

  /// While a send is on its way, check again every 10 s so "Waiting…"
  /// turns into "Sent" by itself. Stops as soon as nothing is pending.
  void _pollWhile(bool active) {
    if (active && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) _refresh();
      });
    } else if (!active && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(rxWaStatusProvider(widget.rx.uuid));
    final waiting = ref.watch(rxWaPendingProvider(widget.rx.id)).value ?? false;
    final e = async.value;
    _pollWhile(waiting || (e?.isWaiting ?? false));

    final (String text, Color color) = switch (e?.status) {
      _ when waiting => (
        'No internet — will go on WhatsApp automatically once it is back',
        d.warn,
      ),
      null when async.isLoading => ('Checking WhatsApp…', d.text4),
      null when async.hasError => (
        'Can\'t check WhatsApp right now (no internet?)',
        d.text4,
      ),
      null => ('Not sent on WhatsApp yet', d.text3),
      'sent' => (
        'Sent on WhatsApp · ${_when(e!.sentAt ?? e.createdAt)}',
        d.tealDeep,
      ),
      'pending' || 'sending' => ('Waiting to go on WhatsApp…', d.ice),
      'failed' => ('WhatsApp failed · ${e!.lastError}', d.alert),
      _ => ('Not sent on WhatsApp · ${e!.lastError}', d.text3),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_rounded, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, size: 16, color: d.text4),
            onPressed: _refresh,
          ),
          TextButton.icon(
            onPressed: _sending || (e?.isWaiting ?? false) ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send_rounded, size: 15, color: d.tealDeep),
            label: Text(
              waiting ? 'Try now' : (e == null ? 'Send on WhatsApp' : 'Resend'),
              style: TextStyle(fontSize: 9.5.sp, color: d.tealDeep),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final c = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final by = ref.read(authControllerProvider)?.fullName ?? '';
    final r = await queuePrescriptionOnWhatsApp(
      c,
      widget.rx,
      manual: true,
      byName: by,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    _refresh();
    final msg = rxWaMessage(r, manual: true);
    if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time =
        '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'today $time';
    }
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${t.day} ${m[t.month - 1]} $time';
  }
}
