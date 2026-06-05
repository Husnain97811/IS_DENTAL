import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../theme/app_radii.dart';
import '../theme/dent_colors.dart';

/// Standard surface panel with an optional header (title + subtitle + trailing).
class DentPanel extends StatelessWidget {
  const DentPanel({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padBody = false});
  final String? title, subtitle;
  final Widget? trailing, child;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return Container(
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: d.line),
        boxShadow: d.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.line))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title!, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(color: d.text4, fontSize: 8.5.sp))),
              ])),
              if (trailing != null) trailing!,
            ]),
          ),
        if (child != null) Padding(padding: EdgeInsets.all(padBody ? 18 : 0), child: child!),
      ]),
    );
  }
}

/// The "Details ›" style header link.
class PanelLink extends StatelessWidget {
  const PanelLink(this.label, {super.key, this.onTap, this.icon = Icons.arrow_forward_rounded});
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    return InkWell(onTap: onTap, child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(color: d.ice, fontSize: 8.5.sp, fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      Icon(icon, size: 14, color: d.ice),
    ]));
  }
}
