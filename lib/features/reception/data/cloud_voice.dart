import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

/// A natural Google voice (WaveNet, English–India) the owner can pick.
class NaturalVoice {
  const NaturalVoice(this.id, this.label);
  final String id; // Google voice name
  final String label;

  static const all = [
    NaturalVoice('en-IN-Wavenet-E', 'Female voice 1 · recommended'),
    NaturalVoice('en-IN-Wavenet-D', 'Female voice 2'),
    NaturalVoice('en-IN-Wavenet-A', 'Female voice 3'),
    NaturalVoice('en-IN-Wavenet-C', 'Male voice 1'),
    NaturalVoice('en-IN-Wavenet-B', 'Male voice 2'),
    NaturalVoice('en-IN-Wavenet-F', 'Male voice 3'),
  ];

  /// The default for every new reception screen.
  static const fallback = 'en-IN-Wavenet-E';

  static String labelOf(String id) =>
      all.where((v) => v.id == id).map((v) => v.label).firstOrNull ?? id;
}

/// Spoken clips from Google, through the clinic's own `speak-name`
/// Supabase function (the Google key never ships inside DentOS).
///
/// Every clip is SAVED on this computer: "Usman Ali." is fetched from
/// Google once, then played from the file every time after — instantly,
/// offline too, and at no cost. That is what keeps the clinic inside
/// Google's free amount.
class CloudVoice {
  CloudVoice(this._signIn);

  /// Makes sure this computer is signed in to the clinic's cloud account.
  final Future<void> Function() _signIn;

  final _inFlight = <String, Future<File?>>{};

  /// Why the last fetch failed, in plain words (null = it worked).
  /// Shown under "Test the voice" so a setup problem is never silent.
  String? lastError;
  Directory? _dir;

  Future<Directory> _folder(String voice) async {
    final base = _dir ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/DentOS/voice',
    );
    final d = Directory('${base.path}/$voice');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// "Usman  Ali." → "usman ali." — the same words always share one file.
  static String normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _fileName(String text) =>
      '${base64Url.encode(utf8.encode(normalize(text).toLowerCase())).replaceAll('=', '')}.mp3';

  /// The saved clip, or null when it isn't saved yet.
  Future<File?> cached(String text, String voice) async {
    final f = File('${(await _folder(voice)).path}/${_fileName(text)}');
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  /// The clip for [text] — from this computer if saved, else from Google
  /// (then saved). Null when offline and not saved yet; the caller then
  /// uses the computer's own voice for that phrase.
  Future<File?> clip(String text, String voice) {
    final t = normalize(text);
    if (t.isEmpty) return Future.value();
    final key = '$voice|${t.toLowerCase()}';
    return _inFlight[key] ??= _fetch(t, voice)
        // never let one stuck request hold up a call
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            lastError = 'Google took too long to answer.';
            return null;
          },
        )
        // A block body on purpose: `=> _inFlight.remove(key)` would RETURN
        // this same future, and whenComplete waits for a returned future —
        // so the request would wait for itself and never finish.
        .whenComplete(() {
          _inFlight.remove(key);
        });
  }

  /// Fetch now so the call later plays instantly (fire and forget).
  void prefetch(String text, String voice) => unawaited(clip(text, voice));

  Future<File?> _fetch(String text, String voice) async {
    final have = await cached(text, voice);
    if (have != null) {
      debugPrint('VOICE: "$text" from this computer');
      return have;
    }
    final sw = Stopwatch()..start();
    try {
      try {
        await _signIn().timeout(const Duration(seconds: 8));
      } catch (e) {
        lastError = 'This computer could not sign in to the clinic cloud: $e';
        debugPrint('VOICE: $lastError');
        return null;
      }
      debugPrint(
        'VOICE: signed in after ${sw.elapsedMilliseconds} ms — asking Google '
        'for "$text" ($voice)',
      );
      final res = await Supabase.instance.client.functions
          .invoke('speak-name', body: {'text': text, 'voice': voice})
          .timeout(const Duration(seconds: 12));
      final data = res.data;
      if (data is! Map || data['ok'] != true || data['audio'] is! String) {
        lastError =
            'speak-name answered: ${data is Map ? data['error'] ?? data : data}';
        debugPrint('VOICE: $lastError');
        return null;
      }
      final bytes = base64.decode(data['audio'] as String);
      if (bytes.isEmpty) {
        lastError = 'Google sent an empty clip.';
        return null;
      }
      final f = File('${(await _folder(voice)).path}/${_fileName(text)}');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      lastError = null;
      debugPrint(
        'VOICE: saved "$text" in ${sw.elapsedMilliseconds} ms '
        '(${bytes.length} bytes) → ${f.path}',
      );
      return f;
    } catch (e) {
      // offline, limit reached, function missing — computer voice is used
      lastError = '$e'.length > 300 ? '$e'.substring(0, 300) : '$e';
      debugPrint('VOICE: failed — $lastError');
      return null;
    }
  }
}
