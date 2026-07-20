import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/branches/presentation/branch_controller.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../../../core/widgets/dent_field.dart';

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
      _pass = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController();
  String _role = _roles.first;
  String? _branchUuid;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authControllerProvider);
    // Admin is pinned to their branch; owner can pick freely.
    if (session != null && session.role == AppRole.admin) {
      _branchUuid = session.branchId;
    }
    // Owner: default to first branch so the field isn't empty
    if (session != null && session.role == AppRole.owner) {
      final branches = ref.read(branchesStreamProvider).value ?? [];
      if (branches.isNotEmpty) _branchUuid = branches.first.uuid;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _randomPassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _generate() async {
    final db = ref.read(appDatabaseProvider);
    final clinicName = await db.clinicName() ?? 'clinic';
    final clinicSlug = clinicName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    final first = (parts.isEmpty || parts.first.isEmpty) ? 'user' : parts.first;
    setState(() {
      _user.text = '${first.toLowerCase()}@$clinicSlug';
      _pass.text = _randomPassword();
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final username = _user.text.trim();
    final password = _pass.text;
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (name.isEmpty || username.isEmpty || password.length < 6) {
      setState(
        () => _error =
            'Enter a name, then Generate (or type a username + 6+ char password).',
      );
      return;
    }
    if (_branchUuid == null) {
      setState(() => _error = 'Select a branch for this user.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a phone number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final db = ref.read(appDatabaseProvider);
    final clinicId = await db.currentClinicId() ?? '';

    try {
      await db.addStaff(
        clinicId: clinicId,
        branchId: _branchUuid,
        fullName: name,
        username: username,
        passwordHash: BCrypt.hashpw(password, BCrypt.gensalt()),
        role: _role,
        email: email,
        phone: phone,
      );
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'That username already exists — Generate again.';
      });
      return;
    }

    if (!mounted) return;

    // Copy credentials silently
    await Clipboard.setData(
      ClipboardData(text: 'Username: $username\nPassword: $password'),
    );

    final roleName = _role[0].toUpperCase() + _role.substring(1);

    // Close create dialog then show confirmation popup
    Navigator.pop(context);
    if (!context.mounted) return;
    await showDentDialog(
      context,
      kind: DentDialogKind.success,
      title: 'Login Created',
      message:
          'Copied to clipboard — share with $name ($roleName). '
          'Password is shown only once.',
      confirmLabel: 'Done',
      rows: [
        DentDialogRow('Username', username),
        DentDialogRow('Password', password),
      ],
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
          child: SingleChildScrollView(
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
                  'Fill in details, then generate an ID & password to hand over.',
                  style: TextStyle(color: d.text3, fontSize: 8.sp),
                ),
                SizedBox(height: 2.h),

                // Name
                DentField(label: 'Full name', controller: _name),
                const SizedBox(height: 12),

                // Email + Phone
                Row(
                  children: [
                    Expanded(
                      child: DentField(
                        label: 'Email',
                        controller: _email,
                        hint: 'staff@example.com',
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DentField(
                        label: 'Phone',
                        controller: _phone,
                        hint: '0300 0000000',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Branch + Role
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final session = ref.read(authControllerProvider);
                          final isOwner = session?.role == AppRole.owner;
                          // Owner picks freely; admin is locked to their branch.
                          if (!isOwner) {
                            final myBranch = branches
                                .where((b) => b.uuid == _branchUuid)
                                .map((b) => b.name)
                                .firstOrNull;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BRANCH',
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
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: d.surface2,
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(color: d.line),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 13,
                                        color: d.text4,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        myBranch ?? 'Your branch',
                                        style: TextStyle(
                                          fontSize: 9.sp,
                                          color: d.text1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return _dd<String?>(
                            d,
                            'Branch',
                            [
                              for (final b in branches)
                                DropdownMenuItem<String?>(
                                  value: b.uuid,
                                  child: Text(b.name),
                                ),
                            ],
                            _branchUuid,
                            (v) => setState(() => _branchUuid = v),
                          );
                        },
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

                // Username + Password
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

                // Generate button
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
