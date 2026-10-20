import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// What happened when we tried to hand a file to WhatsApp.
enum WaShareResult {
  /// WhatsApp app opened (on the patient's chat if we had a number) and the
  /// file is on the clipboard — the user presses ⌘V / Ctrl+V, then Enter.
  ready,

  /// WhatsApp app isn't installed — WhatsApp Web opened in the browser
  /// instead; the file is still on the clipboard.
  web,

  /// Opened, but the file couldn't be put on the clipboard.
  noClipboard,

  /// Neither the app nor the browser opened.
  failed,
}

/// Opens the WhatsApp desktop app on [phone]'s chat with the file ready to
/// paste. WhatsApp has no way for another app to attach a file directly,
/// so the file goes on the clipboard and one paste attaches it.
///
/// The readable copy lives in the app's temp folder and is deleted after
/// 10 minutes (and on the next share, if the app was closed meanwhile).
Future<({WaShareResult result, String path})> shareFileOnWhatsApp({
  required Uint8List bytes,
  required String fileName,
  required String phone,
}) async {
  final sep = Platform.pathSeparator;
  final dir = Directory(
    '${(await getTemporaryDirectory()).path}${sep}DentOS-share',
  );
  await _cleanOld(dir);
  await dir.create(recursive: true);

  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]+'), '-').trim();
  final file = File('${dir.path}$sep${safe.isEmpty ? 'DentOS-file' : safe}');
  await file.writeAsBytes(bytes, flush: true);
  unawaited(
    Future<void>.delayed(const Duration(minutes: 10), () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }),
  );

  // Pictures go on the clipboard as IMAGE data — WhatsApp pastes that as a
  // photo, like a screenshot. Other files (PDF) go on as a file.
  var clip = false;
  try {
    if (_isImage(safe)) {
      await Pasteboard.writeImage(bytes);
      clip = true;
    } else {
      clip = await Pasteboard.writeFiles([file.path]);
    }
  } catch (_) {}

  final digits = _normalize(phone);
  final hasNo = digits.length >= 10;

  WaShareResult r;
  if (await _open(hasNo ? 'whatsapp://send?phone=$digits' : 'whatsapp://')) {
    r = clip ? WaShareResult.ready : WaShareResult.noClipboard;
  } else if (await _open(
    hasNo ? 'https://wa.me/$digits' : 'https://web.whatsapp.com/',
  )) {
    r = clip ? WaShareResult.web : WaShareResult.noClipboard;
  } else {
    r = WaShareResult.failed;
  }
  return (result: r, path: file.path);
}

bool _isImage(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg');
}

/// ⌘V on a Mac, Ctrl+V elsewhere.
String waPasteKey() => Platform.isMacOS ? '⌘V' : 'Ctrl+V';

/// One line telling staff what to do next.
String waShareMessage(
  WaShareResult r, {
  required String what,
  required String who,
}) {
  final paste = waPasteKey();
  return switch (r) {
    WaShareResult.ready =>
      'WhatsApp is open on $who\'s chat — press $paste to attach the $what, then Enter.',
    WaShareResult.web =>
      'WhatsApp app not found, opened WhatsApp Web — press $paste in the chat to attach the $what.',
    WaShareResult.noClipboard =>
      'WhatsApp is open, but the $what could not be copied — click Show file and drag it into the chat.',
    WaShareResult.failed =>
      'Could not open WhatsApp. Is WhatsApp installed on this computer?',
  };
}

Future<bool> _open(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Same rule as everywhere else in DentOS: digits only, 03… → 923…
String _normalize(String raw) {
  var p = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (p.startsWith('0')) p = '92${p.substring(1)}';
  return p;
}

Future<void> _cleanOld(Directory dir) async {
  try {
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    await for (final e in dir.list()) {
      if (e is File && (await e.lastModified()).isBefore(cutoff)) {
        await e.delete();
      }
    }
  } catch (_) {}
}
