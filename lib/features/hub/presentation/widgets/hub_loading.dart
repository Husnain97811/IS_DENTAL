import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';

/// "Getting your clinic ready" — the real steps the loader is working on,
/// ticked off as each one finishes. Shown until every section has data.
class HubLoading extends StatelessWidget {
  const HubLoading({
    super.key,
    required this.step,
    this.error,
    this.onRetry,
    this.onExit,
  });

  /// Index into [hubLoadSteps] of the step running now.
  final int step;
  final Object? error;
  final VoidCallback? onRetry, onExit;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final total = hubLoadSteps.length;
    final progress = (step.clamp(0, total) / total).toDouble();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 26),
            decoration: BoxDecoration(
              color: d.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: d.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  error == null
                      ? 'Getting your clinic ready'
                      : "Couldn't load the Hub",
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: d.text1,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  error == null
                      ? 'Reading this computer’s records. Nothing leaves the clinic.'
                      : '$error',
                  style: TextStyle(
                    color: error == null ? d.text3 : d.alert,
                    fontSize: 10.sp,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                for (var i = 0; i < total; i++) _row(d, i),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 350),
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: d.line,
                      valueColor: AlwaysStoppedAnimation(
                        error == null ? d.ice : d.alert,
                      ),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (onExit != null)
                        TextButton(
                          onPressed: onExit,
                          style: TextButton.styleFrom(foregroundColor: d.text2),
                          child: Text(
                            'Exit Hub',
                            style: TextStyle(fontSize: 10.sp),
                          ),
                        ),
                      const Spacer(),
                      if (onRetry != null)
                        FilledButton.icon(
                          onPressed: onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: d.ice,
                            foregroundColor: AppPalette.onAccent,
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            'Try again',
                            style: TextStyle(fontSize: 10.sp),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(DentColors d, int i) {
    final done = i < step;
    final doing = i == step && error == null;
    final failed = i == step && error != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: done
                ? Container(
                    decoration: BoxDecoration(
                      color: d.teal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: AppPalette.onAccent,
                    ),
                  )
                : failed
                ? Icon(Icons.error_rounded, size: 22, color: d.alert)
                : doing
                ? Padding(
                    padding: const EdgeInsets.all(2),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: d.ice,
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: d.line, width: 2),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hubLoadSteps[i],
              style: TextStyle(
                color: doing || failed ? d.text1 : (done ? d.text2 : d.text4),
                fontSize: 10.4.sp,
                fontWeight: doing ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
