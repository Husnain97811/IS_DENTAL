import 'dart:convert';

enum LicenseTier { basic, standard, premium }

enum CloudPackage { none, cloud }

enum LicenseStatus { notActivated, active, expired, invalid, reconnectRequired }

class License {
  const License({
    required this.clinicId,
    required this.clinicName,
    required this.tier,
    required this.cloudPackage,
    required this.maxBranches,
    required this.maxUsers,
    required this.issuedAt,
    required this.expiresAt,
    required this.machineFingerprint,
    required this.signature,
    this.maxDevices = 1,
  });

  final String clinicId, clinicName, machineFingerprint, signature;
  final LicenseTier tier;
  final CloudPackage cloudPackage;
  final int maxBranches, maxUsers;
  final DateTime issuedAt, expiresAt;

  /// How many computers may run this clinic's install.
  ///
  /// Deliberately OUTSIDE canonicalPayload(): adding a field there changes
  /// the signed bytes and would invalidate every licence already issued.
  /// Licences minted before this field existed decode as 1, which is the
  /// behaviour those clinics already have.
  ///
  /// Unsigned is safe here because it is never trusted on the computer that
  /// reads it — the join-code server reads maxDevices from the licence the
  /// OWNER's authenticated PC sends, and the owner's PC is the only thing
  /// that can mint a code.
  final int maxDevices;

  /// Deterministic bytes the vendor signs and the app verifies.
  /// The vendor signing tool MUST emit these fields in this exact order.
  String canonicalPayload() => jsonEncode({
    'clinicId': clinicId,
    'clinicName': clinicName,
    'tier': tier.name,
    'cloudPackage': cloudPackage.name,
    'maxBranches': maxBranches,
    'maxUsers': maxUsers,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'machineFingerprint': machineFingerprint,
  });

  Map<String, dynamic> toJson() => {
    ...jsonDecode(canonicalPayload()) as Map<String, dynamic>,
    'maxDevices': maxDevices,
    'signature': signature,
  };

  factory License.fromJson(Map<String, dynamic> j) => License(
    clinicId: j['clinicId'],
    clinicName: j['clinicName'],
    tier: LicenseTier.values.byName(j['tier']),
    cloudPackage: CloudPackage.values.byName(j['cloudPackage']),
    maxBranches: j['maxBranches'],
    maxUsers: j['maxUsers'],
    issuedAt: DateTime.parse(j['issuedAt']),
    expiresAt: DateTime.parse(j['expiresAt']),
    machineFingerprint: j['machineFingerprint'],
    signature: j['signature'],
    maxDevices: (j['maxDevices'] as num?)?.toInt() ?? 1,
  );
}

class LicenseState {
  const LicenseState({
    required this.status,
    this.license,
    this.setupComplete = false,
    this.reason,
  });
  final LicenseStatus status;
  final License? license;
  final bool setupComplete;
  final String? reason;
}
