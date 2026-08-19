import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import 'widgets/wa_channel_dialogs.dart';

class WhatsAppScreen extends ConsumerWidget {
  const WhatsAppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    final role = session?.role;
    final isOwner = role == AppRole.owner;
    final premium = ref.watch(isPremiumTierProvider);
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
          // Text(
          //   'WhatsApp & Reminders',
          //   style: Theme.of(context).textTheme.displayLarge,
          // ),
          // const SizedBox(height: 4),
          // Text(
          //   'App notifications always send. WhatsApp is an optional extra channel.',
          //   style: TextStyle(color: d.text3, fontSize: 9.sp),
          // ),
          // SizedBox(height: 2.4.h),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No branch assigned.',
                  style: TextStyle(color: d.text4, fontSize: 10.sp),
                ),
              ),
            )
          else if (premium) ...[
            _OffersSection(),
            SizedBox(height: 2.4.h),
          ],
          for (final b in visible) _BranchWaCard(branch: b, premium: premium),
        ],
      ),
    );
  }
}

class _BranchWaCard extends ConsumerWidget {
  const _BranchWaCard({required this.branch, required this.premium});
  final Branch branch;
  final bool premium;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final b = branch;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Offers section (premium only) ──
          // header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.teal.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 15.sp,
                    color: d.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Reminder channel: ${_channelLabel(b.waReminderChannel)}',
                        style: TextStyle(color: d.text3, fontSize: 9.sp),
                      ),
                    ],
                  ),
                ),
                // master WhatsApp switch (notifications always on)
                Column(
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
                      b.waEnabled ? 'WA on' : 'Notif only',
                      style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: d.line),

          // QR connection row
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
          Divider(height: 1, color: d.line),

          // Official API row
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
        ],
      ),
    );
  }

  static String _channelLabel(String c) => switch (c) {
    'qr' => 'WhatsApp (QR)',
    'official' => 'WhatsApp (Official API)',
    _ => 'Notifications only',
  };

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 13.sp, color: connected ? d.teal : d.text4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (connected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: d.teal.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'CONNECTED',
                          style: TextStyle(
                            color: d.teal,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                ),
              ],
            ),
          ),
          if (connected)
            TextButton(
              onPressed: onDisconnect,
              style: TextButton.styleFrom(foregroundColor: d.alert),
              child: Text(
                'Disconnect',
                style: TextStyle(fontSize: 10.sp, color: Colors.black),
              ),
            )
          else
            OutlinedButton(
              onPressed: onConnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: d.teal,
                side: BorderSide(color: d.teal.withValues(alpha: .5)),
              ),
              child: Text(
                'Connect',
                style: TextStyle(fontSize: 10.sp, color: Colors.black),
              ),
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
          'This unlinks WhatsApp QR for ${b.name}.\n After this your patients only get remainders on mobile app only.',
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

class _OffersSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final offers = ref.watch(offersProvider).value ?? const <Offer>[];

    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.ice.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.campaign_rounded, size: 20, color: d.ice),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offers & Promotions',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                  ),
                  onPressed: () => showOfferComposer(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Offer'),
                ),
              ],
            ),
          ),
          if (offers.isNotEmpty) Divider(height: 1, color: d.line),

          // offers list — capped to 40% of screen height, then scrolls
          if (offers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
              child: Text(
                'No offers yet. Tap "New Offer" to send your first one.',
                style: TextStyle(color: d.text4, fontSize: 8.5.sp),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 40.h),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final o in offers) _offerCard(context, ref, d, o),
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
    Offer o,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d.ice.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.local_offer_rounded, size: 15, color: d.ice),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 9.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${o.sentCount} sent'
                      '${o.branchId == null ? ' · all branches' : ''}'
                      '${o.isExpired ? ' · expired' : ''}',
                      style: TextStyle(color: d.text4, fontSize: 7.sp),
                    ),
                  ],
                ),
              ),
              // resend
              _iconAction(d, Icons.send, 'Resend', () async {
                final ok = await showDentDialog(
                  context,
                  kind: DentDialogKind.warning,
                  title: 'Resend offer?',
                  message:
                      'Send "${o.title}" again to all patients with the app.',
                  confirmLabel: 'Resend',
                  cancelLabel: 'Cancel',
                );
                if (ok != true) return;
                final res = await ref
                    .read(offerRepositoryProvider)
                    .resend(o.id);
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
          const SizedBox(height: 8),
          Text(
            o.body,
            style: TextStyle(color: d.text2, fontSize: 8.sp),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
    icon: Icon(icon, size: 16, color: danger ? d.alert : d.text4),
    tooltip: tip,
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    padding: EdgeInsets.zero,
  );
}
