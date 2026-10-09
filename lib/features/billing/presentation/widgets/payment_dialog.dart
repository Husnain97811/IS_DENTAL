import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/db/lookup_providers.dart';
import '../../../../core/constants/views.dart';
import '../../data/payment_repository.dart';
import '../../domain/invoice.dart';

String _m(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

Future<void> showPaymentDialog(BuildContext context, Invoice inv) => showDialog(
  context: context,
  builder: (_) => _PaymentDialog(inv: inv),
);

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({required this.inv});
  final Invoice inv;
  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  late final TextEditingController _amount;
  final _detail = TextEditingController();
  final _ref = TextEditingController();
  final _note = TextEditingController();
  DateTime _paidAt = DateTime.now();
  String _method = 'Cash';
  bool _saving = false;
  String? _error;

  int get _balance => widget.inv.balance;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _balance > 0 ? '$_balance' : '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _detail.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext dialogCtx) async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    if (amount > _balance) {
      setState(() => _error = 'More than the balance of Rs ${_m(_balance)}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final who = ref.read(authControllerProvider)?.username ?? '';
      await ref
          .read(paymentRepositoryProvider)
          .add(
            invoiceId: widget.inv.id,
            amount: amount,
            paidAt: _paidAt,
            method: _method,
            methodDetail: _detail.text.trim().isEmpty
                ? null
                : _detail.text.trim(),
            reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
            note: _note.text.trim(),
            by: who,
          );
      syncInBackground(ref);
      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext dialogCtx) {
    final d = dialogCtx.dent;
    final methods = ref.watch(paymentMethodsProvider).value ?? const [];
    final names = methods.isEmpty
        ? const ['Cash', 'Bank Transfer', 'Card', 'JazzCash', 'EasyPaisa']
        : methods.map((m) => m.name).toList();
    if (!names.contains(_method)) _method = names.first;

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Take Payment',
                style: Theme.of(dialogCtx).textTheme.headlineSmall?.copyWith(
                  color: d.text1,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '#${widget.inv.invoiceNo} · ${widget.inv.patientName} · '
                'balance Rs ${_m(_balance)}',
                style: TextStyle(color: d.text3, fontSize: 11.sp),
              ),
              SizedBox(height: 2.h),

              _label(d, 'AMOUNT RECEIVED'),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  color: d.text1,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _dec(d, prefix: 'Rs  '),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _quick(d, 'Full balance', _balance),
                    if (_balance >= 2) _quick(d, 'Half', _balance ~/ 2),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _label(d, 'DATE RECEIVED'),
              InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogCtx,
                    initialDate: _paidAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _paidAt = picked);
                },
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: d.line),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_paidAt.day}/${_paidAt.month}/${_paidAt.year}',
                        style: TextStyle(color: d.text1, fontSize: 12.sp),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: d.text2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _label(d, 'METHOD'),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: d.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: d.line),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _method,
                    isExpanded: true,
                    dropdownColor: d.surface,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final n in names)
                        DropdownMenuItem(
                          value: n,
                          child: Text(
                            n,
                            style: TextStyle(color: d.text1, fontSize: 12.sp),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? _method),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _label(d, 'BANK / ACCOUNT (OPTIONAL)'),
              TextField(
                controller: _detail,
                style: TextStyle(color: d.text1, fontSize: 12.sp),
                decoration: _dec(d, hint: 'Meezan, HBL, wallet number…'),
              ),
              const SizedBox(height: 14),

              _label(d, 'TRANSACTION ID / TID (OPTIONAL)'),
              TextField(
                controller: _ref,
                style: TextStyle(color: d.text1, fontSize: 12.sp),
                decoration: _dec(d, hint: 'TID, cheque no, slip no'),
              ),
              const SizedBox(height: 14),

              _label(d, 'NOTE (OPTIONAL)'),
              TextField(
                controller: _note,
                style: TextStyle(color: d.text1, fontSize: 12.sp),
                decoration: _dec(d, hint: 'Partial payment, rest next visit…'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: d.alert, fontSize: 12.sp),
                ),
              ],

              SizedBox(height: 2.4.h),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(dialogCtx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(140, 44),
                    ),
                    onPressed: _saving ? null : () => _save(dialogCtx),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Record Payment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quick(DentColors d, String label, int value) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => setState(() => _amount.text = '$value'),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: d.line),
      ),
      child: Text(
        '$label · Rs ${_m(value)}',
        style: TextStyle(color: d.text3, fontSize: 10.sp),
      ),
    ),
  );

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: TextStyle(
        color: d.text2,
        fontSize: 10.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  InputDecoration _dec(DentColors d, {String? hint, String? prefix}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        hintStyle: TextStyle(color: d.text4, fontSize: 10.5.sp),
        filled: true,
        fillColor: d.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.ice),
        ),
      );
}
