import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/settings/domain/permissions.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../data/xray_export.dart';

/// Owner/Admin only. Exports every stored X-ray as a ZIP,
/// one folder per patient.
class XrayExportButton extends ConsumerStatefulWidget {
  const XrayExportButton({super.key});
  @override
  ConsumerState<XrayExportButton> createState() => _XrayExportButtonState();
}

class _XrayExportButtonState extends ConsumerState<XrayExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    // ── PERMISSION GATE — owner always; others as configured ──
    if (!ref.watch(canProvider(Perm.exportXrays))) {
      return const SizedBox.shrink();
    }

    return OutlinedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: d.ice),
            )
          : const Icon(Icons.download_rounded, size: 16),
      style: OutlinedButton.styleFrom(
        foregroundColor: d.text2,
        side: BorderSide(color: d.line),
        minimumSize: const Size.fromHeight(42),
      ),
      label: Text(
        _busy ? 'Exporting…' : 'Download all X-rays (ZIP)',
        style: TextStyle(fontSize: 10.5.sp),
      ),
    );
  }

  Future<void> _export() async {
    print('>>> export tapped');
    final db = ref.read(appDatabaseProvider);
    final clinic = await db.clinicName() ?? 'Clinic';
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final suggested = '${XrayExport.sanitizePublic(clinic)}_Xrays_$stamp.zip';
    print('>>> suggested name: $suggested');

    try {
      final location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'ZIP archive', extensions: ['zip']),
        ],
      );
      print('>>> save location: ${location?.path}');
      if (location == null) return;

      setState(() => _busy = true);
      final branchId = await db.currentBranchId();
      print('>>> exporting for branch: $branchId');
      final res = await XrayExport.buildZip(
        db: db,
        savePath: location.path,
        branchId: branchId,
      );
      print('>>> result ok=${res.ok} files=${res.fileCount} err=${res.error}');
      if (!mounted) return;
      setState(() => _busy = false);

      await showDentDialog(
        context,
        kind: res.ok ? DentDialogKind.success : DentDialogKind.error,
        title: res.ok ? 'Export complete' : 'Export failed',
        message: res.ok
            ? '${res.fileCount} X-ray(s) from ${res.patientCount} patient(s) '
                  'saved to:\n${location.path}'
            : (res.error ?? 'Something went wrong.'),
        confirmLabel: 'Done',
      );
    } catch (e, st) {
      print('>>> export EXCEPTION: $e');
      print(st);
      if (mounted) setState(() => _busy = false);
    }
  }
}
