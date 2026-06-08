import 'package:freezed_annotation/freezed_annotation.dart';
part 'inventory_item.freezed.dart';

enum StockLevel { ok, low, critical }

@freezed
abstract class InventoryItem with _$InventoryItem {
  const InventoryItem._();
  const factory InventoryItem({
    required int id,
    required String uuid,
    required String name,
    required String category,
    @Default(0) int inStock,
    @Default(0) int parLevel,
    @Default(0) int reorderAt,
    @Default('units') String unit,
  }) = _InventoryItem;

  StockLevel get level {
    if (inStock == 0 || inStock <= reorderAt / 2) return StockLevel.critical;
    if (inStock <= reorderAt) return StockLevel.low;
    return StockLevel.ok;
  }

  double get fraction =>
      parLevel == 0 ? 0 : (inStock / parLevel).clamp(0, 1).toDouble();
}
