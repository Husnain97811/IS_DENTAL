import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../constants/views.dart';

/// Runs [task] behind a small "working…" dialog that can't be dismissed,
/// so staff can see something is happening. [task] can update the line
/// ("Adding photo 2 of 3…") through the notifier it receives.
/// The dialog always closes — also when [task] throws (the error is
/// rethrown for the caller to show).
Future<T> runBusy<T>(
  BuildContext context,
  String message,
  Future<T> Function(ValueNotifier<String> status) task,
) async {
  final status = ValueNotifier<String>(message);
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: _BusyBox(status)),
  ).whenComplete(() => open = false);
  try {
    return await task(status);
  } finally {
    if (open) nav.pop();
    // let the closing animation finish before the notifier goes away
    Future<void>.delayed(const Duration(milliseconds: 400), status.dispose);
  }
}

class _BusyBox extends StatelessWidget {
  const _BusyBox(this.status);
  final ValueNotifier<String> status;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: d.ice,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (_, s, __) => Text(
                    s,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
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
