import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../pages/chat/chat_models.dart';
import 'database_helper.dart';

class ChatSnapshotDbService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<ChatSnapshot>> getByConversationId(String conversationId) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'chat_snapshots',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => _mapToSnapshot(map)).toList();
  }

  Future<ChatSnapshot?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'chat_snapshots',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return _mapToSnapshot(maps.first);
  }

  Future<void> insert(String conversationId, ChatSnapshot snapshot) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'chat_snapshots',
      _snapshotToMap(conversationId, snapshot),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(String conversationId, ChatSnapshot snapshot) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'chat_snapshots',
      _snapshotToMap(conversationId, snapshot),
      where: 'id = ?',
      whereArgs: [snapshot.id],
    );
  }

  Future<void> upsert(String conversationId, ChatSnapshot snapshot) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'chat_snapshots',
      _snapshotToMap(conversationId, snapshot),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'chat_snapshots',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteByConversationId(String conversationId) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'chat_snapshots',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> insertBatch(String conversationId, List<ChatSnapshot> snapshots) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final snapshot in snapshots) {
        await txn.insert(
          'chat_snapshots',
          _snapshotToMap(conversationId, snapshot),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  ChatSnapshot _mapToSnapshot(Map<String, dynamic> map) {
    return ChatSnapshot(
      id: map['id'] as String,
      name: map['name'] as String,
      timestamp: map['timestamp'] as int,
      data: jsonDecode(map['data'] as String) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> _snapshotToMap(String conversationId, ChatSnapshot snapshot) {
    return {
      'id': snapshot.id,
      'conversation_id': conversationId,
      'name': snapshot.name,
      'timestamp': snapshot.timestamp,
      'data': jsonEncode(snapshot.data),
    };
  }
}
