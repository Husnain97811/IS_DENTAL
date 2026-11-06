import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../core/constants/views.dart';

/// Shown when the licence has expired (or the server says the subscription
/// has ended).
///
///  • CLOUD clinics: one button — "Check subscription". It fetches the
///    renewal Inover Studio saved on the cloud, checks its signature, saves
///    it on this computer and unlocks. No key to type. (It also unlocks by
///    itself within seconds of a renewal; the button is for not waiting.)
///    Pasting a licence key stays underneath as the backup.
///  • OFFLINE clinics: a pasted licence key only — they never call out.
class LockedScreen extends ConsumerStatefulWidget {
  const LockedScreen({super.key});
  @override
  ConsumerState<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends ConsumerState<LockedScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  bool _checking = false;
  CloudCheck? _check;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _renew() async {
    final raw = _key.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste the licence you were sent.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final lic = ref.read(licenseControllerProvider).value?.license;
    final ctrl = ref.read(licenseControllerProvider.notifier);
    // An installed clinic only accepts a licence issued to ITSELF.
    final r = lic == null
        ? await ctrl.activate(raw)
        : await ctrl.reactivate(raw);
    if (mounted) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  Future<void> _checkCloud() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    final r = await ref
        .read(licenseControllerProvider.notifier)
        .checkSubscriptionNow();
    // renewed → the router has already left this screen
    if (mounted) {
      setState(() {
        _checking = false;
        _check = r;
      });
    }
  }

  static String _day(DateTime t) {
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
    final l = t.toLocal();
    return '${l.day} ${m[l.month - 1]} ${l.year}';
  }

  /// The button's answer, in plain words.
  (String, bool)? _checkMessage() {
    final c = _check;
    if (c == null) return null;
    return switch (c.result) {
      CloudCheckResult.renewed => (
        'Renewed${c.until == null ? '' : ' until ${_day(c.until!)}'} — unlocking…',
        true,
      ),
      CloudCheckResult.notRenewed => (
        'No renewal yet. Please contact Inover Studio — as soon as they renew, '
            'this computer unlocks by itself.',
        false,
      ),
      CloudCheckResult.offline => (
        'No internet — this computer could not reach the server. Check the '
            'connection and try again, or paste a licence key below.',
        false,
      ),
      CloudCheckResult.notCloud => (
        'This is an offline licence — paste the renewal key below.',
        false,
      ),
      CloudCheckResult.failed => (
        'Could not check right now. Try again, or paste a licence key below.',
        false,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final lic = ref.watch(licenseControllerProvider).value?.license;
    final cloud = lic?.cloudPackage == CloudPackage.cloud;
    final msg = _checkMessage();

    final pasteField = TextField(
      controller: _key,
      maxLines: 4,
      style: TextStyle(fontSize: 11.5.sp, color: d.text1),
      decoration: InputDecoration(
        hintText: 'Paste renewal license…',
        filled: true,
        fillColor: d.surface2,
        hintStyle: TextStyle(color: d.text4, fontSize: 11.sp),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.ice, width: 1.5),
        ),
      ),
    );

    Widget spinner(Color c) => SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: c),
    );

    // paste-a-key: the main button for offline clinics, the backup for cloud
    final renewButton = cloud
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: d.ice,
              side: BorderSide(color: d.ice.withValues(alpha: .5)),
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _busy ? null : _renew,
            child: _busy ? spinner(d.ice) : const Text('Unlock with this key'),
          )
        : FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _busy ? null : _renew,
            child: _busy
                ? spinner(AppPalette.onAccent)
                : const Text('Renew & unlock'),
          );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 48.w,
            constraints: const BoxConstraints(minWidth: 460, maxWidth: 720),
            padding: const EdgeInsets.all(36),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: d.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: d.line),
              boxShadow: d.shadowPop,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_clock_rounded, color: d.warn, size: 30.sp),
                SizedBox(height: 1.6.h),
                Text(
                  'Subscription expired',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 19.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final now = DateTime.now();
                    // The licence itself is still valid — so this lock came
                    // from the cloud check, not from the expiry date. Saying
                    // "expired" here is what made this so hard to diagnose.
                    final stillValid =
                        lic != null && now.isBefore(lic.expiresAt);
                    return Text(
                      lic == null
                          ? 'Enter a valid renewal key to continue.'
                          : stillValid
                          ? 'Your licence is valid until '
                                '${lic.expiresAt.toLocal().toString().split(' ').first}, '
                                'but this computer could not confirm your '
                                'subscription with the server. Your data is '
                                'fully intact. Contact support with the details '
                                'below.'
                          : 'Expired ${lic.expiresAt.toLocal().toString().split(' ').first}. '
                                'Your data and backups are fully intact — '
                                '${cloud ? 'once your subscription is renewed, press Check subscription (or wait a moment: this computer unlocks by itself).' : 'a valid renewal key restores instant access.'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 11.5.sp,
                        height: 1.55,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _DiagnosticsBar(clinicId: lic?.clinicId),
                SizedBox(height: 2.4.h),

                // ── cloud: one button, no key ──
                if (cloud) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onPressed: _checking ? null : _checkCloud,
                    icon: _checking
                        ? spinner(AppPalette.onAccent)
                        : const Icon(Icons.cloud_sync_rounded, size: 26),
                    label: Text(
                      _checking ? 'Checking…' : 'Check subscription',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (msg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        msg.$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: msg.$2 ? d.teal : d.alert,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ),
                  SizedBox(height: 2.4.h),
                  Row(
                    children: [
                      Expanded(child: Divider(color: d.line)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'or paste a licence key',
                          style: TextStyle(color: d.text3, fontSize: 10.5.sp),
                        ),
                      ),
                      Expanded(child: Divider(color: d.line)),
                    ],
                  ),
                  SizedBox(height: 1.6.h),
                ],

                // ── the licence key (offline: the only way; cloud: backup) ──
                pasteField,
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(color: d.alert, fontSize: 10.5.sp),
                    ),
                  ),
                SizedBox(height: 2.h),
                renewButton,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Support panel. One tap gives you the clinic id, the signed-in account,
/// the token's clinic claim and whether the row is readable — copyable,
/// so the client can paste it into WhatsApp.
class _DiagnosticsBar extends ConsumerStatefulWidget {
  const _DiagnosticsBar({this.clinicId});
  final String? clinicId;
  @override
  ConsumerState<_DiagnosticsBar> createState() => _DiagnosticsBarState();
}

class _DiagnosticsBarState extends ConsumerState<_DiagnosticsBar> {
  String? _out;
  bool _busy = false;

  Future<void> _run() async {
    final id = widget.clinicId;
    if (id == null) return;
    setState(() => _busy = true);
    final stored =
        await ref.read(appDatabaseProvider).getSetting('hb_reason') ?? '';
    final probe = await ref.read(cloudServiceProvider).diagnose(id);
    if (mounted) {
      setState(() {
        _busy = false;
        _out = 'clinic=$id\n$stored\n$probe';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    if (_out != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: d.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              _out!,
              style: TextStyle(
                color: d.text2,
                fontSize: 10.sp,
                height: 1.5,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _out!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied — send to support.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: Text(
                'Copy for support',
                style: TextStyle(fontSize: 10.5.sp),
              ),
            ),
          ],
        ),
      );
    }
    return TextButton(
      onPressed: _busy ? null : _run,
      style: TextButton.styleFrom(foregroundColor: d.text3),
      child: Text(
        _busy ? 'Checking…' : 'Why am I seeing this?',
        style: TextStyle(
          fontSize: 10.5.sp,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
