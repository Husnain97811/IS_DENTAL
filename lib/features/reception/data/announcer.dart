import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_tts/flutter_tts.dart';

import 'cloud_voice.dart';
import 'reception_mode.dart';

/// One installed text-to-speech voice.
class TtsVoice {
  const TtsVoice(this.name, this.locale, {this.quality = 0});
  final String name, locale;

  /// 2 = Premium, 1 = Enhanced, 0 = standard (compact). On a Mac the
  /// standard voices are the small, crackly ones; Premium sounds human.
  final int quality;

  String get label =>
      '$name · $locale'
      '${quality == 2
          ? ' · Premium'
          : quality == 1
          ? ' · Enhanced'
          : ''}';

  /// South-Asian English first, then Urdu, then other English.
  int get localeRank {
    final l = locale.toLowerCase().replaceAll('_', '-');
    if (l == 'en-pk') return 0;
    if (l == 'en-in') return 1;
    if (l.startsWith('ur')) return 2;
    if (l == 'en-gb') return 3;
    if (l.startsWith('en')) return 4;
    return 9;
  }

  /// Lower = better. Sound quality matters most — a Premium voice in any
  /// English beats a crackly standard one with the right accent.
  int get rank => (2 - quality) * 10 + localeRank;

  /// Novelty and very old voices — always robotic, never offered.
  static const _toys = {
    'albert',
    'bad news',
    'bahh',
    'bells',
    'boing',
    'bubbles',
    'cellos',
    'deranged',
    'eddy',
    'flo',
    'fred',
    'good news',
    'grandma',
    'grandpa',
    'hysterical',
    'jester',
    'junior',
    'kathy',
    'organ',
    'ralph',
    'reed',
    'rocko',
    'sandy',
    'shelley',
    'superstar',
    'trinoids',
    'whisper',
    'wobble',
    'zarvox',
  };

  bool get isToy {
    final n = name.toLowerCase().replaceAll(RegExp(r'\s*\(.*\)'), '').trim();
    return _toys.contains(n);
  }

  static int qualityOf(Map v) {
    final q = '${v['quality'] ?? ''} ${v['name'] ?? ''}'.toLowerCase();
    if (q.contains('premium')) return 2;
    if (q.contains('enhanced')) return 1;
    return 0;
  }
}

/// Chime + spoken name for the reception screen. Calls are queued, so two
/// doctors calling at the same moment are announced one after the other,
/// never over each other.
class Announcer {
  /// [voice] plays Google natural voice clips when the mode picks one.
  Announcer({this.voice});

  final CloudVoice? voice;
  final _tts = FlutterTts();
  final _player = AudioPlayer(); // chime
  final _speech = AudioPlayer(); // saved natural-voice clips
  Future<void> _queue = Future.value();
  bool _ready = false;
  bool _closed = false;

  static const chimeAsset = 'sounds/dentos_chime.wav'; // under assets/

  /// Voices installed on this computer, best first.
  static Future<List<TtsVoice>> voices() async {
    final tts = FlutterTts();
    try {
      final raw = await tts.getVoices;
      final out = <TtsVoice>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = '${v['name'] ?? ''}';
            final locale = '${v['locale'] ?? ''}';
            if (name.isEmpty) continue;
            final voice = TtsVoice(
              name,
              locale,
              quality: TtsVoice.qualityOf(v),
            );
            if (!voice.isToy && voice.localeRank < 9) out.add(voice);
          }
        }
      }
      out.sort((a, b) {
        final r = a.rank.compareTo(b.rank);
        return r != 0 ? r : a.name.compareTo(b.name);
      });
      return out;
    } catch (_) {
      return const [];
    } finally {
      try {
        await tts.stop();
      } catch (_) {}
    }
  }

  Future<void> _setup(ReceptionMode m) async {
    try {
      await _tts.awaitSpeakCompletion(true);
      var name = m.voiceName, locale = m.voiceLocale;
      if (name == null || locale == null) {
        final all = await voices();
        if (all.isNotEmpty) {
          name = all.first.name;
          locale = all.first.locale;
        }
      }
      if (name != null && locale != null) {
        await _tts.setVoice({'name': name, 'locale': locale});
      } else {
        await _tts.setLanguage('en-US');
      }
      await _tts.setSpeechRate(m.rate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // the default voice still speaks
    }
    _ready = true;
  }

  /// Chime, then name … room (twice if [ReceptionMode.sayTwice]).
  /// [room] is the doctor's room from the reception settings ('' = none).
  /// Returns when this announcement has finished.
  Future<void> announce(ReceptionMode m, String patient, String room) =>
      announceMany(m, [(patient, room)]);

  /// Several calls that arrived together (4 doctors calling at 10:00):
  /// ONE chime, each "name … room" once, then the whole list once more —
  /// about 20 s for 4 patients instead of 4 separate chimes.
  Future<void> announceMany(
    ReceptionMode m,
    List<(String patient, String room)> calls,
  ) {
    if (calls.isEmpty) return Future.value();
    final lines = [for (final (p, r) in calls) announcement(p, r, m.style)];
    final next = _queue.then((_) => _say(m, lines));
    _queue = next.catchError((_) {});
    return next;
  }

  /// Saves the clips for a patient who just arrived, so their call later
  /// plays instantly. Free after the first time; nothing when offline.
  void prefetch(ReceptionMode m, String patient, String room) {
    final v = voice, id = m.naturalVoice;
    if (v == null || id == null) return;
    for (final phrase in announcement(patient, room, m.style)) {
      v.prefetch(phrase, id);
    }
  }

  /// "Test voice" in the setup dialog. Returns null when the natural voice
  /// played, or the reason it didn't (the computer voice was used instead).
  Future<String?> test(ReceptionMode m, {String room = '5'}) async {
    lastProblem = null;
    voice?.lastError = null;
    await announce(m, 'Usman Ali', room).timeout(
      const Duration(seconds: 60),
      onTimeout: () => lastProblem ??= 'The test took too long.',
    );
    if (m.naturalVoice == null) return null;
    return voice?.lastError ?? lastProblem;
  }

  Future<void> _say(ReceptionMode m, List<List<String>> calls) async {
    if (_closed) return;
    // Natural voice: get every clip BEFORE the chime, so there is no gap
    // between the chime and the name. Saved clips are instant.
    final clips = <String, File?>{};
    final v = voice, id = m.naturalVoice;
    if (v != null && id != null) {
      final sw = Stopwatch()..start();
      try {
        await Future.wait([
          for (final phrases in calls)
            for (final p in phrases) v.clip(p, id).then((f) => clips[p] = f),
        ]).timeout(const Duration(seconds: 25));
      } catch (_) {
        // whatever arrived in time is used; the rest falls back below
      }
      debugPrint(
        'VOICE: clips ready in ${sw.elapsedMilliseconds} ms '
        '(${clips.values.where((f) => f != null).length}/${clips.length})',
      );
    }
    try {
      await _player.stop().timeout(const Duration(seconds: 3));
      await _player
          .play(AssetSource(chimeAsset), volume: 1.0)
          .timeout(const Duration(seconds: 3));
      // let the chime finish before the voice starts — overlapping the two
      // is what makes the first word sound broken
      await Future<void>.delayed(const Duration(milliseconds: 1700));
    } catch (_) {
      // no chime — still speak
    }
    for (var round = 0; round < (m.sayTwice ? 2 : 1); round++) {
      for (var c = 0; c < calls.length; c++) {
        final phrases = calls[c];
        for (var j = 0; j < phrases.length; j++) {
          if (_closed) return;
          final file = clips[phrases[j]];
          if (file != null && await _playFile(file)) {
            // played in the natural voice
          } else {
            // not saved yet and no internet — this computer's voice
            if (!_ready) await _setup(m);
            try {
              await _tts.speak(phrases[j]).timeout(const Duration(seconds: 10));
            } catch (_) {}
          }
          // a short breath between the name and the room
          if (j < phrases.length - 1) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
          }
        }
        // a longer gap between two patients
        if (c < calls.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
      if (round == 0 && m.sayTwice) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  /// Plays a saved clip and waits for it to end. False if it can't play.
  ///
  /// 1. audioplayers: open the file, read its length, play, and wait for
  ///    "complete" OR the clip's own length — never a blind 10 s wait.
  /// 2. If that fails on a Mac, macOS's own player (afplay) plays it.
  Future<bool> _playFile(File f) async {
    final name = f.path.split('/').last;
    final sw = Stopwatch()..start();
    try {
      await _speech.stop().timeout(const Duration(seconds: 3));
      await _speech
          .setSource(DeviceFileSource(f.path))
          .timeout(const Duration(seconds: 5));
      final len = await _speech.getDuration().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      debugPrint(
        'VOICE: playing $name (${len?.inMilliseconds ?? '?'} ms, '
        'opened in ${sw.elapsedMilliseconds} ms)',
      );
      final done = _speech.onPlayerComplete.first;
      await _speech.setVolume(1.0);
      await _speech.resume().timeout(const Duration(seconds: 3));
      final wait = (len == null || len == Duration.zero)
          ? const Duration(seconds: 6)
          : len + const Duration(milliseconds: 250);
      await Future.any([done, Future<void>.delayed(wait)]);
      lastProblem = null;
      return true;
    } catch (e) {
      debugPrint('VOICE: audioplayers could not play $name — $e');
      lastProblem = 'The saved clip could not be played: $e';
    }
    if (Platform.isMacOS) {
      try {
        final r = await Process.run('/usr/bin/afplay', [
          f.path,
        ]).timeout(const Duration(seconds: 15));
        debugPrint('VOICE: afplay exit ${r.exitCode} ${r.stderr}');
        if (r.exitCode == 0) {
          lastProblem = null;
          return true;
        }
      } catch (e) {
        debugPrint('VOICE: afplay failed — $e');
      }
    }
    return false;
  }

  /// What went wrong on the last announcement, or null. Shown under
  /// "Test the voice".
  String? lastProblem;

  /// Voice settings changed — the next announcement sets them again.
  void reset() => _ready = false;

  Future<void> dispose() async {
    _closed = true;
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _player.dispose();
      await _speech.dispose();
    } catch (_) {}
  }
}
