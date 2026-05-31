import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/ta.dart';
import '../models/dialogue_style.dart';
import 'database_helper.dart';

class TaDbService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<TA>> getAll() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tas',
      orderBy: 'sort_order ASC, updated_at DESC',
    );
    return maps.map((map) => _mapToTa(map)).toList();
  }

  Future<TA?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tas',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return _mapToTa(maps.first);
  }

  Future<void> insert(TA ta) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'tas',
      _taToMap(ta),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(TA ta) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'tas',
      _taToMap(ta),
      where: 'id = ?',
      whereArgs: [ta.id],
    );
  }

  Future<void> upsert(TA ta) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'tas',
      _taToMap(ta),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'tas',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSortOrder(List<String> orderedIds) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'tas',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> insertBatch(List<TA> tas) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final ta in tas) {
        await txn.insert(
          'tas',
          _taToMap(ta),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Update the original link for a TA (immutable, can only be set once)
  Future<void> setOriginalLink(String id, String originalLink) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'tas',
      {'original_link': originalLink},
      where: 'id = ? AND (original_link IS NULL OR original_link = \'\')',
      whereArgs: [id],
    );
  }

  /// Get the original link for a TA
  Future<String?> getOriginalLink(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tas',
      columns: ['original_link'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return maps.first['original_link'] as String?;
  }

  TA _mapToTa(Map<String, dynamic> map) {
    return TA(
      id: map['id'] as String,
      name: map['name'] as String,
      gender: map['gender'] as String,
      persona: map['persona'] as String,
      intro: map['intro'] as String,
      opening: map['opening'] as String,
      tags: (jsonDecode(map['tags'] as String) as List).cast<String>(),
      images: (jsonDecode(map['images'] as String) as Map).cast<String, String>(),
      dialogueStyle: (jsonDecode(map['dialogue_style'] as String) as List)
          .map((e) => DialogueTurn.fromJson(e as Map<String, dynamic>))
          .toList(),
      archived: map['archived'] == 1,
    );
  }

  Map<String, dynamic> _taToMap(TA ta) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'id': ta.id,
      'name': ta.name,
      'gender': ta.gender,
      'persona': ta.persona,
      'intro': ta.intro,
      'opening': ta.opening,
      'tags': jsonEncode(ta.tags),
      'images': jsonEncode(ta.images),
      'dialogue_style': jsonEncode(ta.dialogueStyle.map((t) => t.toJson()).toList()),
      'archived': ta.archived ? 1 : 0,
      'updated_at': now,
    };
  }

  /// Update the original link for a TA (immutable, can only be set once)
  Future<void> setOriginalLink(String id, String originalLink) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'tas',
      {'original_link': originalLink},
      where: 'id = ? AND (original_link IS NULL OR original_link = \'\')',
      whereArgs: [id],
    );
  }

  /// Get the original link for a TA
  Future<String?> getOriginalLink(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tas',
      columns: ['original_link'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return maps.first['original_link'] as String?;
  }
}
