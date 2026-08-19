import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../data/wa_inbox_service.dart';

final waInboxServiceProvider = Provider((_) => WaInboxService());

final waConversationsProvider =
    FutureProvider.autoDispose<List<WaConversation>>((ref) async {
      final clinicId =
          await ref.watch(appDatabaseProvider).currentClinicId() ?? '';
      if (clinicId.isEmpty) return [];
      return ref.watch(waInboxServiceProvider).fetchConversations(clinicId);
    });
