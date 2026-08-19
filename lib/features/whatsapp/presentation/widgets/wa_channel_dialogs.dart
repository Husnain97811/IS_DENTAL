import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';

/// After connecting Official while QR handles reminders → ask to shift.
Future<void> maybeOfferShiftToOfficial(
  BuildContext context,
  WidgetRef ref,
  Branch b,
) async {
  // only ask if QR currently handles reminders
  if (b.waReminderChannel != 'qr') {
    // no conflict — default reminders to official if none set
    if (b.waReminderChannel == 'none') {
      await ref
          .read(appDatabaseProvider)
          .setBranchReminderChannel(b.id, 'official');
    }
    return;
  }
  final shift = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ChoiceDialog(
      title: 'Official API connected',
      message:
          'Reminders currently send via QR (free). You\'ve now set up the '
          'Official API, where you pay Meta\'s fees. Switch reminder sending to '
          'the Official API, or keep reminders on QR?',
      options: const ['Switch to Official API', 'Keep on QR'],
    ),
  );
  if (shift == true) {
    await ref
        .read(appDatabaseProvider)
        .setBranchReminderChannel(b.id, 'official');
  }
}

/// After losing a channel that was handling reminders → blocking choice.
Future<void> handleChannelLoss(
  BuildContext context,
  WidgetRef ref,
  Branch b, {
  required String lostChannel,
}) async {
  // re-read fresh branch to know what's still connected
  final fresh =
      ref
          .read(branchesStreamProvider)
          .value
          ?.firstWhere((x) => x.id == b.id, orElse: () => b) ??
      b;

  final otherConnected = lostChannel == 'official'
      ? fresh
            .qrConnected // official lost → is QR available?
      : fresh.officialConnected; // qr lost → is official available?

  if (!otherConnected) {
    // nothing else to fall back to → notifications only, silently
    await ref.read(appDatabaseProvider).setBranchReminderChannel(b.id, 'none');
    return;
  }

  final fallbackChannel = lostChannel == 'official' ? 'qr' : 'official';
  final fallbackLabel = fallbackChannel == 'qr' ? 'QR' : 'Official API';

  // blocking dialog — must choose
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ChoiceDialog(
      title: 'Reminder channel changed',
      message:
          'You disconnected ${lostChannel == 'official' ? 'the Official API' : 'QR'}, '
          'which was sending reminders. Where should reminders go now?',
      options: [
        'Notifications + WhatsApp ($fallbackLabel)',
        'Notifications only',
      ],
      returnValues: [fallbackChannel, 'none'],
      dismissible: false,
    ),
  );
  await ref
      .read(appDatabaseProvider)
      .setBranchReminderChannel(b.id, choice ?? 'none');
}

/// Official API setup form.
Future<void> showOfficialApiSetup(
  BuildContext context,
  WidgetRef ref,
  Branch b,
) async {
  final d = context.dent;
  final phone = TextEditingController(text: b.waPhone ?? '');
  final token = TextEditingController(text: b.waApiToken ?? '');
  final phoneId = TextEditingController(text: b.waPhoneId ?? '');

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Official WhatsApp API · ${b.name}',
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter your Meta WhatsApp Business credentials. '
                  'Meta bills you directly for messages.',
                  style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                ),
                const SizedBox(height: 16),
                _f(d, 'WhatsApp Number', phone),
                _f(d, 'API Token', token, obscure: true),
                _f(d, 'Phone Number ID', phoneId),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                      ),
                      onPressed: () async {
                        if (token.text.trim().isEmpty ||
                            phoneId.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'API token and Phone Number ID are required.',
                              ),
                            ),
                          );
                          return;
                        }
                        await ref
                            .read(appDatabaseProvider)
                            .setBranchOfficialApi(
                              id: b.id,
                              apiToken: token.text.trim(),
                              phoneId: phoneId.text.trim(),
                              phone: phone.text.trim().isEmpty
                                  ? null
                                  : phone.text.trim(),
                            );
                        Navigator.pop(ctx);
                        // after connecting official, maybe offer to shift reminders
                        final fresh =
                            ref
                                .read(branchesStreamProvider)
                                .value
                                ?.firstWhere(
                                  (x) => x.id == b.id,
                                  orElse: () => b,
                                ) ??
                            b;
                        if (ctx.mounted) {
                          await maybeOfferShiftToOfficial(ctx, ref, fresh);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _f(
  DentColors d,
  String label,
  TextEditingController c, {
  bool obscure = false,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SizedBox(height: 12),
    Text(
      label.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: 9.5.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
    const SizedBox(height: 6),
    Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: d.line),
      ),
      child: Center(
        child: TextField(
          controller: c,
          obscureText: obscure,
          style: TextStyle(fontSize: 10.sp, color: d.text1),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    ),
  ],
);

class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog({
    required this.title,
    required this.message,
    required this.options,
    this.returnValues,
    this.dismissible = true,
  });
  final String title, message;
  final List<String> options;
  final List<String>? returnValues; // if null, returns bool (first=true)
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return PopScope(
      canPop: dismissible,
      child: Dialog(
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
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(color: d.text2, fontSize: 9.sp, height: 1.4),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < options.length; i++) ...[
                  if (i == 0)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => Navigator.pop(
                        context,
                        returnValues != null ? returnValues![i] : true,
                      ),
                      child: Text(options[i]),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: d.text2,
                          side: BorderSide(color: d.line),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          returnValues != null ? returnValues![i] : false,
                        ),
                        child: Text(options[i]),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
