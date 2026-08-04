import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:is_dental/features/requests/data/booking_request_repository_impl.dart';
import '../../../core/db/app_database.dart';
import '../../branches/presentation/branch_controller.dart';
import '../domain/booking_request.dart';

final bookingRequestRepositoryProvider = Provider<BookingRequestRepository>(
  (ref) => BookingRequestRepository(ref.watch(appDatabaseProvider)),
);

/// Pending requests for the active branch (owner null = all).
final pendingRequestsProvider =
    StreamProvider.autoDispose<List<BookingRequestView>>(
      (ref) => ref
          .watch(bookingRequestRepositoryProvider)
          .watch(status: 'pending', branchId: ref.watch(activeBranchProvider)),
    );

final pendingRequestsCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref
      .watch(bookingRequestRepositoryProvider)
      .watchPendingCount(branchId: ref.watch(activeBranchProvider)),
);

/// For the full-screen tabs.
final requestsByStatusProvider = StreamProvider.autoDispose
    .family<List<BookingRequestView>, String>(
      (ref, status) => ref
          .watch(bookingRequestRepositoryProvider)
          .watch(status: status, branchId: ref.watch(activeBranchProvider)),
    );
