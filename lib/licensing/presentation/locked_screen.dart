import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/dent_colors.dart';
import 'license_controller.dart';

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
          width: 440,
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
              Text(
                lic == null
                    ? 'Enter a valid renewal key to continue.'
                    : 'Expired ${lic.expiresAt.toLocal().toString().split(' ').first}. Your data and backups are fully intact — a valid renewal key restores instant access.',
                textAlign: TextAlign.center,
                style: TextStyle(color: d.text3, fontSize: 9.sp, height: 1.5),
              ),
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
