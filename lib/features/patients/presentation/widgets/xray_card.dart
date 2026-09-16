import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sizer/sizer.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/views.dart';

class XrayCard extends ConsumerWidget {
  const XrayCard({
    super.key,
    required this.patientId,
    required this.patientUuid,
  });
  final int patientId;
  final String patientUuid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final xrays =
        ref.watch(xraysProvider(patientId)).value ?? const <XrayRow>[];

    // license drives both the tier and the subscription window
    final lic = ref.watch(licenseControllerProvider).value?.license;
    final isLimited = lic?.tier == LicenseTier.basic;
    final expiresAt = lic?.expiresAt;

    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.image_rounded, size: 18, color: d.ice),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'X-rays & Imaging',
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                // ── usage / count ──
                if (isLimited && expiresAt != null)
                  FutureBuilder<({int used, int limit, int left})>(
                    future: ref
                        .read(xrayRepositoryProvider)
                        .usage(expiresAt: expiresAt),
                    builder: (_, snap) {
                      final u = snap.data;
                      if (u == null) return const SizedBox.shrink();
                      return Text(
                        '${u.used} / ${u.limit} this year',
                        style: TextStyle(
                          color: u.left <= 10 ? d.warn : d.text4,
                          fontSize: 8.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  )
                else
                  Text(
                    '${xrays.length}',
                    style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                  ),

                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      _pickAndAdd(context, ref, isLimited, expiresAt),

                  icon: const Icon(Icons.add_rounded, size: 15),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.ice,
                    side: BorderSide(color: d.ice.withValues(alpha: .5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  label: Text('Add', style: TextStyle(fontSize: 10.5.sp)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          if (xrays.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No X-rays yet. Tap Add to attach an image or PDF.',
                style: TextStyle(color: d.text4, fontSize: 9.sp),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final x in xrays) _thumb(context, ref, d, x)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, WidgetRef ref, DentColors d, XrayRow x) {
    final isPdf = x.fileType == 'pdf';
    return GestureDetector(
      onTap: () => _viewFull(context, d, x),
      child: Container(
        width: 108,
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: d.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              child: SizedBox(
                width: 108,
                height: 78,
                child: isPdf || !File(x.filePath).existsSync()
                    ? Container(
                        color: d.surface2,
                        child: Icon(
                          isPdf
                              ? Icons.picture_as_pdf_rounded
                              : Icons.broken_image_rounded,
                          color: d.text4,
                          size: 26,
                        ),
                      )
                    : Image.file(File(x.filePath), fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${x.takenAt.day}/${x.takenAt.month}/${x.takenAt.year}',
                      style: TextStyle(color: d.text3, fontSize: 7.5.sp),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final ok = await showDentDialog(
                        context,
                        kind: DentDialogKind.warning,
                        title: 'Delete X-ray?',
                        message:
                            'This permanently removes the file from this computer.',
                        confirmLabel: 'Delete',
                        cancelLabel: 'Cancel',
                      );
                      if (ok == true) {
                        await ref.read(xrayRepositoryProvider).delete(x);
                      }
                    },
                    child: Icon(Icons.close_rounded, size: 13, color: d.text4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewFull(BuildContext context, DentColors d, XrayRow x) async {
    if (x.fileType == 'pdf') {
      // open in the system viewer (Preview on macOS)
      final res = await OpenFilex.open(x.filePath);
      if (res.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${res.message}')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Image.file(File(x.filePath), fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndAdd(
    BuildContext context,
    WidgetRef ref,
    bool isLimited,
    DateTime? expiresAt,
  ) async {
    print('>>> opening picker');

    const typeGroup = XTypeGroup(
      label: 'X-rays',
      extensions: <String>['jpg', 'jpeg', 'png', 'pdf'],
    );
    final files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (files.isEmpty) return;

    final repo = ref.read(xrayRepositoryProvider);
    String? err;
    for (final f in files) {
      err = await repo.add(
        patientId: patientId,
        patientUuid: patientUuid,
        sourcePath: f.path,
        fileName: f.name,
        isLimited: isLimited,
        expiresAt: expiresAt,
      );
      if (err != null) break;
    }
    if (err != null && context.mounted) {
      await showDentDialog(
        context,
        kind: DentDialogKind.warning,
        title: 'Storage limit reached',
        message: err,
        confirmLabel: 'OK',
      );
    }
  }
}
