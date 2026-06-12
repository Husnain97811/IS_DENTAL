import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sizer/sizer.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'auth/presentation/login_screen.dart';
import 'licensing/presentation/setup_wizard.dart';
import 'licensing/presentation/locked_screen.dart';
import 'licensing/presentation/reconnect_required_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: _Preview()));
}

class _Preview extends ConsumerWidget {
  const _Preview();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Sizer(
    builder: (_, __, ___) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: const _Picker(),
    ),
  );
}

class _Picker extends ConsumerWidget {
  const _Picker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget go(String t, Widget s) => Padding(
      padding: const EdgeInsets.all(8),
      child: FilledButton(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => s)),
        child: Text(t),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auth preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .set(
                  ref.read(themeModeProvider) == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            go('Login', const LoginScreen()),
            go('Setup Wizard', const SetupWizard()),
            go('Locked', const LockedScreen()),
            go('Reconnect', const ReconnectRequiredScreen()),
          ],
        ),
      ),
    );
  }
}
