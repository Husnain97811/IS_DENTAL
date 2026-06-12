import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/db/app_database.dart';
import '../data/inventory_repository_impl.dart';
import '../domain/inventory_item.dart';
import '../domain/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepositoryImpl(ref.watch(appDatabaseProvider)),
);
final inventoryStreamProvider = StreamProvider.autoDispose<List<InventoryItem>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchItems(),
);
final lowStockOnlyProvider = StateProvider<bool>((_) => false);
