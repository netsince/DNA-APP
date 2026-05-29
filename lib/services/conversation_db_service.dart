import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/conversation.dart';
import 'database_helper.dart';

class ConversationDbService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<Conversation>> getAll({bool? archived}) async {
    final Database db = await _dbHelper.database;
    String? where;
    List<dynamic>? whereArgs;
    if (archived != null) {
      where = 'archived = ? AND is_group = 0';
      whereArgs = [archived ? 1 : 0];
    } else {
      where = 'is_group = 0';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, updated_at DESC',
    );

    final List<Conversation> conversations = [];
    for (final map in maps) {
      final conversation = await _loadConversationWithRelations(db, map);
      conversations.add(conversation);
    }
    return conversations;
  }

  Future<List<Conversation>> getAllGroups({bool? archived}) async {
    final Database db = await _dbHelper.database;
    String? where;
    List<dynamic>? whereArgs;
    if (archived != null) {
      where = 'archived = ? AND is_group = 1';
      whereArgs = [archived ? 1 : 0];
    } else {
      where = 'is_group = 1';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, updated_at DESC',
    );

    final List<Conversation> conversations = [];
    for (final map in maps) {
      final conversation = await _loadConversationWithRelations(db, map);
      conversations.add(conversation);
    }
    return conversations;
  }

  Future<Conversation?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return _loadConversationWithRelations(db, maps.first);
  }

  Future<void> insert(Conversation conversation) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'conversations',
        _conversationToMap(conversation),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _saveMessages(txn, conversation.id, conversation.messages);
      await _saveSummaries(txn, conversation.id, conversation.summaries);
    });
  }

  Future<void> update(Conversation conversation) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'conversations',
        _conversationToMap(conversation),
        where: 'id = ?',
        whereArgs: [conversation.id],
      );
      await txn.delete(
        'conversation_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversation.id],
      );
      await txn.delete(
        'conversation_summaries',
        where: 'conversation_id = ?',
        whereArgs: [conversation.id],
      );
      await _saveMessages(txn, conversation.id, conversation.messages);
      await _saveSummaries(txn, conversation.id, conversation.summaries);
    });
  }

  Future<void> upsert(Conversation conversation) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'conversations',
        _conversationToMap(conversation),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'conversation_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversation.id],
      );
      await txn.delete(
        'conversation_summaries',
        where: 'conversation_id = ?',
        whereArgs: [conversation.id],
      );
      await _saveMessages(txn, conversation.id, conversation.messages);
      await _saveSummaries(txn, conversation.id, conversation.summaries);
    });
  }

  Future<void> delete(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSortOrder(List<String> orderedIds) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'conversations',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> setArchived(String id, bool archived) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'conversations',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertBatch(List<Conversation> conversations) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final conversation in conversations) {
        await txn.insert(
          'conversations',
          _conversationToMap(conversation),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _saveMessages(txn, conversation.id, conversation.messages);
        await _saveSummaries(txn, conversation.id, conversation.summaries);
      }
    });
  }

  Future<Conversation> _loadConversationWithRelations(Database db, Map<String, dynamic> map) async {
    final String conversationId = map['id'] as String;

    final List<Map<String, dynamic>> messageMaps = await db.query(
      'conversation_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    final List<ConversationMessage> messages = messageMaps
        .map((m) => _mapToMessage(m))
        .toList();

    final List<Map<String, dynamic>> summaryMaps = await db.query(
      'conversation_summaries',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    final List<ConversationSummary> summaries = summaryMaps
        .map((s) => _mapToSummary(s))
        .toList();

    return _mapToConversation(map, messages, summaries);
  }

  Future<void> _saveMessages(Transaction txn, String conversationId, List<ConversationMessage> messages) async {
    for (final message in messages) {
      await txn.insert(
        'conversation_messages',
        _messageToMap(conversationId, message),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _saveSummaries(Transaction txn, String conversationId, List<ConversationSummary> summaries) async {
    for (final summary in summaries) {
      await txn.insert(
        'conversation_summaries',
        _summaryToMap(conversationId, summary),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Conversation _mapToConversation(
    Map<String, dynamic> map,
    List<ConversationMessage> messages,
    List<ConversationSummary> summaries,
  ) {
    return Conversation(
      id: map['id'] as String,
      taId: map['ta_id'] as String,
      worldId: map['world_id'] as String?,
      note: map['note'] as String,
      messages: messages,
      backgroundMode: map['background_mode'] as String,
      summaries: summaries,
      archived: map['archived'] == 1,
      isGroup: map['is_group'] == 1,
      groupName: map['group_name'] as String,
      groupPrompt: map['group_prompt'] as String,
      memberTaIds: (jsonDecode(map['member_ta_ids'] as String) as List).cast<String>(),
      activeTaId: map['active_ta_id'] as String?,
    );
  }

  Map<String, dynamic> _conversationToMap(Conversation conversation) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'id': conversation.id,
      'ta_id': conversation.taId,
      'world_id': conversation.worldId,
      'note': conversation.note,
      'background_mode': conversation.backgroundMode,
      'archived': conversation.archived ? 1 : 0,
      'is_group': conversation.isGroup ? 1 : 0,
      'group_name': conversation.groupName,
      'group_prompt': conversation.groupPrompt,
      'member_ta_ids': jsonEncode(conversation.memberTaIds),
      'active_ta_id': conversation.activeTaId,
      'updated_at': now,
    };
  }

  ConversationMessage _mapToMessage(Map<String, dynamic> map) {
    return ConversationMessage(
      id: map['id'] as String,
      role: map['role'] as String,
      text: map['text'] as String,
      timestamp: map['timestamp'] as int,
      kind: map['kind'] as String,
      summaryId: map['summary_id'] as String?,
      anchorMessageId: map['anchor_message_id'] as String?,
      speakerTaId: map['speaker_ta_id'] as String?,
    );
  }

  Map<String, dynamic> _messageToMap(String conversationId, ConversationMessage message) {
    return {
      'id': message.id,
      'conversation_id': conversationId,
      'role': message.role,
      'text': message.text,
      'timestamp': message.timestamp,
      'kind': message.kind,
      'summary_id': message.summaryId,
      'anchor_message_id': message.anchorMessageId,
      'speaker_ta_id': message.speakerTaId,
    };
  }

  ConversationSummary _mapToSummary(Map<String, dynamic> map) {
    return ConversationSummary(
      id: map['id'] as String,
      text: map['text'] as String,
      createdAt: map['created_at'] as int,
      endMessageId: map['end_message_id'] as String,
    );
  }

  Map<String, dynamic> _summaryToMap(String conversationId, ConversationSummary summary) {
    return {
      'id': summary.id,
      'conversation_id': conversationId,
      'text': summary.text,
      'created_at': summary.createdAt,
      'end_message_id': summary.endMessageId,
    };
  }
}
