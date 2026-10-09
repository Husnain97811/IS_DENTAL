import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';

class DeviceService {
  DeviceService(this._db);
  final AppDatabase _db;

  /// A name the owner will recognise in the device list.
  String _defaultName() {
    final host = Platform.localHostname;
    if (host.trim().isNotEmpty) return host;
    return switch (Platform.operatingSystem) {
      'macos' => 'Mac',
      'windows' => 'Windows PC',
      _ => 'Computer',
    };
  }

  String _platform() =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  /// Makes sure this computer has a local identity and a row in the devices
  /// table. Safe to call on every launch — it only fills in what's missing.
  /// Makes sure this computer has a local identity and a row in the devices
  /// table. Safe to call on every launch — it only fills in what's missing.
  ///
  /// Self-heals recovery: if this install has no row of its own but an
  /// active row already holds its letter, that row belongs to the computer
  /// it replaced. Take it over instead of creating a duplicate — the server
  /// only ever hands out free letters, so a live machine never shares one.
  Future<void> ensureRegistered({String? byUsername}) async {
    final clinicId = await _db.currentClinicId();
    if (clinicId == null || clinicId.isEmpty) return; // not set up yet

    var d = await _db.localDevice();

    final mine = await (_db.select(
      _db.devices,
    )..where((t) => t.uuid.equals(d.uuid))).getSingleOrNull();
    if (mine == null) {
      final sameLetter =
          await (_db.select(_db.devices)
                ..where(
                  (t) => t.letter.equals(d.letter) & t.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      if (sameLetter != null) {
        await _db.adoptDevice(sameLetter.letter);
        d = await _db.localDevice();
      }
    }

    await _db.upsertDevice(
      uuid: d.uuid,
      clinicId: clinicId,
      letter: d.letter,
      name: _defaultName(),
      platform: _platform(),
      joinedByName: byUsername,
      touchLastSeen: true,
    );
  }

  Future<void> rename(int id, String name) => _db
      .update(_db.devices)
      .replace(DevicesCompanion(id: Value(id), name: Value(name)));
}

final deviceServiceProvider = Provider(
  (ref) => DeviceService(ref.watch(appDatabaseProvider)),
);

final devicesStreamProvider = StreamProvider<List<DeviceRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchDevices(),
);
