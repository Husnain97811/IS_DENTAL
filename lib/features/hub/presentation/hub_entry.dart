import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../data/hub_security.dart';

/// The Hub's own route — outside the shell, so it replaces the sidebar.
const kHubRoute = '/hub';

/// The app's theme before the Hub switched to dark, put back on exit.
class _ThemeBefore extends Notifier<ThemeMode?> {
  @override
  ThemeMode? build() => null;
  void set(ThemeMode? v) => state = v;
}

final hubThemeBeforeProvider = NotifierProvider<_ThemeBefore, ThemeMode?>(
  _ThemeBefore.new,
);

/// Confirm → open the Hub. On a plan without it, the upgrade page instead.
Future<void> openReportingHub(BuildContext context, WidgetRef ref) async {
  final access = ref.read(hubAccessProvider);
  if (!access.allowed) return;
  if (!access.onPlan) {
    await showHubUpgrade(context);
    return;
  }
  final ok = await showHubConfirm(
    context,
    icon: Icons.insights_rounded,
    tone: context.dent.ice,
    title: 'Open the Detailed Reporting Hub?',
    message:
        'The Hub takes over the whole screen and asks for your Hub PIN. '
        'Your clinic screens come back when you press Exit.',
    confirm: 'Open Hub',
    cancel: 'Not now',
  );
  if (ok && context.mounted) {
    // The Hub always opens dark; the app's own theme comes back on exit.
    // Switched here, in the same frame as the route change, so nothing
    // flashes light first.
    ref.read(hubThemeBeforeProvider.notifier).set(ref.read(themeModeProvider));
    ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
    context.go(kHubRoute);
  }
}

/// Top bar button. Hidden for anyone who may not open the Hub; shows a
/// lock on plans that don't include it.
class ReportingHubButton extends ConsumerWidget {
  const ReportingHubButton({super.key, this.compact = false, this.gap = 10});

  /// Icon only (narrow top bar).
  final bool compact;

  /// Space before the button — kept inside so a hidden button leaves no gap.
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(hubAccessProvider);
    if (!access.allowed) return const SizedBox.shrink();
    final d = context.dent;
    final locked = !access.onPlan;

    final body = Container(
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      decoration: BoxDecoration(
        gradient: locked
            ? null
            : LinearGradient(
                colors: [
                  d.ice.withValues(alpha: .16),
                  d.teal.withValues(alpha: .12),
                ],
              ),
        color: locked ? d.surface2 : null,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: locked ? d.line : d.ice.withValues(alpha: .35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock_outline_rounded : Icons.insights_rounded,
            size: 18,
            color: locked ? d.text3 : d.ice,
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text(
              'Reporting Hub',
              style: TextStyle(
                color: locked ? d.text3 : d.text1,
                fontSize: 9.8.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(left: gap),
      child: Tooltip(
        message: locked
            ? 'Detailed Reporting Hub · Standard & Premium'
            : 'Detailed Reporting Hub',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => openReportingHub(context, ref),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A calm, consistent yes/no dialog for everything the Hub asks.
Future<bool> showHubConfirm(
  BuildContext context, {
  required IconData icon,
  required Color tone,
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final d = ctx.dent;
      final action = danger ? d.alert : d.ice;
      return Dialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tone, size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: d.text1,
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 10.2.sp,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(foregroundColor: d.text2),
                      child: Text(cancel, style: TextStyle(fontSize: 10.sp)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: action,
                        foregroundColor: danger
                            ? Colors.white
                            : AppPalette.onAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      child: Text(
                        confirm,
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return r ?? false;
}

/// What a Basic / Offline clinic sees when it taps the Hub button.
Future<void> showHubUpgrade(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) {
    final d = ctx.dent;
    const points = [
      'Everything happening right now on one screen — and what needs you',
      'Money in and out, owed money by age, payment methods',
      'Each dentist: visits, collections, no-shows and commission due',
      'Branches side by side, computers, WhatsApp and licence health',
      'Protected by its own PIN, locks itself when you walk away',
    ];
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      d.ice.withValues(alpha: .2),
                      d.teal.withValues(alpha: .12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Icon(Icons.insights_rounded, color: d.ice, size: 30),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: d.warn.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Standard & Premium',
                  style: TextStyle(
                    color: d.warn,
                    fontSize: 9.2.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Detailed Reporting Hub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: d.text1,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'One full-screen view of the whole clinic for the owner.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: d.text3,
                  fontSize: 10.4.sp,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: d.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    for (final p in points)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: d.tealDeep,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p,
                                style: TextStyle(
                                  color: d.text2,
                                  fontSize: 10.sp,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Consumer(
                builder: (_, ref, __) => Text(
                  'Your plan: ${ref.watch(entitlementsProvider).tierLabel}  ·  '
                  'Contact DentOS support to upgrade',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: d.text3, fontSize: 9.6.sp),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.text2,
                    side: BorderSide(color: d.line),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text('Close', style: TextStyle(fontSize: 10.sp)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
