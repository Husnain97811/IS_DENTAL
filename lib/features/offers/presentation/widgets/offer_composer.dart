import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';

/// ── FONT SCALE ──────────────────────────────────────────────
/// One number controls every font size in this screen.
/// 1.00 = original, 1.10 = 10% bigger (current), 1.15 = 15%, etc. and this is for my personal reference only.
/// Change ONLY this to rescale the whole screen's text.
const double _fontScale = 1.50;

/// Applies the scale to any base .sp size.
double _sp(double base) => base * _fontScale;
// ─────────────────────────────────────────────────────────────

Future<void> showOfferComposer(BuildContext context) => showDialog(
  context: context,
  builder: (_) => const Dialog(
    backgroundColor: Colors.transparent,
    child: _OfferComposer(),
  ),
);

class _OfferComposer extends ConsumerStatefulWidget {
  const _OfferComposer();
  @override
  ConsumerState<_OfferComposer> createState() => _OfferComposerState();
}

class _OfferComposerState extends ConsumerState<_OfferComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _imageUrl = TextEditingController();
  DateTime? _expires;
  bool _allBranches = true;
  bool _busy = false;
  int _recipients = 0;
  bool _countLoading = true;
  bool _sendApp = true;
  bool _sendWhatsApp = false;

  static const _kTitleMax = 50;
  static const _kBodyMax = 160; // notification-safe length

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _body.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCount());
  }

  void _refresh() => setState(() {});

  Future<void> _loadCount() async {
    setState(() => _countLoading = true);
    final session = ref.read(authControllerProvider);
    final isOwner = session?.role == AppRole.owner;
    final branchId = isOwner
        ? (_allBranches ? null : ref.read(activeBranchProvider))
        : session?.branchId;
    final n = await ref
        .read(offerRepositoryProvider)
        .recipientCount(branchId: branchId);
    if (mounted)
      setState(() {
        _recipients = n;
        _countLoading = false;
      });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();

    if (title.isEmpty || body.isEmpty) return;

    if (!_sendApp && !_sendWhatsApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one channel to send.')),
      );
      return;
    }

    // confirmation
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Send this offer?',
      message: _countLoading
          ? 'This will notify all patients who have the app.'
          : 'This will send a push notification to $_recipients patient'
                '${_recipients == 1 ? '' : 's'} who have the app'
                '${_allBranches ? '' : ' in this branch'}. This cannot be undone.',
      confirmLabel: 'Send to all',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;

    setState(() => _busy = true);

    // ── resolve session + branch scope by role (defined HERE) ──
    final session = ref.read(authControllerProvider);
    final isOwner = session?.role == AppRole.owner;
    final staff = session?.username ?? 'unknown';
    final branchId = isOwner
        ? (_allBranches ? null : ref.read(activeBranchProvider))
        : session?.branchId;

    final res = await ref
        .read(offerRepositoryProvider)
        .createAndSend(
          title: title,
          body: body,
          imageUrl: _imageUrl.text.trim().isEmpty
              ? null
              : _imageUrl.text.trim(),
          expiresAt: _expires,
          branchId: branchId,
          createdBy: staff,
          sendApp: _sendApp,
          sendWhatsApp: _sendWhatsApp,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);

    await showDentDialog(
      context,
      kind: res.ok ? DentDialogKind.success : DentDialogKind.error,
      title: res.ok ? 'Offer Sent' : 'Sending Issue',
      message: res.ok
          ? 'Your offer was sent to ${res.sent} patient${res.sent == 1 ? '' : 's'}.'
                '${res.sent == 0 ? ' (No patients have the app yet — it\'s saved and will reach them once they install.)' : ''}'
          : (res.error ?? 'Something went wrong.'),
      confirmLabel: 'Done',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    final isOwner = session?.role == AppRole.owner;
    final titleLeft = _kTitleMax - _title.text.length;
    final bodyLeft = _kBodyMax - _body.text.length;
    final canSend =
        _title.text.trim().isNotEmpty &&
        _body.text.trim().isNotEmpty &&
        titleLeft >= 0 &&
        bodyLeft >= 0;

    // Responsive: wider dialog on small screens, capped on large.
    final maxW = 100.w < 560 ? 92.w : 58.w;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 88.h),
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
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: d.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.ice.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.campaign_rounded, size: 18, color: d.ice),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Offer',
                          style: TextStyle(
                            fontSize: _sp(11),
                            color: d.text1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Broadcast to patients with the app',
                          style: TextStyle(fontSize: _sp(7.5), color: d.text3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: _sp(12),
                      color: d.text3,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // live preview
                    _preview(d),
                    const SizedBox(height: 18),

                    _lblRow(d, 'Title', '$titleLeft'),
                    _box(
                      d,
                      TextField(
                        controller: _title,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(_kTitleMax),
                        ],
                        style: TextStyle(fontSize: _sp(9), color: d.text1),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'e.g. Eid Special — 20% off Scaling',
                          hintStyle: TextStyle(
                            color: d.text4,
                            fontSize: _sp(9),
                          ),
                        ),
                      ),
                    ),

                    _lblRow(d, 'Message', '$bodyLeft'),
                    _box(
                      d,
                      TextField(
                        controller: _body,
                        maxLines: 3,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(_kBodyMax),
                        ],
                        style: TextStyle(fontSize: _sp(9), color: d.text1),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText:
                              'Valid till 14 Aug. Book now to claim your discount.',
                          hintStyle: TextStyle(
                            color: d.text4,
                            fontSize: _sp(9),
                          ),
                        ),
                      ),
                      tall: true,
                    ),

                    _lbl(d, 'Image URL (optional)'),
                    _box(
                      d,
                      TextField(
                        controller: _imageUrl,
                        style: TextStyle(fontSize: _sp(9), color: d.text1),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'https://…',
                          hintStyle: TextStyle(
                            color: d.text4,
                            fontSize: _sp(9),
                          ),
                        ),
                      ),
                    ),

                    // expiry + branch
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _lbl(d, 'Valid Until (optional)'),
                              InkWell(
                                onTap: _pickExpiry,
                                borderRadius: BorderRadius.circular(11),
                                child: _boxStatic(
                                  d,
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.event_rounded,
                                        size: 14,
                                        color: d.text3,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _expires == null
                                            ? 'No expiry'
                                            : '${_expires!.day}/${_expires!.month}/${_expires!.year}',
                                        style: TextStyle(
                                          fontSize: _sp(9),
                                          color: d.text1,
                                        ),
                                      ),
                                      if (_expires != null) ...[
                                        const Spacer(),
                                        InkWell(
                                          onTap: () =>
                                              setState(() => _expires = null),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 14,
                                            color: d.text4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    // branch scope toggle
                    // branch scope — OWNER ONLY
                    if (isOwner) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: d.surface2,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: d.line),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.store_mall_directory_rounded,
                              size: 16,
                              color: d.text3,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send to all branches',
                                    style: TextStyle(
                                      fontSize: 8.5.sp,
                                      color: d.text1,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _allBranches
                                        ? 'Every patient of this clinic'
                                        : 'Only this branch\'s patients',
                                    style: TextStyle(
                                      fontSize: 7.sp,
                                      color: d.text4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _allBranches,
                              activeColor: d.ice,
                              onChanged: (v) {
                                setState(() => _allBranches = v);
                                _loadCount();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    const SizedBox(height: 14),
                    Text(
                      'SEND VIA',
                      style: TextStyle(
                        color: d.text4,
                        fontSize: 7.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _channelToggle(
                            d,
                            'App Notification',
                            Icons.notifications_rounded,
                            _sendApp,
                            () => setState(() => _sendApp = !_sendApp),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _channelToggle(
                            d,
                            'WhatsApp',
                            Icons.chat_rounded,
                            _sendWhatsApp,
                            () {
                              // only allow if an official-API branch exists
                              setState(() => _sendWhatsApp = !_sendWhatsApp);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_sendWhatsApp)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'WhatsApp offers use the Official API only (per branch). '
                          'Branches without Official API connected will be skipped.',
                          style: TextStyle(color: d.text4, fontSize: 7.sp),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // recipient count
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: d.ice.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 15,
                            color: d.ice,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _countLoading
                                ? Text(
                                    'Counting recipients…',
                                    style: TextStyle(
                                      fontSize: _sp(8),
                                      color: d.text3,
                                    ),
                                  )
                                : Text(
                                    '$_recipients patient${_recipients == 1 ? '' : 's'} will receive this',
                                    style: TextStyle(
                                      fontSize: _sp(8.5),
                                      color: d.text2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // send button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: canSend ? d.ice : d.line,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: TextStyle(
                    fontSize: _sp(9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: (_busy || !canSend) ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.onAccent,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_busy ? 'Sending…' : 'Send to all patients'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelToggle(
    DentColors d,
    String label,
    IconData icon,
    bool on,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: on ? d.ice.withValues(alpha: .12) : d.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: on ? d.ice : d.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: on ? d.ice : d.text4),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: on ? d.ice : d.text2,
                fontSize: 8.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(
            on ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: on ? d.ice : d.text4,
          ),
        ],
      ),
    ),
  );

  // phone-style notification preview
  Widget _preview(DentColors d) {
    final title = _title.text.trim().isEmpty
        ? 'Your offer title'
        : _title.text.trim();
    final body = _body.text.trim().isEmpty
        ? 'Your message preview appears here.'
        : _body.text.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [d.ice.withValues(alpha: .10), d.teal.withValues(alpha: .06)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREVIEW · how it looks on the patient\'s phone',
            style: TextStyle(
              fontSize: _sp(6.5),
              color: d.text4,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: d.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [d.ice, d.tealDeep]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: _sp(8.5),
                          color: d.text1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: _sp(8), color: d.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lbl(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: _sp(7),
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  Widget _lblRow(DentColors d, String t, String counter) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          t.toUpperCase(),
          style: TextStyle(
            color: d.text4,
            fontSize: _sp(7),
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
        Text(
          counter,
          style: TextStyle(
            color: int.parse(counter) < 0 ? d.alert : d.text4,
            fontSize: _sp(7),
          ),
        ),
      ],
    ),
  );

  Widget _box(DentColors d, Widget child, {bool tall = false}) => Container(
    constraints: BoxConstraints(minHeight: tall ? 70 : 42),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    alignment: tall ? Alignment.topLeft : Alignment.centerLeft,
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: child,
  );

  Widget _boxStatic(DentColors d, Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: d.surface2,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: d.line),
    ),
    child: child,
  );
}
