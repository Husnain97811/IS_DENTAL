import 'branch.dart';

abstract interface class BranchRepository {
  Stream<List<Branch>> watchBranches();
  Future<void> upsertBranch(Branch b);
  Future<void> softDeleteBranch(int id);
}
