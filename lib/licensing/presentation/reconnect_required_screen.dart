import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/dent_colors.dart';
import 'license_controller.dart';

/// Shown when a CLOUD clinic has been offline for more than 48 hours.
/// "Check connection & subscription" reaches the server, picks up any
/// renewal saved meanwhile, confirms the subscription and unlocks.
class ReconnectRequiredScreen extends ConsumerStatefulWidget {
  const ReconnectRequiredScreen({super.key});
  @override
  ConsumerState<ReconnectRequiredScreen> createState() => _S();
}

class _S extends ConsumerState<ReconnectRequiredScreen> {
  bool _busy = false;
  CloudCheck? _check;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _check = null;
    });
    final r = await ref
        .read(licenseControllerProvider.notifier)
        .checkSubscriptionNow();
    // connected and in order → the router has already left this screen
    if (mounted) {
      setState(() {
        _busy = false;
        _check = r;
      });
    }
  }

  String? _message() => switch (_check?.result) {
    null => null,
    CloudCheckResult.renewed => 'Connected — unlocking…',
    CloudCheckResult.offline =>
      'Still can\'t reach the server. Check the internet connection and try '
          'again.',
    CloudCheckResult.notRenewed =>
      'Connected, but the subscription has ended. Please contact Inover '
          'Studio.',
    _ => 'Could not check right now. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final msg = _message();
    final ok = _check?.result == CloudCheckResult.renewed;
    return Scaffold(
      body: Center(
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
              Icon(Icons.wifi_off_rounded, color: d.warn, size: 30.sp),
              SizedBox(height: 1.6.h),
              Text(
                'Reconnect to continue',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "You've been offline for more than 48 hours. DentOS needs to reach the server to verify your subscription and sync. Your data is fully intact — this is just a connectivity check.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: d.text2,
                  fontSize: 11.5.sp,
                  height: 1.55,
                ),
              ),
              SizedBox(height: 2.4.h),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _busy ? null : _go,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.cloud_sync_rounded, size: 26),
                label: Text(
                  _busy ? 'Checking…' : 'Check connection & subscription',
                ),
              ),
              if (msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    msg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ok ? d.teal : d.alert,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
