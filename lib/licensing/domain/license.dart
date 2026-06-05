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
  });

  final String clinicId, clinicName, machineFingerprint, signature;
  final LicenseTier tier;
  final CloudPackage cloudPackage;
  final int maxBranches, maxUsers;
  final DateTime issuedAt, expiresAt;

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
  );
}

class LicenseState {
  const LicenseState({
    required this.status,
    this.license,
    this.setupComplete = false,
  });
  final LicenseStatus status;
  final License? license;
  final bool setupComplete;
}
