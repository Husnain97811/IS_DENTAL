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

  /// Validates a licence and returns it WITHOUT storing anything.
  /// Used by the upgrade flow, which must talk to the cloud before committing.
  Future<({License? license, String? error})> inspect(
    String raw, {
    String? expectedClinicId,
  }) async {
    License lic;
    try {
      lic = License.fromJson(jsonDecode(raw));
    } catch (_) {
      return (license: null, error: 'Invalid license format.');
    }
    if (!_verifier.verify(lic)) {
      return (license: null, error: 'License signature is not valid.');
    }
    if (DateTime.now().isAfter(lic.expiresAt)) {
      return (license: null, error: 'This license has already expired.');
    }
    if (expectedClinicId != null && lic.clinicId != expectedClinicId) {
      return (
        license: null,
        error:
            'This licence belongs to a different clinic '
            '(${lic.clinicId}). Ask for one issued to $expectedClinicId.',
      );
    }
    return (license: lic, error: null);
  }

  // / [expectedClinicId] — when re-activating on a live install, the new licence
  /// must belong to the same clinic. A different id would leave the app
  /// claiming to be a clinic whose data it doesn't hold.
  Future<({bool ok, String? error})> activate(
    String raw, {
    String? expectedClinicId,
  }) async {
    License lic;
    try {
      lic = License.fromJson(jsonDecode(raw));
    } catch (_) {
      return (ok: false, error: 'Invalid license format.');
    }
    if (!_verifier.verify(lic)) {
      return (ok: false, error: 'License signature is not valid.');
    }
    if (DateTime.now().isAfter(lic.expiresAt)) {
      return (ok: false, error: 'This license has already expired.');
    }
    if (expectedClinicId != null && lic.clinicId != expectedClinicId) {
      return (
        ok: false,
        error:
            'This licence belongs to a different clinic '
            '(${lic.clinicId}). Ask for one issued to $expectedClinicId.',
      );
    }

    // A verified licence cannot have been issued in the future, so a clock
    // mark later than its issue date is wrong. Pull it back.
    await _clock.healTo(lic.issuedAt);

    await _db.setSetting(_kLicense, jsonEncode(lic.toJson()));
    return (ok: true, error: null);
  }

  /// After re-activating, keep the stored clinic profile in step with the
  /// new licence. Only the tier changes — name, branch and currency are
  /// whatever the clinic set at setup.
  Future<void> syncProfileTier(License lic) async {
    final p = await _db.select(_db.clinicProfile).getSingleOrNull();
    if (p == null) return;
    await _db.saveProfile(
      clinicId: lic.clinicId,
      name: p.name,
      branch: p.branch,
      currency: p.currency,
      tier: lic.tier.name,
    );
  }

  Future<void> completeSetup({
    required License lic,
    required String clinicName,
    required String branch,
    required String currency,
    required String ownerName,
    required String username,
    required String email,
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
    await _db.setSetting('cloud_email', email);
    await _db.setSetting('cloud_password', password);
    await _db.setSetting('setup_complete', '1');
  }
}

final licenseServiceProvider = Provider<LicenseService>(
  (ref) => LicenseService(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
  ),
);
