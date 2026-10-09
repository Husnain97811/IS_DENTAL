import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sizer/sizer.dart';
import '../../constants/views.dart';
import '../../router/nav_destinations.dart';
import '../../router/app_routes.dart';

String _money(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

// ── Topbar sizing ───────────────────────────────────────────────────────────
// Everything inside the bar is a FIXED pixel size. The bar itself is a fixed
// height on every monitor, so anything scaled with Sizer's .sp grows on a big
// display while the bar does not — which is exactly what overflowed before.
const double _kBarHeight = 68;
const double _kBtn = 44;
const double _kIcon = 21;
const double _kRadius = 12;

class _Notif {
  const _Notif(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;
}

/// One row in the search dropdown. Either [initials] (patient avatar) or [icon].
class _Result {
  const _Result({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.initials,
    this.icon,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? initials;
  final IconData? icon;
}

class AppTopbar extends ConsumerStatefulWidget {
  const AppTopbar({
    super.key,
    required this.destination,
    required this.onToggleSidebar,
  });
  final NavDestination destination;
  final VoidCallback onToggleSidebar;

  @override
  ConsumerState<AppTopbar> createState() => _AppTopbarState();
}

class _AppTopbarState extends ConsumerState<AppTopbar> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchLink = LayerLink();
  final _portal = OverlayPortalController();
  String _query = '';

  /// Actual rendered width of the search box, so the dropdown matches it.
  double _searchWidth = 420;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    setState(() => _query = v);

    // Expenses filters its own table in place — no dropdown.
    if (widget.destination.route == AppRoutes.expenses) {
      ref.read(expenseSearchProvider.notifier).state = v;
      if (_portal.isShowing) _portal.hide();
      return;
    }

    if (v.trim().isEmpty) {
      if (_portal.isShowing) _portal.hide();
    } else {
      if (!_portal.isShowing) _portal.show();
    }
  }

  @override
  void didUpdateWidget(covariant AppTopbar old) {
    super.didUpdateWidget(old);
    // Leaving a screen clears its search, so a stale query can't keep
    // filtering a table the user is no longer looking at.
    if (old.destination.route != widget.destination.route) {
      if (old.destination.route == AppRoutes.expenses) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(expenseSearchProvider.notifier).state = '',
        );
      }
      _searchCtrl.clear();
      _query = '';
      if (_portal.isShowing) _portal.hide();
    }
  }

  void _closeSearch() {
    if (_portal.isShowing) _portal.hide();
    _searchFocus.unfocus();
  }

  void _resetSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
    _closeSearch();
  }

  void _goReset(String route) {
    _resetSearch();
    if (widget.destination.route != route) context.go(route);
  }

  String _hintFor(String route, String monthName) => switch (route) {
    AppRoutes.appointments => 'Search appointments ($monthName)…',
    AppRoutes.treatments => 'Search treatments…',
    AppRoutes.billing => 'Search invoices…',
    AppRoutes.inventory => 'Search inventory…',
    AppRoutes.prescriptions => 'Search medicines…',
    AppRoutes.expenses => 'Search expenses…',
    _ => 'Search patients…',
  };

  List<_Result> _matchesFor(
    String route,
    String q,
    List<Patient> patients,
    List<Invoice> invoices,
    List<InventoryItem> inventory,
    List<Treatment> treatments,
    List<Appointment> appts,
    List<Medicine> medicines,
  ) {
    if (q.isEmpty) return const [];
    String two(int v) => v.toString().padLeft(2, '0');
    switch (route) {
      case AppRoutes.appointments:
        return [
          for (final a in appts)
            if ('${a.patientName} ${a.procedure} ${a.dentist}'
                .toLowerCase()
                .contains(q))
              _Result(
                icon: Icons.event_rounded,
                title: a.patientName,
                subtitle:
                    '${a.procedure} · ${a.startsAt.day}/${a.startsAt.month} · ${two(a.startsAt.hour)}:${two(a.startsAt.minute)}',
                onTap: () {
                  ref.read(selectedDateProvider.notifier).state = DateTime(
                    a.startsAt.year,
                    a.startsAt.month,
                    a.startsAt.day,
                  );
                  ref.read(viewedMonthProvider.notifier).state = (
                    year: a.startsAt.year,
                    month: a.startsAt.month,
                  );
                  _goReset(AppRoutes.appointments);
                },
              ),
        ].take(8).toList();
      case AppRoutes.treatments:
        return [
          for (final t in treatments)
            if ('${t.name} ${t.category}'.toLowerCase().contains(q))
              _Result(
                icon: Icons.medical_services_rounded,
                title: t.name,
                subtitle: '${t.category} · Rs ${_money(t.price)}',
                onTap: () {
                  _resetSearch();
                  showTreatmentEditor(context, existing: t);
                },
              ),
        ].take(8).toList();
      case AppRoutes.prescriptions:
        return [
          for (final m in medicines)
            if ('${m.name} ${m.category} ${m.form}'.toLowerCase().contains(q))
              _Result(
                icon: Icons.medication_rounded,
                title: m.name,
                subtitle: [
                  m.form,
                  m.defaultDosage,
                  m.defaultFrequency,
                  m.category,
                ].where((e) => e.isNotEmpty).join(' · '),
                onTap: () {
                  _resetSearch();
                  showMedicineEditor(context, existing: m);
                },
              ),
        ].take(8).toList();
      case AppRoutes.billing:
        return [
          for (final i in invoices)
            if ('${i.invoiceNo} ${i.patientName} ${i.summary}'
                .toLowerCase()
                .contains(q))
              _Result(
                icon: Icons.receipt_long_rounded,
                title: '#${i.invoiceNo} · ${i.patientName}',
                subtitle: '${i.summary} · Rs ${_money(i.total)}',
                onTap: () {
                  ref.read(selectedInvoiceIdProvider.notifier).state = i.id;
                  _goReset(AppRoutes.billing);
                },
              ),
        ].take(8).toList();
      case AppRoutes.inventory:
        return [
          for (final it in inventory)
            if ('${it.name} ${it.category}'.toLowerCase().contains(q))
              _Result(
                icon: Icons.inventory_2_rounded,
                title: it.name,
                subtitle: '${it.category} · ${it.inStock} ${it.unit}',
                onTap: () => _goReset(AppRoutes.inventory),
              ),
        ].take(8).toList();
      default:
        return [
          for (final p in patients)
            if ('${p.fullName} ${p.phone} ${p.code}'.toLowerCase().contains(q))
              _Result(
                initials: p.initials,
                title: p.fullName,
                subtitle: '#${p.code} · ${p.phone}',
                onTap: () {
                  ref.read(selectedPatientIdProvider.notifier).state = p.id;
                  _goReset(AppRoutes.patients);
                },
              ),
        ].take(8).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final patients =
        ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final invoices =
        ref.watch(invoicesStreamProvider).value ?? const <Invoice>[];
    final inventory =
        ref.watch(inventoryStreamProvider).value ?? const <InventoryItem>[];
    final treatments =
        ref.watch(treatmentsStreamProvider).value ?? const <Treatment>[];
    final viewedMonth = ref.watch(viewedMonthProvider);
    final medicines = ref.watch(medicinesProvider).value ?? const <Medicine>[];

    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthName = monthNames[viewedMonth.month - 1];
    final monthAppts =
        ref
            .watch(
              appointmentsForMonthProvider((
                year: viewedMonth.year,
                month: viewedMonth.month,
              )),
            )
            .value ??
        const <Appointment>[];

    // notifications
    final lowStock = inventory.where((i) => i.level != StockLevel.ok).length;
    final unpaid = invoices.where((i) => i.status != InvoiceStatus.paid).length;
    final recall = patients
        .where((p) => p.status == PatientStatus.recallDue)
        .length;
    final notifs = <_Notif>[
      if (lowStock > 0)
        _Notif(
          Icons.inventory_2_rounded,
          '$lowStock item${lowStock == 1 ? '' : 's'} low on stock',
          AppRoutes.inventory,
        ),
      if (unpaid > 0)
        _Notif(
          Icons.receipt_long_rounded,
          '$unpaid unpaid invoice${unpaid == 1 ? '' : 's'}',
          AppRoutes.billing,
        ),
      if (recall > 0)
        _Notif(
          Icons.event_repeat_rounded,
          '$recall patient${recall == 1 ? '' : 's'} due for recall',
          AppRoutes.patients,
        ),
    ];

    final route = widget.destination.route;
    final q = _query.trim().toLowerCase();
    final results = _matchesFor(
      route,
      q,
      patients,
      invoices,
      inventory,
      treatments,
      monthAppts,
      medicines,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: _kBarHeight,
          decoration: BoxDecoration(
            color: d.surface.withValues(alpha: .7),
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              // Breakpoints measured on the BAR's width, not the screen's —
              // so an expanded sidebar or a half-width window is handled too.
              final compact = w < 980; // action labels → icon only
              final hideTitle = w < 820; // screen title drops
              final hideTheme =
                  w < 700; // theme toggle drops (it's in Settings)
              final gap = compact ? 8.0 : 10.0;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
                child: Row(
                  children: [
                    // ── LEFT: fixed-size, never stretches ──
                    _iconBtn(
                      context,
                      Icons.menu_rounded,
                      widget.onToggleSidebar,
                      tooltip: 'Toggle sidebar',
                    ),
                    if (!hideTitle) ...[
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: w >= 1400 ? 300 : 220,
                        ),
                        child: _title(context, d),
                      ),
                    ],
                    const SizedBox(width: 20),

                    // ── MIDDLE: the ONLY flexible child ──
                    // It takes all free space; the search sits left-aligned
                    // inside it and stops at 560px. Because nothing else
                    // flexes, everything after it is pinned to the right edge.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _searchField(context, route, results, monthName),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // ── RIGHT: actions, always at the end ──
                    if (!hideTheme) ...[
                      _iconBtn(
                        context,
                        isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        () => ref.read(themeModeProvider.notifier).toggle(),
                        tooltip: isDark ? 'Light mode' : 'Dark mode',
                      ),
                      SizedBox(width: gap),
                    ],
                    _notificationBell(context, notifs),
                    // DB status is a system detail — only where system
                    // settings live.
                    if (route == AppRoutes.dashboard ||
                        route == AppRoutes.settings) ...[
                      SizedBox(width: gap),
                      _DbStatusButton(destination: widget.destination),
                    ],
                    if (route == AppRoutes.expenses)
                      ..._expenseActions(context, ref, compact: compact)
                    else if (_showPrimary(ref)) ...[
                      SizedBox(width: gap),
                      _primaryButton(context, ref, compact: compact),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, DentColors d) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.destination.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: d.text1,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      if (widget.destination.subtitle.isNotEmpty)
        Text(
          widget.destination.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: d.text4, fontSize: 12.5, height: 1.3),
        ),
    ],
  );

  // ── search ────────────────────────────────────────────────────────────────
  Widget _searchField(
    BuildContext context,
    String route,
    List<_Result> results,
    String monthName,
  ) {
    final d = context.dent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: LayoutBuilder(
        builder: (context, c) {
          // Remember the real width so the dropdown lines up with the box.
          _searchWidth = c.maxWidth;
          return CompositedTransformTarget(
            link: _searchLink,
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (ctx) => _searchOverlay(ctx, results),
              child: SizedBox(
                height: _kBtn,
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearch,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(fontSize: 15, color: d.text1),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _hintFor(route, monthName),
                    hintStyle: TextStyle(color: d.text4, fontSize: 14),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: d.text4,
                      size: _kIcon,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: d.text4,
                            ),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearch('');
                            },
                          ),
                    filled: true,
                    fillColor: d.surface2,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kRadius),
                      borderSide: BorderSide(color: d.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kRadius),
                      borderSide: BorderSide(color: d.ice, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchOverlay(BuildContext context, List<_Result> results) {
    final d = context.dent;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeSearch,
          ),
        ),
        CompositedTransformFollower(
          link: _searchLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _searchWidth,
                constraints: const BoxConstraints(maxHeight: 400),
                decoration: BoxDecoration(
                  color: d.surface,
                  borderRadius: BorderRadius.circular(_kRadius),
                  border: Border.all(color: d.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No results for “${_query.trim()}”.',
                          style: TextStyle(color: d.text4, fontSize: 13.5),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        children: [
                          for (final r in results)
                            InkWell(
                              onTap: r.onTap,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    _leading(d, r),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.title,
                                            style: TextStyle(
                                              color: d.text1,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            r.subtitle,
                                            style: TextStyle(
                                              color: d.text4,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.north_east_rounded,
                                      size: 16,
                                      color: d.text4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _leading(DentColors d, _Result r) {
    if (r.initials != null) {
      return Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x2638BDF8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          r.initials!,
          style: const TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d.ice.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(r.icon ?? Icons.search_rounded, color: d.ice, size: 18),
    );
  }

  // ── notifications ─────────────────────────────────────────────────────────
  Widget _notificationBell(BuildContext context, List<_Notif> notifs) {
    final d = context.dent;
    return MenuAnchor(
      alignmentOffset: const Offset(-240, 10),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(d.surface),
        side: WidgetStatePropertyAll(BorderSide(color: d.line)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_kRadius)),
        ),
      ),
      menuChildren: notifs.isEmpty
          ? [
              MenuItemButton(
                onPressed: null,
                child: SizedBox(
                  width: 260,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'No new notifications',
                      style: TextStyle(fontSize: 14, color: d.text3),
                    ),
                  ),
                ),
              ),
            ]
          : [
              for (final n in notifs)
                MenuItemButton(
                  leadingIcon: Icon(n.icon, size: 19),
                  onPressed: () => context.go(n.route),
                  child: SizedBox(
                    width: 240,
                    child: Text(n.label, style: const TextStyle(fontSize: 14)),
                  ),
                ),
            ],
      builder: (context, controller, child) => _iconBtn(
        context,
        Icons.notifications_none_rounded,
        () => controller.isOpen ? controller.close() : controller.open(),
        dot: notifs.isNotEmpty,
        tooltip: 'Notifications',
      ),
    );
  }

  // ── shared button ────────────────────────────────────────────────────────
  Widget _iconBtn(
    BuildContext context,
    IconData icon,
    VoidCallback onTap, {
    bool dot = false,
    String? tooltip,
  }) {
    final d = context.dent;
    final btn = Material(
      color: d.surface,
      borderRadius: BorderRadius.circular(_kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kRadius),
        onTap: onTap,
        child: Container(
          width: _kBtn,
          height: _kBtn,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(color: d.line),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: _kIcon, color: d.text3),
              if (dot)
                Positioned(
                  top: 10,
                  right: 11,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: d.alert,
                      shape: BoxShape.circle,
                      border: Border.all(color: d.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  /// Gradient call-to-action. Collapses to an icon with a tooltip when the
  /// bar is narrow, instead of overflowing.
  Widget _accentButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    required bool compact,
  }) {
    final d = context.dent;
    return Tooltip(
      message: compact ? label : '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_kRadius),
          onTap: onTap,
          child: Container(
            height: _kBtn,
            constraints: BoxConstraints(minWidth: compact ? _kBtn : 0),
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
            decoration: BoxDecoration(
              gradient: d.accentGradient,
              borderRadius: BorderRadius.circular(_kRadius),
              boxShadow: [
                BoxShadow(
                  color: d.teal.withValues(alpha: .35),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_rounded,
                  color: AppPalette.onAccent,
                  size: 22,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      color: AppPalette.onAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── expenses: three actions ──────────────────────────────────────────────
  List<Widget> _expenseActions(
    BuildContext context,
    WidgetRef ref, {
    required bool compact,
  }) {
    if (!ref.watch(canProvider(Perm.manageExpenses))) return const [];
    final d = context.dent;
    final period = ref.watch(expensePeriodProvider);
    final gap = compact ? 8.0 : 10.0;

    return [
      // Copying forward only makes sense while viewing a single month.
      if (period.mode == PeriodMode.month) ...[
        SizedBox(width: gap),
        Tooltip(
          message: 'Copy last month',
          child: Material(
            color: d.surface,
            borderRadius: BorderRadius.circular(_kRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_kRadius),
              onTap: () => copyLastMonthFlow(context, ref, period),
              child: Container(
                height: _kBtn,
                constraints: BoxConstraints(minWidth: compact ? _kBtn : 0),
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_kRadius),
                  border: Border.all(color: d.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy_all_rounded, size: _kIcon, color: d.text3),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Copy last month',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          color: d.text2,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      SizedBox(width: gap),
      _iconBtn(
        context,
        Icons.tune_rounded,
        () => showListsManager(context),
        tooltip: 'Manage categories & methods',
      ),
      SizedBox(width: gap),
      _accentButton(
        context,
        label: 'Add Expense',
        onTap: () => showExpenseEditor(context),
        compact: compact,
      ),
    ];
  }

  /// Whether the topbar's primary action applies to this screen and this user.
  bool _showPrimary(WidgetRef ref) {
    final r = widget.destination.route;
    if (r == AppRoutes.settings) return false;
    if (r == AppRoutes.expenses) return false; // handled by _expenseActions
    if (widget.destination.primaryAction.isEmpty) return false;
    // "+ New Offer" — Premium only
    if (r == AppRoutes.whatsapp) return ref.watch(entitlementsProvider).offers;
    // "Export Report" — financial data
    if (r == AppRoutes.reports) {
      return ref.watch(canProvider(Perm.viewFinancials));
    }
    return true;
  }

  Widget _primaryButton(
    BuildContext context,
    WidgetRef ref, {
    required bool compact,
  }) => _accentButton(
    context,
    label: widget.destination.primaryAction,
    onTap: () => _onPrimary(context, ref),
    compact: compact,
  );

  void _onPrimary(BuildContext context, WidgetRef ref) {
    switch (widget.destination.route) {
      case AppRoutes.patients:
        showPatientEditor(context);
      case AppRoutes.billing:
        showInvoiceEditor(context);
      case AppRoutes.inventory:
        showInventoryEditor(context);
      case AppRoutes.dashboard:
      case AppRoutes.appointments:
        showAppointmentEditor(context);
      case AppRoutes.whatsapp:
        if (ref.read(entitlementsProvider).offers) {
          showOfferComposer(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offers are available on the Premium plan.'),
            ),
          );
        }
      case AppRoutes.treatments:
        showTreatmentEditor(context);
      case AppRoutes.prescriptions:
        showMedicineEditor(context);
      case AppRoutes.reports:
        if (!ref.read(canProvider(Perm.viewFinancials))) return;
        showPdfOutput(
          context,
          build: () async {
            final s = await ref.read(reportsSummaryProvider.future);
            final name = await ref.read(clinicNameProvider.future);
            return buildReportsPdf(s, clinicName: name);
          },
          filename: 'dentos-report.pdf',
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.destination.primaryAction} — not wired on this screen yet.',
            ),
          ),
        );
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  DB STATUS
// ═════════════════════════════════════════════════════════════════════════════

class _DbStatusButton extends ConsumerWidget {
  const _DbStatusButton({required this.destination});
  final NavDestination destination;

  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    return Tooltip(
      message: 'Database status',
      child: Material(
        color: d.surface,
        borderRadius: BorderRadius.circular(_kRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kRadius),
          onTap: () => _showDialog(context, ref),
          child: Container(
            width: _kBtn,
            height: _kBtn,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kRadius),
              border: Border.all(color: d.line),
            ),
            child: Icon(Icons.storage_rounded, size: _kIcon, color: d.text3),
          ),
        ),
      ),
    );
  }

  Future<void> _showDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final lastSync = await db.lastSyncAt();
    final clinicId = await db.currentClinicId();
    final isCloud = clinicId != null && clinicId.isNotEmpty;
    final skipped =
        int.tryParse(await db.getSetting('sync_skipped_count') ?? '') ?? 0;
    final skippedWhat = await db.getSetting('sync_skipped') ?? '';
    if (!context.mounted) return;

    final d = context.dent;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: EdgeInsets.zero,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, minWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: d.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: d.ice.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.storage_rounded,
                        color: d.ice,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Database Status',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: d.text1,
                          ),
                        ),
                        Text(
                          'DentOS local + cloud',
                          style: TextStyle(color: d.text4, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // rows
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _row(
                      d,
                      Icons.lock_rounded,
                      'Encryption',
                      'SQLCipher · AES-256',
                      d.ok,
                    ),
                    const SizedBox(height: 14),
                    _row(
                      d,
                      isCloud
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      'Sync mode',
                      isCloud ? 'Local + Cloud (Supabase)' : 'Local only',
                      isCloud ? d.teal : d.warn,
                    ),
                    const SizedBox(height: 14),
                    _row(
                      d,
                      Icons.sync_rounded,
                      'Last synced',
                      _timeAgo(lastSync),
                      lastSync == null ? d.text4 : d.ok,
                    ),
                    if (lastSync != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          lastSync.toString().split('.').first,
                          style: TextStyle(
                            color: d.text4,
                            fontSize: 12,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _row(
                      d,
                      skipped == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.report_problem_rounded,
                      'Last sync result',
                      skipped == 0
                          ? 'All records came through'
                          : '$skipped record${skipped == 1 ? "" : "s"} '
                                'could not be applied',
                      skipped == 0 ? d.ok : d.warn,
                    ),
                    if (skipped > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: d.warn.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          'Usually a duplicate patient code or invoice number '
                          'created on two computers. Contact support with: '
                          '$skippedWhat',
                          style: TextStyle(
                            color: d.text3,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _row(
                      d,
                      Icons.folder_rounded,
                      'Storage',
                      'Local encrypted DB · auto-backup',
                      d.text3,
                    ),
                  ],
                ),
              ),

              // footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: d.warn,
                          side: BorderSide(color: d.line),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await ref
                              .read(appDatabaseProvider)
                              .clearContactWindow();
                          await ref
                              .read(licenseControllerProvider.notifier)
                              .reload();
                        },
                        child: const Text('Force check'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: d.text2,
                          side: BorderSide(color: d.line),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: d.ice,
                          foregroundColor: AppPalette.onAccent,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.go(AppRoutes.settings);
                        },
                        icon: const Icon(Icons.settings_rounded, size: 17),
                        label: const Text('Settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    DentColors d,
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: d.text3,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// class _RefreshButton extends ConsumerStatefulWidget {
//   const _RefreshButton({required this.destination});
//   final NavDestination destination;
//   @override
//   ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
// }

// class _RefreshButtonState extends ConsumerState<_RefreshButton>
//     with SingleTickerProviderStateMixin {
//   late final AnimationController _spin = AnimationController(
//     vsync: this,
//     duration: const Duration(milliseconds: 700),
//   );
//   bool _busy = false;

//   @override
//   void dispose() {
//     _spin.dispose();
//     super.dispose();
//   }

  /// Invalidate the providers the current screen depends on, so it re-reads
  /// fresh local data. Also fires a cloud sync so the newest data is pulled.
  // Future<void> _refresh() async {
  //   if (_busy) return;
  //   setState(() => _busy = true);
  //   _spin.repeat();

  //   // 1. sync (pull latest from cloud) — non-fatal if offline
  //   try {
  //     await syncNow(ref);
  //   } catch (_) {}

  //   // 2. invalidate providers so every screen re-reads fresh local data
  //   ref.invalidate(patientsStreamProvider);
  //   ref.invalidate(invoicesStreamProvider);
  //   ref.invalidate(inventoryStreamProvider);
  //   ref.invalidate(treatmentsStreamProvider);
  //   ref.invalidate(appointmentsForDayProvider);
  //   // month appts for the currently viewed month
  //   final vm = ref.read(viewedMonthProvider);
  //   ref.invalidate(
  //     appointmentsForMonthProvider((year: vm.year, month: vm.month)),
  //   );

  //   _spin.stop();
  //   _spin.reset();
  //   if (mounted) {
  //     setState(() => _busy = false);
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Refreshed ${widget.destination.title.toLowerCase()}'),
  //         duration: const Duration(seconds: 1),
  //       ),
  //     );
  //   }
  // }

  // @override
  // Widget build(BuildContext context) {
  //   final d = context.dent;
  //   return Material(
  //     color: d.surface,
  //     borderRadius: BorderRadius.circular(12),
  //     child: InkWell(
  //       borderRadius: BorderRadius.circular(12),
  //       onTap: _refresh,
  //       child: Container(
  //         width: 20.sp,
  //         height: 20.sp,
  //         decoration: BoxDecoration(
  //           borderRadius: BorderRadius.circular(12),
  //           border: Border.all(color: d.line),
  //         ),
  //         child: RotationTransition(
  //           turns: _spin,
  //           child: Icon(Icons.refresh_rounded, size: 14.sp, color: d.text3),
  //         ),
  //       ),
  //     ),
  //   );
  // }
// }
