import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../router/nav_destinations.dart';
import '../../theme/dent_colors.dart';

class ContextualDrawer extends StatelessWidget {
  const ContextualDrawer({super.key, required this.kind});
  final DrawerKind kind;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      width: 332,
      decoration: BoxDecoration(color: d.surface, border: Border(left: BorderSide(color: d.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.line))),
          child: Row(children: [
            Expanded(child: Text(_titleFor(kind), style: Theme.of(context).textTheme.titleMedium)),
            Text('PINNED', style: TextStyle(color: d.ice, fontSize: 7.sp, fontWeight: FontWeight.w700, letterSpacing: .5)),
          ]),
        ),
        Expanded(child: Center(child: Padding(
          padding: EdgeInsets.all(6.w),
          child: Text('${_titleFor(kind)}\n(wired up in its feature phase)',
              textAlign: TextAlign.center, style: TextStyle(color: d.text4, fontSize: 9.sp, height: 1.6)),
        ))),
      ]),
    );
  }

  String _titleFor(DrawerKind k) => switch (k) {
        DrawerKind.patient => 'Patient Snapshot',
        DrawerKind.booking => 'Quick Book',
        DrawerKind.invoice => 'Invoice Preview',
        DrawerKind.none => '',
      };
}
