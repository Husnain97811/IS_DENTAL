import 'package:supabase_flutter/supabase_flutter.dart';

class WaMessage {
  WaMessage({
    required this.waNumber,
    required this.patientName,
    required this.direction,
    required this.body,
    required this.createdAt,
  });
  final String waNumber;
  final String? patientName;
  final String direction; // 'in' | 'out'
  final String body;
  final DateTime createdAt;
}

class WaConversation {
  WaConversation({
    required this.waNumber,
    required this.patientName,
    required this.lastMessage,
    required this.lastAt,
    required this.messages,
  });
  final String waNumber;
  final String? patientName;
  final String lastMessage;
  final DateTime lastAt;
  final List<WaMessage> messages;
}

class WaInboxService {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Fetch recent messages, grouped into conversations by wa_number.
  Future<List<WaConversation>> fetchConversations(String clinicId) async {
    final rows =
        (await _sb
                .from('wa_messages')
                .select()
                .eq('clinic_id', clinicId)
                .order('created_at', ascending: false)
                .limit(500))
            as List;

    final byNumber = <String, List<WaMessage>>{};
    final names = <String, String?>{};
    for (final r in rows) {
      final num = r['wa_number'] as String;
      names[num] = r['patient_name'] as String?;
      byNumber
          .putIfAbsent(num, () => [])
          .add(
            WaMessage(
              waNumber: num,
              patientName: r['patient_name'] as String?,
              direction: r['direction'] as String,
              body: r['body'] as String? ?? '',
              createdAt: DateTime.parse(r['created_at']),
            ),
          );
    }

    final convos = byNumber.entries.map((e) {
      final msgs = e.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final last = msgs.last;
      return WaConversation(
        waNumber: e.key,
        patientName: names[e.key],
        lastMessage: last.body,
        lastAt: last.createdAt,
        messages: msgs,
      );
    }).toList();

    convos.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return convos;
  }
}
