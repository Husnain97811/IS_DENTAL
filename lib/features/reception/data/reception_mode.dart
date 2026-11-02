import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';

/// The route the reception screen lives on (outside the shell, no login).
const kReceptionRoute = '/reception';

/// How the call is spoken. Short on purpose — a name and a room, like a
/// person at the front desk would say it.
enum VoiceStyle {
  /// "Usman Ali … Room number 5."
  simple,

  /// "Usman Ali … Please come to room number 5."
  polite,

  /// "Usman Ali … Kamra number 5."
  urdu,
}

/// This computer is a reception screen. Stored only on this computer
/// (inside the encrypted database) — it is a property of the machine in
/// the waiting room, not of the clinic.
class ReceptionMode {
  const ReceptionMode({
    required this.branchKey,
    this.style = VoiceStyle.simple,
    this.voiceName,
    this.voiceLocale,
    this.rate = 0.45,
    this.sayTwice = true,
    this.naturalVoice,
  });

  /// Branch uuid, or '' for the whole clinic.
  final String branchKey;
  final VoiceStyle style;

  /// Installed voice chosen at setup; null = best one found automatically.
  final String? voiceName, voiceLocale;

  /// Speaking speed (flutter_tts scale; 0.45 is calm and clear).
  final double rate;

  /// Announce the name two times, like a clinic receptionist would.
  final bool sayTwice;

  /// Google natural voice (e.g. "en-IN-Wavenet-D"), or null to use this
  /// computer's own voice. When set, the computer voice is only the
  /// fallback for a brand-new name while the internet is down.
  final String? naturalVoice;

  ReceptionMode copyWith({
    String? branchKey,
    VoiceStyle? style,
    String? voiceName,
    String? voiceLocale,
    double? rate,
    bool? sayTwice,
    String? naturalVoice,
  }) => ReceptionMode(
    branchKey: branchKey ?? this.branchKey,
    style: style ?? this.style,
    voiceName: voiceName ?? this.voiceName,
    voiceLocale: voiceLocale ?? this.voiceLocale,
    rate: rate ?? this.rate,
    sayTwice: sayTwice ?? this.sayTwice,
    naturalVoice: naturalVoice ?? this.naturalVoice,
  );

  Map<String, dynamic> toJson() => {
    'branchKey': branchKey,
    'style': style.name,
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'rate': rate,
    'sayTwice': sayTwice,
    'naturalVoice': naturalVoice,
  };

  factory ReceptionMode.fromJson(Map<String, dynamic> j) => ReceptionMode(
    branchKey: '${j['branchKey'] ?? ''}',
    style: VoiceStyle.values.firstWhere(
      (s) => s.name == j['style'],
      orElse: () => VoiceStyle.simple,
    ),
    voiceName: j['voiceName'] as String?,
    voiceLocale: j['voiceLocale'] as String?,
    rate: (j['rate'] as num?)?.toDouble() ?? 0.45,
    sayTwice: j['sayTwice'] != false,
    naturalVoice: j['naturalVoice'] as String?,
  );
}

/// null = a normal DentOS computer. Loading = not read yet (the router
/// waits on the splash screen so it never flashes the login first).
class ReceptionModeController extends AsyncNotifier<ReceptionMode?> {
  static const _k = 'reception_mode';

  @override
  Future<ReceptionMode?> build() async {
    final raw = await ref.read(appDatabaseProvider).getSetting(_k);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ReceptionMode.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> enable(ReceptionMode m) async {
    await ref.read(appDatabaseProvider).setSetting(_k, jsonEncode(m.toJson()));
    state = AsyncData(m);
  }

  Future<void> disable() async {
    await ref.read(appDatabaseProvider).setSetting(_k, '');
    state = const AsyncData(null);
  }
}

final receptionModeProvider =
    AsyncNotifierProvider<ReceptionModeController, ReceptionMode?>(
      ReceptionModeController.new,
    );

/// True when [password] is the password of an owner of this clinic.
/// Leaving the reception screen needs it — there is nobody signed in.
Future<bool> checkOwnerPassword(AppDatabase db, String password) async {
  if (password.isEmpty) return false;
  final owners = await (db.select(
    db.users,
  )..where((u) => u.role.equals('owner') & u.isDeleted.equals(false))).get();
  for (final o in owners) {
    try {
      if (BCrypt.checkpw(password, o.passwordHash)) return true;
    } catch (_) {}
  }
  return false;
}

/// "Dr. Muneeba Khan" → "Doctor Muneeba Khan" for the voice;
/// "Muneeba" → "Doctor Muneeba".
String spokenDoctor(String dentist) {
  final n = dentist.trim().replaceFirst(
    RegExp(r'^(dr|doctor)\.?\s+', caseSensitive: false),
    '',
  );
  return 'Doctor $n';
}

/// "Dr Muneeba Khan" on screen, whatever was typed.
String shownDoctor(String dentist) {
  final n = dentist.trim().replaceFirst(
    RegExp(r'^(dr|doctor)\.?\s+', caseSensitive: false),
    '',
  );
  return 'Dr $n';
}

/// "5" → "Room 5"; "Room 5" / "Chair 2" / "X-ray room" stay as typed.
/// Empty = no room set for that doctor.
String shownRoom(String room) {
  final r = room.trim();
  if (r.isEmpty) return '';
  return RegExp(r'^\d+[a-zA-Z]?$').hasMatch(r) ? 'Room $r' : r;
}

/// What is spoken, as separate short phrases with a pause between them —
/// a name, a breath, then where to go. One long sentence is what makes a
/// computer voice sound like a machine.
///
/// With no room set: "Usman Ali … Please come in."
List<String> announcement(String patient, String room, VoiceStyle style) {
  final p = patient.trim().replaceAll(RegExp(r'\s+'), ' ');
  final r = room.trim();
  final number = RegExp(r'^\d+[a-zA-Z]?$').hasMatch(r);
  if (r.isEmpty) {
    return [
      '$p.',
      style == VoiceStyle.urdu ? 'Tashreef laayein.' : 'Please come in.',
    ];
  }
  return [
    '$p.',
    switch (style) {
      VoiceStyle.simple => number ? 'Room number $r.' : '$r.',
      VoiceStyle.polite =>
        number ? 'Please come to room number $r.' : 'Please come to $r.',
      VoiceStyle.urdu => number ? 'Kamra number $r.' : '$r.',
    },
  ];
}

/// The same call as one line, for the setup dialog.
String announcementLine(String patient, String room, VoiceStyle style) =>
    announcement(patient, room, style).join('  …  ');
