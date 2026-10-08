import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/cloud/data/quick_sync.dart';
import 'package:is_dental/core/db/app_database.dart';
import 'package:sizer/sizer.dart';
import '../../../../core/constants/views.dart';
import '../../data/expense_repository.dart';

/// Right-hand sheet for managing expense categories and payment methods.
/// Lives here rather than in Settings: this is where the lists are used.
Future<void> showListsManager(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black.withValues(alpha: .35),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, __, ___) => const _ListsManager(),
  transitionBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

class _ListsManager extends ConsumerStatefulWidget {
  const _ListsManager();
  @override
  ConsumerState<_ListsManager> createState() => _ListsManagerState();
}

class _ListsManagerState extends ConsumerState<_ListsManager> {
  int _tab = 0;
  bool _showHidden = false;
  int? _editingId;
  final _edit = TextEditingController();
  final _add = TextEditingController();

  String get _kind => _tab == 0 ? 'expense_category' : 'payment_method';
  String get _noun => _tab == 0 ? 'category' : 'method';

  @override
  void dispose() {
    _edit.dispose();
    _add.dispose();
    super.dispose();
  }

  Future<void> _save(int id, String original) async {
    final name = _edit.text.trim();
    setState(() => _editingId = null);
    if (name.isEmpty || name == original) return;
    await ref.read(expenseRepositoryProvider).renameLookup(id, name);
    syncInBackground(ref);
  }

  Future<void> _create() async {
    final name = _add.text.trim();
    if (name.isEmpty) return;
    _add.clear();
    await ref.read(expenseRepositoryProvider).addLookup(_kind, name);
    syncInBackground(ref);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final all = ref.watch(allLookupsProvider(_kind)).value ?? const [];
    final counts = ref.watch(categoryUsageProvider).value ?? const {};
    final visible = all.where((r) => !r.isDeleted).toList();
    final hidden = all.where((r) => r.isDeleted).toList();

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: d.surface,
        child: SizedBox(
          width: 420,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── header ──
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 16),
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
                        color: d.ice.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.tune_rounded, color: d.ice, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manage Lists',
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: d.text1,
                            ),
                          ),
                          Text(
                            'Categories and payment methods',
                            style: TextStyle(color: d.text3, fontSize: 8.5.sp),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: d.text3),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── tabs ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
                child: SegmentedControl(
                  items: const ['Categories', 'Payment Methods'],
                  selected: _tab,
                  onChanged: (i) => setState(() {
                    _tab = i;
                    _editingId = null;
                    _add.clear();
                  }),
                ),
              ),

              // ── add row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _add,
                        style: TextStyle(color: d.text1, fontSize: 10.sp),
                        onSubmitted: (_) => _create(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'New $_noun…',
                          hintStyle: TextStyle(
                            color: d.text4,
                            fontSize: 9.5.sp,
                          ),
                          filled: true,
                          fillColor: d.surface2,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 13,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: BorderSide(color: d.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: BorderSide(color: d.ice),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size(52, 46),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _create,
                      child: const Icon(Icons.add_rounded, size: 20),
                    ),
                  ],
                ),
              ),

              // ── list ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      _tile(d, visible[i], counts, i, visible.length),

                    if (hidden.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => setState(() => _showHidden = !_showHidden),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _showHidden
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 17,
                                color: d.text4,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${hidden.length} hidden',
                                style: TextStyle(
                                  color: d.text4,
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showHidden)
                        for (final r in hidden) _hiddenTile(d, r, counts),
                    ],
                  ],
                ),
              ),

              // ── footer note ──
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: d.line)),
                ),
                child: Text(
                  _tab == 0
                      ? 'Hiding a category only removes it from the dropdown. '
                            'Expenses already using it keep their category and '
                            'still appear in reports.'
                      : 'Methods are stored as text on each expense, so '
                            'renaming one here never changes past records.',
                  style: TextStyle(
                    color: d.text3,
                    fontSize: 10.sp,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    DentColors d,
    LookupRow r,
    Map<String, int> counts,
    int index,
    int total,
  ) {
    final editing = _editingId == r.id;
    final used = counts[r.uuid] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: editing ? d.surface2 : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: editing ? d.ice : d.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: editing
                ? TextField(
                    controller: _edit,
                    autofocus: true,
                    style: TextStyle(
                      color: d.text1,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _save(r.id, r.name),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.name,
                        style: TextStyle(
                          color: d.text1,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_tab == 0)
                        Text(
                          used == 0
                              ? 'Not used yet'
                              : '$used expense${used == 1 ? "" : "s"}',
                          style: TextStyle(color: d.text3, fontSize: 9.sp),
                        ),
                    ],
                  ),
          ),
          if (editing) ...[
            IconButton(
              tooltip: 'Save',
              icon: Icon(Icons.check_rounded, size: 17, color: d.teal),
              onPressed: () => _save(r.id, r.name),
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: Icon(Icons.close_rounded, size: 17, color: d.text4),
              onPressed: () => setState(() => _editingId = null),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Move up',
              icon: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 17,
                color: index == 0 ? d.line : d.text4,
              ),
              onPressed: index == 0 ? null : () => _move(r, -1),
            ),
            IconButton(
              tooltip: 'Move down',
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: index == total - 1 ? d.line : d.text4,
              ),
              onPressed: index == total - 1 ? null : () => _move(r, 1),
            ),
            IconButton(
              tooltip: 'Rename',
              icon: Icon(Icons.edit_outlined, size: 16, color: d.text4),
              onPressed: () => setState(() {
                _editingId = r.id;
                _edit.text = r.name;
              }),
            ),
            IconButton(
              tooltip: 'Hide',
              icon: Icon(
                Icons.visibility_off_outlined,
                size: 16,
                color: d.text4,
              ),
              onPressed: () => _hide(r, used),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hiddenTile(DentColors d, LookupRow r, Map<String, int> counts) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: d.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                r.name,
                style: TextStyle(
                  color: d.text4,
                  fontSize: 10.sp,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: d.ice),
              onPressed: () => _restore(r),
              icon: const Icon(Icons.undo_rounded, size: 15),
              label: Text('Restore', style: TextStyle(fontSize: 9.sp)),
            ),
          ],
        ),
      );

  Future<void> _move(LookupRow r, int by) async {
    await ref.read(expenseRepositoryProvider).moveLookup(r.id, _kind, by);
    syncInBackground(ref);
  }

  Future<void> _restore(LookupRow r) async {
    await ref.read(expenseRepositoryProvider).restoreLookup(r.id);
    syncInBackground(ref);
  }

  Future<void> _hide(LookupRow r, int used) async {
    final ok = await showDentDialog(
      context,
      kind: DentDialogKind.warning,
      title: 'Hide "${r.name}"?',
      message: used == 0
          ? 'It disappears from the dropdown. You can restore it any time.'
          : '$used expense${used == 1 ? "" : "s"} already use this $_noun. '
                'They keep it and still appear in reports — it just '
                'disappears from the dropdown for new entries.',
      confirmLabel: 'Hide',
      cancelLabel: 'Cancel',
    );
    if (ok != true) return;
    await ref.read(expenseRepositoryProvider).hideLookup(r.id);
    syncInBackground(ref);
  }
}
