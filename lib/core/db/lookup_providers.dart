import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

/// Owner-editable dropdown lists, both kinds out of `lookup_lists`.
final paymentMethodsProvider = StreamProvider<List<LookupRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchLookups('payment_method'),
);

final expenseCategoriesProvider = StreamProvider<List<LookupRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchLookups('expense_category'),
);
