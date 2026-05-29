import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/world.dart';
import 'database_helper.dart';

class WorldDbService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<World>> getAll() async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'worlds',
      orderBy: 'sort_order ASC, updated_at DESC',
    );
    return maps.map((map) => _mapToWorld(map)).toList();
  }

  Future<World?> getById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'worlds',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return _mapToWorld(maps.first);
  }

  Future<void> insert(World world) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'worlds',
      _worldToMap(world),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(World world) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'worlds',
      _worldToMap(world),
      where: 'id = ?',
      whereArgs: [world.id],
    );
  }

  Future<void> upsert(World world) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'worlds',
      _worldToMap(world),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'worlds',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateSortOrder(List<String> orderedIds) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'worlds',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> insertBatch(List<World> worlds) async {
    final Database db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final world in worlds) {
        await txn.insert(
          'worlds',
          _worldToMap(world),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  World _mapToWorld(Map<String, dynamic> map) {
    return World(
      id: map['id'] as String,
      name: map['name'] as String,
      summary: map['summary'] as String? ?? '',
      description: map['description'] as String,
      tags: (jsonDecode(map['tags'] as String) as List).cast<String>(),
      forbiddenWords: (jsonDecode(map['forbidden_words'] as String) as List).cast<String>(),
      entries: (jsonDecode(map['entries'] as String) as List)
          .map((e) => WorldEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      archived: map['archived'] == 1,
    );
  }

  Map<String, dynamic> _worldToMap(World world) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'id': world.id,
      'name': world.name,
      'summary': world.summary,
      'description': world.description,
      'tags': jsonEncode(world.tags),
      'forbidden_words': jsonEncode(world.forbiddenWords),
      'entries': jsonEncode(world.entries.map((e) => e.toJson()).toList()),
      'archived': world.archived ? 1 : 0,
      'updated_at': now,
    };
  }
}
