import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';
import '../prescription_controller.dart';

Future<void> showPrecautionSetEditor(
  BuildContext context, {
  PrecautionSet? existing,
}) => showDialog(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: _SetEditor(existing: existing),
  ),
);

class _SetEditor extends ConsumerStatefulWidget {
  const _SetEditor({this.existing});
  final PrecautionSet? existing;
  @override
  ConsumerState<_SetEditor> createState() => _S();
}

class _LineRow {
  _LineRow([CareLine? l]) {
    if (l != null) {
      urdu.text = l.urdu;
      english.text = l.english;
    }
  }
  final urdu = TextEditingController();
  final english = TextEditingController();
  void dispose() {
    urdu.dispose();
    english.dispose();
  }

  CareLine toLine() =>
      CareLine(urdu: urdu.text.trim(), english: english.text.trim());
}

class _S extends ConsumerState<_SetEditor> {
  final _name = TextEditingController();
  final List<_LineRow> _rows = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      for (final l in e.lines) _rows.add(_LineRow(l));
    }
    if (_rows.isEmpty) _rows.add(_LineRow());
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final maxW = 100.w < 720 ? 94.w : 62.w;
    final canSave =
        _name.text.trim().isNotEmpty && _rows.any((r) => !r.toLine().isEmpty);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: 90.h),
      child: Container(
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: d.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
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
                      color: d.teal.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.rule_rounded,
                      size: 17,
                      color: d.tealDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.existing == null
                              ? 'New Precaution Set'
                              : 'Edit Precaution Set',
                          style: TextStyle(
                            fontSize: 12.5.sp,
                            color: d.text1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Aftercare lines the doctor can click while prescribing',
                          style: TextStyle(fontSize: 9.5.sp, color: d.text3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(d, 'Set name'),
                    SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _name,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 10.5.sp, color: d.text1),
                        decoration: _dec(
                          d,
                          'e.g. After Extraction — دانت نکالنے کے بعد',
                        ),
                      ),
                    ),

                    _lbl(d, 'Lines'),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'URDU',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: d.text4,
                              fontSize: 8.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ENGLISH',
                            style: TextStyle(
                              color: d.text4,
                              fontSize: 8.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 8),

                    for (var i = 0; i < _rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: TextField(
                                  controller: _rows[i].urdu,
                                  onChanged: (_) => setState(() {}),
                                  textAlign: TextAlign.right,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    fontFamily: 'NotoNaskhArabic',
                                    fontSize: 12.sp,
                                    color: d.text1,
                                    height: 1.8,
                                  ),
                                  decoration: _dec(d, 'اردو میں ہدایت'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: TextField(
                                  controller: _rows[i].english,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    fontSize: 10.5.sp,
                                    color: d.text1,
                                  ),
                                  decoration: _dec(d, 'English instruction'),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: d.alert,
                                ),
                                onPressed: _rows.length == 1
                                    ? null
                                    : () => setState(() {
                                        _rows.removeAt(i).dispose();
                                      }),
                              ),
                            ),
                          ],
                        ),
                      ),

                    OutlinedButton.icon(
                      onPressed: () => setState(() => _rows.add(_LineRow())),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: d.tealDeep,
                        side: BorderSide(
                          color: d.tealDeep.withValues(alpha: .5),
                        ),
                      ),
                      label: Text(
                        'Add line',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'You can fill just Urdu, just English, or both. Whether each '
                      'language prints is controlled in the print format settings.',
                      style: TextStyle(color: d.text4, fontSize: 9.5.sp),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: canSave ? d.ice : d.line,
                      foregroundColor: AppPalette.onAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    onPressed: (!canSave || _busy) ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Save Set', style: TextStyle(fontSize: 10.5.sp)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final lines = _rows
        .map((r) => r.toLine())
        .where((l) => !l.isEmpty)
        .toList();
    await ref
        .read(prescriptionRepositoryProvider)
        .saveSet(
          id: widget.existing?.id,
          name: _name.text.trim(),
          lines: lines,
        );
    if (mounted) Navigator.pop(context);
  }

  Widget _lbl(DentColors d, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 7),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        color: d.text4,
        fontSize: 8.5.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );

  InputDecoration _dec(DentColors d, String hint) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: d.surface2,
    hintText: hint,
    hintStyle: TextStyle(color: d.text4, fontSize: 10.sp),
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: d.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: d.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: d.ice),
    ),
  );
}
