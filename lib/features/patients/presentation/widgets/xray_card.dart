import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../../core/device/device_service.dart';
import '../../data/xray_vault.dart';

/// X-rays on a patient record.
///
/// Every image is decrypted in memory for display — no readable copy is
/// ever written to disk — and PDFs render inside DentOS instead of being
/// handed to Preview or Acrobat. X-rays whose file is on another computer
/// show as placeholders until they are transferred.
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

    // Entitlements, not the tier string — offline AND basic are capped.
    final ent = ref.watch(entitlementsProvider);
    final isLimited = !ent.unlimitedXrays;
    final expiresAt = ref
        .watch(licenseControllerProvider)
        .value
        ?.license
        ?.expiresAt;

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
            padding: EdgeInsets.all((1.2.w).clamp(14.0, 20.0)),
            child: Row(
              children: [
                Icon(Icons.image_rounded, size: 20, color: d.ice),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'X-rays & Imaging',
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                          fontSize: 9.sp,
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
                  icon: const Icon(Icons.add_rounded, size: 16),
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
                style: TextStyle(color: d.text4, fontSize: 10.sp),
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
    final w = (7.5.w).clamp(100.0, 140.0);
    return GestureDetector(
      onTap: () => _viewFull(context, x),
      child: Container(
        width: w,
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
                width: w,
                height: w * .72,
                child: !x.isLocal
                    ? _ElsewhereTile(x: x)
                    : x.fileType == 'pdf'
                    ? Container(
                        color: d.surface2,
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: d.text4,
                          size: 28,
                        ),
                      )
                    : _ThumbImage(x: x, width: w),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  if (x.isEncrypted && x.isLocal)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_rounded, size: 11, color: d.teal),
                    ),
                  Expanded(
                    child: Text(
                      '${x.takenAt.day}/${x.takenAt.month}/${x.takenAt.year}',
                      style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      final ok = await showDentDialog(
                        context,
                        kind: DentDialogKind.warning,
                        title: 'Delete X-ray?',
                        message:
                            'This removes the X-ray from every computer in '
                            'the clinic once they sync.',
                        confirmLabel: 'Delete',
                        cancelLabel: 'Cancel',
                      );
                      if (ok == true) {
                        ref.read(xrayVaultProvider).forget(x.uuid);
                        await ref.read(xrayRepositoryProvider).delete(x);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: d.text4,
                      ),
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

  Future<void> _viewFull(BuildContext context, XrayRow x) async {
    if (!x.isLocal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This X-ray is on another computer. Use Settings → X-ray '
            'transfer to bring it here.',
          ),
        ),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _XrayViewer(x: x),
    );
  }

  Future<void> _pickAndAdd(
    BuildContext context,
    WidgetRef ref,
    bool isLimited,
    DateTime? expiresAt,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'X-rays',
      extensions: <String>['jpg', 'jpeg', 'png', 'pdf'],
    );
    final files = await openFiles(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (files.isEmpty) return;

    // repo.add encrypts on the way in — no readable copy is ever stored.
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

/// Decrypts in the background and shows a small version. `cacheWidth` stops
/// Flutter holding a full-resolution panoramic in memory for a thumbnail.
class _ThumbImage extends ConsumerWidget {
  const _ThumbImage({required this.x, required this.width});
  final XrayRow x;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final bytes = ref.watch(
      xrayBytesProvider((uuid: x.uuid, path: x.filePath, enc: x.isEncrypted)),
    );
    return bytes.when(
      loading: () => Container(
        color: d.surface2,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: d.text4),
        ),
      ),
      error: (e, _) => Tooltip(
        message: '$e'.replaceFirst('Bad state: ', ''),
        child: Container(
          color: d.surface2,
          child: Icon(Icons.lock_outline_rounded, color: d.text4, size: 26),
        ),
      ),
      data: (b) => Image.memory(
        b,
        fit: BoxFit.cover,
        cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.broken_image_rounded, color: d.text4, size: 26),
      ),
    );
  }
}

/// An X-ray that exists in the clinic but whose file is on another computer.
class _ElsewhereTile extends ConsumerWidget {
  const _ElsewhereTile({required this.x});
  final XrayRow x;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final dev = (ref.watch(devicesStreamProvider).value ?? const [])
        .where((v) => v.uuid == x.originDevice)
        .firstOrNull;
    final where = dev == null ? 'another computer' : 'Computer ${dev.letter}';
    return Tooltip(
      message: 'On $where — not transferred to this computer yet',
      child: Container(
        color: d.surface2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other_rounded, color: d.text4, size: 22),
            const SizedBox(height: 4),
            Text(
              'On $where',
              textAlign: TextAlign.center,
              style: TextStyle(color: d.text4, fontSize: 8.sp),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen viewer. Images zoom; PDFs are rasterised page by page inside
/// DentOS, so no readable file is ever handed to another program.
class _XrayViewer extends ConsumerWidget {
  const _XrayViewer({required this.x});
  final XrayRow x;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(
      xrayBytesProvider((uuid: x.uuid, path: x.filePath, enc: x.isEncrypted)),
    );

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.all((2.w).clamp(12.0, 40.0)),
      child: Stack(
        children: [
          Positioned.fill(
            child: bytes.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    '$e'.replaceFirst('Bad state: ', ''),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 11.sp),
                  ),
                ),
              ),
              data: (b) => x.fileType == 'pdf'
                  ? _PdfPages(bytes: b)
                  : InteractiveViewer(
                      maxScale: 6,
                      child: Center(
                        child: Image.memory(b, fit: BoxFit.contain),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfPages extends StatelessWidget {
  const _PdfPages({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Uint8List>>(
    future: Printing.raster(
      bytes,
      dpi: 120,
    ).asyncMap((page) => page.toPng()).toList(),
    builder: (_, snap) {
      if (snap.hasError) {
        return Center(
          child: Text(
            'Could not render this PDF.',
            style: TextStyle(color: Colors.white70, fontSize: 11.sp),
          ),
        );
      }
      if (!snap.hasData) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        );
      }
      return InteractiveViewer(
        maxScale: 5,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          children: [
            for (final p in snap.data!)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.memory(p, fit: BoxFit.contain),
              ),
          ],
        ),
      );
    },
  );
}
