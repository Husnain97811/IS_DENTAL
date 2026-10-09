import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';

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
  final _received = TextEditingController();
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final no = await ref.read(appDatabaseProvider).nextInvoiceNo();
      if (mounted) setState(() => _no.text = no);
    });
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
    _received.dispose();
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

    // Ensure the invoice number is still unique (regenerate if taken).
    final db = ref.read(appDatabaseProvider);
    var invNo = _no.text.trim();
    if (invNo.isEmpty || invNo == '…' || await db.invoiceNoExists(invNo)) {
      invNo = await db.nextInvoiceNo();
      _no.text = invNo;
    }

    try {
      // Always create as pending — the payment below is what moves it to
      // paid, so amountPaid, the status and the patient's balance can
      // never disagree.
      await ref
          .read(billingRepositoryProvider)
          .createInvoice(
            patientId: _patientId!,
            invoiceNo: invNo,
            issuedAt: DateTime.now(),
            status: _status == 'overdue' ? 'overdue' : 'pending',
            summary: items.first.description,
            adjustment: _adj,
            items: items,
          );

      if (_status != 'pending') {
        final typed = int.tryParse(_received.text.trim()) ?? 0;
        // Blank on "paid" means the whole thing.
        final amount = _status == 'paid' && typed == 0 ? _total : typed;
        if (amount > 0) {
          final inv = await (db.select(
            db.invoices,
          )..where((t) => t.invoiceNo.equals(invNo))).getSingleOrNull();
          if (inv != null) {
            await db.insertPayment(
              invoiceId: inv.id,
              amount: amount > _total ? _total : amount,
              paidAt: DateTime.now(),
              receivedByName: ref.read(authControllerProvider)?.username ?? '',
              note: 'Recorded when the invoice was created',
            );
          }
        }
      }
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
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 13.sp),
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
                    _patientPicker(d, patients),

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
                                      fontSize: 12.sp,
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
                                  readOnly: true,

                                  controller: _no,
                                  style: TextStyle(
                                    fontSize: 12.sp,
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

                    // Paid/overdue must record an ACTUAL amount — otherwise
                    // the status says paid while the balance says the full
                    // total, because nothing was ever received.
                    if (_status != 'pending') ...[
                      _label(
                        d,
                        _status == 'paid'
                            ? 'Amount received now'
                            : 'Amount received so far',
                      ),
                      _box(
                        d,
                        TextField(
                          controller: _received,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(fontSize: 12.sp, color: d.text1),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            prefixText: 'Rs  ',
                            hintText: _status == 'paid'
                                ? 'Leave blank if patient pays the full Amount'
                                : '0',
                            hintStyle: TextStyle(
                              color: d.text4,
                              fontSize: 11.sp,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _status == 'paid'
                              ? 'Recorded as a cash payment dated today. '
                                    'Change the method later from the invoice.'
                              : 'Anything already collected. The rest stays '
                                    'on the patient\'s balance.',
                          style: TextStyle(color: d.text3, fontSize: 10.sp),
                        ),
                      ),
                    ],

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
                                    fontSize: 12.sp,
                                    color: d.text1,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: 'Description',
                                    hintStyle: TextStyle(
                                      color: d.text4,
                                      fontSize: 12.sp,
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
                                    fontSize: 12.sp,
                                    color: d.text1,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: 'Rs',
                                    hintStyle: TextStyle(
                                      color: d.text4,
                                      fontSize: 12.sp,
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
                        style: TextStyle(fontSize: 12.sp, color: d.text1),
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

  /// A dropdown over a thousand patients is unusable — this searches
  /// name, code and phone, and shows the outstanding balance so the
  /// receptionist sees what the patient already owes before billing.
  Widget _patientPicker(DentColors d, List<Patient> patients) {
    final selected = _patientId == null
        ? null
        : patients.where((p) => p.id == _patientId).firstOrNull;

    if (selected != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.fullName,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      '#${selected.code}',
                      if (selected.phone.isNotEmpty) selected.phone,
                      if (selected.balance > 0)
                        'Balance: ${_money(selected.balance)}',
                    ].join(' · '),
                    style: TextStyle(
                      color: selected.balance > 0 ? d.alert : d.text4,
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Change patient',
              icon: Icon(Icons.close_rounded, size: 17, color: d.text4),
              onPressed: () => setState(() {
                _patientId = null;
                _selectedPlanId = null;
              }),
            ),
          ],
        ),
      );
    }

    return Autocomplete<Patient>(
      displayStringForOption: (p) => p.fullName,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return patients.take(8);
        return patients
            .where(
              (p) => '${p.fullName} ${p.code} ${p.phone}'
                  .toLowerCase()
                  .contains(q),
            )
            .take(12);
      },
      onSelected: (p) => setState(() {
        _patientId = p.id;
        _selectedPlanId = null;
        _error = null;
      }),
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => _box(
        d,
        TextField(
          controller: ctrl,
          focusNode: focus,
          autofocus: widget.patientId == null,
          style: TextStyle(fontSize: 12.sp, color: d.text1),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: 'Search name, code or phone…',
            hintStyle: TextStyle(color: d.text4, fontSize: 11.sp),
            icon: Icon(Icons.search_rounded, size: 17, color: d.text4),
          ),
        ),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 46.w,
            constraints: const BoxConstraints(maxHeight: 280),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: d.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: d.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .14),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final p in options)
                  InkWell(
                    onTap: () => onSelected(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.fullName,
                                  style: TextStyle(
                                    color: d.text1,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '#${p.code}${p.phone.isEmpty ? "" : " · ${p.phone}"}',
                                  style: TextStyle(
                                    color: d.text4,
                                    fontSize: 10.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (p.balance > 0)
                            Text(
                              'Rs ${_money(p.balance)}',
                              style: AppTypography.mono(
                                size: 10.sp,
                                color: d.alert,
                              ),
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
    );
  }

  String _money(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text2,
        fontSize: 10.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _billStep(DentColors d, TreatmentStep s) {
    // completedAt is set by the Complete action; status alone can lag behind
    // it if a step was completed on another machine before syncing.
    final isDone = s.status == StepStatus.done || s.completedAt != null;
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
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s.completedAt != null)
                  Text(
                    '✓ ${_fmtBillDate(s.completedAt!)}',
                    style: TextStyle(color: d.teal, fontSize: 12.sp),
                  ),
              ],
            ),
          ),
          if (isDone)
            Text(
              'DONE',
              style: TextStyle(
                color: d.teal,
                fontSize: 10.sp,
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
                style: TextStyle(fontSize: 10.5.sp, color: d.text3),
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
              fontSize: bold ? 12.sp : 9.sp,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            'Rs $m',
            style: AppTypography.mono(
              size: bold ? 12.sp : 9.sp,
              color: d.text1,
              weight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
