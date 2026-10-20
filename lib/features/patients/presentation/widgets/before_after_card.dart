import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';

/// Before / after / progress photos for one patient, grouped into cases
/// (one case = one treatment). Stored exactly like X-rays: encrypted, listed
/// on every computer, moved between computers with X-ray & photo transfer.
final patientPhotosProvider = StreamProvider.autoDispose
    .family<List<XrayRow>, int>(
      (ref, patientId) =>
          ref.watch(xrayRepositoryProvider).watchPhotos(patientId),
    );

/// Basic-plan usage. `n` (photo count) is part of the key so it refreshes
/// after every add or delete.
final _photoUsageProvider = FutureProvider.autoDispose
    .family<({int used, int limit, int left}), ({DateTime expires, int n})>(
      (ref, k) => ref
          .read(xrayRepositoryProvider)
          .usage(expiresAt: k.expires, photos: true),
    );

const _kinds = ['before', 'after', 'progress'];
String _kindLabel(String k) => switch (k) {
  'before' => 'Before',
  'after' => 'After',
  _ => 'Progress',
};

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
String _d(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';
String _dShort(DateTime t) => '${t.day} ${_months[t.month - 1]}';
String _fileDate(DateTime t) => '${t.day}-${_months[t.month - 1]}-${t.year}';
String _firstName(String full) {
  final s = full.trim();
  return s.isEmpty ? 'Patient' : s.split(RegExp(r'\s+')).first;
}

// ═════════════════════════════════════════════════════════════ cases ═════
class _Case {
  _Case(this.id, this.photos);
  final String id;
  final List<XrayRow> photos; // oldest first

  List<XrayRow> of(String kind) => photos.where((p) => p.kind == kind).toList();
  List<XrayRow> get befores => of('before');
  List<XrayRow> get afters => of('after');
  bool get canCompare => befores.isNotEmpty && afters.isNotEmpty;

  String get treatment => photos
      .map((p) => p.treatment)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  String get tooth => photos
      .map((p) => p.tooth)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  bool get consent => photos.isNotEmpty && photos.every((p) => p.consent);
  DateTime get first => photos.first.takenAt;
  DateTime get last => photos.last.takenAt;
  String get title => treatment.isEmpty ? 'Treatment photos' : treatment;
  String? get branchId => photos.last.branchId;
}

List<_Case> _group(List<XrayRow> rows) {
  final map = <String, List<XrayRow>>{};
  for (final r in rows) {
    (map[r.pairGroup ?? r.uuid] ??= <XrayRow>[]).add(r);
  }
  final cases = [for (final e in map.entries) _Case(e.key, e.value)];
  cases.sort((a, b) => b.last.compareTo(a.last)); // newest case first
  return cases;
}

// ═════════════════════════════════════════════════════════════ card ══════
class BeforeAfterCard extends ConsumerWidget {
  const BeforeAfterCard({
    super.key,
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
  });
  final int patientId;
  final String patientUuid, patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final photos =
        ref.watch(patientPhotosProvider(patientId)).value ?? const <XrayRow>[];
    final cases = _group(photos);

    final isLimited = !ref.watch(entitlementsProvider).unlimitedXrays;
    final expiresAt = ref
        .watch(licenseControllerProvider)
        .value
        ?.license
        ?.expiresAt;
    final usage = isLimited && expiresAt != null
        ? ref
              .watch(
                _photoUsageProvider((expires: expiresAt, n: photos.length)),
              )
              .value
        : null;

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
                Icon(Icons.compare_rounded, size: 20, color: d.tealDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Before & After',
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  usage != null
                      ? '${usage.used} / ${usage.limit} this year'
                      : '${photos.length}',
                  style: TextStyle(
                    color: usage != null && usage.left <= 10 ? d.warn : d.text4,
                    fontSize: usage != null ? 9.sp : 10.5.sp,
                    fontWeight: usage != null ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _addPhotos(context, ref, cases: cases),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.tealDeep,
                    side: BorderSide(color: d.teal.withValues(alpha: .5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  label: Text('Add', style: TextStyle(fontSize: 10.5.sp)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          if (cases.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No photos yet. Add a Before photo when treatment starts and '
                'an After photo when it is done — then compare them side by side.',
                style: TextStyle(color: d.text4, fontSize: 10.sp, height: 1.5),
              ),
            )
          else
            for (var i = 0; i < cases.length; i++) ...[
              if (i > 0) Divider(height: 1, color: d.line),
              _CaseTile(
                c: cases[i],
                patientId: patientId,
                patientUuid: patientUuid,
                patientName: patientName,
                onAdd: () =>
                    _addPhotos(context, ref, cases: cases, into: cases[i]),
              ),
            ],
        ],
      ),
    );
  }

  Future<void> _addPhotos(
    BuildContext context,
    WidgetRef ref, {
    required List<_Case> cases,
    _Case? into,
  }) async {
    // read everything before the first await — this widget may rebuild
    final repo = ref.read(xrayRepositoryProvider);
    final isLimited = !ref.read(entitlementsProvider).unlimitedXrays;
    final expiresAt = ref
        .read(licenseControllerProvider)
        .value
        ?.license
        ?.expiresAt;

    const group = XTypeGroup(
      label: 'Photos',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[group],
    );
    if (files.isEmpty || !context.mounted) return;

    final meta = await showDialog<_PhotoMeta>(
      context: context,
      builder: (_) => _PhotoDetailsDialog(
        patientId: patientId,
        count: files.length,
        cases: cases,
        into: into,
      ),
    );
    if (meta == null) return;

    if (!context.mounted) return;
    final by = ref.read(authControllerProvider)?.fullName ?? '';
    await addImagingFiles(
      context,
      repo: repo,
      files: files,
      label: '${_kindLabel(meta.kind).toLowerCase()} photo',
      patientId: patientId,
      patientUuid: patientUuid,
      isLimited: isLimited,
      expiresAt: expiresAt,
      kind: meta.kind,
      pairGroup: meta.caseId ?? Uuids.v4(),
      tooth: meta.tooth,
      treatment: meta.treatment,
      consent: meta.consent,
      consentBy: by,
      takenAt: meta.takenAt,
    );
  }
}

// ═════════════════════════════════════════════════════════════ one case ══
class _CaseTile extends ConsumerWidget {
  const _CaseTile({
    required this.c,
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
    required this.onAdd,
  });
  final _Case c;
  final int patientId;
  final String patientUuid, patientName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final span =
        _dShort(c.first) == _dShort(c.last) && c.first.year == c.last.year
        ? _d(c.first)
        : '${_dShort(c.first)} – ${_d(c.last)}';
    final sub = [
      if (c.tooth.isNotEmpty) 'Tooth ${c.tooth}',
      span,
      '${c.photos.length} photo${c.photos.length == 1 ? '' : 's'}',
    ].join('  ·  ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        (1.2.w).clamp(14.0, 20.0),
        14,
        (1.2.w).clamp(14.0, 20.0),
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 10.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (c.consent) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Patient allows use in clinic marketing',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: d.teal.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'CONSENT',
                                style: TextStyle(
                                  color: d.tealDeep,
                                  fontSize: 7.5.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: c.canCompare
                    ? () => showDialog(
                        context: context,
                        builder: (_) => _CompareDialog(
                          c: c,
                          patientId: patientId,
                          patientUuid: patientUuid,
                          patientName: patientName,
                        ),
                      )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                ),
                icon: const Icon(Icons.compare_rounded, size: 16),
                label: Text(
                  c.canCompare ? 'Compare' : 'Needs an After',
                  style: TextStyle(fontSize: 9.5.sp),
                ),
              ),
              IconButton(
                tooltip: 'Add a photo to this case',
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: d.text3,
                ),
                onPressed: onAdd,
              ),
              IconButton(
                tooltip: 'Edit case',
                icon: Icon(Icons.edit_outlined, size: 17, color: d.text3),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _EditCaseDialog(c: c),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in c.photos)
                _PhotoThumb(x: p, patientName: patientName),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════ thumbnail ═
class _PhotoThumb extends ConsumerWidget {
  const _PhotoThumb({required this.x, required this.patientName});
  final XrayRow x;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final w = (7.5.w).clamp(100.0, 140.0);
    final tone = switch (x.kind) {
      'before' => d.warn,
      'after' => d.tealDeep,
      _ => d.ice,
    };

    return GestureDetector(
      onTap: () {
        if (!x.isLocal) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This photo is on another computer. Use Settings → '
                'X-ray & photo transfer to bring it here.',
              ),
            ),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (_) => _PhotoViewer(x: x, patientName: patientName),
        );
      },
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
                height: w * .75,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (x.isLocal)
                      _Decrypted(x: x, width: w, fit: BoxFit.cover)
                    else
                      Tooltip(
                        message: 'On another computer — not transferred yet',
                        child: Container(
                          color: d.surface2,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.devices_other_rounded,
                            color: d.text4,
                            size: 22,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tone,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _kindLabel(x.kind).toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dShort(x.takenAt),
                      style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                    ),
                  ),
                  _ThumbMenu(x: x, patientName: patientName),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbMenu extends ConsumerWidget {
  const _ThumbMenu({required this.x, required this.patientName});
  final XrayRow x;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    return PopupMenuButton<String>(
      tooltip: 'More',
      iconSize: 16,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, size: 16, color: d.text4),
      color: d.surface,
      onSelected: (v) async {
        final repo = ref.read(xrayRepositoryProvider);
        if (v.startsWith('kind:')) {
          await repo.setPhotoKind(x, v.substring(5));
        } else if (v == 'save') {
          await _savePhoto(context, repo, x, patientName);
        } else if (v == 'wa') {
          await _sharePhoto(context, ref, x);
        } else if (v == 'delete') {
          final ok = await showDentDialog(
            context,
            kind: DentDialogKind.warning,
            title: 'Delete photo?',
            message:
                'This removes the photo from every computer in the '
                'clinic once they sync.',
            confirmLabel: 'Delete',
            cancelLabel: 'Cancel',
          );
          if (ok == true) await repo.delete(x);
        }
      },
      itemBuilder: (_) => [
        for (final k in _kinds)
          if (k != x.kind)
            PopupMenuItem(
              value: 'kind:$k',
              child: Text(
                'Mark as ${_kindLabel(k)}',
                style: TextStyle(fontSize: 10.sp),
              ),
            ),
        if (x.isLocal) ...[
          PopupMenuItem(
            value: 'wa',
            child: Text('Send on WhatsApp', style: TextStyle(fontSize: 10.sp)),
          ),
          PopupMenuItem(
            value: 'save',
            child: Text('Save to Downloads', style: TextStyle(fontSize: 10.sp)),
          ),
        ],
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Delete',
            style: TextStyle(fontSize: 10.sp, color: d.alert),
          ),
        ),
      ],
    );
  }
}

/// Decrypts one photo and writes it to Downloads, with "Saving…" shown.
Future<void> _savePhoto(
  BuildContext context,
  XrayRepository repo,
  XrayRow x,
  String patientName,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final saved = await runBusy(context, 'Saving to Downloads…', (_) async {
      final bytes = await repo.readBytes(x);
      final dot = x.fileName.lastIndexOf('.');
      final ext = dot > 0 ? x.fileName.substring(dot).toLowerCase() : '.jpg';
      return saveToDownloads(
        bytes,
        '${_firstName(patientName)}_${_kindLabel(x.kind)}_${_fileDate(x.takenAt)}$ext',
      );
    });
    showSavedToDownloads(messenger, saved);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not save: ${'$e'.replaceFirst('Bad state: ', '')}',
        ),
      ),
    );
  }
}

Future<void> _sharePhoto(BuildContext context, WidgetRef ref, XrayRow x) {
  final repo = ref.read(xrayRepositoryProvider);
  return sharePatientFileOnWhatsApp(
    context: context,
    db: ref.read(appDatabaseProvider),
    patientId: x.patientId,
    load: () => repo.readBytes(x),
    label: '${_kindLabel(x.kind)} photo',
    ext: extOf(x.fileName),
    date: x.takenAt,
  );
}

/// Decrypts in the background and shows the photo. `cacheWidth` keeps a
/// 12 MP photo from being held at full size for a small tile.
class _Decrypted extends ConsumerWidget {
  const _Decrypted({required this.x, required this.width, required this.fit});
  final XrayRow x;
  final double width;
  final BoxFit fit;

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
          child: Icon(Icons.lock_outline_rounded, color: d.text4, size: 24),
        ),
      ),
      data: (b) => Image.memory(
        b,
        fit: fit,
        cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.broken_image_rounded, color: d.text4, size: 24),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════ viewer ════
class _PhotoViewer extends ConsumerWidget {
  const _PhotoViewer({required this.x, required this.patientName});
  final XrayRow x;
  final String patientName;

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
                child: Text(
                  '$e'.replaceFirst('Bad state: ', ''),
                  style: TextStyle(color: Colors.white70, fontSize: 11.sp),
                ),
              ),
              data: (b) => InteractiveViewer(
                maxScale: 6,
                child: Center(child: Image.memory(b, fit: BoxFit.contain)),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _sharePhoto(context, ref, x),
                  icon: const Icon(
                    Icons.chat_rounded,
                    color: Color(0xFF25D366),
                    size: 18,
                  ),
                  label: Text(
                    'Send on WhatsApp',
                    style: TextStyle(color: Colors.white, fontSize: 10.sp),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _savePhoto(
                    context,
                    ref.read(xrayRepositoryProvider),
                    x,
                    patientName,
                  ),
                  icon: const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Save to Downloads',
                    style: TextStyle(color: Colors.white, fontSize: 10.sp),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: Text(
              '${_kindLabel(x.kind)}  ·  ${_d(x.takenAt)}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════ compare ═══
class _CompareDialog extends ConsumerStatefulWidget {
  const _CompareDialog({
    required this.c,
    required this.patientId,
    required this.patientUuid,
    required this.patientName,
  });
  final _Case c;
  final int patientId;
  final String patientUuid, patientName;
  @override
  ConsumerState<_CompareDialog> createState() => _CompareDialogState();
}

class _CompareDialogState extends ConsumerState<_CompareDialog> {
  late int _b = 0; // earliest before
  late int _a = widget.c.afters.length - 1; // latest after
  bool _slider = true;
  double _t = .5;
  bool _saving = false, _sending = false;

  XrayRow get _before => widget.c.befores[_b];
  XrayRow get _after => widget.c.afters[_a];

  AsyncValue<Uint8List> _bytes(XrayRow x) => ref.watch(
    xrayBytesProvider((uuid: x.uuid, path: x.filePath, enc: x.isEncrypted)),
  );

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final c = widget.c;
    final bAsync = _before.isLocal ? _bytes(_before) : null;
    final aAsync = _after.isLocal ? _bytes(_after) : null;
    final bBytes = bAsync?.value, aBytes = aAsync?.value;
    final ready = bBytes != null && aBytes != null;
    final maxW = 100.w < 900 ? 94.w : 72.w;

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: EdgeInsets.all((2.w).clamp(12.0, 40.0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 92.h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            widget.patientName,
                            if (c.tooth.isNotEmpty) 'Tooth ${c.tooth}',
                          ].join('  ·  '),
                          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(
                          'Slider',
                          style: TextStyle(fontSize: 9.5.sp),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(
                          'Side by side',
                          style: TextStyle(fontSize: 9.5.sp),
                        ),
                      ),
                    ],
                    selected: {_slider},
                    onSelectionChanged: (s) =>
                        setState(() => _slider = s.first),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 19, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (c.befores.length > 1 || c.afters.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    if (c.befores.length > 1)
                      _picker(
                        d,
                        'Before',
                        c.befores,
                        _b,
                        (i) => setState(() => _b = i),
                      ),
                    if (c.afters.length > 1)
                      _picker(
                        d,
                        'After',
                        c.afters,
                        _a,
                        (i) => setState(() => _a = i),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // pictures
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: !_before.isLocal || !_after.isLocal
                      ? _note(
                          d,
                          'One of these photos is on another computer. '
                          'Use Settings → X-ray & photo transfer to bring it here.',
                        )
                      : (bAsync?.hasError ?? false) ||
                            (aAsync?.hasError ?? false)
                      ? _note(
                          d,
                          'Could not open one of these photos on this computer.',
                        )
                      : !ready
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (_, box) => _slider
                              ? _sliderView(d, box, bBytes, aBytes)
                              : _sideView(d, box, bBytes, aBytes),
                        ),
                ),
              ),
              const SizedBox(height: 14),

              // actions
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Before ${_d(_before.takenAt)}  →  After ${_d(_after.takenAt)}',
                        style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: !ready || _saving
                          ? null
                          : () => _save(bBytes, aBytes),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: d.text2,
                        side: BorderSide(color: d.line),
                        minimumSize: const Size(0, 42),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 17),
                      label: Text(
                        'Save to Downloads',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: !ready || _sending
                          ? null
                          : () => _send(bBytes, aBytes),
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size(0, 42),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_rounded, size: 17),
                      label: Text(
                        'Send on WhatsApp',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(DentColors d, String t) => Padding(
    padding: const EdgeInsets.all(30),
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: TextStyle(color: d.text3, fontSize: 10.5.sp),
    ),
  );

  Widget _picker(
    DentColors d,
    String label,
    List<XrayRow> rows,
    int sel,
    ValueChanged<int> on,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label: ',
        style: TextStyle(color: d.text3, fontSize: 9.5.sp),
      ),
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(
              _dShort(rows[i].takenAt),
              style: TextStyle(fontSize: 9.sp),
            ),
            selected: i == sel,
            onSelected: (_) => on(i),
            visualDensity: VisualDensity.compact,
          ),
        ),
    ],
  );

  /// Drag (or click) anywhere to move the divider.
  Widget _sliderView(
    DentColors d,
    BoxConstraints box,
    Uint8List b,
    Uint8List a,
  ) {
    final w = box.maxWidth.isFinite && box.maxHeight.isFinite
        ? (box.maxHeight * 4 / 3).clamp(0.0, box.maxWidth)
        : box.maxWidth;
    final h = w * 3 / 4;
    final px = (w * MediaQuery.devicePixelRatioOf(context)).round();
    void move(Offset p) => setState(() => _t = (p.dx / w).clamp(.02, .98));

    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            onHorizontalDragUpdate: (e) => move(e.localPosition),
            onTapDown: (e) => move(e.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    a,
                    fit: BoxFit.cover,
                    cacheWidth: px,
                    gaplessPlayback: true,
                  ),
                  ClipRect(
                    clipper: _LeftPart(_t),
                    child: Image.memory(
                      b,
                      fit: BoxFit.cover,
                      cacheWidth: px,
                      gaplessPlayback: true,
                    ),
                  ),
                  Positioned(
                    left: _t * w - 1.5,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 3, color: Colors.white),
                  ),
                  Positioned(
                    left: _t * w - 19,
                    top: h / 2 - 19,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        size: 20,
                        color: d.text2,
                      ),
                    ),
                  ),
                  Positioned(left: 12, top: 12, child: _tag('BEFORE')),
                  Positioned(right: 12, top: 12, child: _tag('AFTER')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideView(DentColors d, BoxConstraints box, Uint8List b, Uint8List a) {
    var pw = (box.maxWidth - 12) / 2;
    if (box.maxHeight.isFinite && pw * 3 / 4 > box.maxHeight)
      pw = box.maxHeight * 4 / 3;
    final px = (pw * MediaQuery.devicePixelRatioOf(context)).round();
    Widget panel(Uint8List bytes, String tag) => SizedBox(
      width: pw,
      height: pw * 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: px,
              gaplessPlayback: true,
            ),
            Positioned(left: 12, top: 12, child: _tag(tag)),
          ],
        ),
      ),
    );
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          panel(b, 'BEFORE'),
          const SizedBox(width: 12),
          panel(a, 'AFTER'),
        ],
      ),
    );
  }

  Widget _tag(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      t,
      style: TextStyle(
        color: Colors.white,
        fontSize: 8.5.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );

  Future<Uint8List> _compose(Uint8List b, Uint8List a) async {
    final clinic = await ref.read(appDatabaseProvider).clinicName() ?? '';
    final c = widget.c;
    return buildComparisonPng(
      before: b,
      after: a,
      clinicName: clinic,
      title: [
        c.title,
        if (c.tooth.isNotEmpty) 'Tooth ${c.tooth}',
      ].join('  ·  '),
      beforeDate: _before.takenAt,
      afterDate: _after.takenAt,
    );
  }

  String get _fileName {
    final t = widget.c.treatment.isEmpty ? '' : '_${widget.c.treatment}';
    return 'Before-After_${_firstName(widget.patientName)}${t}_${_fileDate(_after.takenAt)}.png';
  }

  Future<void> _save(Uint8List b, Uint8List a) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await runBusy(
        context,
        'Building the picture and saving to Downloads…',
        (_) async => saveToDownloads(await _compose(b, a), _fileName),
      );
      showSavedToDownloads(messenger, saved);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Builds the side-by-side picture and opens WhatsApp on the patient's
  /// chat with it ready to paste.
  Future<void> _send(Uint8List b, Uint8List a) async {
    setState(() => _sending = true);
    try {
      await sharePatientFileOnWhatsApp(
        context: context,
        db: ref.read(appDatabaseProvider),
        patientId: widget.patientId,
        load: () => _compose(b, a),
        label: 'Before & after',
        ext: '.png',
        date: _after.takenAt,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _LeftPart extends CustomClipper<Rect> {
  const _LeftPart(this.t);
  final double t;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);
  @override
  bool shouldReclip(_LeftPart old) => old.t != t;
}

// ═════════════════════════════════════════════════════════════ add dialog ═
class _PhotoMeta {
  const _PhotoMeta({
    required this.kind,
    required this.caseId,
    required this.treatment,
    required this.tooth,
    required this.consent,
    required this.takenAt,
  });
  final String kind;
  final String? caseId; // null = new case
  final String treatment, tooth;
  final bool consent;
  final DateTime takenAt;
}

class _PhotoDetailsDialog extends ConsumerStatefulWidget {
  const _PhotoDetailsDialog({
    required this.patientId,
    required this.count,
    required this.cases,
    this.into,
  });
  final int patientId, count;
  final List<_Case> cases;
  final _Case? into;
  @override
  ConsumerState<_PhotoDetailsDialog> createState() =>
      _PhotoDetailsDialogState();
}

class _PhotoDetailsDialogState extends ConsumerState<_PhotoDetailsDialog> {
  final _treatment = TextEditingController();
  final _tooth = TextEditingController();
  late String? _caseId = widget.into?.id;
  late String _kind = _defaultKind(widget.into);
  bool _consent = false;
  DateTime _taken = DateTime.now();

  static String _defaultKind(_Case? c) {
    if (c == null) return 'before';
    if (c.befores.isEmpty) return 'before';
    return c.afters.isEmpty ? 'after' : 'progress';
  }

  _Case? get _case {
    for (final c in widget.cases) {
      if (c.id == _caseId) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _treatment.dispose();
    _tooth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final joined = _case;
    final procs = <String>{
      for (final a
          in ref
                  .watch(appointmentsForPatientProvider(widget.patientId))
                  .value ??
              const <Appointment>[])
        if (a.procedure.trim().isNotEmpty) a.procedure.trim(),
    }.take(6).toList();

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (38.w).clamp(420.0, 560.0),
          maxHeight: 88.h,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.count == 1 ? 'Add photo' : 'Add ${widget.count} photos',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              _label(d, 'PHOTO IS'),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final k in _kinds)
                    ButtonSegment(
                      value: k,
                      label: Text(
                        _kindLabel(k),
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),

              if (widget.into == null && widget.cases.isNotEmpty) ...[
                _label(d, 'ADD TO'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: d.line),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _caseId,
                      isExpanded: true,
                      dropdownColor: d.surface,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'New case',
                            style: TextStyle(color: d.text1, fontSize: 10.5.sp),
                          ),
                        ),
                        for (final c in widget.cases)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              '${c.title} · ${_dShort(c.first)}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 10.5.sp,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _caseId = v;
                        final c = _case;
                        if (c != null) _kind = _defaultKind(c);
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (joined != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    'Adding to "${joined.title}"'
                    '${joined.tooth.isEmpty ? '' : ' · Tooth ${joined.tooth}'}',
                    style: TextStyle(
                      color: d.text2,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                _label(d, 'TREATMENT'),
                TextField(
                  controller: _treatment,
                  style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                  decoration: _dec(d, 'e.g. Scaling, Braces, Veneers'),
                ),
                if (procs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in procs)
                        ActionChip(
                          label: Text(p, style: TextStyle(fontSize: 9.sp)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _treatment.text = p),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _label(d, 'TOOTH (OPTIONAL)'),
                TextField(
                  controller: _tooth,
                  style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                  decoration: _dec(d, 'e.g. 8, or Upper front'),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Patient allows use in clinic marketing',
                    style: TextStyle(color: d.text1, fontSize: 10.sp),
                  ),
                  subtitle: Text(
                    'Shows the case in Showcase — never with the patient\'s name',
                    style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                  ),
                ),
              ],
              const SizedBox(height: 10),

              _label(d, 'TAKEN ON'),
              InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _taken,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (p != null) {
                    setState(
                      () => _taken = DateTime(
                        p.year,
                        p.month,
                        p.day,
                        _taken.hour,
                        _taken.minute,
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: d.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded, size: 17, color: d.text3),
                      const SizedBox(width: 10),
                      Text(
                        _d(_taken),
                        style: TextStyle(color: d.text1, fontSize: 10.5.sp),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(120, 44),
                    ),
                    onPressed: () {
                      final c = _case;
                      Navigator.pop(
                        context,
                        _PhotoMeta(
                          kind: _kind,
                          caseId: c?.id,
                          treatment: c?.treatment ?? _treatment.text,
                          tooth: c?.tooth ?? _tooth.text,
                          consent: c?.consent ?? _consent,
                          takenAt: _taken,
                        ),
                      );
                    },
                    child: Text('Add', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════ edit case ══
class _EditCaseDialog extends ConsumerStatefulWidget {
  const _EditCaseDialog({required this.c});
  final _Case c;
  @override
  ConsumerState<_EditCaseDialog> createState() => _EditCaseDialogState();
}

class _EditCaseDialogState extends ConsumerState<_EditCaseDialog> {
  late final _treatment = TextEditingController(text: widget.c.treatment);
  late final _tooth = TextEditingController(text: widget.c.tooth);
  late bool _consent = widget.c.consent;
  bool _busy = false;

  @override
  void dispose() {
    _treatment.dispose();
    _tooth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (34.w).clamp(400.0, 520.0)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit case',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _label(d, 'TREATMENT'),
              TextField(
                controller: _treatment,
                style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                decoration: _dec(d, 'e.g. Scaling, Braces, Veneers'),
              ),
              const SizedBox(height: 14),
              _label(d, 'TOOTH (OPTIONAL)'),
              TextField(
                controller: _tooth,
                style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                decoration: _dec(d, 'e.g. 8, or Upper front'),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Patient allows use in clinic marketing',
                  style: TextStyle(color: d.text1, fontSize: 10.sp),
                ),
                subtitle: Text(
                  _consentNote(widget.c, ticked: _consent),
                  style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(120, 44),
                    ),
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await ref
                                .read(xrayRepositoryProvider)
                                .updateCase(
                                  widget.c.id,
                                  treatment: _treatment.text,
                                  tooth: _tooth.text,
                                  consent: _consent,
                                  by:
                                      ref
                                          .read(authControllerProvider)
                                          ?.fullName ??
                                      '',
                                );
                            if (context.mounted) Navigator.pop(context);
                          },
                    child: Text('Save', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Consent recorded by Sara on 12 Oct 2026 · shows in Showcase"
String _consentNote(_Case c, {required bool ticked}) {
  if (!ticked)
    return 'Tick to show this case in Showcase (no patient name is shown)';
  if (!c.consent)
    return 'Will be recorded as given today, by you · shows in Showcase';
  DateTime? at;
  var by = '';
  for (final p in c.photos) {
    at ??= p.consentAt;
    if (by.isEmpty) by = p.consentBy;
  }
  if (at == null) return 'Shows in Showcase';
  return 'Recorded${by.isEmpty ? '' : ' by $by'} on ${_d(at)} · shows in Showcase';
}

// ═════════════════════════════════════════════════════════════ helpers ═══
Widget _label(DentColors d, String t) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    t,
    style: TextStyle(
      color: d.text4,
      fontSize: 8.5.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .5,
    ),
  ),
);

InputDecoration _dec(DentColors d, String hint) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
  filled: true,
  fillColor: d.surface2,
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: d.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: d.ice),
  ),
);
