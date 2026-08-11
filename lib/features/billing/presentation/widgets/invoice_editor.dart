import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/patients/domain/treatment_plan.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../patients/domain/patient.dart';
import '../../../patients/presentation/patients_controller.dart';
import '../../../treatments/presentation/treatments_controller.dart';
import '../billing_controller.dart';

Future<bool?> showInvoiceEditor(
  BuildContext context, {
  int? patientId,
  String? procedure,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      InvoiceEditorDialog(patientId: patientId, procedure: procedure),
);

class InvoiceEditorDialog extends ConsumerStatefulWidget {
  const InvoiceEditorDialog({super.key, this.patientId, this.procedure});
  final int? patientId;
  final String? procedure;
  @override
  ConsumerState<InvoiceEditorDialog> createState() => _S();
}

class _Line {
  final desc = TextEditingController();
  final amt = TextEditingController();
  void dispose() {
    desc.dispose();
    amt.dispose();
  }
}

class _S extends ConsumerState<InvoiceEditorDialog> {
  late final TextEditingController _no;
  late final TextEditingController _adjustment;
  final List<_Line> _lines = [_Line()];
  int? _patientId;
  String _status = 'pending';
  bool _busy = false;
  String? _error;
  int? _selectedPlanId; // which plan is shown in the bill

  @override
  void initState() {
    super.initState();
    _no = TextEditingController(text: 'INV-${1000 + Random().nextInt(9000)}');
    _adjustment = TextEditingController(text: '0');
    _patientId = widget.patientId;

    _lines.clear();

    // Consultation fee — prefer the catalog price, else fall back to code.
    final prices = ref.read(procedurePriceProvider);
    final consultFee = _lookupConsultationFee(prices) ?? _kFallbackConsultFee;
    final consult = _Line();
    consult.desc.text = 'Consultation Fee';
    consult.amt.text = '$consultFee';
    _lines.add(consult);

    // If billed from an appointment, add the procedure as its own line
    final proc = widget.procedure?.trim();
    if (proc != null && proc.isNotEmpty) {
      final line = _Line();
      line.desc.text = proc;
      final price = prices[proc];
      if (price != null) line.amt.text = '$price';
      _lines.add(line);
    }
  }

  /// Fallback if no consultation entry exists in the Treatments catalog.
  static const int _kFallbackConsultFee = 2000;

  /// Finds a "consultation" priced item in the catalog, case-insensitive.
  int? _lookupConsultationFee(Map<String, int> prices) {
    for (final entry in prices.entries) {
      if (entry.key.toLowerCase().contains('consult')) return entry.value;
    }
    return null;
  }

  @override
  void dispose() {
    _no.dispose();
    _adjustment.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _subtotal {
    var sum = 0;
    for (final l in _lines) {
      sum += int.tryParse(l.amt.text.trim()) ?? 0;
    }
    return sum;
  }

  int get _adj => int.tryParse(_adjustment.text.trim()) ?? 0;
  int get _total => _subtotal - _adj;

  Future<void> _addFromCatalog() async {
    final treatments = ref.read(treatmentsStreamProvider).value ?? const [];
    if (treatments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No procedures in the catalog yet.')),
      );
      return;
    }
    final d = context.dent;
    final picked = await showDialog<({String name, int price})>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: d.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Add from Catalog',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: treatments.length,
                  itemBuilder: (_, i) {
                    final t = treatments[i];
                    return ListTile(
                      title: Text(
                        t.name,
                        style: TextStyle(fontSize: 9.5.sp, color: d.text1),
                      ),
                      subtitle: Text(
                        t.category,
                        style: TextStyle(fontSize: 8.sp, color: d.text3),
                      ),
                      trailing: Text(
                        'Rs ${t.price}',
                        style: AppTypography.mono(size: 9.sp, color: d.text1),
                      ),
                      onTap: () =>
                          Navigator.pop(ctx, (name: t.name, price: t.price)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        // reuse the first empty line, else add a new one
        final target = _lines.firstWhere(
          (l) => l.desc.text.trim().isEmpty,
          orElse: () {
            final line = _Line();
            _lines.add(line);
            return line;
          },
        );
        target.desc.text = picked.name;
        target.amt.text = '${picked.price}';
      });
    }
  }

  Future<void> _save() async {
    if (_patientId == null) {
      setState(() => _error = 'Select a patient.');
      return;
    }
    final items = <({String description, int amount})>[];
    for (final l in _lines) {
      final desc = l.desc.text.trim();
      final amt = int.tryParse(l.amt.text.trim()) ?? 0;
      if (desc.isEmpty && amt == 0) continue;
      items.add((description: desc, amount: amt));
    }
    if (items.isEmpty) {
      setState(() => _error = 'Add at least one line item.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(billingRepositoryProvider)
          .createInvoice(
            patientId: _patientId!,
            invoiceNo: _no.text.trim(),
            issuedAt: DateTime.now(),
            status: _status,
            summary: items.first.description,
            adjustment: _adj,
            items: items,
          );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not save: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final patients =
        ref.watch(patientsStreamProvider).value ?? const <Patient>[];

    final plans = _patientId == null
        ? const <TreatmentPlan>[]
        : (ref.watch(plansProvider(_patientId!)).value ??
              const <TreatmentPlan>[]);
    // auto-select first active plan
    if (_selectedPlanId == null && plans.isNotEmpty) {
      final active = plans.firstWhere(
        (p) => p.isActive,
        orElse: () => plans.first,
      );
      _selectedPlanId = active.id;
    }
    final selectedPlan = plans
        .where((p) => p.id == _selectedPlanId)
        .firstOrNull;

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 62.w, maxHeight: 84.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'New Invoice',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 12.sp,
                      color: d.text3,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Patient ──
                    _label(d, 'Patient'),
                    _box(
                      d,
                      DropdownButton<int>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        value: _patientId,
                        hint: Text(
                          'Select patient',
                          style: TextStyle(fontSize: 9.sp, color: d.text4),
                        ),
                        items: [
                          for (final p in patients)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.fullName,
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: d.text1,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _patientId = v),
                      ),
                    ),

                    // ── Treatment Plan (if any) ──
                    if (plans.isNotEmpty) ...[
                      _label(d, 'Treatment Plan'),
                      if (plans.length > 1)
                        _box(
                          d,
                          DropdownButton<int>(
                            isExpanded: true,
                            underline: const SizedBox(),
                            value: _selectedPlanId,
                            items: [
                              for (final p in plans)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    '${p.title}${p.isActive ? '' : ' (done)'}',
                                    style: TextStyle(
                                      fontSize: 9.sp,
                                      color: d.text1,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedPlanId = v),
                          ),
                        ),
                      if (selectedPlan != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: d.surface2,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: d.line),
                          ),
                          child: Column(
                            children: [
                              for (final s in selectedPlan.steps)
                                _billStep(d, s),
                            ],
                          ),
                        ),
                    ],

                    // ── Invoice No + Status ──
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(d, 'Invoice No.'),
                              _box(
                                d,
                                TextField(
                                  controller: _no,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(d, 'Status'),
                              _box(
                                d,
                                DropdownButton<String>(
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  value: _status,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'pending',
                                      child: Text('Pending'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'paid',
                                      child: Text('Paid'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'overdue',
                                      child: Text('Overdue'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _status = v!),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Line items ──
                    _label(d, 'Line items'),
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _box(
                                d,
                                TextField(
                                  controller: _lines[i].desc,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: 'Description',
                                    hintStyle: TextStyle(
                                      color: d.text4,
                                      fontSize: 9.sp,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: _box(
                                d,
                                TextField(
                                  controller: _lines[i].amt,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: d.text1,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: 'Rs',
                                    hintStyle: TextStyle(
                                      color: d.text4,
                                      fontSize: 9.sp,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_lines.length > 1)
                              IconButton(
                                icon: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  size: 18,
                                  color: d.text4,
                                ),
                                onPressed: () => setState(() {
                                  _lines[i].dispose();
                                  _lines.removeAt(i);
                                }),
                              ),
                          ],
                        ),
                      ),

                    // ── Add buttons ──
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _addFromCatalog,
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 16,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: d.ice,
                            side: BorderSide(color: d.line),
                          ),
                          label: const Text('Add from catalog'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _lines.add(_Line())),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: d.text2,
                            side: BorderSide(color: d.line),
                          ),
                          label: const Text('Add line'),
                        ),
                      ],
                    ),

                    // ── Adjustment ──
                    _label(d, 'Adjustment (Rs)'),
                    _box(
                      d,
                      TextField(
                        controller: _adjustment,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 9.sp, color: d.text1),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),

                    // ── Totals ──
                    const SizedBox(height: 14),
                    _totalRow(d, 'Subtotal', _subtotal),
                    if (_adj != 0) _totalRow(d, 'Adjustment', -_adj),
                    const SizedBox(height: 4),
                    _totalRow(d, 'Total', _total, bold: true),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _error!,
                          style: TextStyle(color: d.alert, fontSize: 8.5.sp),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Save ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 17),
                label: const Text('Save Invoice'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: 10.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _billStep(DentColors d, TreatmentStep s) {
    final isDone = s.status == StepStatus.done;
    final isCurrent = s.status == StepStatus.current;
    final color = isDone ? d.teal : (isCurrent ? d.ice : d.text4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s.completedAt != null)
                  Text(
                    '✓ ${_fmtBillDate(s.completedAt!)}',
                    style: TextStyle(color: d.teal, fontSize: 9.sp),
                  ),
              ],
            ),
          ),
          if (isDone)
            Text(
              'DONE',
              style: TextStyle(
                color: d.teal,
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            // add procedure to the invoice
            TextButton(
              onPressed: () => _addStepToInvoice(s),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                '+ Bill',
                style: TextStyle(fontSize: 9.5.sp, color: d.text3),
              ),
            ),
            // mark done
            TextButton(
              onPressed: () async {
                await ref
                    .read(patientRepositoryProvider)
                    .setStepStatus(s.id, StepStatus.done);
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: d.ice.withValues(alpha: .12),
              ),
              child: Text(
                'Mark done',
                style: TextStyle(
                  fontSize: 9.5.sp,
                  color: d.ice,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addStepToInvoice(TreatmentStep s) {
    final prices = ref.read(procedurePriceProvider);
    // match a catalog price by step label if possible
    int? price;
    for (final e in prices.entries) {
      if (s.label.toLowerCase().contains(e.key.toLowerCase()) ||
          e.key.toLowerCase().contains(s.label.toLowerCase())) {
        price = e.value;
        break;
      }
    }
    setState(() {
      final target = _lines.firstWhere(
        (l) => l.desc.text.trim().isEmpty,
        orElse: () {
          final line = _Line();
          _lines.add(line);
          return line;
        },
      );
      target.desc.text = s.label;
      if (price != null) target.amt.text = '$price';
    });
  }

  String _fmtBillDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  Widget _box(DentColors d, Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: child,
  );

  Widget _totalRow(DentColors d, String label, int value, {bool bold = false}) {
    final m = value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (x) => '${x[1]},',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: bold ? d.text1 : d.text3,
              fontSize: bold ? 10.sp : 9.sp,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            'Rs $m',
            style: AppTypography.mono(
              size: bold ? 10.sp : 9.sp,
              color: d.text1,
              weight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
