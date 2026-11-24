import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:dna/services/shared_prefs.dart';

import '../models/conversation.dart';

class ConversationService {
  static const String _key = 'conversations_v1';

  Future<List<Conversation>> load() async {
    final SharedPreferences prefs = await SharedPrefs.instance;
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <Conversation>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(Conversation.fromJson)
            .toList();
      }
    } catch (_) {}
    return <Conversation>[];
  }

  Future<void> save(List<Conversation> conversations) async {
    final SharedPreferences prefs = await SharedPrefs.instance;
    final String raw = jsonEncode(
      conversations.map((Conversation c) => c.toJson()).toList(),
    );
    await prefs.setString(_key, raw);
  }
}
