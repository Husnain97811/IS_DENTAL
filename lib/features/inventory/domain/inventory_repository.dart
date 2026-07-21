import 'inventory_item.dart';

abstract interface class InventoryRepository {
  Stream<List<InventoryItem>> watchItems({String? branchId});
  Future<void> adjustStock(int id, int delta);
  Future<void> seedDemoIfEmpty();

  Future<void> upsertItem(InventoryItem item);
}
