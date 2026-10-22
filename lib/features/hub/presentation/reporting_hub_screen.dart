import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/core/router/app_routes.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';
import 'package:is_dental/core/utils/app_activity.dart';

import '../data/hub_data.dart';
import '../data/hub_pdf.dart';
import '../data/hub_security.dart';
import 'hub_entry.dart';
import 'sections/branches_section.dart';
import 'sections/dentists_section.dart';
import 'sections/health_section.dart';
import 'sections/money_section.dart';
import 'sections/right_now_section.dart';
import 'sections/watch_list_section.dart';
import 'sections/whats_coming_section.dart';
import 'widgets/hub_loading.dart';
import 'widgets/hub_pin_gate.dart';
import 'widgets/hub_ui.dart';

enum HubSection {
  rightNow('Right now', Icons.dashboard_outlined),
  whatsComing("What's coming", Icons.auto_graph_rounded),
  money('Money', Icons.payments_outlined),
  dentists('Dentists', Icons.groups_outlined),
  watchList('Watch list', Icons.policy_outlined),
  branches('Branches', Icons.store_mall_directory_outlined),
  health('System health', Icons.monitor_heart_outlined);

  const HubSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _Phase { starting, gate, loading, ready, failed }

/// The Detailed Reporting Hub — a full-screen mode for the owner (and
/// admins the owner allows). Replaces the sidebar and every clinic screen
/// until Exit.
///
/// Safety: Hub PIN on every visit, 5 wrong → 5 min lockout, numbers blur
/// after 5 quiet minutes, the Hub closes itself after 15, and every visit
/// is recorded.
class ReportingHubScreen extends ConsumerStatefulWidget {
  const ReportingHubScreen({super.key});

  @override
  ConsumerState<ReportingHubScreen> createState() => _ReportingHubScreenState();
}

class _ReportingHubScreenState extends ConsumerState<ReportingHubScreen> {
  static const _lockAfter = Duration(minutes: 5);
  static const _exitAfter = Duration(minutes: 15);
  static const _refreshEvery = Duration(seconds: 60);

  _Phase _phase = _Phase.starting;
  String? _fatal;

  HubSecurity? _sec;
  AuthSession? _session;
  User? _user;
  HubGateMode _gateMode = HubGateMode.unlock;

  HubSection _section = HubSection.rightNow;
  HubPeriod _period = HubPeriod.of(HubPreset.thisMonth);
  String? _scope;
  bool _scopeFixed = false;

  HubData? _data;
  int _step = 0, _gen = 0, _lockCount = 0;
  Object? _loadError;

  bool _hidden = false,
      _locked = false,
      _changingPin = false,
      _refreshing = false,
      _opened = false,
      _left = false;

  DateTime _lastActivity = DateTime.now();
  DateTime? _openedAt;
  Timer? _idleTimer, _autoTimer;

  /// Puts the app's own theme back when the Hub closes (it opens dark).
  VoidCallback? _restoreTheme;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _idleTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkIdle(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idleTimer?.cancel();
    _autoTimer?.cancel();
    _scroll.dispose();
    // Not during unmount itself — providers can't change mid-build.
    final restore = _restoreTheme;
    if (restore != null) Future.microtask(restore);
    // Closed by the app (sign-out, access removed) rather than Exit.
    if (_opened && !_left) {
      _sec?.log(
        _session,
        'hub_exit',
        detail: '${_minutesOpen()} min · closed by the app',
      );
    }
    super.dispose();
  }

  // ───────────────────────────── lifecycle ─────────────────────────────

  Future<void> _start() async {
    final s = ref.read(authControllerProvider);
    if (s == null) return; // the router is already sending us to login
    // Remember the app's theme, and make sure the Hub is dark even when it
    // was opened some other way than the top bar button.
    final themes = ref.read(themeModeProvider.notifier);
    final ThemeMode before =
        ref.read(hubThemeBeforeProvider) ??
        ref.read(themeModeProvider) ??
        ThemeMode.light;
    ref.read(hubThemeBeforeProvider.notifier).set(null);
    _restoreTheme = () => themes.set(before);
    if (ref.read(themeModeProvider) != ThemeMode.dark) {
      themes.set(ThemeMode.dark);
    }
    final sec = ref.read(hubSecurityProvider);
    _sec = sec;
    _session = s;
    _scope = s.branchId; // an admin tied to a branch sees only that branch
    _scopeFixed = s.branchId != null;
    final u = await sec.userFor(s);
    if (!mounted) return;
    if (u == null) {
      setState(() {
        _phase = _Phase.failed;
        _fatal =
            'Your login was not found on this computer. Sync from Settings, '
            'then open the Hub again.';
      });
      return;
    }
    setState(() {
      _user = u;
      _gateMode = sec.hasPin(u) ? HubGateMode.unlock : HubGateMode.setup;
      _phase = _Phase.gate;
    });
  }

  Future<void> _reloadUser() async {
    final s = _session;
    if (s == null) return;
    final u = await _sec!.userFor(s);
    if (u != null && mounted) setState(() => _user = u);
  }

  /// The PIN gate said yes — first entry, after an idle lock, or after a
  /// PIN change.
  Future<void> _unlocked() async {
    await _reloadUser();
    if (!mounted) return;
    _lastActivity = DateTime.now();
    if (!_opened) {
      _opened = true;
      _openedAt = DateTime.now();
      _sec?.log(_session, 'hub_open', detail: _scopeName(null));
    }
    if (_phase == _Phase.ready) {
      setState(() {
        _locked = false;
        _changingPin = false;
      });
      _load(full: false);
      return;
    }
    _autoTimer ??= Timer.periodic(_refreshEvery, (_) {
      if (_phase == _Phase.ready && !_locked && !_changingPin && !_refreshing) {
        _load(full: false, quiet: true);
      }
    });
    _load(full: true);
  }

  Future<void> _load({required bool full, bool quiet = false}) async {
    final gen = ++_gen;
    setState(() {
      if (full) {
        _phase = _Phase.loading;
        _step = 0;
        _loadError = null;
      } else if (!quiet) {
        _refreshing = true;
      }
    });
    final started = DateTime.now();
    try {
      final ent = ref.read(entitlementsProvider);
      final data = await loadHubData(
        db: ref.read(appDatabaseProvider),
        cash: ref.read(cashRepositoryProvider),
        allBranches: await ref.read(branchesStreamProvider.future),
        licence: ref.read(licenseControllerProvider).value?.license,
        ent: ent,
        branchId: _scope,
        period: _period,
        showPayouts: true, // the Hub needs Standard+, which has payouts
        onStep: full
            ? (i) {
                if (mounted && gen == _gen) setState(() => _step = i);
              }
            : null,
      );
      if (full) {
        if (mounted && gen == _gen) {
          setState(() => _step = hubLoadSteps.length);
        }
        // Long enough to read the checklist; never a flash.
        final spent = DateTime.now().difference(started);
        const least = Duration(milliseconds: 1100);
        await Future<void>.delayed(
          spent < least ? least - spent : const Duration(milliseconds: 250),
        );
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = data;
        _phase = _Phase.ready;
        _refreshing = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _refreshing = false;
        if (full || _data == null) {
          _phase = _Phase.loading;
          _loadError = e;
        }
      });
      if (!full && !quiet && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not refresh: $e')));
      }
    }
  }

  // ───────────────────────────── idle / lock ─────────────────────────────

  bool _onKey(KeyEvent _) {
    _touch();
    return false; // never swallow the key
  }

  void _touch() {
    if (_locked || _left) return;
    _lastActivity = DateTime.now();
    // keeps the app's auto sign-out from firing while the Hub is in use
    ref.read(appActivityProvider.notifier).ping();
  }

  void _checkIdle() {
    if (!mounted || _left || _phase == _Phase.starting) return;
    final idle = DateTime.now().difference(_lastActivity);
    if (idle >= _exitAfter) {
      _leave(idle: true);
    } else if (_phase == _Phase.ready && !_locked && idle >= _lockAfter) {
      _lock(auto: true);
    }
  }

  void _lock({bool auto = false}) {
    setState(() {
      _locked = true;
      _changingPin = false;
      _lockCount++;
    });
    _sec?.log(
      _session,
      'hub_idle_lock',
      detail: auto ? 'no activity for 5 minutes' : 'locked by the user',
    );
  }

  int _minutesOpen() =>
      _openedAt == null ? 0 : DateTime.now().difference(_openedAt!).inMinutes;

  // ───────────────────────────── leaving ─────────────────────────────

  void _leave({String? to, String? label, bool idle = false}) {
    if (_left || !mounted) return;
    _left = true;
    if (_opened) {
      _sec?.log(
        _session,
        idle ? 'hub_idle_exit' : 'hub_exit',
        detail:
            '${_minutesOpen()} min'
            '${label == null ? '' : ' · went to $label'}',
      );
    }
    context.go(to ?? AppRoutes.dashboard);
    // same frame as the route change → the clinic screens open in the
    // app's own theme, with no flash
    _restoreTheme?.call();
    _restoreTheme = null;
  }

  Future<void> _confirmExit() async {
    final ok = await showHubConfirm(
      context,
      icon: Icons.logout_rounded,
      tone: context.dent.alert,
      title: 'Leave the Reporting Hub?',
      message:
          'You will go back to the Dashboard. Opening the Hub again asks '
          'for your PIN.',
      confirm: 'Exit Hub',
      cancel: 'Stay',
      danger: true,
    );
    if (ok) _leave();
  }

  Future<void> _go(HubGo go, {String? arg, String? label}) async {
    if (go == HubGo.watchList) {
      setState(() => _section = HubSection.watchList);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    final (route, name) = switch (go) {
      HubGo.appointments => (AppRoutes.appointments, 'Appointments'),
      HubGo.billing => (AppRoutes.billing, 'Billing'),
      HubGo.closeDay => (AppRoutes.billing, 'Day closing'),
      HubGo.expenses => (AppRoutes.expenses, 'Expenses'),
      HubGo.requests => ('${AppRoutes.dashboard}/requests', 'Booking requests'),
      HubGo.whatsapp => (AppRoutes.whatsapp, 'WhatsApp'),
      HubGo.settings => (AppRoutes.settings, 'Settings'),
      HubGo.watchList => (AppRoutes.dashboard, 'Watch list'), // handled above
    };
    final ok = await showHubConfirm(
      context,
      icon: Icons.open_in_new_rounded,
      tone: context.dent.ice,
      title: 'Open $name?',
      message:
          'This leaves the Reporting Hub and opens $name. Coming back asks '
          'for your PIN again.',
      confirm: 'Open $name',
      cancel: 'Stay in Hub',
    );
    if (!ok || !mounted) return;
    if (go == HubGo.closeDay && arg != null) {
      ref.read(dayCloseTargetProvider.notifier).set(arg);
      ref.read(billingTabProvider.notifier).set(1);
    }
    _leave(to: route, label: name);
  }

  // ───────────────────────────── helpers ─────────────────────────────

  String _scopeName(List<Branch>? branches) {
    if (_scope == null) return 'All branches';
    final list = branches ?? ref.read(branchesStreamProvider).value ?? const [];
    return list.where((b) => b.uuid == _scope).map((b) => b.name).firstOrNull ??
        'One branch';
  }

  /// Owner report PDF of everything the Hub shows right now.
  Future<void> _exportPdf() async {
    final data = _data;
    if (data == null) return;
    final clinic = ref.read(clinicProfileProvider).value?.name ?? 'Clinic';
    final scope = _scopeName(null);
    final period = _period.preset == HubPreset.custom
        ? _period.describe
        : '${_period.label} (${_period.describe})';
    _sec?.log(_session, 'hub_export', detail: '$scope · $period');
    await showPdfOutput(
      context,
      build: () => buildHubPdf(
        data,
        clinicName: clinic,
        scopeName: scope,
        periodLabel: period,
        preparedFor: _session?.fullName ?? '',
      ),
      filename: 'dentos-owner-report.pdf',
    );
  }

  void _setScope(String? v) {
    if (v == _scope) return;
    setState(() => _scope = v);
    _load(full: false);
  }

  void _setPeriod(HubPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load(full: false);
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    // Watched so the list stays loaded for the whole visit.
    final branches =
        ref.watch(branchesStreamProvider).value ?? const <Branch>[];
    // Watched here, in build — never inside the LayoutBuilder below.
    final clinic =
        ref.watch(clinicProfileProvider).value?.name ?? 'Your clinic';
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return HubScope(
      hidden: _hidden,
      onGo: _go,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        onPointerHover: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 1280;
              return Column(
                children: [
                  _header(d, branches, compact, clinic: clinic, dark: dark),
                  Divider(height: 1, color: d.line),
                  Expanded(child: _body(d, branches, compact)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body(DentColors d, List<Branch> branches, bool compact) {
    switch (_phase) {
      case _Phase.starting:
        return Center(child: CircularProgressIndicator(color: d.ice));
      case _Phase.failed:
        return HubEmpty(
          _fatal ?? 'Something went wrong.',
          icon: Icons.error_outline,
        );
      case _Phase.gate:
        return HubPinGate(
          key: ValueKey(_gateMode),
          mode: _gateMode,
          user: _user!,
          session: _session!,
          onDone: _unlocked,
          onExit: _confirmExit,
        );
      case _Phase.loading:
        return HubLoading(
          step: _step,
          error: _loadError,
          onRetry: () => _load(full: true),
          onExit: _confirmExit,
        );
      case _Phase.ready:
        final covered = _locked || _changingPin;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rail(d, compact),
            VerticalDivider(width: 1, color: d.line),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: covered,
                      child: ImageFiltered(
                        enabled: covered,
                        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: _content(d, branches),
                      ),
                    ),
                  ),
                  if (covered)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .18),
                        child: _locked
                            ? HubPinGate(
                                key: ValueKey('relock$_lockCount'),
                                mode: HubGateMode.unlock,
                                relock: true,
                                user: _user!,
                                session: _session!,
                                onDone: _unlocked,
                                onExit: _confirmExit,
                              )
                            : HubPinGate(
                                key: const ValueKey('change'),
                                mode: HubGateMode.change,
                                user: _user!,
                                session: _session!,
                                onDone: () async {
                                  await _unlocked();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Your Hub PIN was changed.',
                                      ),
                                    ),
                                  );
                                },
                                onExit: _confirmExit,
                                onCancel: () =>
                                    setState(() => _changingPin = false),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
    }
  }

  // ───────────────────────────── header ─────────────────────────────

  Widget _header(
    DentColors d,
    List<Branch> branches,
    bool compact, {
    required String clinic,
    required bool dark,
  }) {
    final ready = _phase == _Phase.ready && !_locked && !_changingPin;
    final canPickScope = !_scopeFixed && branches.length > 1;

    Widget headerButton({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      Color? color,
    }) {
      final fg = color ?? d.text2;
      return compact
          ? IconButton(
              tooltip: label,
              onPressed: onTap,
              icon: Icon(icon, size: 20, color: fg),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(
                  color: color == null ? d.line : color.withValues(alpha: .45),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: TextStyle(fontSize: 9.8.sp, fontWeight: FontWeight.w700),
              ),
            );
    }

    return Container(
      height: 72,
      color: d.surface,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: d.accentGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: AppPalette.onAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DETAILED REPORTING HUB',
                  style: TextStyle(
                    color: d.ice,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$clinic · ${_scopeName(branches)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: d.text1,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (ready && _data != null) ...[
            if (!compact)
              Text(
                'Updated ${hubClock(_data!.loadedAt)}',
                style: TextStyle(color: d.text3, fontSize: 9.4.sp),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : () => _load(full: false),
              icon: _refreshing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: d.ice,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: d.text2),
            ),
            const SizedBox(width: 6),
            if (canPickScope) ...[
              _scopePicker(d, branches),
              const SizedBox(width: 10),
            ],
            headerButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Owner report',
              onTap: _exportPdf,
            ),
            const SizedBox(width: 6),
            headerButton(
              icon: _hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: _hidden ? 'Show numbers' : 'Hide numbers',
              onTap: () => setState(() => _hidden = !_hidden),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz_rounded, color: d.text2),
              color: d.surface,
              onSelected: (v) {
                if (v == 'pin') setState(() => _changingPin = true);
                if (v == 'lock') _lock();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pin',
                  child: _menuItem(d, Icons.password_rounded, 'Change Hub PIN'),
                ),
                PopupMenuItem(
                  value: 'lock',
                  child: _menuItem(d, Icons.lock_outline_rounded, 'Lock now'),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
          IconButton(
            tooltip: dark ? 'Light mode' : 'Dark mode',
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: d.text2,
            ),
          ),
          const SizedBox(width: 6),
          headerButton(
            icon: Icons.logout_rounded,
            label: 'Exit Hub',
            onTap: _confirmExit,
            color: d.alert,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(DentColors d, IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 18, color: d.text2),
      const SizedBox(width: 10),
      Text(
        text,
        style: TextStyle(color: d.text1, fontSize: 10.sp),
      ),
    ],
  );

  Widget _scopePicker(DentColors d, List<Branch> branches) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: branches.any((b) => b.uuid == _scope) ? _scope : null,
        dropdownColor: d.surface,
        borderRadius: BorderRadius.circular(12),
        icon: Icon(Icons.expand_more_rounded, size: 19, color: d.text3),
        style: TextStyle(color: d.text1, fontSize: 9.8.sp),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(
              'All branches',
              style: TextStyle(color: d.text1, fontSize: 9.8.sp),
            ),
          ),
          for (final b in branches)
            DropdownMenuItem<String?>(
              value: b.uuid,
              child: Text(
                b.name,
                style: TextStyle(color: d.text1, fontSize: 9.8.sp),
              ),
            ),
        ],
        onChanged: _setScope,
      ),
    ),
  );

  // ───────────────────────────── rail ─────────────────────────────

  Widget _rail(DentColors d, bool compact) {
    final data = _data;
    int? badge(HubSection s) => switch (s) {
      HubSection.rightNow => data?.urgent,
      HubSection.health => data?.health.issues,
      HubSection.watchList => data?.watch.flags,
      _ => null,
    };

    return Container(
      width: compact ? 78 : 236,
      color: d.surface,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        18,
        compact ? 10 : 14,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in HubSection.values) ...[
            _railItem(d, s, compact, badge(s)),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          if (!compact)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: d.surface2,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: d.ok),
                      const SizedBox(width: 6),
                      Text(
                        'Protected',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 9.6.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Numbers hide after 5 quiet minutes; the Hub closes '
                    'after 15. Signed in as ${_session?.fullName ?? ''}.',
                    style: TextStyle(
                      color: d.text3,
                      fontSize: 9.sp,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _railItem(DentColors d, HubSection s, bool compact, int? badge) {
    final on = s == _section;
    final fg = on ? d.ice : d.text2;
    final count = badge ?? 0;
    final showBadge = count > 0;
    final badgeTone = s == HubSection.rightNow ? d.alert : d.warn;

    final item = Material(
      color: on ? d.ice.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (on) return;
          setState(() => _section = s);
          if (_scroll.hasClients) _scroll.jumpTo(0);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 12,
            vertical: 12,
          ),
          child: compact
              ? Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(s.icon, size: 22, color: fg),
                    if (showBadge)
                      Positioned(
                        right: 10,
                        top: -4,
                        child: _badge(d, count, badgeTone),
                      ),
                  ],
                )
              : Row(
                  children: [
                    Icon(s.icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          color: on ? d.text1 : d.text2,
                          fontSize: 10.4.sp,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showBadge) _badge(d, count, badgeTone),
                  ],
                ),
        ),
      ),
    );
    return compact ? Tooltip(message: s.label, child: item) : item;
  }

  Widget _badge(DentColors d, int n, Color tone) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: tone,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$n',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 9.sp,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  // ───────────────────────────── content ─────────────────────────────

  Widget _content(DentColors d, List<Branch> branches) {
    final data = _data!;
    final picker = _PeriodPicker(period: _period, onChanged: _setPeriod);

    final page = switch (_section) {
      HubSection.rightNow => RightNowSection(data: data),
      HubSection.whatsComing => WhatsComingSection(data: data),
      HubSection.watchList => WatchListSection(
        data: data,
        period: _period,
        periodPicker: picker,
      ),
      HubSection.money => MoneySection(
        data: data,
        period: _period,
        periodPicker: picker,
      ),
      HubSection.dentists => DentistsSection(
        data: data,
        period: _period,
        periodPicker: picker,
      ),
      HubSection.branches => BranchesSection(
        data: data,
        period: _period,
        periodPicker: picker,
        branchCount: branches.length,
        scopeName: _scope == null ? null : _scopeName(branches),
        onShowAll: _scopeFixed ? null : () => _setScope(null),
      ),
      HubSection.health => HealthSection(data: data),
    };

    return Column(
      children: [
        SizedBox(
          height: 3,
          child: _refreshing
              ? LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(d.ice),
                )
              : null,
        ),
        Expanded(
          // Uses the whole width on any screen; only the side padding grows
          // with the window, so big monitors get more columns, not margins.
          child: LayoutBuilder(
            builder: (context, c) {
              final side = (c.maxWidth * .018).clamp(18.0, 36.0);
              return Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(side, 22, side, 48),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    child: KeyedSubtree(key: ValueKey(_section), child: page),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "This month ▾" — the presets plus a custom date range.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.onChanged});
  final HubPeriod period;
  final ValueChanged<HubPeriod> onChanged;

  Future<void> _custom(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: period.start,
        end: period.end.subtract(const Duration(days: 1)).isAfter(today)
            ? DateTime(today.year, today.month, today.day)
            : period.end.subtract(const Duration(days: 1)),
      ),
      helpText: 'Pick the days to look at',
      saveText: 'Show',
    );
    if (picked == null || !context.mounted) return;
    final days = picked.end.difference(picked.start).inDays + 1;
    if (days > HubPeriod.maxCustomDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick up to 2 years at a time.')),
      );
      return;
    }
    onChanged(HubPeriod.range(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return PopupMenuButton<HubPreset>(
      tooltip: 'Change dates',
      color: d.surface,
      position: PopupMenuPosition.under,
      onSelected: (p) =>
          p == HubPreset.custom ? _custom(context) : onChanged(HubPeriod.of(p)),
      itemBuilder: (_) => [
        for (final p in HubPeriod.presets)
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(
                  p == period.preset
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: p == period.preset ? d.ice : d.text4,
                ),
                const SizedBox(width: 10),
                Text(
                  p.label,
                  style: TextStyle(color: d.text1, fontSize: 10.sp),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: HubPreset.custom,
          child: Row(
            children: [
              Icon(Icons.date_range_rounded, size: 18, color: d.ice),
              const SizedBox(width: 10),
              Text(
                'Custom range…',
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: d.ice),
            const SizedBox(width: 8),
            Text(
              period.label,
              style: TextStyle(
                color: d.text1,
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 18, color: d.text3),
          ],
        ),
      ),
    );
  }
}
