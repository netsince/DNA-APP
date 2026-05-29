import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../models/conversation.dart';
import 'ta_db_service.dart';
import 'world_db_service.dart';
import 'conversation_db_service.dart';

class MigrationService {
  static const String _migrationKey = 'db_migration_completed_v1';

  final TaDbService _taDbService = TaDbService();
  final WorldDbService _worldDbService = WorldDbService();
  final ConversationDbService _conversationDbService = ConversationDbService();

  Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final bool migrationCompleted = prefs.getBool(_migrationKey) ?? false;

    if (migrationCompleted) {
      return;
    }

    await _migrateTas();
    await _migrateWorlds();
    await _migrateConversations();
    await _migrateGroupConversations();

    await prefs.setBool(_migrationKey, true);
  }

  Future<void> _migrateTas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('tas_v1');
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<TA> tas = decoded
            .whereType<Map<String, dynamic>>()
            .map(TA.fromJson)
            .toList();
        await _taDbService.insertBatch(tas);
      }
    } catch (e) {
      print('Migration: Failed to migrate TAs: $e');
    }
  }

  Future<void> _migrateWorlds() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('worlds_v1');
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<World> worlds = decoded
            .whereType<Map<String, dynamic>>()
            .map(World.fromJson)
            .toList();
        await _worldDbService.insertBatch(worlds);
      }
    } catch (e) {
      print('Migration: Failed to migrate Worlds: $e');
    }
  }

  Future<void> _migrateConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('conversations_v1');
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<Conversation> conversations = decoded
            .whereType<Map<String, dynamic>>()
            .map(Conversation.fromJson)
            .toList();
        await _conversationDbService.insertBatch(conversations);
      }
    } catch (e) {
      print('Migration: Failed to migrate Conversations: $e');
    }
  }

  Future<void> _migrateGroupConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('group_conversations_v1');
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<Conversation> conversations = decoded
            .whereType<Map<String, dynamic>>()
            .map(Conversation.fromJson)
            .toList();
        await _conversationDbService.insertBatch(conversations);
      }
    } catch (e) {
      print('Migration: Failed to migrate Group Conversations: $e');
    }
  }

  Future<void> clearOldData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tas_v1');
    await prefs.remove('worlds_v1');
    await prefs.remove('conversations_v1');
    await prefs.remove('group_conversations_v1');
  }
}
