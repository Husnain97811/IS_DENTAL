import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/licensing/domain/reset_token.dart';

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

  static const _kUsedNonces = 'used_reset_nonces';

  /// Consume a vendor reset token and set a new owner password.
  ///
  /// Fully offline: the signature is checked against the compiled-in modulus.
  /// Single-use — the nonce is recorded locally and refused thereafter.
  Future<({bool ok, String? error})> redeemOwnerReset({
    required String raw,
    required String newPassword,
  }) async {
    ResetToken t;
    try {
      t = ResetToken.fromJson(jsonDecode(raw));
    } catch (_) {
      return (ok: false, error: 'That does not look like a reset code.');
    }

    if (!_verifier.verifyReset(t)) {
      return (ok: false, error: 'This reset code is not valid.');
    }

    final clinicId = await _db.currentClinicId();
    if (clinicId == null || t.clinicId != clinicId) {
      return (ok: false, error: 'This reset code is for a different clinic.');
    }

    // monotonic clock — rolling the system date back cannot revive it
    final now = await _clock.now();
    if (now.isAfter(t.expiresAt)) {
      return (
        ok: false,
        error: 'This reset code has expired. Please request a new one.',
      );
    }

    final used = (await _db.getSetting(_kUsedNonces) ?? '').split(',');
    if (used.contains(t.nonce)) {
      return (ok: false, error: 'This reset code has already been used.');
    }

    if (newPassword.length < 6) {
      return (ok: false, error: 'Choose a password of at least 6 characters.');
    }

    final owner =
        await (_db.select(_db.users)
              ..where((u) => u.role.equals('owner') & u.isDeleted.equals(false))
              ..limit(1))
            .getSingleOrNull();
    if (owner == null) {
      return (ok: false, error: 'No owner account found on this device.');
    }

    await (_db.update(_db.users)..where((u) => u.id.equals(owner.id))).write(
      UsersCompanion(
        passwordHash: Value(BCrypt.hashpw(newPassword, BCrypt.gensalt())),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // burn the nonce — keep the last 20 so the list stays bounded
    final next = [...used.where((e) => e.isNotEmpty), t.nonce];
    await _db.setSetting(
      _kUsedNonces,
      next.sublist(next.length > 20 ? next.length - 20 : 0).join(','),
    );

    return (ok: true, error: null);
  }

  /// Finishes a JOIN or a RECOVER. Deliberately does NOT create an owner,
  /// does NOT call register-clinic, and does NOT allow seeding:
  ///
  ///  • createOwner would give the clinic a second owner, against a licence
  ///    that counts the owner toward maxUsers
  ///  • register-clinic re-upserts the clinics row, and a stale licence
  ///    pasted here would roll expires_at back — the heartbeat reads exactly
  ///    that row, so every machine in the clinic would lock out at once
  ///  • seeding would write factory defaults with today's timestamp, which
  ///    last-write-wins would then apply over the owner's real settings
  ///
  /// Staff logins arrive with the users table during the restore.
  Future<void> completeJoin({
    required License lic,
    required String cloudEmail,
    required String cloudPassword,
    required String deviceLetter,
  }) async {
    final existing = await _db.select(_db.clinicProfile).getSingleOrNull();
    await _db.saveProfile(
      clinicId: lic.clinicId,
      name: lic.clinicName,
      branch: existing?.branch ?? '',
      currency: existing?.currency ?? 'PKR (Rs)',
      tier: lic.tier.name,
    );
    await _db.setSetting('cloud_email', cloudEmail);
    await _db.setSetting('cloud_password', cloudPassword);
    await _db.setLocalDeviceLetter(deviceLetter);
    await _db.setSeedAllowed(false);
    await _db.setSetting('setup_complete', '1');
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
    // A genuinely new clinic — this install owns the factory defaults.
    await _db.setSeedAllowed(true);
    await _db.setSetting('setup_complete', '1');
  }
}

final licenseServiceProvider = Provider<LicenseService>(
  (ref) => LicenseService(
    ref.watch(appDatabaseProvider),
    ref.watch(monotonicClockProvider),
  ),
);
