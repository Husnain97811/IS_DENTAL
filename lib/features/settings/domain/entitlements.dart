import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/constants/views.dart';

/// What this installation is allowed to do.
///
/// Three things decide it:
///  • cloudPackage — `none` means no backend exists, so every cloud feature
///    is impossible and the tier is meaningless (treated as basic).
///  • tier — only meaningful when cloud is on.
///  • feature switches — Inover Studio can switch a feature OFF for one
///    clinic ('no:reminders'), or give it as an EXTRA to a plan without it
///    ('reminders'). Ticked in the licence tool, signed into the licence,
///    so a clinic can't change them. See [LicenseFeature].
///
/// Screens never check the tier themselves — they ask for a feature here
/// (`ent.showcase`, `ent.insights` …), so moving a feature between plans is
/// a one-line change in this file. The server applies the SAME rules before
/// it sends any WhatsApp message.
class Entitlements {
  const Entitlements({
    required this.cloud,
    required this.tier,
    required this.maxBranches,
    required this.maxUsers,
    this.features = const <String>{},
  });

  final bool cloud;
  final LicenseTier tier;
  final int maxBranches;
  final int maxUsers;

  /// Signed add-ons and feature switches from the licence ([LicenseFeature]).
  final Set<String> features;

  bool get _standardUp =>
      tier == LicenseTier.standard || tier == LicenseTier.premium;

  bool get _premium => cloud && tier == LicenseTier.premium;

  /// Standard or Premium, on a cloud licence.
  bool get standard => cloud && _standardUp;

  /// A switchable feature: what the plan includes ([plan]), unless it was
  /// switched off for this clinic, or given as an extra. An extra that needs
  /// the cloud only works on a cloud licence.
  bool _switch(String key, {required bool plan, bool needsCloud = true}) {
    if (features.contains('${LicenseFeature.off}$key')) return false;
    if (plan) return true;
    return features.contains(key) && (cloud || !needsCloud);
  }

  /// Was this feature switched off by Inover Studio (rather than simply not
  /// in the plan)? Screens hide it instead of showing an upgrade offer.
  bool switchedOff(String key) =>
      features.contains('${LicenseFeature.off}$key');

  // ── Basic (cloud) ──
  bool get sync => cloud;
  bool get restoreFromCloud => cloud;

  // ── Standard and up ──
  bool get patientApp => standard;
  bool get bookingRequests => standard;
  bool get patientQr => standard;
  bool get clinicQr => standard;

  // ── WhatsApp — switchable per clinic ──

  /// Automatic appointment reminders (day before, 2 hours before, follow-up).
  bool get reminders => _switch(LicenseFeature.reminders, plan: standard);

  /// Prescription PDFs to the patient on WhatsApp — automatic and Send/Resend.
  bool get rxOnWhatsapp => _switch(LicenseFeature.rxWhatsapp, plan: standard);

  /// The Sunday report to the owner's WhatsApp.
  bool get weeklyReport => _switch(LicenseFeature.weeklyReport, plan: standard);

  /// "Your appointment was moved / cancelled" WhatsApp to the patient.
  bool get apptChangeMessages =>
      _switch(LicenseFeature.apptChange, plan: standard);

  /// WhatsApp settings (connect a number, language, …): shown while ANY
  /// WhatsApp feature is on.
  bool get whatsapp =>
      reminders || rxOnWhatsapp || weeklyReport || apptChangeMessages;

  /// Messages a day per WhatsApp number on Basic (every patient message
  /// counts). Null = no plan limit (the server still keeps a safety limit).
  int? get whatsappDailyLimit => standard ? null : 20;

  // ── Reports and extras — switchable per clinic ──

  /// Reports → Insights tab and the "Insights at a glance" card.
  bool get insights => _switch(LicenseFeature.insights, plan: standard);

  /// Reports overview: Still owed to you, Patients seen, Procedures done.
  /// Same switch as [insights].
  bool get practiceStats => insights;

  /// Before & After photos on the patient file.
  bool get beforeAfterPhotos => _switch(LicenseFeature.photos, plan: standard);

  /// Smile Showcase screen. Same switch as [beforeAfterPhotos].
  bool get showcase => beforeAfterPhotos;

  /// Detailed Reporting Hub.
  bool get reportingHub => _switch(LicenseFeature.reportingHub, plan: standard);

  /// Expenses → Dentist payouts.
  bool get dentistPayouts =>
      _switch(LicenseFeature.dentistPayouts, plan: standard);

  /// Google Drive backup — every plan, offline too.
  bool get driveBackup =>
      _switch(LicenseFeature.driveBackup, plan: true, needsCloud: false);

  // ── Payment overdue ──

  /// "View only": everything can be opened and printed, but no new
  /// appointments, patients or invoices. Works offline too.
  bool get viewOnly => features.contains(LicenseFeature.viewOnly);

  // ── Premium only ──
  bool get offers => _premium;

  /// Call patients dialog + reception screen. Premium, or a Standard
  /// licence with the "Reception & patient call" add-on ticked. Needs the
  /// cloud — calls travel through it.
  bool get patientCall =>
      _premium || (standard && features.contains(LicenseFeature.reception));

  /// True when the clinic has patient call only because of the add-on
  /// (shown on the Licence panel).
  bool get patientCallAddOn => patientCall && !_premium;

  /// Owner phone app — Settings → Connected phones. A Standard or Premium
  /// cloud licence with the "Owner phone app" add-on ticked at renewal.
  bool get ownerPhone => standard && features.contains(LicenseFeature.ownerApp);

  /// Booking from a connected phone — any plan, Basic too, with the cloud
  /// and the "Phone booking" add-on.
  bool get phoneBooking =>
      cloud && features.contains(LicenseFeature.phoneBooking);

  /// May phones be connected at all? (Settings → Connected phones)
  bool get pairPhone => ownerPhone || phoneBooking;

  // ── For the Licence card ──

  /// Plain names of the features Inover Studio switched off.
  List<String> get switchedOffNames => [
    for (final e in LicenseFeature.switchNames.entries)
      if (switchedOff(e.key)) e.value,
  ];

  /// Plain names of the features given as extras on top of the plan.
  List<String> get extraNames => [
    for (final e in LicenseFeature.switchNames.entries)
      if (features.contains(e.key) &&
          (cloud || e.key == LicenseFeature.driveBackup))
        e.value,
  ];

  // ── Tier-only (works offline) ──
  bool get unlimitedXrays => tier != LicenseTier.basic;

  /// The 48h reconnect requirement only applies to cloud installs.
  bool get enforcesOnlineCheck => cloud;

  /// Label for upgrade prompts.
  String get tierLabel => switch (tier) {
    LicenseTier.premium => 'Premium',
    LicenseTier.standard => 'Standard',
    LicenseTier.basic => cloud ? 'Basic' : 'Offline',
  };
}

final entitlementsProvider = Provider<Entitlements>((ref) {
  final lic = ref.watch(licenseControllerProvider).value?.license;
  if (lic == null) {
    return const Entitlements(
      cloud: false,
      tier: LicenseTier.basic,
      maxBranches: 1,
      maxUsers: 3,
    );
  }
  final cloud = lic.cloudPackage == CloudPackage.cloud;
  return Entitlements(
    // offline installs are always basic, whatever the licence says
    cloud: cloud,
    tier: cloud ? lic.tier : LicenseTier.basic,
    maxBranches: lic.maxBranches,
    maxUsers: lic.maxUsers,
    // Kept on offline licences too: "view only" and the Drive switch work
    // offline. Every add-on and cloud switch checks [cloud] itself.
    features: lic.features.toSet(),
  );
});
