import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sizer/sizer.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/dent_colors.dart';
import '../../../core/widgets/dent_panel.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/inventory_item.dart';
import 'inventory_controller.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _q = '';
  @override
  void initState() {
    super.initState();
    if (kDebugMode)
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(inventoryRepositoryProvider).seedDemoIfEmpty(),
      );
  }

  (ChipKind, String, Color) _st(InventoryItem it, DentColors d) =>
      switch (it.level) {
        StockLevel.ok => (ChipKind.done, 'In Stock', d.ice),
        StockLevel.low => (ChipKind.waiting, 'Low Stock', d.warn),
        StockLevel.critical => (
          ChipKind.overdue,
          it.inStock == 0 ? 'Out' : 'Critical',
          d.alert,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final d = context.dent;
    final lowOnly = ref.watch(lowStockOnlyProvider);
    final async = ref.watch(inventoryStreamProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Inventory', style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 4),
          Text(
            'Supplies, materials & stock control.',
            style: TextStyle(color: d.text3, fontSize: 9.sp),
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  style: TextStyle(fontSize: 9.sp, color: d.text1),
                  decoration: InputDecoration(
                    hintText: 'Search supplies…',
                    isDense: true,
                    filled: true,
                    fillColor: d.surface,
                    hintStyle: TextStyle(color: d.text4, fontSize: 9.sp),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: d.text4,
                      size: 11.sp,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: d.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: d.ice, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilterChip(
                selected: lowOnly,
                label: const Text('⚠ Low stock only'),
                onSelected: (v) =>
                    ref.read(lowStockOnlyProvider.notifier).state = v,
                selectedColor: d.alert.withValues(alpha: .14),
                checkmarkColor: d.alert,
              ),
            ],
          ),
          SizedBox(height: 1.6.h),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: d.alert)),
            data: (all) {
              var list = all
                  .where((i) => i.name.toLowerCase().contains(_q.toLowerCase()))
                  .toList();
              if (lowOnly)
                list = list.where((i) => i.level != StockLevel.ok).toList();
              return DentPanel(
                child: Column(
                  children: [
                    _header(d),
                    for (final it in list) _row(d, it),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No items.',
                          style: TextStyle(color: d.text4),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _header(DentColors d) {
    TextStyle h() => TextStyle(
      color: d.text4,
      fontSize: 7.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: .7,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('ITEM', style: h())),
          Expanded(flex: 2, child: Text('CATEGORY', style: h())),
          Expanded(flex: 2, child: Text('IN STOCK', style: h())),
          Expanded(flex: 2, child: Text('LEVEL', style: h())),
          Expanded(flex: 2, child: Text('STATUS', style: h())),
        ],
      ),
    );
  }

  Widget _row(DentColors d, InventoryItem it) {
    final (chip, label, barColor) = _st(it, d);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              it.name,
              style: TextStyle(
                color: d.text1,
                fontSize: 9.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              it.category,
              style: TextStyle(color: d.text2, fontSize: 8.5.sp),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${it.inStock} ${it.unit}',
              style: AppTypography.mono(size: 8.5.sp, color: d.text1),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 7,
              width: 90,
              decoration: BoxDecoration(
                color: d.surface2,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: it.fraction == 0 ? 0.04 : it.fraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(label, kind: chip),
            ),
          ),
        ],
      ),
    );
  }
}
