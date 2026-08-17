import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../../data/wa_connect_service.dart';

Future<void> showWaConnectDialog(
  BuildContext context, {
  required String branchId,
  required String branchName,
}) => showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => _WaConnectDialog(branchId: branchId, branchName: branchName),
);

class _WaConnectDialog extends ConsumerStatefulWidget {
  const _WaConnectDialog({required this.branchId, required this.branchName});
  final String branchId;
  final String branchName;
  @override
  ConsumerState<_WaConnectDialog> createState() => _WaConnectDialogState();
}

class _WaConnectDialogState extends ConsumerState<_WaConnectDialog> {
  final _svc = WaConnectService();
  String? _qr;
  String _status = 'connecting';
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _status = 'connecting';
      _error = null;
      _qr = null;
    });
    final r = await _svc.connect(widget.branchId);
    if (!mounted) return;
    if (r.error != null) {
      setState(() {
        _error = r.error;
        _status = 'error';
      });
      return;
    }
    setState(() {
      _qr = r.qr;
      _status = r.status;
    });
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      final r = await _svc.status(widget.branchId);
      if (!mounted) return;
      setState(() {
        _status = r.status;
        if (r.qr != null) _qr = r.qr; // refresh rotating QR
      });
      if (r.status == 'connected') {
        _poll?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final connected = _status == 'connected';

    return Dialog(
      backgroundColor: d.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.chat_rounded, color: d.teal, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connect WhatsApp · ${widget.branchName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (connected) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: d.teal.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_rounded, color: d.teal, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        'WhatsApp Connected',
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This branch can now send WhatsApp reminders.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: d.ice,
                    foregroundColor: AppPalette.onAccent,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ] else if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: d.alert.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Could not connect: $_error',
                    style: TextStyle(color: d.alert, fontSize: 8.5.sp),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _start,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.text2,
                    side: BorderSide(color: d.line),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Retry'),
                ),
              ] else ...[
                Text(
                  'Open WhatsApp on the clinic phone → Linked Devices → '
                  'Link a Device → scan this code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                ),
                const SizedBox(height: 18),
                if (_qr != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: d.line),
                    ),
                    child: Image.memory(
                      base64Decode(_qr!.split(',').last),
                      width: 220,
                      height: 220,
                      gaplessPlayback: true, // avoid flicker on QR refresh
                    ),
                  )
                else
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: d.surface2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: d.text4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Waiting for scan…',
                      style: TextStyle(color: d.text4, fontSize: 8.sp),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
