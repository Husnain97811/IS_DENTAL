import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/constants/views.dart';
import 'prescription_controller.dart';
import 'widgets/medicine_editor.dart';
import 'widgets/precaution_set_editor.dart';

class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});
  @override
  ConsumerState<PrescriptionsScreen> createState() => _S();
}

class _S extends ConsumerState<PrescriptionsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    final canFormat =
        session?.role == AppRole.owner || session?.role == AppRole.admin;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text(
          //   'Prescriptions',
          //   style: Theme.of(context).textTheme.displayLarge,
          // ),
          // const SizedBox(height: 4),
          // Text(
          //   'Medicines catalog, Urdu precaution templates and print format.',
          //   style: TextStyle(color: d.text3, fontSize: 10.5.sp),
          // ),
          SegmentedControl(
            items: canFormat
                ? const ['Medicines', 'Precautions', 'Print Format']
                : const ['Medicines', 'Precautions'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          SizedBox(height: 2.2.h),

          if (_tab == 0) _MedicinesTab(),
          if (_tab == 1) _PrecautionsTab(),
          if (_tab == 2 && canFormat) _FormatTab(),
        ],
      ),
    );
  }
}

// ─────────── MEDICINES ───────────
class _MedicinesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final meds = ref.watch(medicinesProvider).value ?? const <Medicine>[];

    return DentPanel(
      title: 'Medicines Catalog',
      subtitle: '${meds.length} medicines · picked from when prescribing',
      trailing: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: d.ice,
          foregroundColor: AppPalette.onAccent,
          minimumSize: const Size(0, 40),
        ),
        onPressed: () => showMedicineEditor(context),
        icon: const Icon(Icons.add_rounded, size: 17),
        label: Text('Add Medicine', style: TextStyle(fontSize: 10.sp)),
      ),
      child: meds.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                child: Text(
                  'No medicines yet.',
                  style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                ),
              ),
            )
          : Column(
              children: [
                for (final m in meds)
                  InkWell(
                    onTap: () => showMedicineEditor(context, existing: m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: d.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              m.name,
                              style: TextStyle(
                                color: d.text1,
                                fontSize: 11.5.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              m.form,
                              style: TextStyle(
                                color: d.text2,
                                fontSize: 10.5.sp,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              m.defaultDosage,
                              style: TextStyle(
                                color: d.text2,
                                fontSize: 10.5.sp,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              m.defaultFrequency,
                              style: TextStyle(
                                color: d.text2,
                                fontSize: 10.5.sp,
                              ),
                            ),
                          ),
                          if (m.category.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: d.ice.withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                m.category,
                                style: TextStyle(
                                  color: d.ice,
                                  fontSize: 8.5.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 17,
                              color: d.text4,
                            ),
                            onPressed: () async {
                              final ok = await showDentDialog(
                                context,
                                kind: DentDialogKind.warning,
                                title: 'Delete medicine?',
                                message:
                                    'Remove "${m.name}" from the catalog. '
                                    'Existing prescriptions are not affected.',
                                confirmLabel: 'Delete',
                                cancelLabel: 'Cancel',
                              );
                              if (ok == true) {
                                await ref
                                    .read(prescriptionRepositoryProvider)
                                    .deleteMedicine(m.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─────────── PRECAUTIONS ───────────
class _PrecautionsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final sets =
        ref.watch(precautionSetsProvider).value ?? const <PrecautionSet>[];

    return Column(
      children: [
        DentPanel(
          title: 'Precaution Templates',
          subtitle: 'Aftercare lines in Urdu & English, grouped by procedure',
          trailing: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: d.ice,
              foregroundColor: AppPalette.onAccent,
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => showPrecautionSetEditor(context),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text('New Set', style: TextStyle(fontSize: 10.sp)),
          ),
          child: sets.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                    child: Text(
                      'No precaution sets yet.',
                      style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final s in sets)
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: d.line)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: TextStyle(
                                      color: d.text1,
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${s.lines.length} lines',
                                  style: TextStyle(
                                    color: d.text4,
                                    fontSize: 9.5.sp,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 17,
                                    color: d.text3,
                                  ),
                                  onPressed: () => showPrecautionSetEditor(
                                    context,
                                    existing: s,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 17,
                                    color: d.text4,
                                  ),
                                  onPressed: () async {
                                    final ok = await showDentDialog(
                                      context,
                                      kind: DentDialogKind.warning,
                                      title: 'Delete set?',
                                      message:
                                          'Remove "${s.name}" and its lines.',
                                      confirmLabel: 'Delete',
                                      cancelLabel: 'Cancel',
                                    );
                                    if (ok == true) {
                                      await ref
                                          .read(prescriptionRepositoryProvider)
                                          .deleteSet(s.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final l in s.lines)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l.english,
                                        style: TextStyle(
                                          color: d.text3,
                                          fontSize: 9.5.sp,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        l.urdu,
                                        textAlign: TextAlign.right,
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          fontFamily: 'NotoNaskhArabic',
                                          color: d.text1,
                                          fontSize: 11.sp,
                                          height: 1.9,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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

// ─────────── PRINT FORMAT ───────────
class _FormatTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FormatTab> createState() => _FormatTabState();
}

class _FormatTabState extends ConsumerState<_FormatTab> {
  final _rxStart = TextEditingController();
  final _rxPrefix = TextEditingController();
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    _rxStart.text = (await db.rxStartNo()).toString();
    _rxPrefix.text = await db.rxPrefix();
    _preview = await db.nextRxNo();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _rxStart.dispose();
    _rxPrefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return DentPanel(
      title: 'Prescription Numbering',
      subtitle:
          'Set where Rx numbers begin — useful when moving from a paper book',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 110, child: _field(d, 'Prefix', _rxPrefix)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: _field(d, 'Start number', _rxStart),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: Text(
                      'Next prescription:  $_preview',
                      style: TextStyle(
                        color: d.text2,
                        fontSize: 10.5.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'If numbering has already begun, the next number continues from '
              'the highest issued — unless the start you set here is higher, '
              'in which case it jumps forward to it.',
              style: TextStyle(color: d.text4, fontSize: 9.5.sp),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                onPressed: () async {
                  final db = ref.read(appDatabaseProvider);
                  await db.setRxStartNo(int.tryParse(_rxStart.text) ?? 1);
                  await db.setRxPrefix(
                    _rxPrefix.text.trim().isEmpty
                        ? 'RX-'
                        : _rxPrefix.text.trim(),
                  );
                  await _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Numbering saved.')),
                    );
                  }
                },
                child: Text('Save', style: TextStyle(fontSize: 10.5.sp)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(DentColors d, String label, TextEditingController c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: d.text4,
          fontSize: 8.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 42,
        child: TextField(
          controller: c,
          style: TextStyle(fontSize: 10.5.sp, color: d.text1),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: d.surface2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: d.line),
            ),
          ),
        ),
      ),
    ],
  );
}
