import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';

import '../../data/hub_security.dart';
import '../hub_entry.dart';
import 'hub_ui.dart';

/// Settings → Detailed Reporting Hub (owner only): let admins in or not,
/// the owner's PIN status, and the latest Hub activity.
class HubSettingsPanel extends ConsumerStatefulWidget {
  const HubSettingsPanel({super.key});

  @override
  ConsumerState<HubSettingsPanel> createState() => _HubSettingsPanelState();
}

class _HubSettingsPanelState extends ConsumerState<HubSettingsPanel> {
  bool _saving = false;

  Future<void> _setAdmins(bool allowed) async {
    final ok = await showHubConfirm(
      context,
      icon: allowed ? Icons.admin_panel_settings_outlined : Icons.block_rounded,
      tone: allowed ? context.dent.warn : context.dent.ice,
      title: allowed
          ? 'Let admins open the Hub?'
          : 'Stop admins opening the Hub?',
      message: allowed
          ? 'Every admin will see all money figures, each dentist’s earnings '
                'and every branch. Each admin sets their own Hub PIN.'
          : 'Admins inside the Hub right now are sent back to the Dashboard.',
      confirm: allowed ? 'Allow admins' : 'Stop access',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final clinicId = await db.currentClinicId() ?? '';
      final now = DateTime.now();
      final existing =
          await (db.select(db.rolePermissions)..where(
                (t) =>
                    t.role.equals(AppRole.admin.name) &
                    t.key.equals(Perm.viewReportingHub),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.rolePermissions)
            .insert(
              RolePermissionsCompanion.insert(
                clinicId: clinicId,
                role: AppRole.admin.name,
                key: Perm.viewReportingHub,
                allowed: Value(allowed),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (db.update(db.rolePermissions)..where(
              (t) =>
                  t.role.equals(AppRole.admin.name) &
                  t.key.equals(Perm.viewReportingHub),
            ))
            .write(
              RolePermissionsCompanion(
                allowed: Value(allowed),
                updatedAt: Value(now), // → pushed on the next sync
              ),
            );
      }
      await ref
          .read(hubSecurityProvider)
          .log(
            ref.read(authControllerProvider),
            allowed ? 'hub_admins_on' : 'hub_admins_off',
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final onPlan = ref.watch(entitlementsProvider).reportingHub;
    final perms = ref.watch(permissionsProvider).value ?? const {};
    final adminsAllowed =
        perms['${AppRole.admin.name}|${Perm.viewReportingHub}'] ?? false;
    final pinSetAt = ref.watch(myHubPinSetAtProvider).value;
    final events = ref.watch(hubEventsProvider).value ?? const [];

    Widget row({
      required IconData icon,
      required String title,
      required String sub,
      required Widget trailing,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: d.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    color: d.text3,
                    fontSize: 9.sp,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );

    return DentPanel(
      title: 'Detailed Reporting Hub',
      subtitle: onPlan
          ? 'Full-screen owner view · protected by a PIN'
          : 'Standard & Premium plans',
      trailing: OutlinedButton.icon(
        onPressed: () => openReportingHub(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: onPlan ? d.ice : d.text3,
          side: BorderSide(color: d.line),
        ),
        icon: Icon(
          onPlan ? Icons.insights_rounded : Icons.lock_outline_rounded,
          size: 16,
        ),
        label: const Text('Open Hub'),
      ),
      child: Column(
        children: [
          row(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Admins can open the Hub',
            sub: adminsAllowed
                ? 'On — admins see every money figure, using their own Hub PIN.'
                : 'Off — only you can open it. Other roles never can.',
            trailing: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: adminsAllowed,
                    activeColor: d.ice,
                    onChanged: onPlan ? _setAdmins : null,
                  ),
          ),
          row(
            icon: Icons.pin_outlined,
            title: 'Your Hub PIN',
            sub: pinSetAt == null
                ? 'Not set yet — you create it the first time you open the Hub.'
                : 'Set on ${hubDate(pinSetAt)}. Change it from the Hub’s menu. '
                      'Forgot it? Inover Studio can send a one-time reset code.',
            trailing: Icon(
              pinSetAt == null
                  ? Icons.radio_button_unchecked_rounded
                  : Icons.check_circle_rounded,
              color: pinSetAt == null ? d.text4 : d.ok,
              size: 22,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                Text(
                  'RECENT HUB ACTIVITY',
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nothing yet.',
                  style: TextStyle(color: d.text3, fontSize: 9.4.sp),
                ),
              ),
            )
          else
            for (final e in events.take(5))
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Row(
                  children: [
                    Icon(
                      e.kind == 'hub_pin_wrong' || e.kind == 'hub_pin_locked'
                          ? Icons.warning_amber_rounded
                          : Icons.history_rounded,
                      size: 16,
                      color:
                          e.kind == 'hub_pin_wrong' ||
                              e.kind == 'hub_pin_locked'
                          ? d.alert
                          : d.text4,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${hubEventLabel(e.kind)}'
                        '${e.userName.isEmpty ? '' : ' · ${e.userName}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: d.text2, fontSize: 9.4.sp),
                      ),
                    ),
                    Text(
                      '${hubShortDate(e.happenedAt)} · ${hubClock(e.happenedAt)}',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
