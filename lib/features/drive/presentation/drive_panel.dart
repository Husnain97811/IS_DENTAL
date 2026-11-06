import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../data/drive_config.dart';
import '../data/drive_sync.dart';

/// Settings → X-ray & photo sharing.
///
/// Manual transfer files keep working exactly as before. Google Drive is
/// the clinic's choice: connect the same Google account on every computer
/// and X-rays, photos and Showcase pictures follow by themselves.
class DrivePanel extends ConsumerStatefulWidget {
  const DrivePanel({super.key});
  @override
  ConsumerState<DrivePanel> createState() => _DrivePanelState();
}

class _DrivePanelState extends ConsumerState<DrivePanel> {
  bool _connecting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    final allowed =
        session?.role == AppRole.owner ||
        ref.watch(canProvider(Perm.manageBackup));
    final ent = ref.watch(entitlementsProvider);
    // Google Drive backup switched off for this clinic → no panel at all
    if (!allowed || !ent.sync || !ent.driveBackup)
      return const SizedBox.shrink();
    final s = ref.watch(driveSyncProvider);

    return DentPanel(
      title: 'X-ray & photo sharing',
      subtitle: 'How X-rays and photos reach your other computers',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _option(
              d,
              icon: Icons.swap_horiz_rounded,
              title: 'Transfer file',
              body:
                  'Always available. Make an encrypted transfer file on one '
                  'computer and open it on the other (Settings → X-ray '
                  'transfer).',
              on: !s.connected,
            ),
            const SizedBox(height: 10),
            _option(
              d,
              icon: Icons.add_to_drive_rounded,
              title: 'Google Drive  ·  automatic',
              body:
                  'Connect the clinic\'s Google account on every computer. '
                  'Everything already saved is uploaded, and each computer '
                  'downloads what it is missing — then they stay in step by '
                  'themselves. Files stay encrypted: Google can\'t open them.',
              on: s.connected,
            ),
            const SizedBox(height: 16),
            if (!DriveConfig.configured)
              Text(
                'Google Drive isn\'t set up in this DentOS version yet.',
                style: TextStyle(color: d.text4, fontSize: 9.5.sp),
              )
            else if (!s.connected)
              _connectRow(d)
            else
              _status(d, s),
            if (_error != null || s.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error ?? s.error!,
                  style: TextStyle(color: d.alert, fontSize: 9.5.sp),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _connectRow(DentColors d) => Row(
    children: [
      Expanded(
        child: Text(
          _connecting
              ? 'Finish signing in to Google in your browser…'
              : 'Use the same Google account on every computer of the clinic.',
          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        onPressed: _connecting ? null : _connect,
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        icon: _connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_to_drive_rounded, size: 18),
        label: Text(
          'Connect Google Drive',
          style: TextStyle(fontSize: 10.5.sp),
        ),
      ),
    ],
  );

  Widget _status(DentColors d, DriveSyncState s) {
    final ctl = ref.read(driveSyncProvider.notifier);
    final line = s.busy
        ? (s.total > 0 ? '${s.stage} ${s.done} of ${s.total}…' : s.stage)
        : s.lastSync == null
        ? 'Waiting for the first sync…'
        : 'Last synced ${_ago(s.lastSync!)}'
              '${s.lastUp + s.lastDown == 0 ? ' · everything is in step' : ' · ${s.lastUp} uploaded, ${s.lastDown} downloaded'}'
              '${s.failed > 0 ? ' · ${s.failed} will be retried' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_rounded, size: 18, color: d.ok),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.email.isEmpty ? 'Connected' : 'Connected as ${s.email}',
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: s.busy ? null : ctl.run,
              child: Text('Sync now', style: TextStyle(fontSize: 10.sp)),
            ),
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: d.alert),
              onPressed: () => _disconnect(ctl),
              child: Text('Disconnect', style: TextStyle(fontSize: 10.sp)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (s.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              value: s.total > 0 ? s.done / s.total : null,
              minHeight: 4,
              color: d.ice,
              backgroundColor: d.line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        Text(
          line,
          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
        ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final err = await ref.read(driveSyncProvider.notifier).connect();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = err;
    });
  }

  Future<void> _disconnect(DriveSyncController ctl) async {
    final d = context.dent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        title: Text(
          'Disconnect Google Drive on this computer?',
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Nothing is deleted — not here and not on Drive. This computer '
          'just stops uploading and downloading. Other computers keep '
          'syncing.',
          style: TextStyle(fontSize: 10.5.sp, color: d.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(fontSize: 10.sp)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: d.alert),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Disconnect', style: TextStyle(fontSize: 10.sp)),
          ),
        ],
      ),
    );
    if (ok == true) await ctl.disconnect();
  }

  Widget _option(
    DentColors d, {
    required IconData icon,
    required String title,
    required String body,
    required bool on,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: on ? d.ice.withValues(alpha: .07) : d.surface2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: on ? d.ice.withValues(alpha: .5) : d.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: on ? d.ice : d.text3),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(color: d.text3, fontSize: 9.5.sp),
              ),
            ],
          ),
        ),
        if (on) Icon(Icons.check_circle_rounded, size: 18, color: d.ice),
      ],
    ),
  );

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    if (h < 24) return '$h h ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}
