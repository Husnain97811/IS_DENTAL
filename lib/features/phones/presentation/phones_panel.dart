import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/hub/data/hub_security.dart';

import '../data/owner_phones.dart';
import 'pair_phone_dialog.dart';

/// Settings → Connected phones. Owner only; shown when the licence has the
/// "Owner phone app" add-on (Standard or Premium).
class PhonesPanel extends ConsumerWidget {
  const PhonesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final overview = ref.watch(phonesOverviewProvider);

    return DentPanel(
      title: 'Connected phones',
      subtitle: "The owner's phone · Hub on the go",
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: () => ref.invalidate(phonesOverviewProvider),
        icon: Icon(Icons.refresh_rounded, size: 20, color: d.text3),
      ),
      child: overview.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(26),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: d.text3, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e is PhoneApiError ? e.message : 'Could not load phones.',
                  style: TextStyle(color: d.text2, fontSize: 10.sp),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(phonesOverviewProvider),
                child: Text('Retry', style: TextStyle(fontSize: 10.sp)),
              ),
            ],
          ),
        ),
        data: (o) => _content(context, ref, d, o),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    PhonesOverview o,
  ) {
    String? blocker;
    if (!o.onPlan) {
      blocker = PhoneApiError(o.planError ?? 'not_on_plan').message;
    } else if (!o.hasPin) {
      blocker = PhoneApiError('no_pin').message;
    } else if (!o.hasOwnerPhone) {
      blocker = PhoneApiError('no_phone').message;
    } else if (o.full) {
      blocker = PhoneApiError('limit', max: o.max).message;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── owner mobile ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: d.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Owner mobile',
                      style: TextStyle(
                        color: d.text1,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'The phone must type this number to connect',
                      style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                    ),
                  ],
                ),
              ),
              Text(
                o.hasOwnerPhone ? o.ownerPhoneMasked : 'Not set',
                style: TextStyle(
                  color: o.hasOwnerPhone ? d.text1 : d.alert,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _changeNumber(context, ref),
                child: Text(
                  o.hasOwnerPhone ? 'Change' : 'Add',
                  style: TextStyle(fontSize: 10.sp),
                ),
              ),
            ],
          ),
        ),

        // ── the phones ──
        if (o.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Text(
              'No phone connected yet.',
              style: TextStyle(color: d.text3, fontSize: 10.sp),
            ),
          ),
        for (final p in o.devices) _phoneRow(context, ref, d, p),

        // ── connect ──
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocker != null) ...[
                Text(
                  blocker,
                  style: TextStyle(
                    color: d.text2,
                    fontSize: 9.5.sp,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Text(
                    '${o.devices.length} / ${o.max} phones',
                    style: TextStyle(
                      color: d.text3,
                      fontSize: 9.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: d.ice,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: blocker != null
                        ? null
                        : () async {
                            await showPairPhoneDialog(context);
                            if (context.mounted) {
                              ref.invalidate(phonesOverviewProvider);
                            }
                          },
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: Text(
                      'Connect a phone',
                      style: TextStyle(fontSize: 10.sp),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _phoneRow(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    ConnectedPhone p,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: d.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: d.ice.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            p.isIphone
                ? Icons.phone_iphone_rounded
                : Icons.phone_android_rounded,
            color: d.ice,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.model,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${p.platformLabel} · connected ${_day(p.pairedAt)} · '
                'last used ${_ago(p.lastSeenAt)}',
                style: TextStyle(color: d.text3, fontSize: 9.5.sp),
              ),
            ],
          ),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: d.alert,
            side: BorderSide(color: d.alert.withValues(alpha: .4)),
          ),
          onPressed: () => _disconnect(context, ref, p),
          child: Text('Disconnect', style: TextStyle(fontSize: 9.5.sp)),
        ),
      ],
    ),
  );

  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref,
    ConnectedPhone p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PinActionDialog(
        title: 'Disconnect ${p.model}?',
        message:
            'It stops working at once and must be connected again with a new '
            'QR code to use DentOS. Enter your Hub PIN to confirm.',
        actionLabel: 'Disconnect',
        danger: true,
        run: (api, pin, _) => api.revoke(p.id, pin),
      ),
    );
    if (done == true) {
      if (context.mounted) ref.invalidate(phonesOverviewProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${p.model} was disconnected.')),
      );
    }
  }

  Future<void> _changeNumber(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PinActionDialog(
        title: 'Owner mobile number',
        message:
            'The phone being connected must type this number. If a number was '
            'set before, it gets a WhatsApp alert about the change.',
        actionLabel: 'Save',
        askNumber: true,
        run: (api, pin, number) => api.setOwnerPhone(number, pin),
      ),
    );
    if (done == true) {
      if (context.mounted) ref.invalidate(phonesOverviewProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Owner mobile number saved.')),
      );
    }
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _day(DateTime? t) =>
      t == null ? '—' : '${t.day} ${_months[t.month - 1]} ${t.year}';

  static String _ago(DateTime? t) {
    if (t == null) return '—';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 2) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    if (h < 24) return '$h h ago';
    final days = h ~/ 24;
    return days == 1 ? 'yesterday' : '$days days ago';
  }
}

/// Asks for the Hub PIN (and a number when [askNumber]), runs [run] on the
/// server, and closes with true when it worked. Wrong PINs are counted on
/// this computer and on the server.
class _PinActionDialog extends ConsumerStatefulWidget {
  const _PinActionDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.run,
    this.askNumber = false,
    this.danger = false,
  });

  final String title, message, actionLabel;
  final bool askNumber, danger;
  final Future<void> Function(OwnerPhonesApi api, String pin, String number)
  run;

  @override
  ConsumerState<_PinActionDialog> createState() => _PinActionDialogState();
}

class _PinActionDialogState extends ConsumerState<_PinActionDialog> {
  final _pin = TextEditingController();
  final _number = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final pin = _pin.text.trim();
    final number = _number.text.trim();
    if (widget.askNumber && number.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = PhoneApiError('bad_number').message);
      return;
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Enter your 4 to 6 digit Hub PIN.');
      return;
    }
    final session = ref.read(authControllerProvider);
    if (session == null || session.role != AppRole.owner) {
      setState(() => _error = 'Only the owner can do this.');
      return;
    }
    final sec = ref.read(hubSecurityProvider);
    final api = ref.read(ownerPhonesApiProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final owner = await sec.userFor(session);
      if (owner == null || !sec.hasPin(owner)) {
        throw PhoneApiError('no_pin');
      }
      final check = await sec.checkPin(owner, session, pin);
      if (!check.ok) {
        _pin.clear();
        throw check.result == HubCheckResult.locked
            ? PhoneApiError('locked', until: check.until)
            : PhoneApiError('wrong_pin', triesLeft: check.triesLeft);
      }
      await api.retryAfterPinSync(owner, () => widget.run(api, pin, number));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is PhoneApiError
            ? e.message
            : PhoneApiError('server').message;
      });
    }
  }

  InputDecoration _deco(DentColors d, String label, String hint) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle: TextStyle(color: d.text3, fontSize: 10.sp),
        hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
        filled: true,
        fillColor: d.surface2,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: d.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: d.ice, width: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
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
                widget.title,
                style: TextStyle(
                  color: d.text1,
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.message,
                style: TextStyle(color: d.text2, fontSize: 10.sp, height: 1.45),
              ),
              const SizedBox(height: 18),
              if (widget.askNumber) ...[
                TextField(
                  controller: _number,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  maxLength: 16,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                  ],
                  style: TextStyle(color: d.text1, fontSize: 11.sp),
                  decoration: _deco(d, 'Mobile number', '0300 1234567'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _pin,
                autofocus: !widget.askNumber,
                enabled: !_busy,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  color: d.text1,
                  fontSize: 12.sp,
                  letterSpacing: 6,
                ),
                decoration: _deco(d, 'Hub PIN', '••••'),
                onSubmitted: (_) => _busy ? null : _go(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: d.alert,
                    fontSize: 10.sp,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.danger ? d.alert : d.ice,
                      foregroundColor: widget.danger
                          ? Colors.white
                          : AppPalette.onAccent,
                      minimumSize: const Size(130, 46),
                    ),
                    onPressed: _busy ? null : _go,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Text(
                            widget.actionLabel,
                            style: TextStyle(fontSize: 10.5.sp),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
