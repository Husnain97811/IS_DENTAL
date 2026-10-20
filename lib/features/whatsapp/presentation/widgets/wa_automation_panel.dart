import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/wa_outbox.dart';

/// Shown inside a branch's WhatsApp card when QR is connected:
/// prescription auto-send, weekly owner summary, and the message log.
class WaAutomationPanel extends ConsumerStatefulWidget {
  const WaAutomationPanel({
    super.key,
    required this.branchUuid,
    required this.branchName,
  });
  final String branchUuid, branchName;
  @override
  ConsumerState<WaAutomationPanel> createState() => _WaAutomationPanelState();
}

class _WaAutomationPanelState extends ConsumerState<WaAutomationPanel> {
  final _phone = TextEditingController();
  bool _loaded = false, _saving = false, _rxAuto = true;
  String _savedPhone = '';

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final canEdit = ref.watch(canProvider(Perm.manageWhatsapp));
    final async = ref.watch(waBranchSettingsProvider(widget.branchUuid));
    final s = async.value;
    if (s != null && !_loaded) {
      _loaded = true;
      _rxAuto = s.rxAuto;
      _savedPhone = s.summaryPhone;
      _phone.text = _display(s.summaryPhone);
    }
    final phoneChanged =
        waNormalizePhone(_phone.text) != waNormalizePhone(_savedPhone);

    if (async.hasError && s == null) {
      return _pad(
        Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 13.sp, color: d.text4),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'WhatsApp settings need internet. Check the connection and refresh.',
                style: TextStyle(color: d.text3, fontSize: 9.5.sp),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(waBranchSettingsProvider(widget.branchUuid)),
              child: Text('Refresh', style: TextStyle(fontSize: 10.sp)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── prescriptions ──
        _pad(
          Row(
            children: [
              Icon(Icons.medication_rounded, size: 13.sp, color: d.text4),
              const SizedBox(width: 12),
              Expanded(
                child: _title(
                  d,
                  'Send prescriptions on WhatsApp',
                  'The PDF goes to the patient automatically when a new prescription is saved',
                ),
              ),
              Switch(
                value: _rxAuto,
                activeColor: d.teal,
                onChanged: !canEdit || _saving || s == null
                    ? null
                    : (v) {
                        setState(() => _rxAuto = v);
                        _save(phone: _savedPhone);
                      },
              ),
            ],
          ),
        ),
        Divider(height: 1, color: d.line),

        // ── weekly summary ──
        _pad(
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 13.sp, color: d.text4),
              const SizedBox(width: 12),
              Expanded(
                child: _title(
                  d,
                  'Weekly summary to owner',
                  _savedPhone.isEmpty
                      ? 'Off · add a number to get visits, money in, expenses and still owed every Sunday ~7 PM'
                      : 'Every Sunday ~7 PM to ${_display(_savedPhone)}',
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: 150, maxWidth: 230),
                child: SizedBox(
                  width: 15.w,
                  height: 40,
                  child: TextField(
                    controller: _phone,
                    enabled: canEdit && s != null,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 10.sp, color: d.text1),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: d.surface2,
                      hintText: '03xx xxxxxxx',
                      hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: d.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: d.line),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: !canEdit || _saving || !phoneChanged
                    ? null
                    : () => _save(phone: _phone.text),
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(
                  _phone.text.trim().isEmpty && _savedPhone.isNotEmpty
                      ? 'Turn off'
                      : 'Save',
                  style: TextStyle(fontSize: 10.sp),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: d.line),

        // ── log ──
        _pad(
          Row(
            children: [
              Icon(Icons.history_rounded, size: 13.sp, color: d.text4),
              const SizedBox(width: 12),
              Expanded(
                child: _title(
                  d,
                  'Message log',
                  'Every WhatsApp from this branch — sent, waiting, failed and why',
                ),
              ),
              OutlinedButton(
                onPressed: () => showWaLogDialog(
                  context,
                  branchUuid: widget.branchUuid,
                  branchName: widget.branchName,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.teal,
                  side: BorderSide(color: d.teal.withValues(alpha: .5)),
                ),
                child: Text(
                  'Open',
                  style: TextStyle(fontSize: 10.sp, color: d.text1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: child,
  );

  Widget _title(DentColors d, String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t,
        style: TextStyle(
          color: d.text1,
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        sub,
        style: TextStyle(color: d.text3, fontSize: 10.sp),
      ),
    ],
  );

  /// 923001234567 → 0300 1234567 (how staff type it)
  static String _display(String p) {
    if (p.startsWith('92') && p.length == 12) {
      return '0${p.substring(2, 5)} ${p.substring(5)}';
    }
    return p;
  }

  Future<void> _save({required String phone}) async {
    final messenger = ScaffoldMessenger.of(context);
    final cleaned = phone.trim().isEmpty ? '' : waNormalizePhone(phone);
    if (cleaned.isNotEmpty && cleaned.length < 11) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter a full mobile number, e.g. 0300 1234567.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final clinicId =
          await ref.read(appDatabaseProvider).currentClinicId() ?? '';
      await saveWaBranchSettings(
        clinicId: clinicId,
        branchUuid: widget.branchUuid,
        rxAuto: _rxAuto,
        summaryPhone: cleaned,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _savedPhone = cleaned;
        _phone.text = _display(cleaned);
      });
      ref.invalidate(waBranchSettingsProvider(widget.branchUuid));
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save (needs internet): $e')),
      );
    }
  }
}

// ═════════════════════════ message log dialog ═════════════════════════

Future<void> showWaLogDialog(
  BuildContext context, {
  required String branchUuid,
  required String branchName,
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _WaLog(branchUuid: branchUuid, branchName: branchName),
  ),
);

class _WaLog extends ConsumerWidget {
  const _WaLog({required this.branchUuid, required this.branchName});
  final String branchUuid, branchName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final canEdit = ref.watch(canProvider(Perm.manageWhatsapp));
    final async = ref.watch(waLogProvider(branchUuid));
    final list = async.value ?? const <WaLogEntry>[];
    final maxW = 100.w < 700 ? 94.w : 58.w;

    final today = DateTime.now();
    bool isToday(DateTime t) =>
        t.year == today.year && t.month == today.month && t.day == today.day;
    final sentToday = list
        .where(
          (e) => e.status == 'sent' && e.sentAt != null && isToday(e.sentAt!),
        )
        .length;
    final waiting = list.where((e) => e.isWaiting).length;
    final failed = list.where((e) => e.status == 'failed').length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 84.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.teal.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.history_rounded, size: 18, color: d.teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Message log · $branchName',
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Sent today $sentToday  ·  Waiting $waiting  ·  Failed $failed',
                          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh_rounded, size: 18, color: d.text3),
                    onPressed: () => ref.invalidate(waLogProvider(branchUuid)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Flexible(
              child: async.isLoading && list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : async.hasError && list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load the log (needs internet).',
                        style: TextStyle(color: d.alert, fontSize: 10.sp),
                      ),
                    )
                  : list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No WhatsApp messages yet from this branch.',
                        style: TextStyle(color: d.text4, fontSize: 10.sp),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: list.length,
                      itemBuilder: (_, i) =>
                          _row(context, ref, d, list[i], canEdit),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    DentColors d,
    WaLogEntry e,
    bool canEdit,
  ) {
    final color = switch (e.status) {
      'sent' => d.tealDeep,
      'pending' || 'sending' => d.ice,
      'failed' => d.alert,
      _ => d.text4,
    };
    final when = e.status == 'sent'
        ? _fmt(e.sentAt ?? e.createdAt)
        : e.isWaiting
        ? 'goes ${_fmt(e.notBefore ?? e.createdAt)}'
        : _fmt(e.createdAt);
    final who = e.patientName.isNotEmpty ? e.patientName : _phone(e.phone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              e.statusLabel.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 8.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$who  ·  ${e.kindLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d.text1,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (e.lastError.isNotEmpty && e.status != 'sent')
                  Text(
                    e.lastError,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: d.text3, fontSize: 9.sp),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            when,
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          if (canEdit && e.status == 'failed')
            _act(d, Icons.replay_rounded, 'Try again', () async {
              await retryWaMessage(e.id);
              ref.invalidate(waLogProvider(branchUuid));
            }),
          if (canEdit && e.status == 'pending')
            _act(d, Icons.block_rounded, 'Don\'t send', () async {
              await cancelWaMessage(e.id);
              ref.invalidate(waLogProvider(branchUuid));
            }),
        ],
      ),
    );
  }

  Widget _act(DentColors d, IconData icon, String tip, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 16, color: d.text3),
          onPressed: onTap,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
        ),
      );

  static String _phone(String p) => p.startsWith('92') && p.length == 12
      ? '0${p.substring(2, 5)} ${p.substring(5)}'
      : p;

  static String _fmt(DateTime t) {
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time =
        '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return time;
    }
    const m = [
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
    return '${t.day} ${m[t.month - 1]} $time';
  }
}
