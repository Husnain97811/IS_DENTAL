import 'package:flutter/material.dart';

/// Shows a message that ALWAYS goes away after [duration].
///
/// Newer Flutter keeps a SnackBar with a button (Show, Show file…) on screen
/// until it is clicked — and so does every Flutter version when the
/// computer's accessibility keyboard navigation is on. This closes it
/// ourselves once it has been visible for [duration].
void showDentSnack(
  ScaffoldMessengerState messenger, {
  required Widget content,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 5),
}) {
  var closed = false;
  final c = messenger.showSnackBar(
    SnackBar(
      content: content,
      action: action,
      duration: duration,
      // only fires once this message is the one on screen, so hiding the
      // "current" message below can never hide a different one
      onVisible: () => Future<void>.delayed(duration, () {
        if (!closed) messenger.hideCurrentSnackBar();
      }),
    ),
  );
  c.closed.whenComplete(() => closed = true);
}
