import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/constants/views.dart';
import '../../../core/utils/dent_snack.dart';

const _months = [
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

/// Opens WhatsApp on this patient's chat with an X-ray, photo or picture
/// ready to paste, and tells staff what to press. Shows "Preparing…" while
/// the file is decrypted/built, and every error as a message.
///
/// [load] produces the bytes (decrypt an X-ray, build a comparison…).
/// [label] names the file and the message ("X-ray", "Before photo",
/// "Before & after"). [ext] includes the dot (".jpg", ".pdf", ".png").
Future<void> sharePatientFileOnWhatsApp({
  required BuildContext context,
  required AppDatabase db,
  required int patientId,
  required Future<Uint8List> Function() load,
  required String label,
  required String ext,
  required DateTime date,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final out = await runBusy(context, 'Preparing $label for WhatsApp…', (
      _,
    ) async {
      final bytes = await load();
      final p = await (db.select(
        db.patients,
      )..where((t) => t.id.equals(patientId))).getSingleOrNull();
      final full = (p?.fullName ?? '').trim();
      final first = full.isEmpty ? 'Patient' : full.split(RegExp(r'\s+')).first;
      final fileName =
          '${first}_${label.replaceAll(' & ', '-').replaceAll(' ', '-')}_'
          '${date.day}-${_months[date.month - 1]}-${date.year}$ext';
      final r = await shareFileOnWhatsApp(
        bytes: bytes,
        fileName: fileName,
        phone: p?.phone ?? '',
      );
      return (r: r, first: first, phoned: (p?.phone ?? '').trim().isNotEmpty);
    });

    final what = label.startsWith('X-ray') ? label : label.toLowerCase();
    var text = waShareMessage(out.r.result, what: what, who: out.first);
    if (!out.phoned && out.r.result != WaShareResult.failed) {
      text =
          'This patient has no phone number — pick the chat in WhatsApp, '
          'then press ${waPasteKey()} to attach the $what.';
    }
    showDentSnack(
      messenger,
      duration: const Duration(seconds: 8),
      content: Text(text),
      action: out.r.result == WaShareResult.failed
          ? null
          : SnackBarAction(
              label: 'Show file',
              onPressed: () => revealInFolder(out.r.path),
            ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not prepare the $label: ${'$e'.replaceFirst('Bad state: ', '')}',
        ),
      ),
    );
  }
}

/// ".jpg" from "IMG_2041.JPG"; falls back to [fallback].
String extOf(String fileName, {String fallback = '.jpg'}) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(dot).toLowerCase() : fallback;
}
