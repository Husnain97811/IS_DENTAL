import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/dent_colors.dart';
import '../../../../core/widgets/dent_field.dart';
import '../../../branches/presentation/branch_controller.dart';

const _roles = ['admin', 'clinician', 'receptionist'];

Future<void> showStaffEditor(BuildContext context) =>
    showDialog(context: context, builder: (_) => const StaffEditorDialog());

class StaffEditorDialog extends ConsumerStatefulWidget {
  const StaffEditorDialog({super.key});
  @override
  ConsumerState<StaffEditorDialog> createState() => _S();
}

class _S extends ConsumerState<StaffEditorDialog> {
  final _name = TextEditingController(),
      _user = TextEditingController(),
      _pass = TextEditingController();
  String _role = _roles.first;
  String? _branchUuid; // null = all branches
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _randomPassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _generate() {
    final branches = ref.read(branchesStreamProvider).value ?? [];
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    final first = (parts.isEmpty || parts.first.isEmpty) ? 'user' : parts.first;
    var bcode = 'hq';
    if (_branchUuid != null) {
      final match = branches.where((b) => b.uuid == _branchUuid);
      if (match.isNotEmpty) {
        final clean = match.first.name
            .replaceAll(RegExp(r'[^A-Za-z]'), '')
            .toLowerCase();
        bcode = clean.isEmpty
            ? 'br'
            : (clean.length >= 3 ? clean.substring(0, 3) : clean);
      }
    }
    final n = Random().nextInt(90) + 10;
    setState(() {
      _user.text = '${first.toLowerCase()}.$bcode$n';
      _pass.text = _randomPassword();
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _user.text.trim().isEmpty ||
        _pass.text.length < 6) {
      setState(
        () => _error =
            'Enter a name, then Generate (or type a username + 6+ char password).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = ref.read(appDatabaseProvider);
    final clinicId = await db.currentClinicId() ?? '';
    final username = _user.text.trim(), password = _pass.text;
    try {
      await db.addStaff(
        clinicId: clinicId,
        branchId: _branchUuid,
        fullName: _name.text.trim(),
        username: username,
        passwordHash: BCrypt.hashpw(password, BCrypt.gensalt()),
        role: _role,
      );
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'That username already exists — Generate again.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    await showDialog(
      context: context,
      builder: (_) => _CredentialsCard(username: username, password: password),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final branches = ref.watch(branchesStreamProvider).value ?? [];
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create Staff Login',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a branch and role, then generate an ID & password to hand over.',
                style: TextStyle(color: d.text3, fontSize: 8.sp),
              ),
              SizedBox(height: 2.h),
              DentField(label: 'Full name', controller: _name),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _dd<String?>(
                      d,
                      'Branch',
                      [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All branches'),
                        ),
                        for (final b in branches)
                          DropdownMenuItem<String?>(
                            value: b.uuid,
                            child: Text(b.name),
                          ),
                      ],
                      _branchUuid,
                      (v) => setState(() => _branchUuid = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dd<String>(
                      d,
                      'Role',
                      [
                        for (final r in _roles)
                          DropdownMenuItem(
                            value: r,
                            child: Text(
                              '${r[0].toUpperCase()}${r.substring(1)}',
                            ),
                          ),
                      ],
                      _role,
                      (v) => setState(() => _role = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DentField(
                label: 'Username',
                controller: _user,
                hint: 'auto-generated',
              ),
              const SizedBox(height: 12),
              DentField(
                label: 'Password',
                controller: _pass,
                hint: 'auto-generated',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.ice,
                    side: BorderSide(color: d.line),
                  ),
                  label: const Text('Generate ID & password'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: d.alert, fontSize: 8.5.sp),
                  ),
                ),
              SizedBox(height: 2.4.h),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                    ),
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppPalette.onAccent,
                            ),
                          )
                        : const Text('Create login'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dd<T>(
    DentColors d,
    String label,
    List<DropdownMenuItem<T>> items,
    T value,
    ValueChanged<T?> onChanged,
  ) => Column(
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
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: d.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: d.line),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          underline: const SizedBox(),
          style: TextStyle(fontSize: 9.sp, color: d.text1),
          items: items,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _CredentialsCard extends StatelessWidget {
  const _CredentialsCard({required this.username, required this.password});
  final String username, password;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    Widget row(String label, String value) => Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 6.5.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.mono(
                    size: 10.sp,
                    color: d.text1,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 16, color: d.text3),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );
    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.verified_user_rounded, color: d.teal, size: 18.sp),
              SizedBox(height: 1.h),
              Text(
                'Login created',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Copy these now — the password is shown only once.',
                textAlign: TextAlign.center,
                style: TextStyle(color: d.text3, fontSize: 8.5.sp),
              ),
              row('Username', username),
              row('Password', password),
              SizedBox(height: 2.h),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
