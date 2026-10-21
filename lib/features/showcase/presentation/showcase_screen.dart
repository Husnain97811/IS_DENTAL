import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';
import '../../../core/constants/views.dart';
import 'package:is_dental/core/widgets/plan_locked.dart';
import '../data/showcase_cases.dart';
import 'showcase_slideshow.dart';
import 'widgets/crop_editor.dart';
import 'widgets/cropped_photo.dart';
import 'widgets/showcase_export_dialog.dart';

/// Opens one case large, with the before/after slider.
Future<void> openShowcaseCase(BuildContext context, ShowcaseCase c) =>
    showDialog(
      context: context,
      builder: (_) => _CaseViewer(c: c),
    );

/// The clinic's portfolio: every before & after result a patient agreed to
/// share, ready to show, post or play on the waiting-room screen.
/// No patient names anywhere on this screen — safe to open in front of
/// other patients.
class ShowcaseScreen extends ConsumerStatefulWidget {
  const ShowcaseScreen({super.key});
  @override
  ConsumerState<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends ConsumerState<ShowcaseScreen> {
  String? _treatment; // null = all
  bool _bestOnly = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(entitlementsProvider).showcase) {
      return const SingleChildScrollView(
        child: PlanLocked(
          feature: 'Smile Showcase',
          icon: Icons.auto_awesome_rounded,
          pitch:
              'Turn your best before & after results into marketing — '
              'with the patient\'s consent, and never their name.',
          points: [
            'Gallery of every consented case, best ones starred',
            'Ready-to-post pictures for Instagram, Facebook and your website',
            'Full-screen slideshow for the waiting-room TV',
            'Crop each photo to the smile in seconds',
          ],
        ),
      );
    }
    final d = context.dent;
    final async = ref.watch(showcaseCasesProvider);
    final all = async.value ?? const <ShowcaseCase>[];
    // the top bar's search: treatment, tooth or the patient's name
    final query = ref.watch(showcaseSearchProvider).trim();
    final people = query.isEmpty
        ? const <String, ShowcasePatient>{}
        : ref.watch(showcasePatientsProvider).value ??
              const <String, ShowcasePatient>{};

    // treatment → number of cases, most common first
    final counts = <String, int>{};
    for (final c in all) {
      counts[c.title] = (counts[c.title] ?? 0) + 1;
    }
    final treatments = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (_treatment != null && !counts.containsKey(_treatment))
      _treatment = null;

    final shown = [
      for (final c in all)
        if ((_treatment == null || c.title == _treatment) &&
            (!_bestOnly || c.featured) &&
            c.matches(query, patientName: people[c.patientUuid]?.name ?? ''))
          c,
    ];
    final starred = all.where((c) => c.featured).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        (1.8.w).clamp(16.0, 28.0),
        20,
        (1.8.w).clamp(16.0, 28.0),
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── toolbar ──
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(
                        d,
                        'All',
                        all.length,
                        _treatment == null,
                        () => setState(() => _treatment = null),
                      ),
                      for (final t in treatments)
                        _chip(
                          d,
                          t,
                          counts[t]!,
                          _treatment == t,
                          () => setState(() => _treatment = t),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                selected: _bestOnly,
                // stays clickable while on, so it can always be switched off
                onSelected: starred == 0 && !_bestOnly
                    ? null
                    : (v) => setState(() => _bestOnly = v),
                showCheckmark: false,
                avatar: Icon(
                  _bestOnly ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 17,
                  color: _bestOnly ? d.warn : d.text3,
                ),
                label: Text(
                  'Best only ($starred)',
                  style: TextStyle(fontSize: 9.5.sp),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: shown.any((c) => c.isLocal)
                    ? () => _slideshow(shown)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: d.ice,
                  foregroundColor: AppPalette.onAccent,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.slideshow_rounded, size: 18),
                label: Text('Slideshow', style: TextStyle(fontSize: 10.sp)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 15, color: d.tealDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${shown.length} case${shown.length == 1 ? '' : 's'}'
                  '${query.isEmpty ? '' : ' matching “$query”'}'
                  ' · every patient here agreed to share · no names shown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.text3, fontSize: 9.sp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── content ──
          Expanded(
            child: async.isLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : all.isEmpty
                ? const _EmptyShowcase()
                : shown.isEmpty
                ? Center(
                    child: Text(
                      query.isNotEmpty
                          ? 'No cases match “$query”${_treatment != null || _bestOnly ? ' with these filters' : ''}.'
                          : 'No starred cases for this treatment yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: d.text4, fontSize: 10.5.sp),
                    ),
                  )
                : LayoutBuilder(builder: (_, box) => _grid(box, shown)),
          ),
        ],
      ),
    );
  }

  Widget _grid(BoxConstraints box, List<ShowcaseCase> cases) {
    const gap = 18.0;
    final cols = (box.maxWidth / 380).floor().clamp(1, 5);
    final tileW = (box.maxWidth - gap * (cols - 1)) / cols;
    // two 4:3 photos side by side + the caption under them
    final tileH = tileW * 3 / 8 + 76;
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: cases.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        mainAxisExtent: tileH,
      ),
      itemBuilder: (_, i) => _CaseCard(c: cases[i]),
    );
  }

  Widget _chip(DentColors d, String label, int n, bool on, VoidCallback tap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: on,
          onSelected: (_) => tap(),
          showCheckmark: false,
          selectedColor: d.ice.withValues(alpha: .16),
          side: BorderSide(color: on ? d.ice : d.line),
          label: Text(
            '$label  $n',
            style: TextStyle(
              fontSize: 9.5.sp,
              color: on ? d.ice : d.text2,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );

  Future<void> _slideshow(List<ShowcaseCase> cases) async {
    final clinic = await ref.read(appDatabaseProvider).clinicName() ?? '';
    if (!mounted) return;
    await openShowcaseSlideshow(
      context,
      cases: cases.where((c) => c.isLocal).toList(),
      clinicName: clinic,
    );
  }
}

// ═════════════════════════════════════════════════════════════ card ══════
class _CaseCard extends ConsumerStatefulWidget {
  const _CaseCard({required this.c});
  final ShowcaseCase c;
  @override
  ConsumerState<_CaseCard> createState() => _CaseCardState();
}

class _CaseCardState extends ConsumerState<_CaseCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final c = widget.c;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? d.ice.withValues(alpha: .6) : d.line,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? .12 : .04),
              blurRadius: _hover ? 22 : 8,
              offset: Offset(0, _hover ? 10 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => openShowcaseCase(context, c),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: CroppedPhoto(
                                photo: c.before,
                                crop: c.beforeCrop,
                              ),
                            ),
                          ),
                          Container(width: 2, color: d.surface),
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: CroppedPhoto(
                                photo: c.after,
                                crop: c.afterCrop,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _MiniTag(
                          'BEFORE',
                          Colors.black.withValues(alpha: .55),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _MiniTag('AFTER', d.tealDeep),
                      ),
                      Positioned(top: 8, right: 8, child: _StarButton(c: c)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: d.text1,
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: d.text4,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      [
                                        c.durationShort,
                                        if (c.tooth.isNotEmpty)
                                          'Tooth ${c.tooth}',
                                      ].join('  ·  '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: d.text3,
                                        fontSize: 9.sp,
                                      ),
                                    ),
                                  ),
                                  if (c.isCropped) ...[
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Cropped to the smile',
                                      child: Icon(
                                        Icons.crop_rounded,
                                        size: 13,
                                        color: d.tealDeep,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        _CaseMenu(c: c),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text, this.bg);
  final String text;
  final Color bg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 7.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    ),
  );
}

class _StarButton extends ConsumerWidget {
  const _StarButton({required this.c, this.big = false});
  final ShowcaseCase c;
  final bool big;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = context.dent;
    final on = c.featured;
    return Tooltip(
      message: on ? 'Remove from best cases' : 'Mark as one of the best',
      child: Material(
        color: Colors.white.withValues(alpha: .92),
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () =>
              ref.read(xrayRepositoryProvider).setCaseFeatured(c.id, !on),
          child: Padding(
            padding: EdgeInsets.all(big ? 8 : 6),
            child: Icon(
              on ? Icons.star_rounded : Icons.star_outline_rounded,
              size: big ? 22 : 18,
              color: on ? d.warn : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseMenu extends StatelessWidget {
  const _CaseMenu({required this.c});
  final ShowcaseCase c;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert_rounded, size: 19, color: d.text3),
      color: d.surface,
      onSelected: (v) => switch (v) {
        'post' => showShowcaseExport(context, c),
        'crop' => showCropEditor(context, c),
        _ => openShowcaseCase(context, c),
      },
      itemBuilder: (_) => [
        _item(d, 'view', Icons.compare_rounded, 'Open large', true),
        _item(d, 'post', Icons.ios_share_rounded, 'Create a post', c.isLocal),
        _item(d, 'crop', Icons.crop_rounded, 'Crop to the smile', c.isLocal),
      ],
    );
  }

  PopupMenuItem<String> _item(
    DentColors d,
    String v,
    IconData i,
    String t,
    bool enabled,
  ) => PopupMenuItem(
    value: v,
    enabled: enabled,
    child: Row(
      children: [
        Icon(i, size: 17, color: enabled ? d.text2 : d.text4),
        const SizedBox(width: 10),
        Text(t, style: TextStyle(fontSize: 10.sp)),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════ viewer ════
/// One case, large: drag the divider to compare. Star, crop and post from
/// here; the consent record is shown underneath.
class _CaseViewer extends ConsumerStatefulWidget {
  const _CaseViewer({required this.c});
  final ShowcaseCase c;
  @override
  ConsumerState<_CaseViewer> createState() => _CaseViewerState();
}

class _CaseViewerState extends ConsumerState<_CaseViewer> {
  double _t = .5;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    // follow live changes (star, crop) while the dialog is open
    final live = ref.watch(showcaseCasesProvider).value;
    var c = widget.c;
    for (final x in live ?? const <ShowcaseCase>[]) {
      if (x.id == c.id) c = x;
    }
    final maxW = 100.w < 900 ? 94.w : 62.w;
    final consent = c.consentAt == null
        ? 'Consent given by the patient'
        : 'Consent recorded${c.consentBy.isEmpty ? '' : ' by ${c.consentBy}'} on ${_d(c.consentAt!)}';

    return Dialog(
      backgroundColor: d.surface,
      insetPadding: EdgeInsets.all((2.w).clamp(12.0, 40.0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 92.h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: d.text1,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            c.durationLine,
                            if (c.tooth.isNotEmpty) 'Tooth ${c.tooth}',
                            '${_d(c.before.takenAt)} → ${_d(c.after.takenAt)}',
                          ].join('  ·  '),
                          style: TextStyle(color: d.text3, fontSize: 9.5.sp),
                        ),
                      ],
                    ),
                  ),
                  _StarButton(c: c, big: true),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: d.text3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final w = box.maxHeight.isFinite
                          ? (box.maxHeight * 4 / 3).clamp(0.0, box.maxWidth)
                          : box.maxWidth;
                      final h = w * 3 / 4;
                      void move(Offset p) =>
                          setState(() => _t = (p.dx / w).clamp(.02, .98));
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: GestureDetector(
                              onHorizontalDragUpdate: (e) =>
                                  move(e.localPosition),
                              onTapDown: (e) => move(e.localPosition),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CroppedPhoto(
                                      photo: c.after,
                                      crop: c.afterCrop,
                                    ),
                                    ClipRect(
                                      clipper: _LeftPart(_t),
                                      child: CroppedPhoto(
                                        photo: c.before,
                                        crop: c.beforeCrop,
                                      ),
                                    ),
                                    Positioned(
                                      left: _t * w - 1.5,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 3,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Positioned(
                                      left: _t * w - 19,
                                      top: h / 2 - 19,
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.compare_arrows_rounded,
                                          size: 20,
                                          color: d.text2,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: _MiniTag(
                                        'BEFORE',
                                        Colors.black.withValues(alpha: .6),
                                      ),
                                    ),
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: _MiniTag('AFTER', d.tealDeep),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: d.tealDeep,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        consent,
                        style: TextStyle(color: d.text3, fontSize: 9.sp),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: c.isLocal
                          ? () => showCropEditor(context, c)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: d.text2,
                        side: BorderSide(color: d.line),
                        minimumSize: const Size(0, 42),
                      ),
                      icon: const Icon(Icons.crop_rounded, size: 17),
                      label: Text(
                        c.isCropped ? 'Adjust crop' : 'Crop to the smile',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: c.isLocal
                          ? () => showShowcaseExport(context, c)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: d.ice,
                        foregroundColor: AppPalette.onAccent,
                        minimumSize: const Size(0, 42),
                      ),
                      icon: const Icon(Icons.ios_share_rounded, size: 17),
                      label: Text(
                        'Create a post',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeftPart extends CustomClipper<Rect> {
  const _LeftPart(this.t);
  final double t;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);
  @override
  bool shouldReclip(_LeftPart old) => old.t != t;
}

// ═════════════════════════════════════════════════════════════ empty ═════
class _EmptyShowcase extends StatelessWidget {
  const _EmptyShowcase();

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    Widget step(String n, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: d.ice.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Text(
              n,
              style: TextStyle(
                color: d.ice,
                fontSize: 9.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            t,
            style: TextStyle(color: d.text2, fontSize: 10.sp),
          ),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d.ice.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 34, color: d.ice),
            ),
            const SizedBox(height: 18),
            Text(
              'Your showcase is empty',
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: d.text1,
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your best results will appear here — ready to post, show and play.',
              style: TextStyle(color: d.text3, fontSize: 10.5.sp),
            ),
            const SizedBox(height: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                step('1', 'Open a patient → Before & After'),
                step('2', 'Add a Before and an After photo'),
                step('3', 'Tick "Patient allows use in clinic marketing"'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _d(DateTime t) {
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
  return '${t.day} ${m[t.month - 1]} ${t.year}';
}
