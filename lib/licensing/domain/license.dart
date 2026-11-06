import 'dart:convert';

enum LicenseTier { basic, standard, premium }

enum CloudPackage { none, cloud }

enum LicenseStatus { notActivated, active, expired, invalid, reconnectRequired }

/// Paid add-ons a licence can carry on top of its tier.
class LicenseFeature {
  /// Reception screen + patient call. Premium includes it; a Standard
  /// licence gets it only when this is ticked in the licence tool.
  static const reception = 'reception';

  /// Owner phone app (Settings → Connected phones). Standard or Premium;
  /// ticked in the licence tool at renewal.
  static const ownerApp = 'ownerapp';

  /// Booking from a connected phone (new patients too). Any plan — Basic
  /// too — with the cloud; ticked in the licence tool at renewal.
  static const phoneBooking = 'phonebook';

  // ── Feature switches (licence tool → "Feature switches") ──
  // Plan default = Standard and Premium have them, Basic doesn't (Drive:
  // every plan). 'reminders' = an extra, 'no:reminders' = switched off.
  static const reminders = 'reminders';
  static const rxWhatsapp = 'rxwa';
  static const weeklyReport = 'weekly';
  static const apptChange = 'apptchange';
  static const reportingHub = 'hub';
  static const insights = 'insights';
  static const dentistPayouts = 'payouts';
  static const photos = 'photos';
  static const driveBackup = 'drive';

  /// Put in front of a switch to turn it OFF: 'no:reminders'.
  static const off = 'no:';

  /// "Payment overdue": open and print everything, add nothing new.
  static const viewOnly = 'viewonly';

  /// Plain names, for the Licence card.
  static const switchNames = {
    reminders: 'Automatic reminders',
    rxWhatsapp: 'Prescriptions on WhatsApp',
    weeklyReport: 'Weekly report',
    apptChange: '"Appointment changed" messages',
    reportingHub: 'Reporting Hub',
    insights: 'Insights & stats',
    dentistPayouts: 'Dentist payouts',
    photos: 'Before/after & Showcase',
    driveBackup: 'Google Drive backup',
  };

  static const all = {reception, ownerApp, phoneBooking, viewOnly};
}

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
    this.features = const [],
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

  /// Paid add-ons ([LicenseFeature]). SIGNED — unlike maxDevices, these
  /// unlock features on the computer that reads them, so a clinic must not
  /// be able to type one in.
  ///
  /// Kept out of the signed bytes when empty, so every licence issued
  /// before add-ons existed still verifies exactly as before. Always sorted,
  /// so the tool and the app build the same bytes.
  final List<String> features;

  bool has(String feature) => features.contains(feature);

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
    if (features.isNotEmpty) 'features': [...features]..sort(),
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
    features: [
      for (final f in (j['features'] as List?) ?? const []) f.toString(),
    ]..sort(),
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
