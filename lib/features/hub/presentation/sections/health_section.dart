import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_data.dart';
import '../../data/hub_security.dart';
import '../widgets/hub_ui.dart';

/// System health — is every computer syncing, is WhatsApp sending, when
/// does the licence end, and who opened the Hub.
class HealthSection extends StatelessWidget {
  const HealthSection({super.key, required this.data});
  final HubData data;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final h = data.health;
    final left = h.licenceDaysLeft;
    final now = DateTime.now();
    final stale = h.devices
        .where(
          (x) =>
              !x.isThis &&
              (x.lastSeen == null || now.difference(x.lastSeen!).inDays >= 3),
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionTitle(
          title: 'System health',
          subtitle:
              'Computers, sync, WhatsApp and licence · checked at '
              '${hubClock(data.loadedAt)}',
        ),
        HubGrid(
          minWidth: 220,
          maxColumns: 4,
          children: [
            HubKpi(
              label: 'Things to fix',
              value: h.issues == 0 ? 'None' : '${h.issues}',
              valueColor: h.issues == 0 ? d.ok : d.alert,
              sub: h.issues == 0
                  ? 'Everything is working'
                  : 'Listed on this page in red',
            ),
            HubKpi(
              label: 'Last sync on this computer',
              value: h.cloud ? hubAgo(h.lastSyncHere) : 'Offline plan',
              sub: h.cloud
                  ? (h.lastSyncHere == null
                        ? 'Never synced'
                        : '${hubDate(h.lastSyncHere!)} · ${hubClock(h.lastSyncHere!)}')
                  : 'This install has no cloud copy',
            ),
            HubKpi(
              label: 'Computers',
              value: '${h.devices.length}',
              valueColor: stale > 0 ? d.alert : null,
              sub: stale == 0
                  ? 'All syncing'
                  : '$stale not syncing for 3+ days',
            ),
            HubKpi(
              label: 'Licence',
              value: left == null
                  ? '—'
                  : left <= 0
                  ? 'Ends today'
                  : '$left days left',
              valueColor: left != null && left <= 14 ? d.alert : null,
              sub:
                  '${h.plan} plan'
                  '${h.expiresAt == null ? '' : ' · until ${hubDate(h.expiresAt!)}'}',
            ),
          ],
        ),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _Computers(h: h),
          right: _WhatsApp(h: h),
        ),
        const SizedBox(height: 18),
        HubTwoUp(
          left: _Plan(h: h),
          right: const _HubActivity(),
        ),
      ],
    );
  }
}

Widget _statusDot(Color c) => Container(
  width: 10,
  height: 10,
  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
);

class _Computers extends StatelessWidget {
  const _Computers({required this.h});
  final HubHealth h;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final now = DateTime.now();
    return HubCard(
      icon: Icons.computer_rounded,
      tone: d.ice,
      title: 'Computers',
      subtitle: 'When each one last sent its work to the cloud',
      trailing: const HubGoLink('Settings', HubGo.settings),
      child: Column(
        children: [
          if (h.devices.isEmpty)
            const HubEmpty(
              'No computers registered yet.',
              icon: Icons.computer,
            ),
          for (final x in h.devices)
            () {
              final days = x.lastSeen == null
                  ? null
                  : now.difference(x.lastSeen!).inDays;
              final tone = x.isThis
                  ? d.ok
                  : days == null || days >= 3
                  ? d.alert
                  : days >= 1
                  ? d.warn
                  : d.ok;
              return Container(
                padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: d.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        x.letter,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          color: d.text1,
                          fontSize: 11.5.sp,
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
                            x.name.isEmpty ? 'Computer ${x.letter}' : x.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: d.text1,
                              fontSize: 10.2.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              if (x.platform.isNotEmpty) x.platform,
                              if (x.isThis) 'this computer',
                            ].join(' · '),
                            style: TextStyle(color: d.text3, fontSize: 9.sp),
                          ),
                        ],
                      ),
                    ),
                    _statusDot(tone),
                    const SizedBox(width: 8),
                    Text(
                      x.isThis
                          ? 'In use now'
                          : x.lastSeen == null
                          ? 'Never synced'
                          : 'Synced ${hubAgo(x.lastSeen)}',
                      style: TextStyle(
                        color: tone == d.ok ? d.text2 : tone,
                        fontSize: 9.6.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }(),
          if (h.skipped > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  Icon(Icons.sync_problem_rounded, size: 18, color: d.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${h.skipped} record${h.skipped == 1 ? '' : 's'} could not '
                      'sync last time and are only on this computer.',
                      style: TextStyle(color: d.text2, fontSize: 9.6.sp),
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

class _WhatsApp extends StatelessWidget {
  const _WhatsApp({required this.h});
  final HubHealth h;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return HubCard(
      icon: Icons.chat_outlined,
      tone: d.teal,
      title: 'WhatsApp',
      subtitle: h.waChecked
          ? 'Connection and message queue · last 7 days'
          : (h.cloud
                ? "Connection only — couldn't reach the message queue"
                : 'Needs the cloud plan'),
      trailing: const HubGoLink('WhatsApp', HubGo.whatsapp),
      child: h.wa.isEmpty
          ? const HubEmpty('No branches yet.', icon: Icons.chat_outlined)
          : Column(
              children: [
                for (final w in h.wa)
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: d.line)),
                    ),
                    child: Row(
                      children: [
                        _statusDot(
                          !w.on ? d.text4 : (w.connected ? d.ok : d.alert),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.branch,
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.2.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                !w.on
                                    ? 'Turned off — app reminders only'
                                    : (w.connected
                                          ? 'Connected'
                                          : 'Disconnected — nothing is going out'),
                                style: TextStyle(
                                  color: w.on && !w.connected
                                      ? d.alert
                                      : d.text3,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (w.failed != null && w.failed! > 0)
                          HubPill('${w.failed} failed', d.alert),
                        if (w.waiting != null && w.waiting! > 0) ...[
                          const SizedBox(width: 6),
                          HubPill('${w.waiting} waiting', d.warn),
                        ],
                        if (w.on &&
                            w.connected &&
                            (w.failed ?? 0) == 0 &&
                            (w.waiting ?? 0) == 0 &&
                            w.failed != null)
                          HubPill('All sent', d.ok),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.h});
  final HubHealth h;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    Widget usage(String label, int used, int max) {
      final f = max <= 0 ? 0.0 : used / max;
      final tone = f >= 1 ? d.alert : (f >= .8 ? d.warn : d.teal);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$used of $max',
                  style: TextStyle(
                    color: tone == d.teal ? d.text2 : tone,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: f.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: d.line,
                valueColor: AlwaysStoppedAnimation(tone),
              ),
            ),
          ],
        ),
      );
    }

    final left = h.licenceDaysLeft;
    return HubCard(
      icon: Icons.verified_outlined,
      tone: left != null && left <= 14 ? d.alert : d.ok,
      title: 'Plan & licence',
      subtitle: h.expiresAt == null
          ? '${h.plan} plan'
          : '${h.plan} plan · renews ${hubDate(h.expiresAt!)}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(
          children: [
            usage('Staff logins', h.users, h.maxUsers),
            usage('Branches', h.branches, h.maxBranches),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.cloud_done_outlined, size: 18, color: d.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h.cloud
                        ? 'Cloud backup: every sync keeps a copy of your records '
                              'in the cloud. X-ray and photo files stay on the '
                              'computer that took them.'
                        : 'Offline plan: no cloud copy. Keep a backup of this '
                              'computer.',
                    style: TextStyle(
                      color: d.text3,
                      fontSize: 9.4.sp,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HubActivity extends ConsumerWidget {
  const _HubActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final events = ref.watch(hubEventsProvider).value ?? const [];
    return HubCard(
      icon: Icons.history_rounded,
      tone: d.warn,
      title: 'Hub activity',
      subtitle: 'Who opened this screen, wrong PINs and PIN changes',
      child: events.isEmpty
          ? const HubEmpty('Nothing recorded yet.', icon: Icons.history_rounded)
          : Column(
              children: [
                for (final e in events)
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: d.line)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          e.kind == 'hub_pin_wrong' ||
                                  e.kind == 'hub_pin_locked'
                              ? Icons.warning_amber_rounded
                              : Icons.circle,
                          size:
                              e.kind == 'hub_pin_wrong' ||
                                  e.kind == 'hub_pin_locked'
                              ? 18
                              : 8,
                          color:
                              e.kind == 'hub_pin_wrong' ||
                                  e.kind == 'hub_pin_locked'
                              ? d.alert
                              : d.text4,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hubEventLabel(e.kind),
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 9.8.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  if (e.userName.isNotEmpty) e.userName,
                                  if (e.device.isNotEmpty)
                                    'Computer ${e.device}',
                                ].join(' · '),
                                style: TextStyle(
                                  color: d.text3,
                                  fontSize: 9.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${hubShortDate(e.happenedAt)} · ${hubClock(e.happenedAt)}',
                          style: TextStyle(color: d.text3, fontSize: 9.sp),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
