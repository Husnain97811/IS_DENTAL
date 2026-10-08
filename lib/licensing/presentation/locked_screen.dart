import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../core/constants/views.dart';

class LockedScreen extends ConsumerStatefulWidget {
  const LockedScreen({super.key});
  @override
  ConsumerState<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends ConsumerState<LockedScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _renew() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref
        .read(licenseControllerProvider.notifier)
        .activate(_key.text.trim());
    if (mounted)
      setState(() {
        _busy = false;
        _error = r.error;
      });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final lic = ref.watch(licenseControllerProvider).value?.license;
    return Scaffold(
      body: Center(
        child: Container(
          width: 40.w,
          padding: const EdgeInsets.all(30),
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
              Icon(Icons.lock_clock_rounded, color: d.warn, size: 20.sp),
              SizedBox(height: 1.6.h),
              Text(
                'Subscription expired',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (_) {
                  final now = DateTime.now();
                  // The licence itself is still valid — so this lock came
                  // from the cloud check, not from the expiry date. Saying
                  // "expired" here is what made this so hard to diagnose.
                  final stillValid = lic != null && now.isBefore(lic.expiresAt);
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
                              'Your data and backups are fully intact — a '
                              'valid renewal key restores instant access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: d.text3,
                      fontSize: 9.sp,
                      height: 1.5,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _DiagnosticsBar(clinicId: lic?.clinicId),
              SizedBox(height: 2.4.h),
              TextField(
                controller: _key,
                maxLines: 4,
                style: TextStyle(fontSize: 9.5.sp, color: d.text1),
                decoration: InputDecoration(
                  hintText: 'Paste renewal license…',
                  filled: true,
                  fillColor: d.surface2,
                  hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: d.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide(color: d.ice, width: 1.5),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: d.alert, fontSize: 8.5.sp),
                  ),
                ),
              SizedBox(height: 2.h),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : _renew,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Text('Renew & unlock'),
              ),
            ],
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
                fontSize: 8.sp,
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
                style: TextStyle(fontSize: 8.5.sp),
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
        style: TextStyle(fontSize: 8.5.sp),
      ),
    );
  }
}
