import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/core/utils/pdf_output.dart';
import 'package:is_dental/features/patients/presentation/widgets/inventory_editor.dart';
import 'package:is_dental/features/reports/data/reports_pdf.dart';
import 'package:is_dental/features/reports/presentation/reports_controller.dart';
import 'package:sizer/sizer.dart';

import '../../router/nav_destinations.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import '../../theme/dent_colors.dart';
import '../../theme/theme_controller.dart';

import '../../router/app_routes.dart';
import '../../../features/patients/presentation/widgets/patient_editor.dart';
import '../../../features/billing/presentation/widgets/invoice_editor.dart';
import '../../../features/appointments/presentation/widgets/appointment_editor.dart';
import '../../../features/treatments/presentation/widgets/treatment_editor.dart';
import '../../../features/branches/presentation/widgets/branch_switcher.dart';

import 'package:is_dental/features/patients/domain/patient.dart';
import 'package:is_dental/features/patients/presentation/patients_controller.dart';
import 'package:is_dental/features/billing/domain/invoice.dart';
import 'package:is_dental/features/billing/presentation/billing_controller.dart';
import 'package:is_dental/features/inventory/domain/inventory_item.dart';
import 'package:is_dental/features/inventory/presentation/inventory_controller.dart';
import 'package:is_dental/features/treatments/domain/treatment.dart';
import 'package:is_dental/features/treatments/presentation/treatments_controller.dart';
import 'package:is_dental/features/appointments/domain/appointment.dart';
import 'package:is_dental/features/appointments/presentation/appointments_controller.dart';

String _money(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    setState(() => _query = v);
    if (v.trim().isEmpty) {
      if (_portal.isShowing) _portal.hide();
    } else {
      if (!_portal.isShowing) _portal.show();
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
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: d.surface.withValues(alpha: .7),
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              _iconBtn(context, Icons.menu_rounded, widget.onToggleSidebar),
              SizedBox(width: 3.w),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.destination.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    widget.destination.subtitle,
                    style: TextStyle(color: d.text4, fontSize: 8.sp),
                  ),
                ],
              ),
              SizedBox(width: 3.w),
              Expanded(child: _searchField(context, route, results, monthName)),
              const SizedBox(width: 10),
              const BranchSwitcher(),
              SizedBox(width: 2.w),
              _iconBtn(
                context,
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                () => ref.read(themeModeProvider.notifier).toggle(),
              ),
              const SizedBox(width: 10),
              _notificationBell(context, notifs),
              const SizedBox(width: 10),
              _iconBtn(context, Icons.storage_rounded, () {}),
              const SizedBox(width: 10),
              _primaryButton(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(
    BuildContext context,
    String route,
    List<_Result> results,
    String monthName,
  ) {
    final d = context.dent;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: CompositedTransformTarget(
          link: _searchLink,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (ctx) => _searchOverlay(ctx, results),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearch,
              style: TextStyle(fontSize: 9.5.sp, color: d.text1),
              decoration: InputDecoration(
                isDense: true,
                hintText: _hintFor(route, monthName),
                hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: d.text4,
                  size: 11.sp,
                ),
                filled: true,
                fillColor: d.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: d.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: d.ice, width: 1.5),
                ),
              ),
            ),
          ),
        ),
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
                width: 420,
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  color: d.surface,
                  borderRadius: BorderRadius.circular(12),
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
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No results for “${_query.trim()}”.',
                          style: TextStyle(color: d.text4, fontSize: 8.5.sp),
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
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    _leading(d, r),
                                    const SizedBox(width: 11),
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
                                              fontSize: 9.sp,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            r.subtitle,
                                            style: TextStyle(
                                              color: d.text4,
                                              fontSize: 7.5.sp,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.north_east_rounded,
                                      size: 9.sp,
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
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x2638BDF8),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          r.initials!,
          style: TextStyle(
            color: const Color(0xFF38BDF8),
            fontWeight: FontWeight.w700,
            fontSize: 8.sp,
          ),
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d.ice.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(r.icon ?? Icons.search_rounded, color: d.ice, size: 10.sp),
    );
  }

  Widget _notificationBell(BuildContext context, List<_Notif> notifs) {
    return MenuAnchor(
      alignmentOffset: const Offset(-240, 10),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.dent.surface),
        side: WidgetStatePropertyAll(BorderSide(color: context.dent.line)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: notifs.isEmpty
          ? [
              const MenuItemButton(
                onPressed: null,
                child: SizedBox(
                  width: 220,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No new notifications'),
                  ),
                ),
              ),
            ]
          : [
              for (final n in notifs)
                MenuItemButton(
                  leadingIcon: Icon(n.icon, size: 10.sp),
                  onPressed: () => context.go(n.route),
                  child: SizedBox(width: 220, child: Text(n.label)),
                ),
            ],
      builder: (context, controller, child) => _iconBtn(
        context,
        Icons.notifications_none_rounded,
        () => controller.isOpen ? controller.close() : controller.open(),
        dot: notifs.isNotEmpty,
      ),
    );
  }

  Widget _iconBtn(
    BuildContext context,
    IconData icon,
    VoidCallback onTap, {
    bool dot = false,
  }) {
    final d = context.dent;
    return Material(
      color: d.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: d.line),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 11.sp, color: d.text3),
              if (dot)
                Positioned(
                  top: 9,
                  right: 10,
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
  }

  Widget _primaryButton(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onPrimary(context, ref),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: d.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: d.teal.withValues(alpha: .35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.add_rounded,
                color: AppPalette.onAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                widget.destination.primaryAction,
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  color: AppPalette.onAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      case AppRoutes.treatments:
        showTreatmentEditor(context);
      case AppRoutes.reports:
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
