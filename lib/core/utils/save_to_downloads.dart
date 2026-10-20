import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dent_snack.dart';

/// Writes [bytes] straight into the user's Downloads folder — no save dialog.
/// An existing name gets " (1)", " (2)"… so nothing is ever overwritten.
///
/// macOS: needs `com.apple.security.files.downloads.read-write` in both
/// .entitlements files, otherwise the file lands inside the app's sandbox.
Future<({String path, String name})> saveToDownloads(
  Uint8List bytes,
  String fileName,
) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  if (!await dir.exists()) await dir.create(recursive: true);

  final safe = fileName
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]+'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final dot = safe.lastIndexOf('.');
  final base = dot > 0
      ? safe.substring(0, dot)
      : (safe.isEmpty ? 'DentOS' : safe);
  final ext = dot > 0 ? safe.substring(dot) : '';
  final sep = Platform.pathSeparator;

  var file = File('${dir.path}$sep$base$ext');
  for (var n = 1; await file.exists(); n++) {
    file = File('${dir.path}$sep$base ($n)$ext');
  }
  final tmp = File('${file.path}.part');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(file.path);
  return (path: file.path, name: file.path.split(sep).last);
}

/// Opens the folder with the file selected (Finder / Explorer).
Future<void> revealInFolder(String path) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      // two arguments so a path with spaces ("Ali (1).png") still works
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {}
}

/// "Saved to Downloads · name" with a Show button.
void showSavedToDownloads(
  ScaffoldMessengerState messenger,
  ({String path, String name}) saved,
) {
  showDentSnack(
    messenger,
    duration: const Duration(seconds: 5),
    content: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text('Saved to Downloads · ${saved.name}')),
      ],
    ),
    action: SnackBarAction(
      label: 'Show',
      onPressed: () => revealInFolder(saved.path),
    ),
  );
}
