import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/cloud_registration.dart';
import 'package:is_dental/cloud/data/device_join.dart';
import 'package:is_dental/cloud/data/sync_engine.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:is_dental/core/device/device_service.dart';
import 'package:is_dental/core/shell/auth_shell.dart';
import 'package:sizer/sizer.dart';
import 'dart:io';
import '../../core/theme/dent_colors.dart';
import '../domain/license.dart';
import 'license_controller.dart';

/// What this install is doing. A joining or recovering computer follows a
/// completely different path from a new clinic — it must never create an
/// owner, register the clinic, or seed defaults.
enum _Mode { newClinic, join, recover }

class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});
  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  int _step = 0;
  _Mode? _mode;
  bool _busy = false;
  String? _error;
  String? _progress;

  final _license = TextEditingController();
  final _branch = TextEditingController(text: 'Rawalpindi');
  final _currency = TextEditingController(text: 'PKR (Rs)');
  final _owner = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _email = TextEditingController();
  final _joinCode = TextEditingController();
  final _recoverEmail = TextEditingController();
  final _recoverPass = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _license,
      _branch,
      _currency,
      _owner,
      _user,
      _pass,
      _email,
      _joinCode,
      _recoverEmail,
      _recoverPass,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  License? get _lic => ref.read(licenseControllerProvider).value?.license;

  String get _deviceName {
    final h = Platform.localHostname;
    return h.trim().isEmpty ? Platform.operatingSystem : h;
  }

  // ── step 0 ────────────────────────────────────────────────────────────
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
      if (r.ok) _step = 1;
    });
  }

  // ── step 2: new clinic ────────────────────────────────────────────────
  Future<void> _finishNew() async {
    final email = _email.text.trim();
    if (_owner.text.isEmpty ||
        _user.text.isEmpty ||
        !email.contains('@') ||
        _pass.text.length < 6) {
      setState(
        () => _error =
            'Enter owner name, username, a valid email, and a 6+ char password.',
      );
      return;
    }
    final lic = _lic;
    if (lic == null) {
      setState(() => _error = 'License missing — go back and activate.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    if (lic.cloudPackage == CloudPackage.cloud) {
      final reg = await ref
          .read(cloudRegistrationProvider)
          .register(license: lic.toJson(), email: email, password: _pass.text);
      if (!reg.ok) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = reg.error;
          });
        }
        return;
      }
    }

    await ref
        .read(licenseControllerProvider.notifier)
        .completeSetup(
          clinicName: lic.clinicName,
          branch: _branch.text.trim(),
          currency: _currency.text.trim(),
          ownerName: _owner.text.trim(),
          username: _user.text.trim(),
          email: email,
          password: _pass.text,
        );
    await ref
        .read(deviceServiceProvider)
        .ensureRegistered(byUsername: _user.text.trim());
  }

  // ── step 2: join ──────────────────────────────────────────────────────
  Future<void> _finishJoin() async {
    final lic = _lic;
    if (lic == null) return;
    final code = _joinCode.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = 'Enter the code from the other computer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Checking the code…';
    });

    final res = await ref
        .read(deviceJoinProvider)
        .redeem(license: lic.toJson(), code: code, deviceName: _deviceName);
    if (!res.ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error = res.error;
        });
      }
      return;
    }

    await _restoreAndFinish(
      email: res.email!,
      password: res.password!,
      letter: res.letter!,
    );
  }

  // ── step 2: recover ───────────────────────────────────────────────────
  Future<void> _finishRecover() async {
    final lic = _lic;
    if (lic == null) return;
    final email = _recoverEmail.text.trim();
    if (!email.contains('@') || _recoverPass.text.isEmpty) {
      setState(() => _error = 'Enter the cloud email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Signing in…';
    });

    final r = await ref
        .read(deviceJoinProvider)
        .signInAsOwner(
          email: email,
          password: _recoverPass.text,
          clinicId: lic.clinicId,
        );
    if (!r.ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error = r.error;
        });
      }
      return;
    }

    // The replacement machine inherits letter A, so no device slot leaks
    // when a computer dies.
    await _restoreAndFinish(
      email: email,
      password: _recoverPass.text,
      letter: 'A',
    );
  }

  // ── shared tail for join + recover ────────────────────────────────────
  Future<void> _restoreAndFinish({
    required String email,
    required String password,
    required String letter,
  }) async {
    final lic = _lic!;
    try {
      // Credentials first — restoreFromCloud signs in with them.
      final db = ref.read(appDatabaseProvider);
      await db.setSetting('cloud_email', email);
      await db.setSetting('cloud_password', password);
      // Set BEFORE the wipe: from here an empty table means "not pulled
      // yet", never "new clinic".
      await db.setSeedAllowed(false);

      if (mounted) setState(() => _progress = 'Downloading your clinic…');
      await ref.read(syncEngineProvider).restoreFromCloud(lic.clinicId);

      if (mounted) setState(() => _progress = 'Finishing up…');
      await ref
          .read(licenseControllerProvider.notifier)
          .completeJoin(
            cloudEmail: email,
            cloudPassword: password,
            deviceLetter: letter,
          );
      await ref.read(deviceServiceProvider).ensureRegistered();
      // Router now sees setupComplete and sends us to the login screen.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error =
              'Could not download the clinic: $e\n\n'
              'Check the internet connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final lic = ref.watch(licenseControllerProvider).value?.license;
    final cloud = lic?.cloudPackage == CloudPackage.cloud;

    return AuthShell(
      maxWidth: 552,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthBrand(title: 'Welcome to DentOS', subtitle: _subtitle()),
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

          if (_step == 1) _modePicker(d, lic, cloud),

          if (_step == 2 && _mode == _Mode.newClinic) ...[
            _lockedField(d, 'Clinic name', lic?.clinicName ?? ''),
            AuthField(label: 'Branch', controller: _branch),
            AuthField(label: 'Currency', controller: _currency),
            if (lic != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                  'Tier: ${lic.tier.name} · seats: ${lic.maxUsers} · '
                  'branches: ${lic.maxBranches} · computers: ${lic.maxDevices}',
                  style: TextStyle(color: d.text4, fontSize: 8.sp),
                ),
              ),
          ],

          if (_step == 3 && _mode == _Mode.newClinic) ...[
            AuthField(label: 'Owner full name', controller: _owner),
            AuthField(label: 'Username', controller: _user),
            AuthField(
              label: 'Email',
              controller: _email,
              hint: 'used for cloud sign-in',
            ),
            AuthField(label: 'Password', controller: _pass, obscure: true),
          ],

          if (_step == 2 && _mode == _Mode.join) _joinPane(d, lic),
          if (_step == 2 && _mode == _Mode.recover) _recoverPane(d, lic),

          if (_progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: d.ice,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _progress!,
                    style: TextStyle(color: d.text3, fontSize: 9.sp),
                  ),
                ],
              ),
            ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: TextStyle(color: d.alert, fontSize: 8.5.sp, height: 1.5),
              ),
            ),

          SizedBox(height: 2.4.h),
          _actions(d),
        ],
      ),
    );
  }

  String _subtitle() {
    if (_step == 0) return 'Activate your license';
    if (_step == 1) return 'What would you like to do?';
    return switch (_mode) {
      _Mode.join => 'Add this computer',
      _Mode.recover => 'Recover your clinic',
      _ => _step == 2 ? 'Clinic profile' : 'Owner account',
    };
  }

  // ── mode picker ───────────────────────────────────────────────────────
  Widget _modePicker(DentColors d, License? lic, bool cloud) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _modeCard(
        d,
        _Mode.newClinic,
        Icons.add_business_rounded,
        'Set up a new clinic',
        'This is the first computer. You will create the owner account.',
        enabled: true,
      ),
      const SizedBox(height: 10),
      _modeCard(
        d,
        _Mode.join,
        Icons.devices_rounded,
        'Add this computer to an existing clinic',
        cloud
            ? 'Your clinic already runs DentOS. Get a code from Settings → '
                  'Computers on the first PC.'
            : 'Needs the cloud package — two offline installs cannot share '
                  'data.',
        enabled: cloud && (lic?.maxDevices ?? 1) > 1,
      ),
      const SizedBox(height: 10),
      _modeCard(
        d,
        _Mode.recover,
        Icons.restore_rounded,
        'Recover this clinic',
        cloud
            ? 'Your previous computer was lost or replaced. Everything up to '
                  'its last sync comes back.'
            : 'Offline installs have no cloud copy to recover from.',
        enabled: cloud,
      ),
    ],
  );

  Widget _modeCard(
    DentColors d,
    _Mode mode,
    IconData icon,
    String title,
    String body, {
    required bool enabled,
  }) {
    final on = _mode == mode;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? () => setState(() => _mode = mode) : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? d.ice.withValues(alpha: .08) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? d.ice : d.line, width: on ? 1.6 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: on ? d.ice : d.text3),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: TextStyle(
                        color: d.text3,
                        fontSize: 8.5.sp,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── join ──────────────────────────────────────────────────────────────
  Widget _joinPane(DentColors d, License? lic) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _infoBox(
        d,
        'On the first computer, open Settings → Computers → Add a computer. '
        'The code is valid for 30 minutes.',
      ),
      const SizedBox(height: 14),
      AuthField(
        label: 'Join code',
        controller: _joinCode,
        hint: 'ABCD-EFGH',
        onSubmit: _busy ? null : _finishJoin,
      ),
      _infoBox(
        d,
        'Everything from the clinic will be downloaded to this computer, and '
        'your staff will sign in with the usernames they already have.',
      ),
    ],
  );

  // ── recover ───────────────────────────────────────────────────────────
  Widget _recoverPane(DentColors d, License? lic) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (lic != null)
        _infoBox(
          d,
          '${lic.clinicName} · ${lic.clinicId}\n\n'
          'Everything up to your last sync will be restored to this computer.',
        ),
      const SizedBox(height: 14),
      AuthField(
        label: 'Cloud account email',
        controller: _recoverEmail,
        hint: 'the email you set when you first installed DentOS',
      ),
      AuthField(
        label: 'Cloud account password',
        controller: _recoverPass,
        obscure: true,
        hint: 'NOT your daily login — the one set at first install',
        onSubmit: _busy ? null : _finishRecover,
      ),
      _infoBox(
        d,
        'Don\'t have these? Call Inover Studio and quote your clinic ID '
        '${lic?.clinicId ?? ""} — we can issue a recovery code.',
      ),
    ],
  );

  Widget _infoBox(DentColors d, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: d.surface2.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(11),
    ),
    child: SelectableText(
      text,
      style: TextStyle(color: d.text3, fontSize: 8.5.sp, height: 1.5),
    ),
  );

  // ── actions ───────────────────────────────────────────────────────────
  Widget _actions(DentColors d) {
    final isLast =
        (_mode == _Mode.newClinic && _step == 3) ||
        (_mode != _Mode.newClinic && _step == 2);

    String label;
    VoidCallback? onPressed;
    if (_step == 0) {
      label = 'Activate';
      onPressed = _activate;
    } else if (_step == 1) {
      label = 'Continue';
      onPressed = _mode == null ? null : () => setState(() => _step = 2);
    } else if (_mode == _Mode.newClinic && _step == 2) {
      label = 'Continue';
      onPressed = () => setState(() => _step = 3);
    } else {
      label = switch (_mode) {
        _Mode.join => 'Join this clinic',
        _Mode.recover => 'Restore my clinic',
        _ => 'Finish setup',
      };
      onPressed = switch (_mode) {
        _Mode.join => _finishJoin,
        _Mode.recover => _finishRecover,
        _ => _finishNew,
      };
    }

    return Row(
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
          width: isLast ? 200 : 165,
          child: AuthButton(label: label, busy: _busy, onPressed: onPressed),
        ),
      ],
    );
  }

  Widget _stepDots(DentColors d) {
    final total = _mode == _Mode.newClinic ? 4 : 3;
    return Row(
      children: List.generate(
        total,
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
  }

  Widget _lockedField(DentColors d, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: d.text2,
            fontSize: 9.8.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 50,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: d.surface2.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: d.line.withValues(alpha: .7)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: d.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.lock_rounded, size: 15, color: d.text4),
            ],
          ),
        ),
      ],
    ),
  );
}
