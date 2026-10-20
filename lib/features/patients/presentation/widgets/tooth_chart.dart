import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/theme/app_palette.dart';
import 'package:is_dental/core/theme/app_typography.dart';
import 'package:is_dental/core/theme/dent_colors.dart';
import 'package:is_dental/core/widgets/dent_panel.dart';
import 'package:is_dental/core/widgets/segmented_control.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../data/tooth_chart_repository.dart';
import '../../domain/tooth_finding.dart';
import '../patients_controller.dart';

// How it works
// ─────────────
//  • Patient screen: click a tooth → its findings + history in the side panel.
//                    double-click a tooth → the "chart this tooth" dialog.
//                    Shift-click → select several, then "Chart N teeth…".
//  • Sidebar / drawer (CompactToothChart): click a tooth → the dialog.
//  • The dialog shows what is on the tooth, its history, and lets you add a
//    finding: pick the condition, the surfaces (on a big tooth), the status.

// ── layout constants (logical pixels, before the chart scales to fit) ──────
const double _kToothW = 40;
const double _kToothH = 73;
const double _kColW = 44;

const _adultUR = [18, 17, 16, 15, 14, 13, 12, 11];
const _adultUL = [21, 22, 23, 24, 25, 26, 27, 28];
const _adultLR = [48, 47, 46, 45, 44, 43, 42, 41];
const _adultLL = [31, 32, 33, 34, 35, 36, 37, 38];
const _childUR = [55, 54, 53, 52, 51];
const _childUL = [61, 62, 63, 64, 65];
const _childLR = [85, 84, 83, 82, 81];
const _childLL = [71, 72, 73, 74, 75];

const _mon = [
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
String _date(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

/// Colour per status: red = to do, blue = done here, grey = was already
/// there, amber = decay found.
Color statusColor(FindingStatus s, DentColors d) => switch (s) {
  FindingStatus.planned => d.alert,
  FindingStatus.done => d.ice,
  FindingStatus.existing => d.text4,
  FindingStatus.found => d.warn,
};

// ═════════════════════════════════════════════════════════════════════════════
//  Tooth numbering — display only. Everything is STORED and synced as FDI
//  (11–48), so switching the numbering never changes any data.
// ═════════════════════════════════════════════════════════════════════════════

enum ToothNumbering {
  /// 1–32, starting at the upper-right wisdom tooth (milk teeth A–T).
  universal,

  /// Two digits: quarter of the mouth + tooth (11–48, milk teeth 51–85).
  fdi,
}

extension ToothNumberingX on ToothNumbering {
  String get label => switch (this) {
    ToothNumbering.universal => '1–32',
    ToothNumbering.fdi => 'FDI (11–48)',
  };
}

/// The number shown for a tooth. [fdi] is the stored FDI number.
String toothLabel(int fdi, ToothNumbering n) {
  if (n == ToothNumbering.fdi) return '$fdi';
  final q = fdi ~/ 10, t = fdi % 10;
  String letter(int i) => String.fromCharCode(65 + i); // 0 → A
  return switch (q) {
    1 => '${9 - t}', //  18 → 1 … 11 → 8
    2 => '${8 + t}', //  21 → 9 … 28 → 16
    3 => '${25 - t}', // 38 → 17 … 31 → 24
    4 => '${24 + t}', // 41 → 25 … 48 → 32
    5 => letter(5 - t), //  55 → A … 51 → E
    6 => letter(4 + t), //  61 → F … 65 → J
    7 => letter(15 - t), // 75 → K … 71 → O
    8 => letter(14 + t), // 81 → P … 85 → T
    _ => '$fdi',
  };
}

String _plainLabel(int fdi) => '$fdi';

/// Which numbering this computer shows. Saved in local settings.
class ToothNumberingNotifier extends Notifier<ToothNumbering> {
  static const _key = 'tooth_numbering';

  @override
  ToothNumbering build() {
    _load();
    return ToothNumbering.universal;
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(appDatabaseProvider).getSetting(_key);
      final n = ToothNumbering.values.asNameMap()[v];
      if (n != null && n != state) state = n;
    } catch (_) {}
  }

  Future<void> set(ToothNumbering n) async {
    state = n;
    await ref.read(appDatabaseProvider).setSetting(_key, n.name);
  }
}

final toothNumberingProvider =
    NotifierProvider<ToothNumberingNotifier, ToothNumbering>(
      ToothNumberingNotifier.new,
    );

/// Small "Numbering: 1–32 ▾" menu shown under the chart.
class _NumberingMenu extends ConsumerWidget {
  const _NumberingMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final n = ref.watch(toothNumberingProvider);
    return PopupMenuButton<ToothNumbering>(
      tooltip: 'Tooth numbering',
      initialValue: n,
      onSelected: (v) => ref.read(toothNumberingProvider.notifier).set(v),
      itemBuilder: (_) => [
        for (final v in ToothNumbering.values)
          PopupMenuItem(value: v, child: Text(v.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Numbering: ${n.label}',
              style: TextStyle(color: d.text3, fontSize: 9.sp),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: d.text3, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Milk teeth (51–85, 20 teeth) are only for children; everyone else gets
/// the normal 32 adult teeth (11–48). Children 6–12 have both kinds, so for
/// them the patient screen offers a switch.
const kChildAgeLimit = 13;
bool _isChild(int? age) => age != null && age < kChildAgeLimit;
bool _hasMilkFindings(List<ToothFinding> all) =>
    all.any((f) => !f.isDeleted && isPrimaryTooth(f.fdi));

String _me(WidgetRef ref) => ref.read(authControllerProvider)?.username ?? '';

/// After any change: keep the old single-state `tooth_records` in step (the
/// patient app and older PCs read it) and push to the cloud.
Future<void> _afterChange(
  WidgetRef ref,
  int patientId,
  Iterable<int> fdis,
) async {
  final repo = ref.read(toothChartRepositoryProvider);
  final patients = ref.read(patientRepositoryProvider);
  for (final fdi in fdis.toSet()) {
    final live = await repo.liveFor(patientId, fdi);
    await patients.setToothState(patientId, fdi, legacyStateFor(live));
  }
  syncInBackground(ref);
}

// ═════════════════════════════════════════════════════════════════════════════
//  1. Patient screen card: chart + side panel
// ═════════════════════════════════════════════════════════════════════════════

class DentalChartCard extends ConsumerStatefulWidget {
  const DentalChartCard({
    super.key,
    required this.patientId,
    required this.patientUuid,
    this.age,
  });
  final int patientId;
  final String patientUuid;

  /// Patient age in years — decides adult or milk teeth.
  final int? age;

  @override
  ConsumerState<DentalChartCard> createState() => _DentalChartCardState();
}

class _DentalChartCardState extends ConsumerState<DentalChartCard> {
  final Set<int> _sel = {};
  // null = not chosen by the user yet → decided by age.
  bool? _childChoice;

  void _tap(int fdi, bool additive) => setState(() {
    if (additive) {
      _sel.contains(fdi) ? _sel.remove(fdi) : _sel.add(fdi);
    } else {
      final only = _sel.length == 1 && _sel.contains(fdi);
      _sel.clear();
      if (!only) _sel.add(fdi);
    }
  });

  void _open(int fdi) {
    final many = _sel.length > 1 && _sel.contains(fdi);
    final fdis = many ? (_sel.toList()..sort()) : [fdi];
    if (!many) {
      setState(() {
        _sel
          ..clear()
          ..add(fdi);
      });
    }
    showToothDialog(
      context,
      patientId: widget.patientId,
      patientUuid: widget.patientUuid,
      fdis: fdis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final all =
        ref.watch(toothFindingsProvider(widget.patientId)).value ??
        const <ToothFinding>[];

    final numbering = ref.watch(toothNumberingProvider);
    String lbl(int f) => toothLabel(f, numbering);
    final child = _childChoice ?? _isChild(widget.age);
    // The switch only appears where it makes sense: children, or someone who
    // already has milk-tooth findings recorded.
    final showSwitch = _isChild(widget.age) || _hasMilkFindings(all);

    return DentPanel(
      title: 'Dental Chart',
      subtitle: child
          ? 'Milk teeth (20) · click for details · double-click to chart'
          : 'Click a tooth for details · double-click to chart it',
      trailing: showSwitch
          ? SegmentedControl(
              items: const ['Permanent', 'Milk teeth'],
              selected: child ? 1 : 0,
              onChanged: (i) => setState(() {
                _childChoice = i == 1;
                _sel.clear();
              }),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, c) {
          final chart = Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ToothChartView(
                  findings: all,
                  primaryTeeth: child,
                  labelOf: lbl,
                  selected: _sel,
                  onTap: _tap,
                  onDoubleTap: _open,
                ),
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: ToothChartLegend()),
                    _NumberingMenu(),
                  ],
                ),
              ],
            ),
          );
          final side = Padding(
            padding: const EdgeInsets.all(18),
            child: _SidePanel(
              patientId: widget.patientId,
              selection: _sel.toList()..sort(),
              all: all,
              onOpen: () => _open((_sel.toList()..sort()).first),
              onClear: () => setState(_sel.clear),
            ),
          );
          if (c.maxWidth >= 1100) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: chart),
                Container(
                  width: 340,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: d.line)),
                  ),
                  child: side,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              chart,
              Divider(height: 1, color: d.line),
              side,
            ],
          );
        },
      ),
    );
  }
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.patientId,
    required this.selection,
    required this.all,
    required this.onOpen,
    required this.onClear,
  });

  final int patientId;
  final List<int> selection;
  final List<ToothFinding> all;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final numbering = ref.watch(toothNumberingProvider);
    String lbl(int f) => toothLabel(f, numbering);

    // ── nothing selected: recent activity ──
    if (selection.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            eyebrow: 'Patient',
            title: 'Recent charting',
            sub: 'Click a tooth to see it · double-click to chart it',
          ),
          const SizedBox(height: 14),
          _Timeline(
            events: _events(d, all).take(8).toList(),
            showTooth: true,
            labelOf: lbl,
          ),
        ],
      );
    }

    // ── several teeth ──
    if (selection.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            eyebrow: 'Selection',
            title: '${selection.length} teeth',
            sub: selection.map(lbl).join(' · '),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'Chart ${selection.length} teeth…',
            onTap: onOpen,
          ),
          const SizedBox(height: 10),
          _GhostButton(label: 'Clear selection', onTap: onClear),
        ],
      );
    }

    // ── one tooth ──
    final fdi = selection.first;
    final live = all.where((f) => f.fdi == fdi && !f.isDeleted).toList();
    final hist = _events(d, all.where((f) => f.fdi == fdi));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          eyebrow: 'Tooth',
          title: lbl(fdi),
          sub: toothName(fdi),
          mono: true,
        ),
        const SizedBox(height: 14),
        _Label('Current findings'),
        const SizedBox(height: 6),
        _FindingsList(patientId: patientId, fdi: fdi, live: live),
        const SizedBox(height: 12),
        _PrimaryButton(label: 'Chart this tooth…', onTap: onOpen),
        const SizedBox(height: 16),
        _Label(
          'History · ${hist.length} entr${hist.length == 1 ? 'y' : 'ies'}',
        ),
        const SizedBox(height: 8),
        _Timeline(events: hist, showTooth: false, labelOf: lbl),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  2. Sidebar / drawer: small chart, click opens the dialog
// ═════════════════════════════════════════════════════════════════════════════

class CompactToothChart extends ConsumerStatefulWidget {
  const CompactToothChart({
    super.key,
    required this.patientId,
    required this.patientUuid,
    this.age,
  });
  final int patientId;
  final String patientUuid;
  final int? age;

  @override
  ConsumerState<CompactToothChart> createState() => _CompactToothChartState();
}

class _CompactToothChartState extends ConsumerState<CompactToothChart> {
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final all =
        ref.watch(toothFindingsProvider(widget.patientId)).value ??
        const <ToothFinding>[];
    void open(int fdi, [bool additive = false]) => showToothDialog(
      context,
      patientId: widget.patientId,
      patientUuid: widget.patientUuid,
      fdis: [fdi],
    );
    // No switch here: adults see their 32 teeth, children their 20 milk teeth.
    final child = _isChild(widget.age);
    final numbering = ref.watch(toothNumberingProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToothChartView(
          findings: all,
          primaryTeeth: child,
          labelOf: (f) => toothLabel(f, numbering),
          selected: const {},
          showQuadrantLabels: false,
          numberSize: 17,
          stacked: true,
          onTap: open,
          onDoubleTap: open,
        ),
        const SizedBox(height: 6),
        Text(
          'Tap a tooth to see or chart it',
          textAlign: TextAlign.center,
          style: TextStyle(color: d.text4, fontSize: 8.sp),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  3. The chart drawing itself (used by both)
// ═════════════════════════════════════════════════════════════════════════════

class ToothChartView extends StatefulWidget {
  const ToothChartView({
    super.key,
    required this.findings,
    required this.primaryTeeth,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.showQuadrantLabels = true,
    this.numberSize = 16,
    this.stacked = false,
    this.labelOf = _plainLabel,
  });

  /// All findings of the patient (deleted ones are ignored here).
  final List<ToothFinding> findings;

  /// true = the 20 primary (milk) teeth, false = the 32 adult teeth.
  final bool primaryTeeth;
  final Set<int> selected;

  /// [additive] is true when Shift / Ctrl / Cmd was held.
  final void Function(int fdi, bool additive) onTap;
  final void Function(int fdi) onDoubleTap;
  final bool showQuadrantLabels;

  /// Font size of the tooth numbers (before the chart shrinks to fit).
  final double numberSize;

  /// For narrow places (the sidebar): each quarter of the mouth on its own
  /// row of 8 teeth instead of 16 across, so teeth and numbers are about
  /// twice as big.
  final bool stacked;

  /// Text shown for a tooth (see [toothLabel]).
  final String Function(int fdi) labelOf;

  @override
  State<ToothChartView> createState() => _ToothChartViewState();
}

class _ToothChartViewState extends State<ToothChartView> {
  // Captured on tap-down: with double-tap enabled, onTap fires ~300 ms later
  // and the key might already be released.
  bool _additive = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final byTooth = <int, List<ToothFinding>>{};
    for (final f in widget.findings) {
      if (!f.isDeleted) (byTooth[f.fdi] ??= []).add(f);
    }

    final ur = widget.primaryTeeth ? _childUR : _adultUR;
    final ul = widget.primaryTeeth ? _childUL : _adultUL;
    final lr = widget.primaryTeeth ? _childLR : _adultLR;
    final ll = widget.primaryTeeth ? _childLL : _adultLL;
    final width = (ur.length + ul.length) * _kColW + 20;

    Widget label(String a, String b) => SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final t in [a, b])
            Text(
              t.toUpperCase(),
              style: TextStyle(
                color: d.text4,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
        ],
      ),
    );

    Widget arch(List<int> left, List<int> right, bool upper) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: upper
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        for (final t in left) _tooth(d, t, byTooth[t] ?? const [], upper),
        Container(
          width: 2,
          height: _kToothH + 26,
          margin: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: d.line2,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        for (final t in right) _tooth(d, t, byTooth[t] ?? const [], upper),
      ],
    );

    if (widget.stacked) {
      Widget rowLabel(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 2, top: 4),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            color: d.text4,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
      );
      Widget quarter(String label, List<int> teeth, bool upper) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          rowLabel(label),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in teeth)
                _tooth(d, t, byTooth[t] ?? const [], upper),
            ],
          ),
        ],
      );
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // In number order: 11→18, 21→28, 31→38, 41→48.
            quarter('Upper right', [...ur]..sort(), true),
            quarter('Upper left', [...ul]..sort(), true),
            Container(
              width: ur.length * _kColW,
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: d.line2,
            ),
            quarter('Lower left', [...ll]..sort(), false),
            quarter('Lower right', [...lr]..sort(), false),
          ],
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showQuadrantLabels) ...[
            label('Upper right', 'Upper left'),
            const SizedBox(height: 4),
          ],
          arch(ur, ul, true),
          Container(
            width: width,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: d.line2,
          ),
          arch(lr, ll, false),
          if (widget.showQuadrantLabels) ...[
            const SizedBox(height: 4),
            label('Lower right', 'Lower left'),
          ],
        ],
      ),
    );
  }

  Widget _tooth(DentColors d, int fdi, List<ToothFinding> live, bool upper) {
    final selected = widget.selected.contains(fdi);

    final num = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? d.teal : null,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        widget.labelOf(fdi),
        style: AppTypography.mono(
          size: widget.numberSize,
          color: selected ? const Color(0xFF04121F) : d.text1,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
    );

    final body = CustomPaint(
      size: const Size(_kToothW, _kToothH),
      painter: _ToothPainter(
        fdi: fdi,
        live: live,
        selected: selected,
        base: d.surface,
        stroke: d.line2,
        selection: d.teal,
        colorOf: (s) => statusColor(s, d),
      ),
    );

    final tip = StringBuffer('${widget.labelOf(fdi)} · ${toothName(fdi)}');
    if (live.isEmpty) {
      tip.write('\nNo findings');
    } else {
      for (final f in live) {
        tip.write('\n• ${f.label} — ${f.status.label}');
      }
    }

    // The number and the tooth are one target.
    return Tooltip(
      message: tip.toString(),
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            final k = HardwareKeyboard.instance;
            _additive =
                k.isShiftPressed || k.isControlPressed || k.isMetaPressed;
          },
          onTap: () => widget.onTap(fdi, _additive),
          onDoubleTap: () => widget.onDoubleTap(fdi),
          child: SizedBox(
            width: _kColW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: upper ? [num, body] : [body, num],
            ),
          ),
        ),
      ),
    );
  }
}

class ToothChartLegend extends StatelessWidget {
  const ToothChartLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    Widget item(Color c, String l) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          l,
          style: TextStyle(color: d.text3, fontSize: 9.sp),
        ),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(d.warn, 'Caries found'),
        item(d.alert, 'Planned'),
        item(d.ice, 'Done here'),
        item(d.text4, 'Existing on arrival'),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  4. The tooth dialog
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the chart dialog for one tooth, or for several (then only
/// whole-tooth conditions can be added).
Future<void> showToothDialog(
  BuildContext context, {
  required int patientId,
  required String patientUuid,
  required List<int> fdis,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ToothDialog(
      patientId: patientId,
      patientUuid: patientUuid,
      fdis: fdis,
    ),
  );
}

const _diagnosis = [ToothKind.caries, ToothKind.missing];
const _restorative = [
  ToothKind.filling,
  ToothKind.sealant,
  ToothKind.crown,
  ToothKind.rct,
  ToothKind.implant,
  ToothKind.bridge,
];
const _surgical = [ToothKind.extraction];

class _ToothDialog extends ConsumerStatefulWidget {
  const _ToothDialog({
    required this.patientId,
    required this.patientUuid,
    required this.fdis,
  });
  final int patientId;
  final String patientUuid;
  final List<int> fdis;

  @override
  ConsumerState<_ToothDialog> createState() => _ToothDialogState();
}

class _ToothDialogState extends ConsumerState<_ToothDialog> {
  ToothKind? _kind;
  FindingStatus _status = FindingStatus.planned;
  final Set<String> _surfaces = {};
  final _note = TextEditingController();
  bool _busy = false;
  bool _showHistory = false;
  String? _flash; // short confirmation after adding

  bool get _single => widget.fdis.length == 1;
  int get _fdi => widget.fdis.first;
  FindingStatus get _effStatus => _kind?.forcedStatus ?? _status;

  bool get _canAdd {
    if (_kind == null || _busy) return false;
    if (_kind!.bySurface) return _surfaces.isNotEmpty;
    return true;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _pick(ToothKind k) => setState(() {
    _kind = _kind == k ? null : k;
    _surfaces.clear();
    _flash = null;
    // Sensible default per condition.
    if (k == ToothKind.extraction ||
        k == ToothKind.rct ||
        k == ToothKind.crown) {
      _status = FindingStatus.planned;
    }
  });

  Future<void> _add() async {
    if (!_canAdd) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(toothChartRepositoryProvider);
      final kind = _kind!;
      var n = 0;
      for (final fdi in widget.fdis) {
        final ok = await repo.add(
          patientId: widget.patientId,
          patientUuid: widget.patientUuid,
          fdi: fdi,
          kind: kind,
          status: _effStatus,
          surfaces: kind.bySurface ? _surfaces : const {},
          note: _note.text,
          by: _me(ref),
        );
        if (ok) n++;
      }
      await _afterChange(ref, widget.patientId, widget.fdis);
      if (!mounted) return;
      final what = kind.bySurface
          ? '${kind.label} ${surfaceNotation(_surfaces)}'
          : kind.label;
      setState(() {
        _flash = n == 0
            ? '$what is already recorded'
            : _single
            ? '$what added'
            : '$what added to $n teeth';
        _kind = null;
        _surfaces.clear();
        _note.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _flash = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final numbering = ref.watch(toothNumberingProvider);
    final all =
        ref.watch(toothFindingsProvider(widget.patientId)).value ??
        const <ToothFinding>[];
    final live = _single
        ? all.where((f) => f.fdi == _fdi && !f.isDeleted).toList()
        : const <ToothFinding>[];
    final gone = _single && isToothGone(live);
    final hist = _single
        ? _events(d, all.where((f) => f.fdi == _fdi))
        : const <_Event>[];

    Widget chip(ToothKind k) {
      final disabled = (!_single && k.bySurface) || (gone && k.bySurface);
      return _Chip(
        label: k.label,
        selected: _kind == k,
        enabled: !disabled,
        swatch: switch (k) {
          ToothKind.caries => d.warn,
          ToothKind.missing => d.text4,
          _ => null,
        },
        onTap: () => _pick(k),
      );
    }

    Widget group(String title, List<ToothKind> kinds) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Label(title),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final k in kinds) chip(k)],
            ),
          ),
        ],
      ),
    );

    final kind = _kind;

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _single
                        ? _Heading(
                            eyebrow: 'Tooth',
                            title: toothLabel(_fdi, numbering),
                            sub: toothName(_fdi),
                            mono: true,
                          )
                        : _Heading(
                            eyebrow: 'Chart several teeth',
                            title: '${widget.fdis.length} teeth',
                            sub: widget.fdis
                                .map((f) => toothLabel(f, numbering))
                                .join(' · '),
                          ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: d.text3),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: d.line),

            // ── body ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_single) ...[
                      _Label('On this tooth now'),
                      const SizedBox(height: 6),
                      _FindingsList(
                        patientId: widget.patientId,
                        fdi: _fdi,
                        live: live,
                      ),
                      const SizedBox(height: 18),
                    ],
                    _Label('Add'),
                    const SizedBox(height: 10),
                    group('Diagnosis', _diagnosis),
                    group('Treatment', _restorative),
                    group('Surgery', _surgical),
                    if (gone)
                      Text(
                        'This tooth is missing or extracted — surface conditions are off.',
                        style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                      ),
                    if (!_single)
                      Text(
                        'Fillings, sealants and caries are charted one tooth at a time.',
                        style: TextStyle(color: d.text4, fontSize: 8.5.sp),
                      ),

                    // ── surfaces ──
                    if (kind != null && kind.bySurface) ...[
                      const SizedBox(height: 8),
                      _Label('Surfaces — tap to select'),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _SurfacePicker(
                            fdi: _fdi,
                            selected: _surfaces,
                            color: statusColor(_effStatus, d),
                            onToggle: (s) => setState(() {
                              _surfaces.contains(s)
                                  ? _surfaces.remove(s)
                                  : _surfaces.add(s);
                            }),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _surfaces.isEmpty
                                      ? 'No surface selected'
                                      : '${kind.label} ${surfaceNotation(_surfaces)}',
                                  style: TextStyle(
                                    color: _surfaces.isEmpty
                                        ? d.text4
                                        : d.text1,
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final q in _quickSets(_fdi))
                                      _Chip(
                                        label: q,
                                        selected:
                                            surfaceNotation(_surfaces) == q,
                                        onTap: () => setState(() {
                                          _surfaces
                                            ..clear()
                                            ..addAll(q.split(''));
                                        }),
                                      ),
                                    _Chip(
                                      label: 'Clear',
                                      selected: false,
                                      onTap: () => setState(_surfaces.clear),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ── status ──
                    if (kind != null && kind.forcedStatus == null) ...[
                      const SizedBox(height: 16),
                      _Label('Record as'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (s, l) in const [
                            (FindingStatus.planned, 'Planned'),
                            (FindingStatus.done, 'Done today'),
                            (FindingStatus.existing, 'Existing'),
                          ])
                            _Chip(
                              label: l,
                              selected: _status == s,
                              swatch: statusColor(s, d),
                              onTap: () => setState(() => _status = s),
                            ),
                        ],
                      ),
                    ],

                    // ── note ──
                    if (kind != null) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _note,
                        style: TextStyle(color: d.text1, fontSize: 10.sp),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Note (optional)',
                          hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ],

                    if (_flash != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: d.ok,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _flash!,
                              style: TextStyle(
                                color: d.text2,
                                fontSize: 9.5.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ── history ──
                    if (_single) ...[
                      const SizedBox(height: 18),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            setState(() => _showHistory = !_showHistory),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              _Label(
                                'History · ${hist.length} entr${hist.length == 1 ? 'y' : 'ies'}',
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _showHistory
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 18,
                                color: d.text4,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showHistory) ...[
                        const SizedBox(height: 8),
                        _Timeline(
                          events: hist,
                          showTooth: false,
                          labelOf: (f) => toothLabel(f, numbering),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // ── footer ──
            Divider(height: 1, color: d.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      kind == null
                          ? 'Pick a condition to add'
                          : '${kind.label}'
                                '${kind.bySurface && _surfaces.isNotEmpty ? ' ${surfaceNotation(_surfaces)}' : ''}'
                                ' · ${_effStatus.label.toLowerCase()}',
                      style: TextStyle(color: d.text3, fontSize: 9.sp),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Done', style: TextStyle(color: d.text2)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      disabledBackgroundColor: d.line,
                      minimumSize: const Size(110, 42),
                    ),
                    onPressed: _canAdd ? _add : null,
                    child: Text(_busy ? 'Saving…' : 'Add'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One-tap surface combinations, in clinical notation.
  List<String> _quickSets(int fdi) => isPosteriorTooth(fdi)
      ? const ['O', 'MO', 'DO', 'MOD', 'B', 'L']
      : const ['I', 'M', 'D', 'B', 'L'];
}

// ── big tappable tooth face for picking surfaces ─────────────────────────────

class _SurfacePicker extends StatelessWidget {
  const _SurfacePicker({
    required this.fdi,
    required this.selected,
    required this.color,
    required this.onToggle,
  });
  final int fdi;
  final Set<String> selected;
  final Color color;
  final void Function(String letter) onToggle;

  static const double size = 150;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final g = _ToothGeometry(fdi);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) {
          // Map the tap back to the 36×36 crown box the chart uses.
          final p = e.localPosition * (36 / size);
          final region = _ToothGeometry.regionAt(p);
          onToggle(g.letter(region));
        },
        child: CustomPaint(
          size: const Size.square(size),
          painter: _SurfacePickerPainter(
            geometry: g,
            selected: selected,
            color: color,
            base: d.surface2,
            stroke: d.line2,
            text: d.text2,
          ),
        ),
      ),
    );
  }
}

class _SurfacePickerPainter extends CustomPainter {
  _SurfacePickerPainter({
    required this.geometry,
    required this.selected,
    required this.color,
    required this.base,
    required this.stroke,
    required this.text,
  });
  final _ToothGeometry geometry;
  final Set<String> selected;
  final Color color, base, stroke, text;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 36;
    canvas.save();
    canvas.scale(k);
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / k * 1.5
      ..color = stroke;
    final centers = <String, Offset>{};
    _ToothGeometry.facePaths().forEach((region, path) {
      final letter = geometry.letter(region);
      canvas.drawPath(
        path,
        fill..color = selected.contains(letter) ? color : base,
      );
      canvas.drawPath(path, line);
      centers[letter] = path.getBounds().center;
    });
    canvas.restore();

    for (final e in centers.entries) {
      final on = selected.contains(e.key);
      final tp = TextPainter(
        text: TextSpan(
          text: e.key,
          style: TextStyle(
            color: on ? Colors.white : text,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = e.value * k;
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _SurfacePickerPainter old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared pieces: findings list, timeline, headings, chips, buttons
// ═════════════════════════════════════════════════════════════════════════════

class _FindingsList extends ConsumerWidget {
  const _FindingsList({
    required this.patientId,
    required this.fdi,
    required this.live,
  });
  final int patientId;
  final int fdi;
  final List<ToothFinding> live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    if (live.isEmpty) {
      return Text(
        'Healthy — nothing recorded.',
        style: TextStyle(color: d.text3, fontSize: 9.5.sp),
      );
    }
    final repo = ref.read(toothChartRepositoryProvider);
    return Column(
      children: [
        for (final f in live)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: d.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: d.line),
            ),
            child: Row(
              children: [
                _Pill(status: f.status),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.surfacesUnknown
                            ? '${f.label} · surfaces not recorded'
                            : f.label,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_date(f.createdAt)} · ${f.createdBy.isEmpty ? '—' : f.createdBy}',
                        style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                      ),
                      if ((f.note ?? '').isNotEmpty)
                        Text(
                          f.note!,
                          style: TextStyle(color: d.text2, fontSize: 8.5.sp),
                        ),
                    ],
                  ),
                ),
                if (f.status == FindingStatus.planned)
                  IconButton(
                    tooltip: 'Mark done',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: d.ice,
                    ),
                    onPressed: () async {
                      await repo.markDone(f.id, by: _me(ref));
                      await _afterChange(ref, patientId, [fdi]);
                    },
                  ),
                IconButton(
                  tooltip: 'Note',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.sticky_note_2_outlined,
                    size: 17,
                    color: d.text4,
                  ),
                  onPressed: () async {
                    final note = await _askNote(
                      context,
                      d,
                      f,
                      toothLabel(f.fdi, ref.read(toothNumberingProvider)),
                    );
                    if (note == null) return;
                    await repo.setNote(f.id, note);
                    await _afterChange(ref, patientId, [fdi]);
                  },
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 17, color: d.text4),
                  onPressed: () async {
                    await repo.softDelete(f.id, by: _me(ref));
                    await _afterChange(ref, patientId, [fdi]);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _askNote(
    BuildContext context,
    DentColors d,
    ToothFinding f,
    String toothNo,
  ) {
    final c = TextEditingController(text: f.note ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Note · $toothNo ${f.label}'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. sensitive to cold, deep lesion',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
            ),
            onPressed: () => Navigator.pop(dialogCtx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

typedef _Event = ({DateTime at, int fdi, String text, String by, Color tone});

/// History is derived from the findings themselves: when each was created,
/// completed and removed. Nothing is overwritten, so nothing is lost.
List<_Event> _events(DentColors d, Iterable<ToothFinding> fs) {
  final out = <_Event>[];
  for (final f in fs) {
    final c = f.completedAt;
    final doneOnCreate =
        f.status == FindingStatus.done &&
        c != null &&
        c.difference(f.createdAt).inSeconds.abs() < 5;
    // A finding that is "done" now was "planned" when it was created,
    // unless it was recorded as done straight away.
    final createdStatus = doneOnCreate
        ? FindingStatus.done
        : (f.status == FindingStatus.done ? FindingStatus.planned : f.status);
    final createdAs = switch (createdStatus) {
      FindingStatus.found => 'found',
      FindingStatus.existing =>
        f.isImported ? 'imported from old chart' : 'recorded as existing',
      FindingStatus.planned => 'planned',
      FindingStatus.done => 'completed',
    };
    out.add((
      at: f.createdAt,
      fdi: f.fdi,
      text: '${f.label} $createdAs',
      by: f.createdBy,
      tone: statusColor(createdStatus, d),
    ));
    if (c != null && !doneOnCreate) {
      out.add((
        at: c,
        fdi: f.fdi,
        text: '${f.label} completed',
        by: f.completedBy ?? '',
        tone: statusColor(FindingStatus.done, d),
      ));
    }
    if (f.isDeleted && f.deletedAt != null) {
      out.add((
        at: f.deletedAt!,
        fdi: f.fdi,
        text: '${f.label} removed',
        by: f.deletedBy ?? '',
        tone: d.text4,
      ));
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.events,
    required this.showTooth,
    this.labelOf = _plainLabel,
  });
  final List<_Event> events;
  final bool showTooth;
  final String Function(int fdi) labelOf;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    if (events.isEmpty) {
      return Text(
        'No history yet.',
        style: TextStyle(color: d.text3, fontSize: 9.5.sp),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in events.take(40))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d.surface,
                    border: Border.all(color: e.tone, width: 3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showTooth ? '${labelOf(e.fdi)} · ${e.text}' : e.text,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_date(e.at)}${e.by.isEmpty ? '' : ' · ${e.by}'}',
                        style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.eyebrow,
    required this.title,
    required this.sub,
    this.mono = false,
  });
  final String eyebrow, title, sub;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(eyebrow),
        const SizedBox(height: 2),
        Text(
          title,
          style: mono
              ? AppTypography.mono(
                  size: 22,
                  color: d.text1,
                ).copyWith(fontWeight: FontWeight.w700)
              : TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: d.text1,
                ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            style: TextStyle(color: d.text3, fontSize: 9.5.sp),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: context.dent.text4,
      fontSize: 8.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .6,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.status});
  final FindingStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status, context.dent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 7.5.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: context.dent.ice,
      foregroundColor: AppPalette.onAccent,
      minimumSize: const Size.fromHeight(44),
    ),
    onPressed: onTap,
    child: Text(label),
  );
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: context.dent.text2,
      side: BorderSide(color: context.dent.line),
      minimumSize: const Size.fromHeight(42),
    ),
    onPressed: onTap,
    child: Text(label),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatch,
    this.enabled = true,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? swatch;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? d.ice.withValues(alpha: .12) : d.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? d.ice : d.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? d.text1 : d.text2,
                  fontSize: 9.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Geometry: the one place that knows where each surface is
// ═════════════════════════════════════════════════════════════════════════════

class _ToothGeometry {
  _ToothGeometry(this.fdi);
  final int fdi;

  bool get upper => isUpperTooth(fdi);

  /// Top of the crown box. Upper teeth have roots above the box, lower below.
  double get bo => upper ? 26 : 2;
  double ry(double y) => upper ? y : _kToothH - y;
  Rect get box => Rect.fromLTWH(2, bo, 36, 36);

  /// Region → surface letter, as seen from the front of the patient.
  /// Upper row: outside edge (top) is buccal. Lower row: outside (bottom).
  /// Mesial always faces the midline.
  String letter(String region) {
    final mesialRight = const [1, 4, 5, 8].contains(quadrantOf(fdi));
    return switch (region) {
      'top' => upper ? 'B' : 'L',
      'bottom' => upper ? 'L' : 'B',
      'left' => mesialRight ? 'D' : 'M',
      'right' => mesialRight ? 'M' : 'D',
      _ => isPosteriorTooth(fdi) ? 'O' : 'I',
    };
  }

  /// Region of a point inside a 36×36 crown box at (0,0).
  static String regionAt(Offset p) {
    const c = Offset(18, 18);
    if (Rect.fromCenter(center: c, width: 14, height: 14).contains(p)) {
      return 'center';
    }
    final dx = p.dx - c.dx, dy = p.dy - c.dy;
    if (dy.abs() >= dx.abs()) return dy < 0 ? 'top' : 'bottom';
    return dx < 0 ? 'left' : 'right';
  }

  /// The five surface shapes inside a 36×36 box at (0,0).
  static Map<String, Path> facePaths([Offset o = Offset.zero]) {
    Offset b(double x, double y) => Offset(o.dx + x, o.dy + y);
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);
    return {
      'top': poly([b(0, 0), b(36, 0), b(25, 11), b(11, 11)]),
      'bottom': poly([b(11, 25), b(25, 25), b(36, 36), b(0, 36)]),
      'left': poly([b(0, 0), b(11, 11), b(11, 25), b(0, 36)]),
      'right': poly([b(36, 0), b(36, 36), b(25, 25), b(25, 11)]),
      'center': Path()..addRect(Rect.fromLTWH(o.dx + 11, o.dy + 11, 14, 14)),
    };
  }

  Map<String, Path> surfaces() => facePaths(Offset(2, bo));

  /// Root outlines, plus neck/apex points for drawing a root canal line.
  List<({Path path, Offset neck, Offset apex})> roots() {
    final defs = isMultiRoot(fdi)
        ? const [
            [
              [8.0, 23.0],
              [19.0, 23.0],
              [16.0, 3.0],
              [11.0, 3.0],
            ],
            [
              [21.0, 23.0],
              [32.0, 23.0],
              [29.0, 3.0],
              [24.0, 3.0],
            ],
          ]
        : const [
            [
              [12.0, 23.0],
              [28.0, 23.0],
              [23.0, 2.0],
              [17.0, 2.0],
            ],
          ];
    return [
      for (final r in defs)
        (
          path: Path()
            ..addPolygon([for (final p in r) Offset(p[0], ry(p[1]))], true),
          neck: Offset((r[0][0] + r[1][0]) / 2, ry(22)),
          apex: Offset((r[2][0] + r[3][0]) / 2, ry(5)),
        ),
    ];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Painter for one tooth on the chart
// ═════════════════════════════════════════════════════════════════════════════

class _ToothPainter extends CustomPainter {
  _ToothPainter({
    required this.fdi,
    required this.live,
    required this.selected,
    required this.base,
    required this.stroke,
    required this.selection,
    required this.colorOf,
  });

  final int fdi;
  final List<ToothFinding> live;
  final bool selected;
  final Color base, stroke, selection;
  final Color Function(FindingStatus) colorOf;

  ToothFinding? _find(ToothKind k) {
    final m = live.where((f) => f.kind == k).toList()
      ..sort((a, b) => b.status.rank.compareTo(a.status.rank));
    return m.isEmpty ? null : m.first;
  }

  /// The status shown on one surface: the highest-ranked finding covering it.
  /// A crown, or an imported filling with unknown surfaces, covers them all.
  FindingStatus? _surfaceStatus(String letter) {
    FindingStatus? best;
    for (final f in live) {
      final covers =
          (f.kind.bySurface &&
              (f.surfaces.contains(letter) || f.surfacesUnknown)) ||
          f.kind == ToothKind.crown;
      if (covers && (best == null || f.status.rank > best.rank)) {
        best = f.status;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _ToothGeometry(fdi);
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = stroke;
    Paint pen(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;

    final implant = _find(ToothKind.implant);
    final gone = isToothGone(live) && implant == null;

    // ── body: roots + surfaces (faded when the tooth is gone) ──
    if (gone) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = const Color(0x47000000),
      );
    }

    if (implant != null) {
      final c = colorOf(implant.status);
      final top = g.upper ? 4.0 : _kToothH - 23;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(16, top, 8, 19),
          const Radius.circular(2),
        ),
        fill..color = c.withValues(alpha: .85),
      );
      for (var y = 7.0; y <= 20; y += 4) {
        canvas.drawLine(Offset(13, g.ry(y)), Offset(27, g.ry(y)), pen(c, 2));
      }
    } else {
      for (final r in g.roots()) {
        canvas.drawPath(r.path, fill..color = base);
        canvas.drawPath(r.path, line);
      }
    }

    g.surfaces().forEach((region, path) {
      final st = _surfaceStatus(g.letter(region));
      canvas.drawPath(path, fill..color = st == null ? base : colorOf(st));
      canvas.drawPath(path, line);
    });

    if (gone) canvas.restore();

    // ── overlays ──
    final rct = _find(ToothKind.rct);
    if (rct != null && implant == null) {
      for (final r in g.roots()) {
        canvas.drawLine(r.neck, r.apex, pen(colorOf(rct.status), 3));
      }
    }
    final crown = _find(ToothKind.crown);
    if (crown != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(g.box.inflate(1), const Radius.circular(5)),
        pen(colorOf(crown.status), 3.2),
      );
    }
    final bridge = _find(ToothKind.bridge);
    if (bridge != null) {
      final y = g.upper ? g.bo - 3 : g.bo + 39;
      canvas.drawLine(
        Offset(-3, y),
        Offset(43, y),
        pen(colorOf(bridge.status), 4),
      );
    }
    final missing = _find(ToothKind.missing);
    final ext = _find(ToothKind.extraction);
    if (missing != null || ext != null) {
      final c = colorOf(missing != null ? FindingStatus.existing : ext!.status);
      canvas.drawLine(const Offset(3, 3), const Offset(37, 70), pen(c, 3));
      canvas.drawLine(const Offset(37, 3), const Offset(3, 70), pen(c, 3));
    }
    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(g.box.inflate(3), const Radius.circular(6)),
        pen(selection, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ToothPainter old) => true;
}
