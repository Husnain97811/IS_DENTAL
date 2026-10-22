import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';

import '../../data/hub_data.dart';
import '../widgets/hub_ui.dart';

/// Branches side by side for the period: money, visits, no-shows, what is
/// owed, when the cash was last counted and whether WhatsApp is up.
class BranchesSection extends StatelessWidget {
  const BranchesSection({
    super.key,
    required this.data,
    required this.period,
    required this.periodPicker,
    required this.branchCount,
    required this.scopeName,
    this.onShowAll,
  });

  final HubData data;
  final HubPeriod period;
  final Widget periodPicker;

  /// How many branches the clinic has.
  final int branchCount;

  /// The one branch being looked at, or null for all branches.
  final String? scopeName;

  /// Switch the Hub to "All branches" — null when not allowed (an admin
  /// tied to one branch).
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final list = data.branches;

    Widget notice(String title, String text, {Widget? action}) => HubCard(
      icon: Icons.store_mall_directory_outlined,
      tone: d.ice,
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(color: d.text2, fontSize: 10.2.sp, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'Branches',
          subtitle: '${period.describe} · side by side',
          trailing: list.isEmpty ? null : periodPicker,
        ),
        if (branchCount <= 1)
          notice(
            'One branch',
            'Your clinic has a single branch, so every other page of the Hub '
                'already shows all of it. Branches appear here side by side '
                'once you open a second one.',
          )
        else if (list.isEmpty)
          notice(
            'Showing ${scopeName ?? 'one branch'} only',
            'The comparison needs all branches.',
            action: onShowAll == null
                ? null
                : FilledButton.icon(
                    onPressed: onShowAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                    ),
                    icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                    label: Text(
                      'Compare all branches',
                      style: TextStyle(fontSize: 10.sp),
                    ),
                  ),
          )
        else ...[
          _Compare(list: list),
          const SizedBox(height: 18),
          HubGrid(
            minWidth: 320,
            maxColumns: 3,
            children: [for (final b in list) _BranchCard(b: b)],
          ),
        ],
      ],
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({required this.list});
  final List<HubBranch> list;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final top = list.fold<int>(1, (m, b) => b.collected > m ? b.collected : m);
    final total = list.fold<int>(0, (s, b) => s + b.collected);
    return HubCard(
      icon: Icons.leaderboard_outlined,
      tone: d.teal,
      title: 'Collected by branch',
      subtitle: 'Bar length compares branches with each other',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(
          children: [
            for (final b in [
              ...list,
            ]..sort((x, y) => y.collected.compareTo(x.collected)))
              HubShareRow(
                label: b.name,
                amount: b.collected,
                fraction: b.collected / top,
                color: d.teal,
                note: total == 0
                    ? null
                    : '${(b.collected / total * 100).round()}% of clinic',
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.b});
  final HubBranch b;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final today = dayKey(DateTime.now());
    final closedAgo = b.lastClosed == null
        ? null
        : DateTime.now().difference(parseDayKey(b.lastClosed!)).inDays;
    final (closeText, closeTone) = b.lastClosed == null
        ? ('Cash never closed', d.alert)
        : b.lastClosed == today
        ? ('Closed today', d.ok)
        : closedAgo == 1
        ? ('Last closed yesterday', d.ok)
        : (
            'Last closed $closedAgo days ago',
            closedAgo! > 3 ? d.alert : d.warn,
          );
    final due = b.completed + b.noShows;
    final noShowPct = due == 0 ? 0 : (b.noShows / due * 100).round();

    Widget line(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: d.text3, fontSize: 9.8.sp),
            ),
          ),
          value,
        ],
      ),
    );
    final valueStyle = TextStyle(
      color: d.text1,
      fontSize: 10.2.sp,
      fontWeight: FontWeight.w700,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              hubIconTile(
                d,
                Icons.store_mall_directory_rounded,
                d.ice,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  b.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: d.text1,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              HubPill(
                !b.waOn
                    ? 'WhatsApp off'
                    : (b.waConnected ? 'WhatsApp on' : 'WhatsApp down'),
                !b.waOn ? d.text3 : (b.waConnected ? d.ok : d.alert),
                icon: Icons.chat_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'COLLECTED',
            style: TextStyle(
              color: d.text4,
              fontSize: 9.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          HubAmount(
            b.collected,
            style: TextStyle(
              fontFamily: AppFonts.display,
              color: d.text1,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: d.line),
          const SizedBox(height: 4),
          line('Expenses', HubAmount(b.expenses, style: valueStyle)),
          line(
            'Net profit',
            HubAmount(
              b.net,
              style: valueStyle.copyWith(color: b.net < 0 ? d.alert : d.ok),
            ),
          ),
          line('Visits booked', Text('${b.appts}', style: valueStyle)),
          line('Visits finished', Text('${b.completed}', style: valueStyle)),
          line(
            'No-shows',
            Text(
              '${b.noShows} · $noShowPct%',
              style: valueStyle.copyWith(
                color: noShowPct >= 15 ? d.alert : null,
              ),
            ),
          ),
          line(
            'Still owed',
            HubAmount(
              b.owed,
              style: valueStyle.copyWith(color: b.owed > 0 ? d.warn : null),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: HubPill(
              closeText,
              closeTone,
              icon: Icons.point_of_sale_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
