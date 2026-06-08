import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../../core/theme/dent_colors.dart';
import '../../domain/tooth_record.dart';

class Odontogram extends StatelessWidget {
  const Odontogram({super.key, required this.states, required this.onToothTap});
  final Map<int, ToothState> states;
  final void Function(int fdi) onToothTap;

  static const _upper = [
    18,
    17,
    16,
    15,
    14,
    13,
    12,
    11,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
  ];
  static const _lower = [
    48,
    47,
    46,
    45,
    44,
    43,
    42,
    41,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _arch(context, _upper),
        const SizedBox(height: 7),
        _arch(context, _lower),
        const SizedBox(height: 13),
        Wrap(
          spacing: 13,
          runSpacing: 9,
          children: [
            _legend(d, d.surface2, d.line2, 'Healthy'),
            _legend(d, d.warn.withValues(alpha: .5), d.warn, 'Caries'),
            _legend(d, d.ice.withValues(alpha: .6), d.ice, 'Treated'),
            _legend(d, d.teal.withValues(alpha: .6), d.tealDeep, 'Crown'),
            _legend(d, d.line2, d.line2, 'Missing'),
          ],
        ),
      ],
    );
  }

  Widget _arch(BuildContext context, List<int> teeth) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: teeth
          .map((n) => _tooth(context, n, states[n] ?? ToothState.healthy))
          .toList(),
    ),
  );

  Widget _tooth(BuildContext context, int fdi, ToothState state) {
    final d = context.dent;
    final (fill, border) = _colors(state, d);
    return Tooltip(
      message: 'Tooth $fdi · ${state.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => onToothTap(fdi),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.6),
          child: Opacity(
            opacity: state == ToothState.missing ? .55 : 1,
            child: Container(
              width: 17,
              height: 22,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                  bottom: Radius.circular(6),
                ),
                border: Border.all(color: border),
              ),
              child: state == ToothState.missing
                  ? CustomPaint(painter: _Slash(d.line2))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color) _colors(ToothState s, DentColors d) => switch (s) {
    ToothState.healthy => (d.surface2, d.line2),
    ToothState.caries => (d.warn.withValues(alpha: .4), d.warn),
    ToothState.treated => (d.ice.withValues(alpha: .45), d.ice),
    ToothState.crown => (d.teal.withValues(alpha: .45), d.tealDeep),
    ToothState.missing => (d.surface2, d.line2),
  };

  Widget _legend(DentColors d, Color fill, Color border, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: border),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(color: d.text3, fontSize: 7.5.sp),
      ),
    ],
  );
}

class _Slash extends CustomPainter {
  _Slash(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) => c.drawLine(
    Offset(2, s.height - 2),
    Offset(s.width - 2, 2),
    Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round,
  );
  @override
  bool shouldRepaint(covariant _Slash old) => old.color != color;
}
