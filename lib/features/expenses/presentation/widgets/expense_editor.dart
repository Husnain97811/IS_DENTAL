import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/db/lookup_providers.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/expense_repository.dart';

Future<void> showExpenseEditor(BuildContext context, {ExpenseRow? existing}) =>
    showDialog(
      context: context,
      builder: (_) => _ExpenseEditor(existing: existing),
    );

class _ExpenseEditor extends ConsumerStatefulWidget {
  const _ExpenseEditor({this.existing});
  final ExpenseRow? existing;
  @override
  ConsumerState<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends ConsumerState<_ExpenseEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _desc;
  late final TextEditingController _vendor;
  late final TextEditingController _detail;
  late final TextEditingController _ref;

  late DateTime _paidAt;
  String? _categoryUuid;
  String _method = 'Cash';
  String? _branchId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : '${e.amount}');
    _desc = TextEditingController(text: e?.description ?? '');
    _vendor = TextEditingController(text: e?.vendor ?? '');
    _detail = TextEditingController(text: e?.methodDetail ?? '');
    _ref = TextEditingController(text: e?.reference ?? '');
    _paidAt = e?.paidAt ?? DateTime.now();
    _categoryUuid = (e?.categoryUuid.isEmpty ?? true) ? null : e!.categoryUuid;
    _method = e?.method ?? 'Cash';
    _branchId = e?.branchId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _vendor.dispose();
    _detail.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext dialogCtx) async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    if (_categoryUuid == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    if ((_branchId ?? '').isEmpty) {
      setState(() => _error = 'Pick a branch.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final who = ref.read(authControllerProvider)?.username ?? '';
      if (_isEdit) {
        await repo.edit(
          id: widget.existing!.id,
          branchId: _branchId!,
          categoryUuid: _categoryUuid!,
          amount: amount,
          paidAt: _paidAt,
          description: _desc.text.trim(),
          vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
          method: _method,
          methodDetail: _detail.text.trim().isEmpty
              ? null
              : _detail.text.trim(),
          reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          by: who,
        );
      } else {
        await repo.create(
          branchId: _branchId!,
          categoryUuid: _categoryUuid!,
          amount: amount,
          paidAt: _paidAt,
          description: _desc.text.trim(),
          vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
          method: _method,
          methodDetail: _detail.text.trim().isEmpty
              ? null
              : _detail.text.trim(),
          reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          by: who,
        );
      }
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
    final session = ref.watch(authControllerProvider);
    final lockedBranch = session?.branchId;
    final branches =
        ref.watch(branchesStreamProvider).value ?? const <Branch>[];
    final cats = ref.watch(expenseCategoriesProvider).value ?? const [];
    final methods = ref.watch(paymentMethodsProvider).value ?? const [];
    final methodNames = methods.isEmpty
        ? const ['Cash', 'Bank Transfer', 'Card', 'JazzCash', 'EasyPaisa']
        : methods.map((m) => m.name).toList();
    if (!methodNames.contains(_method)) _method = methodNames.first;

    // Staff are locked to their own branch; the owner picks one explicitly
    // rather than silently inheriting "All branches".
    _branchId ??=
        lockedBranch ??
        ref.read(activeBranchProvider) ??
        (branches.isNotEmpty ? branches.first.uuid : null);

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'Edit Expense' : 'New Expense',
                style: Theme.of(dialogCtx).textTheme.headlineSmall,
              ),
              SizedBox(height: 2.h),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(d, 'AMOUNT'),
                        TextField(
                          controller: _amount,
                          autofocus: !_isEdit,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _dec(d, prefix: 'Rs  '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(d, 'DATE PAID'),
                        _box(
                          d,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogCtx,
                              initialDate: _paidAt,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _paidAt = picked);
                            }
                          },
                          child: Row(
                            children: [
                              Text(
                                '${_paidAt.day}/${_paidAt.month}/${_paidAt.year}',
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.sp,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 15,
                                color: d.text4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _label(d, 'CATEGORY'),
              _dropdown<String>(
                d,
                value: _categoryUuid,
                hint: 'Pick a category',
                items: [for (final c in cats) (c.uuid, c.name)],
                onChanged: (v) => setState(() => _categoryUuid = v),
              ),
              const SizedBox(height: 14),

              _label(d, 'BRANCH'),
              if (lockedBranch != null)
                _box(
                  d,
                  child: Row(
                    children: [
                      Text(
                        branches
                                .where((b) => b.uuid == lockedBranch)
                                .map((b) => b.name)
                                .firstOrNull ??
                            'Your branch',
                        style: TextStyle(color: d.text3, fontSize: 10.sp),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: d.text4,
                      ),
                    ],
                  ),
                )
              else
                _dropdown<String>(
                  d,
                  value: _branchId,
                  hint: 'Pick a branch',
                  items: [for (final b in branches) (b.uuid, b.name)],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
              const SizedBox(height: 14),

              _label(d, 'DESCRIPTION'),
              TextField(
                controller: _desc,
                style: TextStyle(color: d.text1, fontSize: 10.sp),
                decoration: _dec(d, hint: 'October rent, lab bill, salaries…'),
              ),
              const SizedBox(height: 14),

              _label(d, 'PAID TO (OPTIONAL)'),
              TextField(
                controller: _vendor,
                style: TextStyle(color: d.text1, fontSize: 10.sp),
                decoration: _dec(d, hint: 'Vendor, lab or landlord'),
              ),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(d, 'METHOD'),
                        _dropdown<String>(
                          d,
                          value: _method,
                          items: [for (final n in methodNames) (n, n)],
                          onChanged: (v) =>
                              setState(() => _method = v ?? _method),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(d, 'BANK ACCOUNT'),
                        TextField(
                          controller: _detail,
                          style: TextStyle(color: d.text1, fontSize: 10.sp),
                          decoration: _dec(d, hint: 'Optional'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _label(d, 'TRANSACTION ID / TID (OPTIONAL)'),
              TextField(
                controller: _ref,
                style: TextStyle(color: d.text1, fontSize: 10.sp),
                decoration: _dec(d, hint: 'TID, cheque no, bill no'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: d.alert, fontSize: 9.sp),
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
                      minimumSize: const Size(150, 44),
                    ),
                    onPressed: _saving ? null : () => _save(dialogCtx),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEdit ? 'Save Changes' : 'Add Expense'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(DentColors d, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: TextStyle(
        color: d.text4,
        fontSize: 9.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _box(DentColors d, {required Widget child, VoidCallback? onTap}) =>
      InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: d.surface2,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: d.line),
          ),
          child: child,
        ),
      );

  Widget _dropdown<T>(
    DentColors d, {
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) => _box(
    d,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: d.surface,
        borderRadius: BorderRadius.circular(12),
        hint: hint == null
            ? null
            : Text(
                hint,
                style: TextStyle(color: d.text4, fontSize: 10.sp),
              ),
        items: [
          for (final (v, label) in items)
            DropdownMenuItem(
              value: v,
              child: Text(
                label,
                style: TextStyle(color: d.text1, fontSize: 10.sp),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );

  InputDecoration _dec(DentColors d, {String? hint, String? prefix}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        hintStyle: TextStyle(color: d.text4, fontSize: 9.5.sp),
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
