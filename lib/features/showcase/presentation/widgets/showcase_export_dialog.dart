import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../../core/utils/save_to_downloads.dart';
import '../../../patients/data/photo_compare_image.dart';
import '../../../patients/data/xray_vault.dart';
import '../../data/showcase_cases.dart';

/// Turns a case into a ready-to-post picture: pick the shape (square,
/// portrait, wide), the brand colour, edit the headline, see a live
/// preview, save to Downloads. The patient's name is never on it.
Future<void> showShowcaseExport(BuildContext context, ShowcaseCase c) =>
    showDialog(
      context: context,
      builder: (_) => _ExportDialog(c: c),
    );

// remembered while the app is open, so a batch of posts looks consistent
ShowcaseFormat _lastFormat = ShowcaseFormat.square;
int _lastAccent = 0;
bool _lastContact = true;
const _kContactKey = 'showcase_contact';

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog({required this.c});
  final ShowcaseCase c;
  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  late final _title = TextEditingController(text: widget.c.title);
  late final _line = TextEditingController(text: widget.c.durationLine);
  final _contactCtl = TextEditingController();
  ShowcaseFormat _format = _lastFormat;
  int _accent = _lastAccent;
  bool _contact = _lastContact;

  Uint8List? _before, _after, _preview;
  String _clinic = '';
  String? _error;
  bool _rendering = false, _saving = false;
  int _renderId = 0;
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _title.dispose();
    _line.dispose();
    _contactCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final vault = ref.read(xrayVaultProvider);
    try {
      final r = await Future.wait([
        vault.read(widget.c.before),
        vault.read(widget.c.after),
      ]);
      _before = r[0];
      _after = r[1];
      _clinic = await db.clinicName() ?? '';
      // the line used last time, otherwise the prescription letterhead's
      final saved = (await db.getSetting(_kContactKey) ?? '').trim();
      _contactCtl.text = saved.isNotEmpty
          ? saved
          : (await db.rxSetting('contact')).trim();
      await _render();
    } catch (e) {
      if (mounted)
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  /// Builds the post. Only the newest request is shown, so quick changes
  /// never flash an older picture.
  Future<void> _render() async {
    if (!mounted || _before == null || _after == null) return;
    final id = ++_renderId;
    setState(() => _rendering = true);
    try {
      final png = await _build();
      if (mounted && id == _renderId) {
        setState(() {
          _preview = png;
          _rendering = false;
        });
      }
    } catch (e) {
      if (mounted && id == _renderId) {
        setState(() {
          _error = '$e';
          _rendering = false;
        });
      }
    }
  }

  Future<Uint8List> _build() => buildShowcasePng(
    before: _before!,
    after: _after!,
    beforeCrop: widget.c.beforeCrop,
    afterCrop: widget.c.afterCrop,
    format: _format,
    clinicName: _clinic,
    contact: _contact ? _contactCtl.text.trim() : '',
    treatment: _title.text.trim(),
    duration: _line.text.trim(),
    accent: kShowcaseAccents[_accent],
  );

  void _set(VoidCallback change) {
    setState(change);
    _lastFormat = _format;
    _lastAccent = _accent;
    _lastContact = _contact;
    _render();
  }

  /// Re-render shortly after typing stops, not on every key.
  void _onTyped(String _) {
    setState(() {}); // keeps the empty-contact hint in step with the text
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 450), _render);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      _typing?.cancel();
      final png = await _build(); // always the exact current settings
      // remember the contact line for the next post
      unawaited(
        ref
            .read(appDatabaseProvider)
            .setSetting(_kContactKey, _contactCtl.text.trim()),
      );
      final n = DateTime.now();
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
      final name = (_title.text.trim().isEmpty ? 'Smile' : _title.text.trim())
          .replaceAll(RegExp(r'\s+'), '-');
      final saved = await saveToDownloads(
        png,
        'Showcase_${name}_${_format.label}_${n.day}-${m[n.month - 1]}-${n.year}.png',
      );
      if (!mounted) return;
      Navigator.pop(context);
      showSavedToDownloads(messenger, saved);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final wide = 100.w >= 900;
    final maxW = wide ? (78.w).clamp(820.0, 1240.0) : 94.w;

    final preview = _previewPane(d);
    final options = _optionsPane(d);

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: EdgeInsets.all((2.w).clamp(12.0, 40.0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 92.h),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.ice.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.ios_share_rounded,
                      size: 18,
                      color: d.ice,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create a post',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Ready for Instagram, Facebook, your website or the clinic TV',
                          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 19, color: d.text3),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: preview),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: (24.w).clamp(300.0, 360.0),
                            child: SingleChildScrollView(child: options),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 46.h, child: preview),
                            const SizedBox(height: 16),
                            options,
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: d.tealDeep,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No patient name on the picture · patient gave consent',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _preview == null || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Save to Downloads',
                      style: TextStyle(fontSize: 10.5.sp),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewPane(DentColors d) => Container(
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: d.line),
    ),
    padding: const EdgeInsets.all(18),
    child: _error != null
        ? Center(
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: d.alert, fontSize: 10.sp),
            ),
          )
        : _preview == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: _format.aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        _preview!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
              if (_rendering)
                Positioned(
                  right: 6,
                  top: 6,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: d.ice,
                    ),
                  ),
                ),
            ],
          ),
  );

  Widget _optionsPane(DentColors d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(d, 'SHAPE'),
      for (final f in ShowcaseFormat.values) ...[
        _formatTile(d, f),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      _label(d, 'COLOUR'),
      Wrap(
        spacing: 10,
        children: [
          for (var i = 0; i < kShowcaseAccents.length; i++)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _set(() => _accent = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kShowcaseAccents[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == _accent ? d.text1 : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: i == _accent
                    ? const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
        ],
      ),
      const SizedBox(height: 18),
      _label(d, 'HEADLINE'),
      _field(d, _title, 'e.g. Porcelain veneers'),
      const SizedBox(height: 10),
      _label(d, 'LINE UNDER IT'),
      _field(d, _line, 'e.g. Completed in 6 months'),
      const SizedBox(height: 8),
      SwitchListTile(
        value: _contact,
        onChanged: (v) => _set(() => _contact = v),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          'Show clinic contact',
          style: TextStyle(
            color: d.text1,
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Printed under the clinic name',
          style: TextStyle(color: d.text3, fontSize: 9.sp),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: _contact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(d, _contactCtl, 'e.g. 0300 1234567 · @smileclinic'),
                  if (_contactCtl.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Type a phone number, website or Instagram handle to show it on the post.',
                        style: TextStyle(color: d.warn, fontSize: 8.5.sp),
                      ),
                    ),
                ],
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );

  Widget _formatTile(DentColors d, ShowcaseFormat f) {
    final on = f == _format;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _set(() => _format = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? d.ice.withValues(alpha: .10) : d.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? d.ice : d.line, width: on ? 1.6 : 1),
        ),
        child: Row(
          children: [
            // a tiny outline of the shape
            SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: AspectRatio(
                  aspectRatio: f.aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: on ? d.ice : d.text4,
                        width: 1.6,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${f.label}  ·  ${f.size}',
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    f.useFor,
                    style: TextStyle(color: d.text3, fontSize: 9.sp),
                  ),
                ],
              ),
            ),
            if (on) Icon(Icons.check_circle_rounded, size: 18, color: d.ice),
          ],
        ),
      ),
    );
  }

  Widget _field(DentColors d, TextEditingController c, String hint) =>
      TextField(
        controller: c,
        onChanged: _onTyped,
        style: TextStyle(fontSize: 10.5.sp, color: d.text1),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
          filled: true,
          fillColor: d.surface2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: d.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: d.ice),
          ),
        ),
      );

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        color: d.text4,
        fontSize: 8.5.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    ),
  );
}
