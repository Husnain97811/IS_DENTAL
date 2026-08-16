import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../constants/views.dart';

// ─────────────────────────────────────────────
// Kind
// ─────────────────────────────────────────────
enum DentDialogKind { success, warning, error }

// ─────────────────────────────────────────────
// Copyable row model
// ─────────────────────────────────────────────
class DentDialogRow {
  const DentDialogRow(this.label, this.value);
  final String label;
  final String value;
}

// ─────────────────────────────────────────────
// Launcher
// ─────────────────────────────────────────────
Future<bool?> showDentDialog(
  BuildContext context, {
  required DentDialogKind kind,
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  List<DentDialogRow> rows = const [],
  String? inputLabel, // optional text input
  String? inputHint,
  String? inputInitial,
}) => showDialog<bool>(
  context: context,
  builder: (_) => DentDialog(
    kind: kind,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    rows: rows,
    inputLabel: inputLabel,
    inputHint: inputHint,
    inputInitial: inputInitial,
  ),
);

// ─────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────
class DentDialog extends StatefulWidget {
  const DentDialog({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.confirmLabel = 'OK',
    this.cancelLabel,
    this.rows = const [],
    this.inputLabel,
    this.inputHint,
    this.inputInitial,
  });

  final DentDialogKind kind;
  final String title;
  final String message;
  final String confirmLabel;
  final String? cancelLabel;
  final List<DentDialogRow> rows;
  final String? inputLabel;
  final String? inputHint;
  final String? inputInitial;

  @override
  State<DentDialog> createState() => _DentDialogState();
}

class _DentDialogState extends State<DentDialog> {
  late final TextEditingController? _inputCtrl;

  @override
  void initState() {
    super.initState();
    _inputCtrl = widget.inputLabel != null
        ? TextEditingController(text: widget.inputInitial ?? '')
        : null;
  }

  @override
  void dispose() {
    _inputCtrl?.dispose();
    super.dispose();
  }

  // ── kind → visuals ──
  _KindStyle _style(DentColors d) => switch (widget.kind) {
    DentDialogKind.success => _KindStyle(
      icon: Icons.check_circle_rounded,
      iconColor: d.teal,
      bgColor: d.teal.withValues(alpha: .13),
      buttonColor: d.ice,
    ),
    DentDialogKind.warning => _KindStyle(
      icon: Icons.warning_amber_rounded,
      iconColor: d.warn,
      bgColor: d.warn.withValues(alpha: .13),
      buttonColor: d.warn,
    ),
    DentDialogKind.error => _KindStyle(
      icon: Icons.error_rounded,
      iconColor: d.alert,
      bgColor: d.alert.withValues(alpha: .13),
      buttonColor: d.alert,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final s = _style(d);

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
              // ── Icon ──
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: s.bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(s.icon, color: s.iconColor, size: 36),
                ),
              ),
              SizedBox(height: 1.6.h),

              // ── Title ──
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),

              // ── Message ──
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: d.text3, fontSize: 10.5.sp),
              ),

              // ── Copyable rows ──
              if (widget.rows.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final row in widget.rows)
                  _credRow(d, row.label, row.value),
              ],

              // ── Optional input ──
              if (widget.inputLabel != null) ...[
                const SizedBox(height: 16),
                Text(
                  widget.inputLabel!.toUpperCase(),
                  style: TextStyle(
                    color: d.text4,
                    fontSize: 7.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _inputCtrl,
                  style: TextStyle(fontSize: 9.sp, color: d.text1),
                  decoration: InputDecoration(
                    hintText: widget.inputHint,
                    hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                    isDense: true,
                    filled: true,
                    fillColor: d.surface2,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: d.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: d.ice, width: 1.5),
                    ),
                  ),
                ),
              ],

              SizedBox(height: 2.h),

              // ── Buttons ──
              if (widget.cancelLabel != null) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: d.text2,
                    side: BorderSide(color: d.line),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(widget.cancelLabel!),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: s.buttonColor,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(widget.confirmLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credRow(DentColors d, String label, String value) => Container(
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
}

// ── internal style holder ──
class _KindStyle {
  const _KindStyle({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.buttonColor,
  });
  final IconData icon;
  final Color iconColor, bgColor, buttonColor;
}
