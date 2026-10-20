import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/views.dart';

/// Adds picked X-rays or photos one by one behind "Adding 2 of 3…", then
/// says exactly what happened: a ✓ message, or a dialog naming every file
/// that could not be added and why. Used by the X-ray and Before & After
/// cards.
///
/// [label] is singular and lower-case after the first word: "X-ray",
/// "before photo".
Future<void> addImagingFiles(
  BuildContext context, {
  required XrayRepository repo,
  required List<XFile> files,
  required String label,
  required int patientId,
  required String patientUuid,
  required bool isLimited,
  DateTime? expiresAt,
  String kind = 'xray',
  String? pairGroup,
  String tooth = '',
  String treatment = '',
  bool consent = false,
  String consentBy = '',
  DateTime? takenAt,
}) async {
  if (files.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final failed = <String>[];
  String? limitError;
  var added = 0;

  await runBusy(context, 'Adding $label…', (status) async {
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      status.value = files.length == 1
          ? 'Encrypting and saving the $label…'
          : 'Adding $label ${i + 1} of ${files.length}…';
      try {
        final err = await repo.add(
          patientId: patientId,
          patientUuid: patientUuid,
          sourcePath: f.path,
          fileName: f.name,
          takenAt: takenAt,
          isLimited: isLimited,
          expiresAt: expiresAt,
          kind: kind,
          pairGroup: pairGroup,
          tooth: tooth,
          treatment: treatment,
          consent: consent,
          consentBy: consentBy,
        );
        if (err != null) {
          limitError = err;
          break; // the plan's limit — the rest would fail the same way
        }
        added++;
      } catch (e) {
        failed.add('• ${f.name} — ${_reason(e)}');
      }
    }
  });

  final plural = added == 1 ? label : '${label}s';
  if (limitError == null && failed.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text('✓ $added $plural added and encrypted.')),
    );
    return;
  }
  if (!context.mounted) return;
  await showDentDialog(
    context,
    kind: DentDialogKind.warning,
    title: added == 0 ? 'Nothing was added' : 'Some files were not added',
    message: [
      if (added > 0) '$added $plural added.',
      if (limitError != null) limitError!,
      if (failed.isNotEmpty) 'Could not add:\n${failed.join('\n')}',
    ].join('\n\n'),
    confirmLabel: 'OK',
  );
}

String _reason(Object e) {
  if (e is FileSystemException) {
    return 'the file could not be read (moved, or no permission)';
  }
  final s = '$e'
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}
