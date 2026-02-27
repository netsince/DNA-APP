import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

class ChatSnapshotStore {
  static const String _snapshotKeyPrefix = 'conversation_snapshots_v1_';

  Future<List<ChatSnapshot>> loadSnapshots(String conversationId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('$_snapshotKeyPrefix$conversationId') ?? '';
    if (raw.isEmpty) {
      return <ChatSnapshot>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <ChatSnapshot>[];
      }
      return decoded
          .whereType<Map>()
          .map((Map item) => ChatSnapshot.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <ChatSnapshot>[];
    }
  }

  Future<void> saveSnapshots(String conversationId, List<ChatSnapshot> snapshots) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(snapshots.map((s) => s.toJson()).toList());
    await prefs.setString('$_snapshotKeyPrefix$conversationId', raw);
  }
}
