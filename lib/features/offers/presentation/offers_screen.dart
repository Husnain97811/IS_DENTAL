import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import '../domain/offer.dart';
import 'offers_controller.dart';
import 'widgets/offer_composer.dart';

/// ── FONT SCALE ──────────────────────────────────────────────
/// One number controls the offer-card fonts on this screen.
/// (The page heading and the "New Offer" button are intentionally
/// left at their normal theme sizes and are NOT affected by this.)
/// 1.00 = original, 1.10 = 10% bigger (current), 1.15 = 15%, etc.
const double _fontScale = 1.10;
double _sp(double base) => base * _fontScale;
// ─────────────────────────────────────────────────────────────

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  static String _fmt(DateTime dt) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final offers = ref.watch(offersProvider).value ?? const <Offer>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Heading + New Offer button (NOT scaled — normal theme sizes) ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offers & Broadcasts',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send promotions to patients who have the app.',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: () => showOfferComposer(context),
                icon: const Icon(Icons.campaign_rounded, size: 18),
                label: const Text('New Offer'),
              ),
            ],
          ),
          SizedBox(height: 2.4.h),

          if (offers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.local_offer_outlined, size: 34, color: d.text4),
                    const SizedBox(height: 10),
                    Text(
                      'No offers sent yet',
                      style: TextStyle(
                        color: d.text3,
                        fontSize: _sp(10.5).sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "New Offer" to send your first promotion.',
                      style: TextStyle(color: d.text4, fontSize: _sp(9.5).sp),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final o in offers) _offerCard(context, ref, d, o),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: d.ice.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.local_offer_rounded, size: 18, color: d.ice),
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
                        fontSize: _sp(10).sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Sent ${_fmt(o.createdAt)} · ${o.sentCount} recipient${o.sentCount == 1 ? '' : 's'}'
                      '${o.branchId == null ? ' · all branches' : ''}',
                      style: TextStyle(color: d.text4, fontSize: _sp(8.5).sp),
                    ),
                  ],
                ),
              ),
              if (o.isExpired)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: d.text4.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'EXPIRED',
                    style: TextStyle(
                      fontSize: _sp(6.5).sp,
                      color: d.text3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: d.text4,
                ),
                onPressed: () async {
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
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            o.body,
            style: TextStyle(color: d.text2, fontSize: _sp(8.5).sp),
          ),
          if (o.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Valid until ${_fmt(o.expiresAt!)}',
              style: TextStyle(color: d.text3, fontSize: _sp(7.5).sp),
            ),
          ],
        ],
      ),
    );
  }
}
