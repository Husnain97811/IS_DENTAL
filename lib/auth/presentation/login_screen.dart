import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/shell/auth_shell.dart';
import 'package:sizer/sizer.dart';

import '../../core/theme/dent_colors.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .login(_user.text, _pass.text);
    if (mounted)
      setState(() {
        _busy = false;
        _error = err;
      }); // success → router redirects automatically
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return AuthShell(
      maxWidth: 40.w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthBrand(
            title: 'Sign in',
            subtitle: 'DentOS · Clinical Suite',
          ),
          SizedBox(height: 3.h),
          AuthField(label: 'Username', controller: _user),
          AuthField(
            label: 'Password',
            controller: _pass,
            obscure: true,
            onSubmit: _submit,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _error!,
                style: TextStyle(color: d.alert, fontSize: 8.5.sp),
              ),
            ),
          SizedBox(height: 1.4.h),
          AuthButton(label: 'Sign in', busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool obscure = false,
    VoidCallback? onSubmit,
  }) {
    final d = context.dent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: d.text4,
              fontSize: 7.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: obscure,
            onSubmitted: (_) => onSubmit?.call(),
            style: TextStyle(fontSize: 9.5.sp, color: d.text1),
            decoration: InputDecoration(
              filled: true,
              fillColor: d.surface2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: d.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: d.ice, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
