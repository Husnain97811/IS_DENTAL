import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/licensing/data/license_service.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';

Future<void> showOwnerResetDialog(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: _OwnerReset(),
      ),
    );

class _OwnerReset extends ConsumerStatefulWidget {
  const _OwnerReset();
  @override
  ConsumerState<_OwnerReset> createState() => _S();
}

class _S extends ConsumerState<_OwnerReset> {
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String _clinicId = '';

  @override
  void initState() {
    super.initState();
    _loadClinicId();
  }

  Future<void> _loadClinicId() async {
    final id = await ref.read(appDatabaseProvider).currentClinicId() ?? '';
    if (mounted) setState(() => _clinicId = id);
  }

  @override
  void dispose() {
    _code.dispose(); _pass.dispose(); _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 100.w < 560 ? 92.w : 46.w),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset owner password',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Contact your DentOS provider and quote the clinic ID below. '
                   'They will send you a one-time reset code.',
                  style: TextStyle(color: d.text3, fontSize: 10.sp, height: 1.5)),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: d.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: d.line)),
                child: Row(children: [
                  Text('CLINIC ID', style: TextStyle(
                    color: d.text4, fontSize: 8.sp, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Expanded(child: SelectableText(
                    _clinicId.isEmpty ? '—' : _clinicId,
                    style: TextStyle(
                      fontFamily: AppFonts.mono, color: d.text1,
                      fontSize: 10.sp, fontWeight: FontWeight.w700))),
                ]),
              ),

              _lbl(d, 'Reset code'),
              TextField(
                controller: _code,
                maxLines: 3,
                style: TextStyle(
                    fontFamily: AppFonts.mono, fontSize: 9.sp, color: d.text1),
                decoration: _dec(d, '{"action":"ownerReset"…'),
              ),

              _lbl(d, 'New password'),
              TextField(
                controller: _pass, obscureText: true,
                style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                decoration: _dec(d, 'at least 6 characters')),

              _lbl(d, 'Confirm password'),
              TextField(
                controller: _confirm, obscureText: true,
                style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                decoration: _dec(d, 'type it again')),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: d.alert, fontSize: 9.5.sp))),

              const SizedBox(height: 22),
              Row(children: [
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp))),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice, foregroundColor: AppPalette.onAccent,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 22)),
                  onPressed: _busy ? null : _redeem,
                  child: _busy
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Reset password',
                          style: TextStyle(fontSize: 10.5.sp))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _redeem() async {
    if (_pass.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });

    final r = await ref.read(licenseServiceProvider).redeemOwnerReset(
      raw: _code.text.trim(),
      newPassword: _pass.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    Navigator.pop(context);
    await showDentDialog(
      context,
      kind: DentDialogKind.success,
      title: 'Password reset',
      message: 'Sign in with your new password. '
          'This reset code cannot be used again.',
      confirmLabel: 'Done',
    );
  }

  Widget _lbl(DentColors d, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 7),
        child: Text(t.toUpperCase(), style: TextStyle(
          color: d.text4, fontSize: 8.5.sp,
          fontWeight: FontWeight.w700, letterSpacing: .5)),
      );

  InputDecoration _dec(DentColors d, String hint) => InputDecoration(
        isDense: true, filled: true, fillColor: d.surface2,
        hintText: hint,
        hintStyle: TextStyle(color: d.text4, fontSize: 9.5.sp),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: d.line)),
      );
}