import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sizer/sizer.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import '../theme/dent_colors.dart';

// One looping, muted background player shared across all auth screens (no restart between them).
final _authPlayerProvider = Provider<Player>((ref) {
  final player = Player();
  player
    ..setVolume(0)
    ..setPlaylistMode(PlaylistMode.loop)
    ..open(Media('asset:///assets/video/dental_bg.mp4'), play: true);
  ref.onDispose(player.dispose);
  return player;
});
final _authControllerProvider = Provider<VideoController>(
  (ref) => VideoController(ref.watch(_authPlayerProvider)),
);

class AuthShell extends ConsumerWidget {
  const AuthShell({super.key, required this.child, this.maxWidth = 552});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Ambient(),
          Opacity(
            opacity:
                0.264, // low-opacity dental footage; transparent if the asset is missing
            child: Video(
              controller: ref.watch(_authControllerProvider),
              fit: BoxFit.cover,
              controls: NoVideoControls,
              fill: Colors.transparent,
            ),
          ),
          const _Scrim(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28.8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _Glass(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ambient extends StatelessWidget {
  const _Ambient();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF05080F) : const Color(0xFF0A1322),
      ),
      child: const Stack(
        fit: StackFit.expand,
        children: [
          _Blob(
            alignment: Alignment(-0.85, -0.95),
            color: Color(0x5538BDF8),
            size: 648,
          ),
          _Blob(
            alignment: Alignment(1.15, -0.55),
            color: Color(0x4413E0C4),
            size: 600,
          ),
          _Blob(
            alignment: Alignment(0.2, 1.25),
            color: Color(0x3338BDF8),
            size: 720,
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.color,
    required this.size,
  });
  final Alignment alignment;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _Scrim extends StatelessWidget {
  const _Scrim();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x55020509), Color(0xAA020509)],
      ),
    ),
  );
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28.8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 31.2, sigmaY: 31.2),
        child: Container(
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: d.surface.withValues(alpha: dark ? 0.42 : 0.74),
            borderRadius: BorderRadius.circular(28.8),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.55 : 0.22),
                blurRadius: 72,
                offset: const Offset(0, 36),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Row(
      children: [
        Container(
          width: 55.2,
          height: 55.2,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: d.accentGradient,
            borderRadius: BorderRadius.circular(16.8),
            boxShadow: [
              BoxShadow(
                color: d.ice.withValues(alpha: .5),
                blurRadius: 24,
                offset: const Offset(0, 9.6),
              ),
            ],
          ),
          child: Text(
            'D',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 16.8.sp,
              fontWeight: FontWeight.w700,
              color: AppPalette.onAccent,
            ),
          ),
        ),
        const SizedBox(width: 15.6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: d.text3, fontSize: 10.8.sp),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.onSubmit,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final VoidCallback? onSubmit;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: d.text4,
              fontSize: 9.8.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 7.2),
          TextField(
            controller: controller,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            onSubmitted: (_) => onSubmit?.call(),
            style: TextStyle(fontSize: 13.8.sp, color: d.text1),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: d.text4, fontSize: 10.8.sp),
              filled: true,
              fillColor: d.surface2.withValues(alpha: 0.55),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15.6,
                vertical: 14.4,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13.2),
                borderSide: BorderSide(color: d.line.withValues(alpha: .7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13.2),
                borderSide: BorderSide(color: d.ice, width: 1.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return SizedBox(
      height: 57.6,
      width: 21.6,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.6),
          ),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 21.6,
                height: 21.6,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppPalette.onAccent,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 11.4.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
