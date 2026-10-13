import 'package:drift/drift.dart' hide Column;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../patients/data/xray_transfer.dart';

const _kExt = 'dentosx';

String _size(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}

final _xrayStatusProvider =
    StreamProvider.autoDispose<({int here, int elsewhere})>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.patientXrays,
      )..where((t) => t.isDeleted.equals(false))).watch().map(
        (rows) => (
          here: rows.where((r) => r.isLocal).length,
          elsewhere: rows.where((r) => !r.isLocal).length,
        ),
      );
    });

final _meProvider = FutureProvider<String>(
  (ref) async => (await ref.watch(appDatabaseProvider).localDevice()).uuid,
);

/// Settings panel. Gated on the Export X-rays permission.
class XrayTransferPanel extends ConsumerWidget {
  const XrayTransferPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canProvider(Perm.exportXrays))) {
      return const SizedBox.shrink();
    }
    final d = context.dent;
    final s = ref.watch(_xrayStatusProvider).value ?? (here: 0, elsewhere: 0);
    final cloud = ref.watch(entitlementsProvider).cloud;

    return DentPanel(
      title: 'X-ray transfer',
      subtitle: 'Encrypted — only DentOS can open them',
      child: Padding(
        padding: EdgeInsets.all((1.2.w).clamp(14.0, 20.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _stat(d, 'On this computer', '${s.here}', d.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _stat(
                    d,
                    'Not here yet',
                    '${s.elsewhere}',
                    s.elsewhere > 0 ? d.warn : d.text4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              cloud
                  ? 'X-rays stay on the computer that took them. Transfer '
                        'creates an encrypted file for another computer; '
                        'carry the file and the code separately.'
                  : 'Offline installs can create an encrypted backup. It can '
                        'only be opened with a recovery code from Inover Studio.',
              style: TextStyle(color: d.text3, fontSize: 10.sp, height: 1.5),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice,
                    foregroundColor: AppPalette.onAccent,
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _TransferDialog(),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    cloud ? 'Transfer X-rays' : 'Create backup',
                    style: TextStyle(fontSize: 10.5.sp),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.text2,
                    side: BorderSide(color: d.line),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _ReceiveDialog(),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'Receive X-rays',
                    style: TextStyle(fontSize: 10.5.sp),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(DentColors d, String label, String value, Color tone) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: d.text1,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: d.text3, fontSize: 9.5.sp),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog();
  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  /// '' = everything (new computer or backup).
  String? _target;
  Future<({int count, int bytes})>? _plan;
  bool _busy = false;
  String? _error;
  ({String code, DateTime expires, int count, int bytes})? _done;
  ({int count, int bytes})? _backupDone;

  void _replan() {
    final t = _target;
    _plan = ref
        .read(xrayTransferProvider)
        .plan(forDevice: (t == null || t.isEmpty) ? null : t);
  }

  Future<void> _go(BuildContext dialogCtx) async {
    final cloud = ref.read(entitlementsProvider).cloud;
    final db = ref.read(appDatabaseProvider);
    final clinic = (await db.clinicName() ?? 'Clinic').replaceAll(
      RegExp(r'[^A-Za-z0-9]+'),
      '-',
    );
    final n = DateTime.now();
    final stamp =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

    final loc = await getSaveLocation(
      suggestedName: '$clinic-xrays-$stamp.$_kExt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'DentOS X-ray transfer', extensions: [_kExt]),
      ],
    );
    if (loc == null) return;
    final path = loc.path.endsWith('.$_kExt') ? loc.path : '${loc.path}.$_kExt';

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (cloud) await ref.read(cloudServiceProvider).ensureSignedIn();
      final t = _target;
      final r = await ref
          .read(xrayTransferProvider)
          .export(
            savePath: path,
            forDevice: (t == null || t.isEmpty) ? null : t,
            by: ref.read(authControllerProvider)?.username ?? '',
            cloud: cloud,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r.error != null) {
          _error = r.error;
        } else if (r.code != null) {
          _done = (
            code: r.code!,
            expires: r.expiresAt!,
            count: r.count,
            bytes: r.bytes,
          );
        } else {
          _backupDone = (count: r.count, bytes: r.bytes);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext dialogCtx) {
    final d = dialogCtx.dent;
    final cloud = ref.watch(entitlementsProvider).cloud;
    final me = ref.watch(_meProvider).value;
    final devices = (ref.watch(devicesStreamProvider).value ?? const [])
        .where((x) => x.isActive && !x.isDeleted && x.uuid != me)
        .toList();

    if (_target == null && me != null) {
      _target = cloud && devices.isNotEmpty ? devices.first.uuid : '';
      _replan();
    }

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (38.w).clamp(420.0, 560.0)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                cloud ? 'Transfer X-rays' : 'Create encrypted backup',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (_done != null)
                ..._result(d, dialogCtx)
              else if (_backupDone != null)
                ..._backupResult(d, dialogCtx)
              else ...[
                if (cloud) ...[
                  _label(d, 'SEND TO'),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: d.surface2,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: d.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _target,
                        isExpanded: true,
                        dropdownColor: d.surface,
                        items: [
                          for (final x in devices)
                            DropdownMenuItem(
                              value: x.uuid,
                              child: Text(
                                '${x.name.isEmpty ? "Computer" : x.name} '
                                '(${x.letter}) — only what it is missing',
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.5.sp,
                                ),
                              ),
                            ),
                          DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Everything — new computer or backup',
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 10.5.sp,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _target = v;
                                _replan();
                              }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                FutureBuilder<({int count, int bytes})>(
                  future: _plan,
                  builder: (_, snap) {
                    final p = snap.data;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: d.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        p == null
                            ? 'Working out what to send…'
                            : p.count == 0
                            ? 'Nothing to send — that computer already has '
                                  'every X-ray from this one.'
                            : '${p.count} X-ray${p.count == 1 ? "" : "s"} · '
                                  '${_size(p.bytes)}',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: d.alert, fontSize: 10.sp),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(dialogCtx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size(170, 44),
                      ),
                      onPressed: _busy ? null : () => _go(dialogCtx),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Choose where to save'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _result(DentColors d, BuildContext dialogCtx) {
    final r = _done!;
    final h = r.expires.hour % 12 == 0 ? 12 : r.expires.hour % 12;
    final ap = r.expires.hour >= 12 ? 'PM' : 'AM';
    return [
      Text(
        '${r.count} X-rays · ${_size(r.bytes)} saved. On the other computer: '
        'Settings → X-ray transfer → Receive X-rays, pick the file, and enter '
        'this code.',
        style: TextStyle(color: d.text3, fontSize: 10.5.sp, height: 1.5),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: d.ice),
        ),
        child: Center(
          child: SelectableText(
            r.code,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              color: d.text1,
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Single use · valid until ${r.expires.day}/${r.expires.month} '
        '$h:${r.expires.minute.toString().padLeft(2, '0')} $ap · '
        'carry the file and the code separately',
        textAlign: TextAlign.center,
        style: TextStyle(color: d.text4, fontSize: 9.sp),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: d.text2,
                side: BorderSide(color: d.line),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => Clipboard.setData(ClipboardData(text: r.code)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy code'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _backupResult(DentColors d, BuildContext dialogCtx) => [
    Text(
      '${_backupDone!.count} X-rays · ${_size(_backupDone!.bytes)} saved as '
      'an encrypted backup. Keep it somewhere other than this computer. To '
      'open it, contact Inover Studio for a recovery code.',
      style: TextStyle(color: d.text3, fontSize: 10.5.sp, height: 1.5),
    ),
    const SizedBox(height: 18),
    FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: d.ice,
        foregroundColor: AppPalette.onAccent,
        minimumSize: const Size.fromHeight(44),
      ),
      onPressed: () => Navigator.pop(dialogCtx),
      child: const Text('Done'),
    ),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
class _ReceiveDialog extends ConsumerStatefulWidget {
  const _ReceiveDialog();
  @override
  ConsumerState<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends ConsumerState<_ReceiveDialog> {
  final _code = TextEditingController();
  final _token = TextEditingController();
  String? _path;
  bool _useRecovery = false;
  String? _request;
  bool _busy = false;
  int _done = 0, _total = 0;
  String? _error;
  ({int added, int already, int noPatient, int damaged})? _result;

  @override
  void dispose() {
    _code.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'DentOS X-ray transfer', extensions: [_kExt]),
      ],
    );
    if (f == null) return;
    setState(() {
      _path = f.path;
      _request = null;
      _error = null;
    });
    if (_useRecovery) await _makeRequest();
  }

  Future<void> _makeRequest() async {
    if (_path == null) return;
    try {
      final r = await ref.read(xrayTransferProvider).recoveryRequest(_path!);
      if (mounted) setState(() => _request = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _go() async {
    if (_path == null) {
      setState(() => _error = 'Choose the transfer file first.');
      return;
    }
    if (!_useRecovery && _code.text.trim().length < 6) {
      setState(() => _error = 'Enter the code from the other computer.');
      return;
    }
    if (_useRecovery && _token.text.trim().isEmpty) {
      setState(() => _error = 'Paste the recovery code from Inover Studio.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_useRecovery) {
        await ref.read(cloudServiceProvider).ensureSignedIn();
      }
      final r = await ref
          .read(xrayTransferProvider)
          .receive(
            path: _path!,
            code: _useRecovery ? null : _code.text,
            vendorToken: _useRecovery ? _token.text : null,
            onProgress: (a, b) {
              if (mounted) {
                setState(() {
                  _done = a;
                  _total = b;
                });
              }
            },
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r.error != null) {
          _error = r.error;
        } else {
          _result = (
            added: r.added,
            already: r.already,
            noPatient: r.noPatient,
            damaged: r.damaged,
          );
        }
      });
      // Tell the other computers what this one now holds.
      if (r.error == null) syncInBackground(ref);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext dialogCtx) {
    final d = dialogCtx.dent;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (38.w).clamp(420.0, 560.0)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Receive X-rays',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (_result != null)
                ..._summary(d, dialogCtx)
              else ...[
                _label(d, 'TRANSFER FILE'),
                InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: _busy ? null : _pick,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: d.surface2,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _path == null ? d.line : d.ice),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          color: d.text3,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _path == null
                                ? 'Choose the .dentosx file'
                                : _path!.split(RegExp(r'[\\/]')).last,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _path == null ? d.text4 : d.text1,
                              fontSize: 10.5.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (!_useRecovery) ...[
                  _label(d, 'TRANSFER CODE'),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      color: d.text1,
                      fontSize: 14.sp,
                      letterSpacing: 2,
                    ),
                    decoration: _dec(d, 'ABCD-EFGH'),
                    onSubmitted: (_) => _busy ? null : _go(),
                  ),
                ] else ...[
                  _label(d, 'SEND THIS TO INOVER STUDIO'),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: d.surface2,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _request ?? 'Choose the file first.',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              color: d.text3,
                              fontSize: 8.5.sp,
                            ),
                          ),
                        ),
                        if (_request != null)
                          IconButton(
                            tooltip: 'Copy',
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 17,
                              color: d.text3,
                            ),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: _request!),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label(d, 'RECOVERY CODE'),
                  TextField(
                    controller: _token,
                    enabled: !_busy,
                    maxLines: 4,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      color: d.text1,
                      fontSize: 9.sp,
                    ),
                    decoration: _dec(d, 'Paste the full code you received'),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _useRecovery = !_useRecovery;
                              _error = null;
                            });
                            if (_useRecovery) _makeRequest();
                          },
                    child: Text(
                      _useRecovery
                          ? 'I have a transfer code'
                          : 'No code, or a different clinic ID? Recover via Inover Studio',
                      style: TextStyle(fontSize: 9.5.sp),
                    ),
                  ),
                ),
                if (_busy && _total > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _done / _total,
                    minHeight: 6,
                    color: d.ice,
                    backgroundColor: d.surface2,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Checking and storing $_done of $_total…',
                    style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: d.alert,
                      fontSize: 10.sp,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(dialogCtx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size(150, 44),
                      ),
                      onPressed: _busy ? null : _go,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Receive'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _summary(DentColors d, BuildContext dialogCtx) {
    final r = _result!;
    Widget line(IconData i, Color c, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(i, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: TextStyle(color: d.text1, fontSize: 10.5.sp),
            ),
          ),
        ],
      ),
    );
    return [
      line(Icons.check_circle_rounded, d.ok, '${r.added} X-rays received'),
      if (r.already > 0)
        line(Icons.done_all_rounded, d.text4, '${r.already} were already here'),
      if (r.noPatient > 0)
        line(
          Icons.person_off_rounded,
          d.warn,
          '${r.noPatient} skipped — patient not on this computer yet. Sync, '
          'then receive the same file again (ask for a new code).',
        ),
      if (r.damaged > 0)
        line(
          Icons.report_problem_rounded,
          d.alert,
          '${r.damaged} could not be verified and were not stored.',
        ),
      const SizedBox(height: 10),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
          minimumSize: const Size.fromHeight(44),
        ),
        onPressed: () => Navigator.pop(dialogCtx),
        child: const Text('Done'),
      ),
    ];
  }
}

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
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: d.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: d.ice),
  ),
);
