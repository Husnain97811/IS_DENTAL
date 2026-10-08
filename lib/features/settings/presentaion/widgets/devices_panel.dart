import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../../../core/constants/views.dart';
import '../../../../licensing/presentation/license_providers.dart';

/// Owner-only list of the computers running this clinic's install.
class DevicesPanel extends ConsumerWidget {
  const DevicesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final ent = ref.watch(entitlementsProvider);
    final lic = ref.watch(currentLicenseProvider);
    final rows = ref.watch(devicesStreamProvider).value ?? const <DeviceRow>[];
    final live = rows.where((r) => r.isActive && !r.isDeleted).toList();

    // Licences minted before maxDevices existed mean a single computer.
    final max = lic?.maxDevices ?? 1;

    if (!ent.cloud) {
      return DentPanel(
        title: 'Computers',
        subtitle: 'Offline installs are single-computer',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Sharing data between computers needs the cloud package. '
            'Two offline installs have no way to reach each other.',
            style: TextStyle(color: d.text4, fontSize: 9.sp, height: 1.5),
          ),
        ),
      );
    }

    return DentPanel(
      title: 'Computers',
      subtitle: '${live.length} of $max in use',
      trailing: live.length >= max
          ? null
          : PanelLink(
              'Add a computer',
              onTap: () => _showJoinCode(context, ref),
            ),
      child: Column(
        children: [
          for (final r in live) _row(context, ref, d, r),
          if (live.length >= max)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Your plan allows $max computer${max == 1 ? '' : 's'}. '
                'Remove one to free a slot.',
                style: TextStyle(color: d.text4, fontSize: 8.5.sp),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, DentColors d, DeviceRow r) {
    final isThis = ref.watch(thisDeviceUuidProvider).value == r.uuid;
    final seen = r.lastSeenAt;
    final stale = seen == null || DateTime.now().difference(seen).inDays > 7;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isThis ? d.ice : d.text4).withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              r.letter,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: isThis ? d.ice : d.text3,
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.name.isEmpty ? 'Computer ${r.letter}' : r.name,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isThis) ...[
                      const SizedBox(width: 8),
                      StatusChip('This computer', kind: ChipKind.inProgress),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (r.platform.isNotEmpty) r.platform.split(' ').first,
                    if (r.letter != 'A') 'numbers end in -${r.letter}',
                    seen == null ? 'never synced' : 'last seen ${_ago(seen)}',
                  ].join(' · '),
                  style: TextStyle(
                    color: stale ? d.warn : d.text4,
                    fontSize: 8.sp,
                  ),
                ),
              ],
            ),
          ),
          if (!isThis && r.letter != 'A')
            IconButton(
              tooltip: 'Remove this computer',
              icon: Icon(Icons.link_off_rounded, size: 16, color: d.text4),
              onPressed: () => _revoke(context, ref, r),
            ),
        ],
      ),
    );
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, DeviceRow r) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.error,
      title: 'Remove ${r.name.isEmpty ? "Computer ${r.letter}" : r.name}?',
      message:
          'That computer loses access immediately and cannot sync again. '
          'Anything it recorded and already synced is kept. Anything it '
          'recorded but never synced is lost.\n\n'
          'Letter ${r.letter} is freed for a replacement computer.',
      confirmLabel: 'Remove it',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'revoke-device',
        body: {'deviceUuid': r.uuid},
      );
      final data = res.data as Map?;
      if (data?['ok'] != true) throw Exception(data?['error'] ?? 'Failed');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Computer removed.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not remove it: $e')));
      }
    }
  }

  Future<void> _showJoinCode(BuildContext context, WidgetRef ref) =>
      showDialog(context: context, builder: (_) => const _JoinCodeDialog());
}

final thisDeviceUuidProvider = FutureProvider<String>(
  (ref) async => (await ref.watch(appDatabaseProvider).localDevice()).uuid,
);

class _JoinCodeDialog extends ConsumerStatefulWidget {
  const _JoinCodeDialog();
  @override
  ConsumerState<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends ConsumerState<_JoinCodeDialog> {
  String? _code;
  String? _letter;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    final lic = ref.read(currentLicenseProvider);
    if (lic == null) {
      setState(() {
        _busy = false;
        _error = 'No licence on this computer.';
      });
      return;
    }
    try {
      await ref.read(cloudServiceProvider).ensureSignedIn();
      final res = await Supabase.instance.client.functions.invoke(
        'create-join-code',
        body: {'license': lic.toJson()},
      );
      final data = res.data as Map?;
      if (data?['ok'] != true) throw Exception(data?['error'] ?? 'Failed');
      if (mounted) {
        setState(() {
          _busy = false;
          _code = data!['code'] as String;
          _letter = data['letter'] as String;
        });
      }
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
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a computer',
                style: Theme.of(dialogCtx).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: d.alert, fontSize: 9.5.sp),
                )
              else ...[
                Text(
                  'On the new computer, install DentOS, paste the same '
                  'licence, choose "Add this computer to an existing '
                  'clinic", and enter this code.',
                  style: TextStyle(
                    color: d.text3,
                    fontSize: 9.5.sp,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: d.ice),
                  ),
                  child: Center(
                    child: SelectableText(
                      _code!,
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
                const SizedBox(height: 12),
                Text(
                  'Valid for 30 minutes · one computer only · it will become '
                  'computer $_letter, and its patient and invoice numbers '
                  'will end in -$_letter',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: d.text4, fontSize: 8.sp, height: 1.5),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.text2,
                    side: BorderSide(color: d.line),
                    minimumSize: const Size.fromHeight(42),
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _code!));
                    if (dialogCtx.mounted) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                        const SnackBar(content: Text('Code copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy code'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
