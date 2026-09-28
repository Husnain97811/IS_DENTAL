import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/constants/views.dart';

class LicencePanel extends ConsumerStatefulWidget {
  const LicencePanel({super.key});
  @override
  ConsumerState<LicencePanel> createState() => _S();
}

class _S extends ConsumerState<LicencePanel> {
  final _raw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final session = ref.watch(authControllerProvider);
    if (session?.role != AppRole.owner) return const SizedBox.shrink();

    final lic = ref.watch(licenseControllerProvider).value?.license;
    final ent = ref.watch(entitlementsProvider);
    if (lic == null) return const SizedBox.shrink();

    final daysLeft = lic.expiresAt.difference(DateTime.now()).inDays;

    return DentPanel(
      title: 'Licence',
      subtitle: 'Paste a new licence to upgrade or renew',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(
              d,
              'Plan',
              '${ent.tierLabel == 'Basic' ? "Basic" : ent.tierLabel}${ent.cloud ? " · Cloud" : " · Offline"}',
            ),
            _rowCopy(d, 'Clinic ID', lic.clinicId),
            _row(d, 'Branches', '${lic.maxBranches} allowed'),
            _row(d, 'Staff logins', '${lic.maxUsers} allowed'),
            _row(
              d,
              'Expires',
              '${_fmt(lic.expiresAt)}'
                  '${daysLeft < 0 ? "  ·  expired" : "  ·  $daysLeft days left"}',
              warn: daysLeft < 30,
            ),

            const SizedBox(height: 18),
            Text(
              'NEW LICENCE',
              style: TextStyle(
                color: d.text4,
                fontSize: 8.5.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _raw,
              maxLines: 4,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 9.5.sp,
                color: d.text1,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: d.surface2,
                hintText: '{"clinicId":"…',
                hintStyle: TextStyle(color: d.text4, fontSize: 9.5.sp),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(color: d.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(color: d.line),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(color: d.alert, fontSize: 9.5.sp),
                ),
              ),

            const SizedBox(height: 14),
            Text(
              'Applying a new licence changes only your plan. '
              'Patients, staff, settings and cloud data are untouched.',
              style: TextStyle(color: d.text4, fontSize: 9.sp),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                onPressed: _busy ? null : _apply,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Apply licence',
                        style: TextStyle(fontSize: 10.5.sp),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    final raw = _raw.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste the licence you were sent.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final r = await ref
        .read(licenseControllerProvider.notifier)
        .reactivate(raw);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    _raw.clear();
    final ent = ref.read(entitlementsProvider);
    await showDentDialog(
      context,
      kind: DentDialogKind.success,
      title: 'Licence updated',
      message:
          'Your plan is now ${ent.tierLabel}. '
          'Nothing was removed — all your data is as it was.\n\n'
          'Some screens appear after a restart.',
      confirmLabel: 'Done',
    );
  }

  Widget _row(DentColors d, String k, String v, {bool warn = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: TextStyle(color: d.text3, fontSize: 10.sp),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              color: warn ? d.warn : d.text1,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _rowCopy(DentColors d, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: TextStyle(color: d.text3, fontSize: 10.sp),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              color: d.text1,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          icon: Icon(Icons.copy_rounded, size: 15, color: d.text4),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: v));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Clinic ID copied.')));
          },
        ),
      ],
    ),
  );

  String _fmt(DateTime d) =>
      '${d.day} '
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} '
      '${d.year}';
}
