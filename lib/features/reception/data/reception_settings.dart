import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:is_dental/core/constants/views.dart';

/// What a reception screen shows — chosen by the owner on any computer,
/// kept in the cloud (`reception_settings`), live on the screen.
///
/// One row per clinic + branch. [branchKey] '' = the whole clinic.
class ReceptionSettings {
  const ReceptionSettings({
    this.doctors = const [],
    this.cases = const [],
    this.rooms = const {},
    this.autoCall = false,
  });

  static const empty = ReceptionSettings();
  static const maxDoctors = 3;
  static const maxCases = 4;

  /// Up to 3 doctors, one column each. Empty = the doctors with patients
  /// today, chosen automatically.
  final List<String> doctors;

  /// Up to 4 Showcase case ids (pairGroup), shown at random.
  final List<String> cases;

  /// Doctor → room ("5", "Room 5", "Chair 2"). Spoken as
  /// "Usman Ali … Room number 5" and shown under the doctor's name.
  final Map<String, String> rooms;

  /// Call the next arrived patient by itself when the doctor is free and
  /// the appointment time has come. Off unless the owner turns it on.
  final bool autoCall;

  /// The room for [dentist], '' when none is set.
  String roomOf(String dentist) => (rooms[dentist] ?? '').trim();

  Map<String, dynamic> toJson() => {
    'doctors': doctors,
    'cases': cases,
    'rooms': rooms,
    'auto_call': autoCall,
  };

  factory ReceptionSettings.fromJson(Map<String, dynamic> j) =>
      ReceptionSettings(
        doctors: [for (final d in (j['doctors'] as List? ?? const [])) '$d'],
        cases: [for (final c in (j['cases'] as List? ?? const [])) '$c'],
        rooms: {
          for (final e in ((j['rooms'] as Map?) ?? const {}).entries)
            if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim(),
        },
        autoCall: j['auto_call'] == true,
      );
}

String _cacheKey(String branchKey) => 'reception_settings:$branchKey';

/// Live settings for one branch key. Yields the copy saved on this
/// computer first, so a reception screen restarted without internet still
/// shows the right doctors and cases.
final receptionSettingsProvider =
    StreamProvider.family<ReceptionSettings, String>((ref, branchKey) async* {
      final db = ref.watch(appDatabaseProvider);
      final cloud = ref.watch(cloudServiceProvider);
      final cached = await db.getSetting(_cacheKey(branchKey));
      ReceptionSettings? last;
      try {
        last = cached == null
            ? null
            : ReceptionSettings.fromJson(jsonDecode(cached));
      } catch (_) {}
      yield last ?? ReceptionSettings.empty;

      final cid = await db.currentClinicId();
      if (cid == null) return;
      // Keep listening; when the connection drops, wait and listen again.
      while (true) {
        try {
          await cloud.ensureSignedIn();
          final live = Supabase.instance.client
              .from('reception_settings')
              .stream(primaryKey: ['clinic_id', 'branch_key'])
              .eq('clinic_id', cid);
          await for (final rows in live) {
            Map<String, dynamic>? row;
            for (final r in rows) {
              if ((r['branch_key'] ?? '') == branchKey) row = r;
            }
            final s = row == null
                ? ReceptionSettings.empty
                : ReceptionSettings.fromJson(row);
            await db.setSetting(_cacheKey(branchKey), jsonEncode(s.toJson()));
            yield s;
          }
        } catch (_) {
          // offline — keep showing the last settings
        }
        await Future<void>.delayed(const Duration(seconds: 30));
      }
    });

/// Saves the owner's choice for [branchKey]. Returns null, or a message.
Future<String?> saveReceptionSettings(
  WidgetRef ref, {
  required String branchKey,
  required ReceptionSettings settings,
}) async {
  final db = ref.read(appDatabaseProvider);
  final cloud = ref.read(cloudServiceProvider);
  final by = ref.read(authControllerProvider)?.fullName;
  try {
    final cid = await db.currentClinicId();
    if (cid == null) return 'This computer is not set up yet.';
    await cloud.ensureSignedIn();
    await Supabase.instance.client
        .from('reception_settings')
        .upsert({
          'clinic_id': cid,
          'branch_key': branchKey,
          'doctors': settings.doctors,
          'cases': settings.cases,
          'rooms': settings.rooms,
          'auto_call': settings.autoCall,
          'updated_by': by,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'clinic_id,branch_key')
        .timeout(const Duration(seconds: 10));
    await db.setSetting(_cacheKey(branchKey), jsonEncode(settings.toJson()));
    return null;
  } catch (_) {
    return 'No internet — the reception screen settings were not saved. '
        'Try again when the connection is back.';
  }
}

/// Doctors shown on the screen: the owner's choice, else up to 3 doctors
/// who have patients or calls today (alphabetical, so columns don't jump).
List<String> receptionDoctors(
  ReceptionSettings s, {
  required Iterable<String> busyToday,
}) {
  final picked = s.doctors.where((d) => d.trim().isNotEmpty).toList();
  if (picked.isNotEmpty) {
    return picked.take(ReceptionSettings.maxDoctors).toList();
  }
  final auto = busyToday.where((d) => d.trim().isNotEmpty).toSet().toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return auto.take(ReceptionSettings.maxDoctors).toList();
}
