import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../branches/presentation/branch_controller.dart';
import '../data/offer_repository.dart';
import '../domain/offer.dart';

final offerRepositoryProvider = Provider<OfferRepository>(
  (ref) => OfferRepository(ref.watch(appDatabaseProvider)),
);

final offersProvider = StreamProvider.autoDispose<List<Offer>>(
  (ref) => ref
      .watch(offerRepositoryProvider)
      .watchOffers(branchId: ref.watch(activeBranchProvider)),
);
