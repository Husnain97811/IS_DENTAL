import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/activity_log.dart';
import '../../data/hub_data.dart';
import '../../data/hub_score.dart';
import 'hub_ui.dart';

IconData hubScorePartIcon(HubScoreKey k) => switch (k) {
  HubScoreKey.collections => Icons.payments_outlined,
  HubScoreKey.owed => Icons.account_balance_wallet_outlined,
  HubScoreKey.visits => Icons.person_off_outlined,
  HubScoreKey.chairs => Icons.event_seat_outlined,
  HubScoreKey.regulars => Icons.repeat_rounded,
  HubScoreKey.system => Icons.devices_other_outlined,
  HubScoreKey.discounts => Icons.local_offer_outlined,
};

String _points(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

/// "▲ 4 vs the 30 days before" — null when there is nothing to compare.
HubDelta? hubScoreDelta(HubScore s) {
  final c = s.change;
  if (c == null) return null;
  if (c == 0) return const HubDelta('Same as the 30 days before', null);
  return HubDelta(
    '${c > 0 ? '▲' : '▼'} ${c.abs()} vs the 30 days before',
    c > 0,
  );
}

// ═══════════════════════════ the card on Right now ══════════════════════════

/// Clinic health — the big ring, what is pulling it down, and a way into
/// every part.
class HubHealthCard extends StatelessWidget {
  const HubHealthCard({super.key, required this.scores, this.title});
  final HubScores scores;

  /// "Clinic health" by default; the branch name in a one-branch view.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hub = HubScope.of(context);
    final s = scores.clinic;
    final tone = hubScoreTone(d, s.value);
    final delta = hubScoreDelta(s);
    final drags = s.drags.take(3).toList();

    final summary = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (title ?? 'Clinic health').toUpperCase(),
          style: TextStyle(
            color: d.text3,
            fontSize: 9.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: .9,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.label,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: s.ready ? tone : d.text1,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.ready
              ? 'Last 30 days · ${s.parts.where((p) => p.counted).length} of '
                    '${s.parts.length} parts measured'
              : (s.completeOn == null
                    ? 'Needs a few more weeks of records'
                    : 'The score starts around ${hubDate(s.completeOn!)}'),
          style: TextStyle(color: d.text3, fontSize: 9.6.sp, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (delta != null)
              HubPill(
                delta.text,
                delta.good == null ? d.text3 : (delta.good! ? d.ok : d.alert),
              ),
            if (s.ready && s.partial)
              HubPill(
                'Partial · complete ${s.completeOn == null ? 'later' : 'by ${hubShortDate(s.completeOn!)}'}',
                d.warn,
                icon: Icons.timelapse_rounded,
              ),
          ],
        ),
      ],
    );

    final pulling = drags.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.verified_rounded, color: d.ok, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.ready
                        ? 'Nothing is pulling the score down. Keep it up.'
                        : 'Not enough records yet to say what needs work.',
                    style: TextStyle(color: d.text2, fontSize: 10.2.sp),
                  ),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "WHAT'S PULLING IT DOWN",
                style: TextStyle(
                  color: d.text3,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .9,
                ),
              ),
              const SizedBox(height: 6),
              for (final p in drags)
                _DragRow(part: p, hidden: hub.hidden, onGo: hub.onGo),
            ],
          );

    final detailsButton = OutlinedButton.icon(
      onPressed: () => showHubScoreDetails(
        context,
        score: s,
        chairs: scores.chairs,
        title: title ?? 'Clinic health',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: d.ice,
        side: BorderSide(color: d.ice.withValues(alpha: .45)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Text(
        'See all parts',
        style: TextStyle(fontSize: 9.8.sp, fontWeight: FontWeight.w700),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        // a soft wash of the score's colour (no plain colour: a box takes
        // a colour or a gradient, never both)
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.withValues(alpha: .10), d.surface],
          stops: const [0, .55],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: HubTwoUp(
        breakAt: 900,
        leftFlex: 5,
        rightFlex: 6,
        left: Row(
          children: [
            HubScoreRing(value: s.value, size: 124, caption: 'of 100'),
            const SizedBox(width: 20),
            Expanded(child: summary),
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pulling,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: detailsButton),
          ],
        ),
      ),
    );
  }
}

class _DragRow extends StatelessWidget {
  const _DragRow({
    required this.part,
    required this.hidden,
    required this.onGo,
  });
  final HubScorePart part;
  final bool hidden;
  final void Function(HubGo go, {String? arg, String? label}) onGo;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final tone = part.share >= .7
        ? d.ice
        : part.share >= .4
        ? d.warn
        : d.alert;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hubIconTile(d, hubScorePartIcon(part.key), tone, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        part.label,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.2.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '-${_points(part.lost)} pts',
                      style: TextStyle(
                        color: tone,
                        fontSize: 9.8.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  part.text(hidden),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d.text3,
                    fontSize: 9.4.sp,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (part.go != null && part.action != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onGo(part.go!, label: part.action),
              style: TextButton.styleFrom(
                foregroundColor: d.ice,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                part.action!,
                style: TextStyle(fontSize: 9.4.sp, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════ branch mini score ══════════════════════════════

/// The small score at the top of a branch card.
class HubBranchHealth extends StatelessWidget {
  const HubBranchHealth({
    super.key,
    required this.score,
    required this.branchName,
    required this.chairs,
  });

  final HubScore score;
  final String branchName;
  final List<HubChairInfo> chairs;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hidden = HubScope.of(context).hidden;
    final top = score.drags.firstOrNull;
    return Material(
      color: d.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showHubScoreDetails(
          context,
          score: score,
          chairs: chairs,
          title: '$branchName health',
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              HubScoreRing(value: score.value, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health · ${score.label}',
                      style: TextStyle(
                        color: hubScoreTone(d, score.value),
                        fontSize: 10.2.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      top == null
                          ? (score.ready
                                ? 'Nothing pulling it down'
                                : 'Needs more records')
                          : 'Biggest drag: ${top.label.toLowerCase()} · '
                                '${top.text(hidden)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: d.text3,
                        fontSize: 9.2.sp,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: d.text3),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ every part, in a dialog ════════════════════════

/// All parts of a score with points, what was seen, how it is worked out,
/// the button to fix it, and the chairs setting.
Future<void> showHubScoreDetails(
  BuildContext context, {
  required HubScore score,
  required List<HubChairInfo> chairs,
  required String title,
}) {
  // A dialog is a new route, outside the Hub's HubScope — carry it over.
  final hub = HubScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => HubScope(
      hidden: hub.hidden,
      onReload: hub.onReload,
      onGo: (go, {arg, label}) {
        Navigator.of(dialogCtx).pop();
        hub.onGo(go, arg: arg, label: label);
      },
      child: _ScoreDialog(score: score, chairs: chairs, title: title),
    ),
  );
}

class _ScoreDialog extends StatelessWidget {
  const _ScoreDialog({
    required this.score,
    required this.chairs,
    required this.title,
  });

  final HubScore score;
  final List<HubChairInfo> chairs;
  final String title;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hub = HubScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final counted = score.parts.where((p) => p.counted).toList()
      ..sort((a, b) => b.lost.compareTo(a.lost));
    final left = score.parts.where((p) => !p.counted).toList();

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width * .72).clamp(560.0, 920.0),
          maxHeight: size.height * .88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  HubScoreRing(value: score.value, size: 74),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          score.ready
                              ? '${score.label} · last 30 full days · '
                                    'parts not measured yet are left out and '
                                    'the rest scaled to 100'
                              : 'Not enough records for a score yet',
                          style: TextStyle(
                            color: d.text3,
                            fontSize: 9.6.sp,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: d.text2),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: d.line),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                children: [
                  for (final p in counted)
                    _PartTile(part: p, hidden: hub.hidden),
                  if (left.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'NOT IN THE SCORE',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .9,
                      ),
                    ),
                    for (final p in left)
                      _PartTile(part: p, hidden: hub.hidden),
                  ],
                  if (chairs.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ChairsBox(chairs: chairs),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.part, required this.hidden});
  final HubScorePart part;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final hub = HubScope.of(context);
    final on = part.counted;
    final tone = !on
        ? d.text4
        : part.share >= .85
        ? d.ok
        : part.share >= .6
        ? d.ice
        : part.share >= .35
        ? d.warn
        : d.alert;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: d.surface2.withValues(alpha: on ? 1 : .5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                hubIconTile(d, hubScorePartIcon(part.key), tone, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              part.label,
                              style: TextStyle(
                                color: on ? d.text1 : d.text3,
                                fontSize: 10.6.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            on
                                ? '${_points(part.earned!)} / ${part.weight}'
                                : (part.missing == null
                                      ? 'Not for this view'
                                      : 'Not yet'),
                            style: TextStyle(
                              color: on ? tone : d.text4,
                              fontSize: 10.2.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (on)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: part.share,
                            minHeight: 7,
                            backgroundColor: d.line,
                            valueColor: AlwaysStoppedAnimation(tone),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        on
                            ? part.text(hidden)
                            : (part.missing ?? part.text(hidden)),
                        style: TextStyle(
                          color: d.text2,
                          fontSize: 9.8.sp,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (on && part.go != null && part.action != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => hub.onGo(part.go!, label: part.action),
                    style: TextButton.styleFrom(foregroundColor: d.ice),
                    child: Text(
                      part.action!,
                      style: TextStyle(
                        fontSize: 9.4.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          HubHow(part.how, hasAmounts: false),
        ],
      ),
    );
  }
}

/// How many chairs each branch has — worked out, or typed in.
class _ChairsBox extends ConsumerStatefulWidget {
  const _ChairsBox({required this.chairs});
  final List<HubChairInfo> chairs;

  @override
  ConsumerState<_ChairsBox> createState() => _ChairsBoxState();
}

class _ChairsBoxState extends ConsumerState<_ChairsBox> {
  String? _saving;

  Future<void> _edit(HubChairInfo c) async {
    final d = context.dent;
    final field = TextEditingController(text: '${c.used}');
    final picked = await showDialog<int?>(
      context: context,
      builder: (dialogCtx) {
        void submit() {
          final v = int.tryParse(field.text.trim());
          if (v != null && v >= 1 && v <= 50) Navigator.of(dialogCtx).pop(v);
        }

        return AlertDialog(
          backgroundColor: d.surface,
          title: Text(
            'Chairs at ${c.name}',
            style: TextStyle(color: d.text1, fontSize: 13.sp),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your bookings suggest ${c.auto}. Type the real number of '
                'chairs patients can be seen in at the same time.',
                style: TextStyle(color: d.text2, fontSize: 10.sp, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: field,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: TextStyle(color: d.text1, fontSize: 12.sp),
                decoration: const InputDecoration(
                  labelText: 'Chairs (1–50)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            if (c.chosen != null)
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(0),
                child: Text(
                  'Use worked out (${c.auto})',
                  style: TextStyle(fontSize: 10.sp),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel', style: TextStyle(fontSize: 10.sp)),
            ),
            FilledButton(
              onPressed: submit,
              child: Text('Save', style: TextStyle(fontSize: 10.sp)),
            ),
          ],
        );
      },
    );
    field.dispose();
    if (picked == null || !mounted) return;
    // captured now: this dialog closes once the number is saved
    final reload = HubScope.of(context).onReload;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // read before the await — the dialog may close while it saves
    final db = ref.read(appDatabaseProvider);
    final session = ref.read(authControllerProvider);
    setState(() => _saving = c.uuid);
    try {
      await db.setSetting(hubChairsKey(c.uuid), picked == 0 ? '' : '$picked');
      // A line in the synced activity record, so the owner phone shows the
      // same chair count as this computer. 0 = "worked out from bookings"
      // again. logActivity never throws.
      await logActivity(
        db,
        'hub_chairs',
        session: session,
        detail: '${c.uuid}|$picked',
      );
    } catch (e) {
      if (mounted) setState(() => _saving = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save the chairs: $e')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          picked == 0
              ? '${c.name}: chairs are worked out from bookings again.'
              : '${c.name}: $picked chair${picked == 1 ? '' : 's'} saved. '
                    'The score is being updated.',
        ),
      ),
    );
    if (nav.canPop()) nav.pop(); // the score dialog — reopen to see it
    reload?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: d.ice.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.ice.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_seat_outlined, color: d.ice, size: 20),
              const SizedBox(width: 8),
              Text(
                'Chairs',
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.6.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Used for chair use here and for "Add a dentist" in What if. '
            'The owner phone uses the same number.',
            style: TextStyle(color: d.text3, fontSize: 9.4.sp, height: 1.4),
          ),
          const SizedBox(height: 6),
          for (final c in widget.chairs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: TextStyle(color: d.text1, fontSize: 10.sp),
                    ),
                  ),
                  Text(
                    '${c.used} · ${c.chosen == null ? 'worked out' : 'set by you'}',
                    style: TextStyle(
                      color: d.text2,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _saving == c.uuid
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: d.ice,
                          ),
                        )
                      : TextButton(
                          onPressed: () => _edit(c),
                          child: Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 9.6.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
