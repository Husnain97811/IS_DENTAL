import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/dent_colors.dart';
import 'license_controller.dart';

class ReconnectRequiredScreen extends ConsumerStatefulWidget {
  const ReconnectRequiredScreen({super.key});
  @override
  ConsumerState<ReconnectRequiredScreen> createState() => _S();
}

class _S extends ConsumerState<ReconnectRequiredScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
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
              Icon(Icons.wifi_off_rounded, color: d.warn, size: 20.sp),
              SizedBox(height: 1.6.h),
              Text(
                'Reconnect to continue',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                "You've been offline for more than 48 hours. DentOS needs to reach the server to verify your subscription and sync. Your data is fully intact — this is just a connectivity check.",
                textAlign: TextAlign.center,
                style: TextStyle(color: d.text3, fontSize: 9.sp, height: 1.5),
              ),
              SizedBox(height: 2.4.h),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await ref
                            .read(licenseControllerProvider.notifier)
                            .reload();
                        if (mounted) setState(() => _busy = false);
                      },
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Text('Retry connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
