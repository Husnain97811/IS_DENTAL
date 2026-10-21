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
      return _row(
        d,
        icon: Icons.cloud_off_rounded,
        tone: d.warn,
        text: Text(
          'WhatsApp settings need internet. Check the connection and refresh.',
          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
        ),
        trailing: TextButton.icon(
          onPressed: () =>
              ref.invalidate(waBranchSettingsProvider(widget.branchUuid)),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text('Refresh', style: TextStyle(fontSize: 10.sp)),
        ),
      );
    }

    final summaryOn = _savedPhone.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── prescriptions ──
        _row(
          d,
          icon: Icons.medication_rounded,
          tone: _rxAuto ? d.teal : d.text4,
          text: _title(
            d,
            'Send prescriptions on WhatsApp',
            'The PDF goes to the patient automatically when a new prescription is saved',
          ),
          trailing: Switch(
            value: _rxAuto,
            activeColor: d.teal,
            onChanged: !canEdit || _saving || s == null
                ? null
                : (v) {
                    setState(() => _rxAuto = v);
                    _save(phone: _savedPhone);
                  },
          ),
        ),
        _divider(d),

        // ── weekly summary ──
        LayoutBuilder(
          builder: (context, c) {
            final field = _summaryField(d, canEdit, s != null, phoneChanged);
            final title = _title(
              d,
              'Weekly summary to owner',
              summaryOn
                  ? 'Every Sunday ~7 PM to ${_display(_savedPhone)}'
                  : 'Off · add a number to get visits, money in, expenses and still owed every Sunday ~7 PM',
            );
            // side by side when there's room, the number under the text when not
            if (c.maxWidth >= 720) {
              return _row(
                d,
                icon: Icons.insights_rounded,
                tone: summaryOn ? d.ice : d.text4,
                text: title,
                trailing: field,
              );
            }
            return _row(
              d,
              icon: Icons.insights_rounded,
              tone: summaryOn ? d.ice : d.text4,
              text: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 10), field],
              ),
            );
          },
        ),
        _divider(d),

        // ── log ──
        _row(
          d,
          icon: Icons.history_rounded,
          tone: d.ice,
          text: _title(
            d,
            'Message log',
            'Every WhatsApp from this branch — sent, waiting, failed and why',
          ),
          trailing: OutlinedButton.icon(
            onPressed: () => showWaLogDialog(
              context,
              branchUuid: widget.branchUuid,
              branchName: widget.branchName,
            ),
            icon: Icon(Icons.open_in_new_rounded, size: 16, color: d.ice),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: d.line),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            label: Text(
              'Open',
              style: TextStyle(fontSize: 10.sp, color: d.text1),
            ),
          ),
        ),
      ],
    );
  }

  /// Number box + Save, kept together so they never split across lines.
  Widget _summaryField(
    DentColors d,
    bool canEdit,
    bool ready,
    bool phoneChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
        child: SizedBox(
          width: 15.w,
          height: 40,
          child: TextField(
            controller: _phone,
            enabled: canEdit && ready,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 10.sp, color: d.text1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: d.surface2,
              hintText: '03xx xxxxxxx',
              hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
              prefixIcon: Icon(Icons.phone_rounded, size: 16, color: d.text4),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: d.ice, width: 1.4),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppPalette.onAccent,
                ),
              )
            : Text(
                _phone.text.trim().isEmpty && _savedPhone.isNotEmpty
                    ? 'Turn off'
                    : 'Save',
                style: TextStyle(fontSize: 10.sp),
              ),
      ),
    ],
  );

  /// One setting: tinted icon tile · title and explanation · control.
  Widget _row(
    DentColors d, {
    required IconData icon,
    required Color tone,
    required Widget text,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 13.sp, color: tone),
        ),
        const SizedBox(width: 14),
        Expanded(child: text),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    ),
  );

  Widget _divider(DentColors d) =>
      Divider(height: 1, indent: 70, endIndent: 18, color: d.line);

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
      const SizedBox(height: 2),
      Text(
        sub,
        style: TextStyle(color: d.text3, fontSize: 10.sp, height: 1.35),
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

enum _LogFilter { all, waiting, failed, sent }

class _WaLog extends ConsumerStatefulWidget {
  const _WaLog({required this.branchUuid, required this.branchName});
  final String branchUuid, branchName;
  @override
  ConsumerState<_WaLog> createState() => _WaLogState();
}

class _WaLogState extends ConsumerState<_WaLog> {
  _LogFilter _filter = _LogFilter.all;

  bool _matches(WaLogEntry e) => switch (_filter) {
    _LogFilter.all => true,
    _LogFilter.waiting => e.isWaiting,
    _LogFilter.failed => e.status == 'failed',
    _LogFilter.sent => e.status == 'sent',
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final branchUuid = widget.branchUuid;
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
    final shown = list.where(_matches).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 84.h),
      child: Container(
        clipBehavior: Clip.antiAlias,
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
                color: d.surface2.withValues(alpha: .5),
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: d.teal.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: d.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Message log · ${widget.branchName}',
                          style: TextStyle(
                            color: d.text1,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        icon: async.isLoading && list.isNotEmpty
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: d.text3,
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                size: 18,
                                color: d.text3,
                              ),
                        onPressed: () =>
                            ref.invalidate(waLogProvider(branchUuid)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: d.text3,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // filters double as the day's numbers
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(d, _LogFilter.all, 'All', list.length, d.text2),
                      _chip(
                        d,
                        _LogFilter.sent,
                        'Sent today $sentToday',
                        null,
                        d.tealDeep,
                      ),
                      _chip(d, _LogFilter.waiting, 'Waiting', waiting, d.ice),
                      _chip(d, _LogFilter.failed, 'Failed', failed, d.alert),
                    ],
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
                  ? _empty(
                      d,
                      Icons.cloud_off_rounded,
                      'Could not load the log (needs internet).',
                      tone: d.alert,
                    )
                  : list.isEmpty
                  ? _empty(
                      d,
                      Icons.chat_bubble_outline_rounded,
                      'No WhatsApp messages yet from this branch.',
                    )
                  : shown.isEmpty
                  ? _empty(
                      d,
                      Icons.filter_alt_off_rounded,
                      'Nothing here for this filter.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _row(d, shown[i], canEdit),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    DentColors d,
    _LogFilter f,
    String label,
    int? count,
    Color tone,
  ) {
    final on = _filter == f;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? tone.withValues(alpha: .14) : d.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? tone : d.line),
        ),
        child: Text(
          count == null ? label : '$label  $count',
          style: TextStyle(
            color: on ? tone : d.text3,
            fontSize: 9.5.sp,
            fontWeight: on ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _empty(DentColors d, IconData icon, String text, {Color? tone}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: tone ?? d.text4),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: tone ?? d.text4, fontSize: 10.sp),
            ),
          ],
        ),
      );

  Widget _row(DentColors d, WaLogEntry e, bool canEdit) {
    final branchUuid = widget.branchUuid;
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
            style: TextStyle(
              color: d.text3,
              fontSize: 9.sp,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
