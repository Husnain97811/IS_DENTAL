import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/whatsapp/presentation/wa_language_provider.dart';

import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import 'widgets/wa_channel_dialogs.dart';
import 'widgets/wa_automation_panel.dart';

// ── shared look ──────────────────────────────────────────────────────────────

/// The white card every section sits on.
BoxDecoration _cardDeco(DentColors d) => BoxDecoration(
  color: d.surface,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: d.line),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: .035),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ],
);

/// Tinted square behind a section or row icon.
Widget _iconTile(Color tone, IconData icon, {double box = 40, double? size}) =>
    Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(box * .28),
      ),
      child: Icon(icon, size: size ?? box * .5, color: tone),
    );

/// Small uppercase label that opens a group of rows inside a card.
Widget _sectionLabel(DentColors d, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
  child: Text(
    text,
    style: TextStyle(
      color: d.text4,
      fontSize: 8.5.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  ),
);

/// A coloured status pill ("CONNECTED", "Sending on WhatsApp" …).
Widget _pill(String text, Color tone, double fontSize, {IconData? icon}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: tone),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: tone,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

// ═════════════════════════════════ screen ═════════════════════════════════

class WhatsAppScreen extends ConsumerWidget {
  const WhatsAppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    final role = session?.role;
    final isOwner = role == AppRole.owner;

    // licence-backed entitlements — replaces isPremiumTierProvider
    final ent = ref.watch(entitlementsProvider);

    // Branch still exists in the shell; block it here until the router
    // redirect is wired.
    if (!ent.whatsapp) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.fromLTRB(36, 32, 36, 30),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: _cardDeco(d),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d.teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 28.sp,
                  color: d.teal,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'WhatsApp & Reminders',
                style: TextStyle(
                  color: d.text2,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Available on Standard and Premium. '
                'This clinic is on ${ent.tierLabel}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: d.text4, fontSize: 10.sp),
              ),
            ],
          ),
        ),
      );
    }

    final branches =
        ref.watch(branchesStreamProvider).value ?? const <Branch>[];
    final visible = isOwner
        ? branches
        : branches.where((b) => b.uuid == session?.branchId).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visible.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: _cardDeco(d),
              child: Column(
                children: [
                  Icon(
                    Icons.store_mall_directory_outlined,
                    size: 28,
                    color: d.text4,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No branch assigned.',
                    style: TextStyle(color: d.text4, fontSize: 10.sp),
                  ),
                ],
              ),
            )
          else ...[
            // ── Offers — Premium only ──
            if (ent.offers) ...[_OffersSection(), SizedBox(height: 2.4.h)],

            // ── Inbox — official API replies only ──
            if (visible.any((b) => b.officialConnected)) ...[
              _InboxSection(),
              SizedBox(height: 2.4.h),
            ],
          ],

          for (final b in visible)
            _BranchWaCard(branch: b, premium: ent.offers),
        ],
      ),
    );
  }
}

// ═════════════════════════════════ branch ═════════════════════════════════

class _BranchWaCard extends ConsumerWidget {
  const _BranchWaCard({required this.branch, required this.premium});
  final Branch branch;
  final bool premium;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    // Re-read the LIVE row so toggles (language, WA switch, connections)
    // rebuild this card the moment the DB changes.
    final b = (ref.watch(branchesStreamProvider).value ?? const <Branch>[])
        .firstWhere((x) => x.id == branch.id, orElse: () => branch);

    final live = b.waEnabled && b.anyWhatsApp;
    final (statusText, statusTone) = live
        ? ('Sending on WhatsApp', d.teal)
        : b.anyWhatsApp
        ? ('WhatsApp paused', d.warn)
        : ('Not connected', d.text4);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: _cardDeco(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── header ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  d.teal.withValues(alpha: live ? .09 : .03),
                  d.surface,
                ],
              ),
            ),
            child: Row(
              children: [
                _iconTile(d.teal, Icons.storefront_rounded, size: 15.sp),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            b.name,
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _pill(statusText, statusTone, 9.sp),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Reminder channel: ${_channelLabel(b.waReminderChannel)}',
                        style: TextStyle(color: d.text3, fontSize: 9.sp),
                      ),
                    ],
                  ),
                ),
                // master WhatsApp switch (notifications always on)
                Tooltip(
                  message: b.anyWhatsApp
                      ? 'Off = reminders go as app notifications only'
                      : 'Connect QR or the Official API first',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: b.waEnabled,
                        activeColor: d.teal,
                        onChanged: b.anyWhatsApp
                            ? (v) => ref
                                  .read(appDatabaseProvider)
                                  .setBranchWaEnabled(b.id, v)
                            : null, // can't enable if nothing connected
                      ),
                      Text(
                        b.waEnabled ? 'WhatsApp on' : 'App only',
                        style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),

          // ── connections ──
          _sectionLabel(d, 'CONNECTIONS'),
          _connectionRow(
            context,
            ref,
            d,
            icon: Icons.qr_code_rounded,
            title: 'QR (WhatsApp Web)',
            subtitle: 'Reminders only · free',
            connected: b.qrConnected,
            onConnect: () => showWaConnectDialog(
              context,
              branchLocalId: b.id,
              branchId: b.uuid,
              branchName: b.name,
            ),
            onDisconnect: () => _disconnectQr(context, ref, b),
          ),
          Divider(height: 1, indent: 72, endIndent: 18, color: d.line),
          _connectionRow(
            context,
            ref,
            d,
            icon: Icons.verified_rounded,
            title: 'Official API',
            subtitle: 'Reminders + offers · you pay Meta',
            connected: b.officialConnected,
            onConnect: () => _setupOfficial(context, ref, b),
            onDisconnect: () => _disconnectOfficial(context, ref, b),
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: d.line),

          // ── automation ──
          _sectionLabel(d, 'AUTOMATION'),
          if (b.qrConnected) ...[
            _languageRow(context, ref, d, b),
            Divider(height: 1, indent: 70, endIndent: 18, color: d.line),
            // prescriptions on WhatsApp · weekly summary · message log
            WaAutomationPanel(branchUuid: b.uuid, branchName: b.name),
          ] else
            _automationHint(d),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  static String _channelLabel(String c) => switch (c) {
    'qr' => 'WhatsApp (QR)',
    'official' => 'WhatsApp (Official API)',
    _ => 'Notifications only',
  };

  /// What the Automation group holds, until QR is connected.
  Widget _automationHint(DentColors d) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.line),
      ),
      child: Row(
        children: [
          _iconTile(d.ice, Icons.auto_mode_rounded, box: 38, size: 13.sp),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect QR to switch these on',
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reminder language, prescriptions on WhatsApp, the weekly '
                  'owner summary and the message log.',
                  style: TextStyle(color: d.text3, fontSize: 10.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _languageRow(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    Branch b,
  ) {
    final current =
        ref.watch(branchWaLanguageProvider(b.id)).value ?? b.waLanguage;

    Widget seg(String code, String label) {
      final on = current == code;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: on
              ? null
              : () async {
                  await ref
                      .read(appDatabaseProvider)
                      .setBranchWaLanguage(b.id, code);
                  pushBranchLanguage(b.uuid, code);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? d.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? d.ice : Colors.transparent),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? d.ice : d.text2,
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w700,
                fontFamily: code == 'ur' ? 'NotoNaskhArabic' : null,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          _iconTile(d.ice, Icons.translate_rounded, box: 38, size: 13.sp),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reminder language',
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Language of the WhatsApp reminders sent from this branch',
                  style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // segmented English | اردو
          Container(
            width: (16.w).clamp(190.0, 250.0),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: d.surface2,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: d.line),
            ),
            child: Row(
              children: [
                seg('en', 'English'),
                const SizedBox(width: 3),
                seg('ur', 'اردو'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionRow(
    BuildContext context,
    WidgetRef ref,
    DentColors d, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool connected,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          _iconTile(connected ? d.teal : d.text4, icon, size: 13.sp),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (connected)
                      _pill(
                        'CONNECTED',
                        d.teal,
                        9.sp,
                        icon: Icons.check_circle_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (connected)
            OutlinedButton.icon(
              onPressed: onDisconnect,
              icon: Icon(Icons.link_off_rounded, size: 16, color: d.alert),
              style: OutlinedButton.styleFrom(
                foregroundColor: d.alert,
                side: BorderSide(color: d.alert.withValues(alpha: .35)),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: buttonShape,
              ),
              label: Text(
                'Disconnect',
                style: TextStyle(fontSize: 10.sp, color: d.alert),
              ),
            )
          else
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.add_link_rounded, size: 17),
              style: FilledButton.styleFrom(
                backgroundColor: d.ice,
                foregroundColor: AppPalette.onAccent,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: buttonShape,
              ),
              label: Text('Connect', style: TextStyle(fontSize: 10.sp)),
            ),
        ],
      ),
    );
  }

  Future<void> _disconnectQr(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Disconnect QR?',
      message:
          'This unlinks WhatsApp QR for ${b.name}.\n'
          'After this, patients get reminders only as notifications in the mobile app.',
      confirmLabel: 'Disconnect',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;

    await WaConnectService().disconnect(b.uuid);
    await ref.read(appDatabaseProvider).setBranchQrStatus(b.id, null);

    // if reminders were on QR, decide fallback
    if (b.waReminderChannel == 'qr') {
      if (context.mounted) {
        await handleChannelLoss(context, ref, b, lostChannel: 'qr');
      }
    }
  }

  Future<void> _setupOfficial(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    // opens a form for token + phone id; on save, applies + maybe shift dialog
    await showOfficialApiSetup(context, ref, b);
  }

  Future<void> _disconnectOfficial(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Disconnect Official API?',
      message:
          'This removes the Meta API credentials for ${b.name}. '
          'Offers and official-API reminders will stop.',
      confirmLabel: 'Disconnect',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;

    await ref
        .read(appDatabaseProvider)
        .setBranchOfficialApi(
          id: b.id,
          apiToken: null,
          phoneId: null,
          phone: b.waPhone,
        );

    if (b.waReminderChannel == 'official') {
      if (context.mounted) {
        await handleChannelLoss(context, ref, b, lostChannel: 'official');
      }
    }
  }
}

// ═════════════════════════════════ offers ═════════════════════════════════

class _OffersSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final offers = ref.watch(offersProvider).value ?? const <Offer>[];
    final ent = ref.watch(entitlementsProvider);

    // Premium only (the screen checks too); needs the WhatsApp permission
    if (!ent.offers) return const SizedBox.shrink();
    if (!ref.watch(canProvider(Perm.manageWhatsapp))) {
      return Center(
        child: Text(
          'You don\'t have access to this screen.',
          style: TextStyle(color: d.text4, fontSize: 10.sp),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDeco(d),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [d.ice.withValues(alpha: .08), d.surface],
              ),
            ),
            child: Row(
              children: [
                _iconTile(d.ice, Icons.campaign_rounded, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Offers & Promotions',
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _pill(
                            'Premium',
                            d.warn,
                            9.sp,
                            icon: Icons.workspace_premium_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Send promotions to patients with the app',
                        style: TextStyle(color: d.text3, fontSize: 9.sp),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice,
                    foregroundColor: AppPalette.onAccent,
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => showOfferComposer(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Offer'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),

          // offers list — capped to 40% of screen height, then scrolls
          if (offers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
              child: Column(
                children: [
                  Icon(Icons.local_offer_outlined, size: 26, color: d.text4),
                  const SizedBox(height: 8),
                  Text(
                    'No offers yet. Tap "New Offer" to send your first one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 40.h),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < offers.length; i++)
                      _offerCard(
                        context,
                        ref,
                        d,
                        offers[i],
                        last: i == offers.length - 1,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _offerCard(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    Offer o, {
    required bool last,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: o.isExpired ? .55 : 1,
            child: _iconTile(
              d.ice,
              Icons.local_offer_rounded,
              box: 36,
              size: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.title,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${o.sentCount} sent'
                  '${o.branchId == null ? ' · all branches' : ''}'
                  '${o.isExpired ? ' · expired' : ''}',
                  style: TextStyle(
                    color: o.isExpired ? d.text3 : d.text1,
                    fontSize: 9.5.sp,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  o.body,
                  style: TextStyle(color: d.text1, fontSize: 9.5.sp),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // resend
          _iconAction(d, Icons.send_rounded, 'Resend', () async {
            final ok = await showDentDialog(
              context,
              kind: DentDialogKind.warning,
              title: 'Resend offer?',
              message: 'Send "${o.title}" again to all patients with the app.',
              confirmLabel: 'Resend',
              cancelLabel: 'Cancel',
            );
            if (ok != true) return;
            final res = await ref.read(offerRepositoryProvider).resend(o.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    res.ok
                        ? 'Resent to ${res.sent} patient${res.sent == 1 ? '' : 's'}.'
                        : (res.error ?? 'Resend failed.'),
                  ),
                ),
              );
            }
          }),
          // delete
          _iconAction(d, Icons.delete_outline_rounded, 'Delete', () async {
            final ok = await showDentDialog(
              context,
              kind: DentDialogKind.warning,
              title: 'Delete offer?',
              message: 'Remove "${o.title}" from history.',
              confirmLabel: 'Delete',
              cancelLabel: 'Cancel',
            );
            if (ok == true) {
              await ref.read(offerRepositoryProvider).deleteOffer(o.id);
            }
          }, danger: true),
        ],
      ),
    );
  }

  Widget _iconAction(
    DentColors d,
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool danger = false,
  }) => IconButton(
    icon: Icon(icon, size: 16, color: danger ? d.alert : d.text3),
    tooltip: tip,
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    padding: EdgeInsets.zero,
  );
}

// ═════════════════════════════════ inbox ══════════════════════════════════

class _InboxSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final convosAsync = ref.watch(waConversationsProvider);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDeco(d),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [d.teal.withValues(alpha: .08), d.surface],
              ),
            ),
            child: Row(
              children: [
                _iconTile(d.teal, Icons.inbox_rounded, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Inbox',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Patient replies (Official API)',
                        style: TextStyle(color: d.text3, fontSize: 8.sp),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, size: 18, color: d.text3),
                  onPressed: () => ref.invalidate(waConversationsProvider),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),
          convosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Could not load inbox: $e',
                style: TextStyle(color: d.alert, fontSize: 8.sp),
              ),
            ),
            data: (convos) => convos.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.mark_chat_read_outlined,
                          size: 26,
                          color: d.text4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No messages yet. Patient replies will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                        ),
                      ],
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 45.h),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final c in convos) _convoTile(context, d, c),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _convoTile(BuildContext context, DentColors d, WaConversation c) {
    final name = c.patientName ?? c.waNumber;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return InkWell(
      onTap: () => _showConversation(context, d, c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: d.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d.teal.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: d.teal,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    c.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: d.text3, fontSize: 8.sp),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _ago(c.lastAt),
              style: TextStyle(color: d.text4, fontSize: 7.sp),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: d.text4),
          ],
        ),
      ),
    );
  }

  void _showConversation(BuildContext context, DentColors d, WaConversation c) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460, maxHeight: 70.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    _iconTile(d.teal, Icons.chat_rounded, box: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.patientName ?? c.waNumber,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: d.text3),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: d.line),
              Flexible(
                child: Container(
                  color: d.surface2.withValues(alpha: .5),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in c.messages)
                        Align(
                          alignment: m.direction == 'in'
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(maxWidth: 70.w),
                            decoration: BoxDecoration(
                              color: m.direction == 'in'
                                  ? d.surface
                                  : d.teal.withValues(alpha: .15),
                              border: m.direction == 'in'
                                  ? Border.all(color: d.line)
                                  : null,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: Radius.circular(
                                  m.direction == 'in' ? 4 : 14,
                                ),
                                bottomRight: Radius.circular(
                                  m.direction == 'in' ? 14 : 4,
                                ),
                              ),
                            ),
                            child: Text(
                              m.body,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 8.5.sp,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
