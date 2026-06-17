import 'dart:async';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/shell/auth_shell.dart';
import 'package:sizer/sizer.dart';

import '../../core/db/app_database.dart';
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

  static const _lockKey = 'login_locked_until_ms'; // matches AuthService
  Timer? _ticker;
  int? _lockedUntilMs;

  @override
  void initState() {
    super.initState();
    _refreshLock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // re-evaluate the countdown every second
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _refreshLock() async {
    final v = await ref.read(appDatabaseProvider).getSetting(_lockKey);
    if (mounted) setState(() => _lockedUntilMs = int.tryParse(v ?? ''));
  }

  Duration get _remaining {
    if (_lockedUntilMs == null) return Duration.zero;
    final ms = _lockedUntilMs! - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  Future<void> _submit() async {
    if (_remaining > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .login(_user.text, _pass.text);
    await _refreshLock(); // a failed attempt may have just locked us
    if (mounted)
      setState(() {
        _busy = false;
        _error = err;
      });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final rem = _remaining;
    final locked = rem > Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final mmss = '${two(rem.inMinutes)}:${two(rem.inSeconds % 60)}';

    return AuthShell(
      maxWidth: 410,
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
          if (locked)
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: d.warn.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: d.warn.withValues(alpha: .35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock_rounded, size: 16, color: d.warn),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Too many attempts — locked',
                      style: TextStyle(color: d.text2, fontSize: 8.5.sp),
                    ),
                  ),
                  Text(
                    mmss,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w700,
                      color: d.warn,
                    ),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _error!,
                style: TextStyle(color: d.alert, fontSize: 8.5.sp),
              ),
            ),
          SizedBox(height: 1.4.h),
          AuthButton(
            label: locked ? 'Locked' : 'Sign in',
            busy: _busy,
            onPressed: locked ? null : _submit,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _seedTestUser,
              child: Text(
                'Create test login (dev)',
                style: TextStyle(fontSize: 8.5.sp, color: d.text4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // DEV ONLY — makes a known owner login and clears any lockout.
  Future<void> _seedTestUser() async {
    final db = ref.read(appDatabaseProvider);
    await db.setSetting(_lockKey, '0'); // clear lockout
    await db.setSetting('login_fail_count', '0');
    final clinicId = await db.currentClinicId() ?? 'CL-0001';
    try {
      await db.addStaff(
        clinicId: clinicId,
        branchId: null,
        fullName: 'Test Owner',
        username: 'admin',
        passwordHash: BCrypt.hashpw('admin123', BCrypt.gensalt()),
        role: 'owner',
      );
    } catch (_) {
      /* already exists */
    }
    await _refreshLock();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login ready → username: admin · password: admin123'),
        ),
      );
    }
  }
}
