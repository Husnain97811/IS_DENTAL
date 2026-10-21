import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:is_dental/core/router/app_routes.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/all_prescriptions.dart';
import 'prescription_preview.dart';

const _months = [
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

/// Every prescription written in the branch: search by patient, phone,
/// file no., RX no. or medicine; tap one to view, print, download or
/// send it on WhatsApp.
class AllPrescriptionsTab extends ConsumerStatefulWidget {
  const AllPrescriptionsTab({super.key});
  @override
  ConsumerState<AllPrescriptionsTab> createState() =>
      _AllPrescriptionsTabState();
}

class _AllPrescriptionsTabState extends ConsumerState<AllPrescriptionsTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _text = '';
  RxPeriod _period = RxPeriod.all;

  /// Last list shown — kept on screen while a new search loads, so the
  /// list never blinks empty between keystrokes.
  List<RxListEntry>? _last;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onTyped(String v) {
    setState(() {}); // clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _text = v.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _text = '');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final async = ref.watch(
      allPrescriptionsProvider((text: _text, period: _period)),
    );
    if (async.hasValue) _last = async.value;
    final list = _last;
    final filtered = _text.isNotEmpty || _period != RxPeriod.all;

    final subtitle = list == null
        ? 'Loading…'
        : filtered
        ? '${list.length}${list.length >= kRxListLimit ? '+' : ''} found'
        : list.length >= kRxListLimit
        ? 'Latest $kRxListLimit · newest first'
        : '${list.length} written · newest first';

    return DentPanel(
      title: 'All Prescriptions',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(d),
          if (async.hasError)
            _message(
              d,
              Icons.error_outline_rounded,
              'Could not load prescriptions',
              '${async.error}',
              alert: true,
            )
          else if (list == null)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            filtered
                ? _message(
                    d,
                    Icons.search_off_rounded,
                    'No prescriptions match',
                    'Try a patient name, phone, file no., RX no. or medicine.',
                  )
                : _message(
                    d,
                    Icons.medication_outlined,
                    'No prescriptions yet',
                    'Prescriptions written from a patient\'s file will appear here.',
                  )
          else
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 860;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide) _header(d),
                    for (final e in list)
                      _RxRow(key: ValueKey(e.id), e: e, wide: wide),
                    if (list.length >= kRxListLimit)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Showing the latest $kRxListLimit. Search or pick a period to find older ones.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: d.text4, fontSize: 9.sp),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _toolbar(DentColors d) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: (32.w).clamp(260.0, 440.0),
          child: TextField(
            controller: _search,
            onChanged: _onTyped,
            style: TextStyle(fontSize: 10.5.sp, color: d.text1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Patient, phone, file no., RX no. or medicine',
              hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: d.text3),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: Icon(Icons.close_rounded, size: 16, color: d.text3),
                      onPressed: _clear,
                    ),
              filled: true,
              fillColor: d.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.ice),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in RxPeriod.values)
              ChoiceChip(
                label: Text(p.label, style: TextStyle(fontSize: 9.5.sp)),
                selected: _period == p,
                showCheckmark: false,
                selectedColor: d.ice.withValues(alpha: .14),
                side: BorderSide(color: _period == p ? d.ice : d.line),
                labelStyle: TextStyle(
                  color: _period == p ? d.ice : d.text2,
                  fontWeight: _period == p ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => setState(() => _period = p),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _header(DentColors d) {
    TextStyle s() => TextStyle(
      color: d.text4,
      fontSize: 8.5.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .6,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: d.surface2,
        border: Border.symmetric(horizontal: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(flex: 22, child: Text('PRESCRIPTION', style: s())),
          Expanded(flex: 30, child: Text('PATIENT', style: s())),
          Expanded(flex: 36, child: Text('MEDICINES', style: s())),
          Expanded(flex: 18, child: Text('DOCTOR', style: s())),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _message(
    DentColors d,
    IconData icon,
    String title,
    String body, {
    bool alert = false,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (alert ? d.alert : d.ice).withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: alert ? d.alert : d.ice),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            color: d.text1,
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
        ),
      ],
    ),
  );
}

enum _RxAction { view, download, patient, delete }

class _RxRow extends ConsumerStatefulWidget {
  const _RxRow({super.key, required this.e, required this.wide});
  final RxListEntry e;
  final bool wide;
  @override
  ConsumerState<_RxRow> createState() => _RxRowState();
}

class _RxRowState extends ConsumerState<_RxRow> {
  bool _hover = false, _opening = false;

  RxListEntry get e => widget.e;

  /// The list only holds a summary — the full prescription is read here.
  Future<Prescription?> _load() async {
    final rx = await ref.read(prescriptionRepositoryProvider).byId(e.id);
    if (rx == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This prescription was removed.')),
      );
    }
    return rx;
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final rx = await _load();
      if (rx == null || !mounted) return;
      await showPrescriptionPreview(
        context,
        rx: rx,
        patientName: e.patientName,
        patientUuid: e.patientUuid,
        allergies: e.allergies,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _act(_RxAction a) async {
    switch (a) {
      case _RxAction.view:
        await _open();
      case _RxAction.download:
        final rx = await _load();
        if (rx == null || !mounted) return;
        await savePrescriptionToDownloads(
          context,
          ref.read(appDatabaseProvider),
          rx,
        );
      case _RxAction.patient:
        context.push('${AppRoutes.patients}/${e.patientId}');
      case _RxAction.delete:
        final ok = await showDentDialog(
          context,
          kind: DentDialogKind.warning,
          title: 'Delete prescription?',
          message: 'Remove ${e.rxNo} from ${e.patientName}\'s record.',
          confirmLabel: 'Delete',
          cancelLabel: 'Cancel',
        );
        if (ok == true) {
          await ref
              .read(prescriptionRepositoryProvider)
              .deletePrescription(e.id, e.patientId);
        }
    }
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time =
        '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    final date = diff == 0
        ? 'Today'
        : diff == 1
        ? 'Yesterday'
        : '${t.day} ${_months[t.month - 1]}${t.year == now.year ? '' : ' ${t.year}'}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;

    final rxCell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.rxNo,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            color: d.text1,
            fontSize: 10.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _when(e.issuedAt),
          style: TextStyle(color: d.text3, fontSize: 9.sp),
        ),
      ],
    );

    final patientCell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                e.patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (e.hasAllergy) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Allergy: ${e.allergies!.trim()}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: d.alert.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Allergy',
                    style: TextStyle(
                      color: d.alert,
                      fontSize: 7.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (e.patientCode.isNotEmpty) e.patientCode,
            if (e.phone.isNotEmpty) e.phone,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: d.text3,
            fontSize: 9.sp,
            fontFamily: AppFonts.mono,
          ),
        ),
      ],
    );

    final medsCell = Row(
      children: [
        if (e.medicines.isNotEmpty) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: d.teal.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '${e.medicines.length}',
              style: TextStyle(
                color: d.tealDeep,
                fontSize: 8.5.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            e.medicinesLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: e.medicines.isEmpty ? d.text4 : d.text2,
              fontSize: 9.5.sp,
              fontStyle: e.medicines.isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ),
      ],
    );

    final menu = SizedBox(
      width: 40,
      child: _opening
          ? Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: d.ice),
              ),
            )
          : PopupMenuButton<_RxAction>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert_rounded, size: 18, color: d.text3),
              color: d.surface,
              onSelected: _act,
              itemBuilder: (_) => [
                _item(
                  d,
                  _RxAction.view,
                  Icons.visibility_outlined,
                  ref.watch(entitlementsProvider).rxOnWhatsapp
                      ? 'View & send'
                      : 'View',
                ),
                _item(
                  d,
                  _RxAction.download,
                  Icons.download_rounded,
                  'Download PDF',
                ),
                _item(
                  d,
                  _RxAction.patient,
                  Icons.person_outline_rounded,
                  'Open patient file',
                ),
                const PopupMenuDivider(),
                _item(
                  d,
                  _RxAction.delete,
                  Icons.delete_outline_rounded,
                  'Delete',
                  danger: true,
                ),
              ],
            ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.fromLTRB(
            18,
            widget.wide ? 12 : 14,
            6,
            widget.wide ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: _hover ? d.surface2 : Colors.transparent,
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: widget.wide
              ? Row(
                  children: [
                    Expanded(flex: 22, child: rxCell),
                    Expanded(
                      flex: 30,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: patientCell,
                      ),
                    ),
                    Expanded(
                      flex: 36,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: medsCell,
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(
                        e.doctorName.isEmpty ? '—' : e.doctorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: d.text2, fontSize: 9.5.sp),
                      ),
                    ),
                    menu,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: patientCell),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    e.rxNo,
                                    style: TextStyle(
                                      fontFamily: AppFonts.mono,
                                      color: d.text1,
                                      fontSize: 9.5.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _when(e.issuedAt),
                                    style: TextStyle(
                                      color: d.text3,
                                      fontSize: 8.5.sp,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          medsCell,
                          if (e.doctorName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              e.doctorName,
                              style: TextStyle(color: d.text3, fontSize: 9.sp),
                            ),
                          ],
                        ],
                      ),
                    ),
                    menu,
                  ],
                ),
        ),
      ),
    );
  }

  PopupMenuItem<_RxAction> _item(
    DentColors d,
    _RxAction a,
    IconData icon,
    String label, {
    bool danger = false,
  }) => PopupMenuItem(
    value: a,
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 17, color: danger ? d.alert : d.text2),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: danger ? d.alert : d.text1, fontSize: 10.sp),
        ),
      ],
    ),
  );
}
