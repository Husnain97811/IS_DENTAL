import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/core/shell/auth_shell.dart';
import 'package:sizer/sizer.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/dent_colors.dart';
import 'license_controller.dart';

class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});
  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  final _license = TextEditingController();
  final _clinic = TextEditingController();
  final _branch = TextEditingController(text: 'Rawalpindi');
  final _currency = TextEditingController(text: 'PKR (Rs)');
  final _owner = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _license,
      _clinic,
      _branch,
      _currency,
      _owner,
      _user,
      _pass,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref
        .read(licenseControllerProvider.notifier)
        .activate(_license.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.error;
      if (r.ok) {
        _clinic.text =
            ref.read(licenseControllerProvider).value?.license?.clinicName ??
            '';
        _step = 1;
      }
    });
  }

  Future<void> _finish() async {
    if (_owner.text.isEmpty || _user.text.isEmpty || _pass.text.length < 6) {
      setState(
        () => _error = 'Enter owner name, username, and a password (6+ chars).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref
        .read(licenseControllerProvider.notifier)
        .completeSetup(
          clinicName: _clinic.text.trim(),
          branch: _branch.text.trim(),
          currency: _currency.text.trim(),
          ownerName: _owner.text.trim(),
          username: _user.text.trim(),
          password: _pass.text,
        );
    // Gate rebuilds into the app automatically once status becomes active+setup.
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final lic = ref.watch(licenseControllerProvider).value?.license;
    return AuthShell(
      maxWidth: 40.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthBrand(
            title: 'Welcome to DentOS',
            subtitle: const [
              'Activate your license',
              'Clinic profile',
              'Owner account',
            ][_step],
          ),
          SizedBox(height: 3.h),
          _stepDots(d),
          SizedBox(height: 2.4.h),
          if (_step == 0)
            AuthField(
              label: 'License key',
              controller: _license,
              hint: 'Paste your signed license (.dentos) contents',
              maxLines: 5,
            ),
          if (_step == 1) ...[
            AuthField(label: 'Clinic name', controller: _clinic),
            AuthField(label: 'Branch', controller: _branch),
            AuthField(label: 'Currency', controller: _currency),
            if (lic != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tier: ${lic.tier.name} · seats: ${lic.maxUsers} · branches: ${lic.maxBranches}',
                  style: TextStyle(color: d.text4, fontSize: 8.sp),
                ),
              ),
          ],
          if (_step == 2) ...[
            AuthField(label: 'Owner full name', controller: _owner),
            AuthField(label: 'Username', controller: _user),
            AuthField(label: 'Password', controller: _pass, obscure: true),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: TextStyle(color: d.alert, fontSize: 8.5.sp),
              ),
            ),
          SizedBox(height: 2.4.h),
          Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _step--;
                          _error = null;
                        }),
                  child: const Text('Back'),
                ),
              const Spacer(),
              SizedBox(
                width: 165,
                child: AuthButton(
                  label: _step == 0
                      ? 'Activate'
                      : (_step == 1 ? 'Continue' : 'Finish setup'),
                  busy: _busy,
                  onPressed: _step == 0
                      ? _activate
                      : (_step == 1
                            ? () => setState(() => _step = 2)
                            : _finish),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDots(DentColors d) => Row(
    children: List.generate(
      3,
      (i) => Expanded(
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: i <= _step ? d.accentGradient : null,
            color: i <= _step ? null : d.line2,
          ),
        ),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    bool obscure = false,
    int lines = 1,
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
            maxLines: lines,
            style: TextStyle(fontSize: 9.5.sp, color: d.text1),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
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
