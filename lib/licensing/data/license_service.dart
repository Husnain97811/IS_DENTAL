import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/utils/monotonic_clock.dart';
import '../domain/license.dart';
import 'license_verifier.dart';

class LicenseService {
  LicenseService(this._db, this._clock);
  final AppDatabase _db;
  final MonotonicClock _clock;
  final _verifier = LicenseVerifier();

  static const _kLicense = 'license_blob';
  static const _kSetup = 'setup_complete';

  Future<License?> _stored() async {
    final s = await _db.getSetting(_kLicense);
    if (s == null) return null;
    try {
      return License.fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  /// License-only status (no connectivity). Connectivity is layered by the controller.
  Future<LicenseState> resolveLicense() async {
    final lic = await _stored();
    if (lic == null)
      return const LicenseState(status: LicenseStatus.notActivated);
    if (!_verifier.verify(lic))
      return LicenseState(status: LicenseStatus.invalid, license: lic);
    final now = await _clock.now();
    if (now.isAfter(lic.expiresAt))
      return LicenseState(status: LicenseStatus.expired, license: lic);
    final setup =
        (await _db.getSetting(_kSetup)) == '1' && (await _db.userCount()) > 0;
    return LicenseState(
      status: LicenseStatus.active,
      license: lic,
      setupComplete: setup,
    );
  }

  Future<({bool ok, String? error})> activate(String raw) async {
    License lic;
    try {
      lic = License.fromJson(jsonDecode(raw));
    } catch (_) {
      return (ok: false, error: 'Invalid license format.');
    }
    if (!_verifier.verify(lic))
      return (ok: false, error: 'License signature is not valid.');
    if (DateTime.now().isAfter(lic.expiresAt))
      return (ok: false, error: 'This license has already expired.');
    await _db.setSetting(_kLicense, jsonEncode(lic.toJson()));
    return (ok: true, error: null);
  }

  Future<void> completeSetup({
    required License lic,
    required String clinicName,
    required String branch,
    required String currency,
    required String ownerName,
    required String username,
    required String password,
  }) async {
    await _db.saveProfile(
      clinicId: lic.clinicId,
      name: clinicName,
      branch: branch,
      currency: currency,
      tier: lic.tier.name,
    );
    await _db.createOwner(
      clinicId: lic.clinicId,
      fullName: ownerName,
      username: username,
      passwordHash: BCrypt.hashpw(password, BCrypt.gensalt()),
    );
    await _db.setSetting(_kSetup, '1');
  }
}

final licenseServiceProvider = Provider<LicenseService>(
  (ref) => LicenseService(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
  ),
);
