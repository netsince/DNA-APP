import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/world.dart';

class WorldService {
  static const String _worldsKey = 'worlds_v1';

  Future<List<World>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_worldsKey);
    if (raw == null || raw.isEmpty) {
      return <World>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(World.fromJson)
            .toList();
      }
    } catch (_) {}
    return <World>[];
  }

  Future<void> save(List<World> worlds) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(worlds.map((World world) => world.toJson()).toList());
    await prefs.setString(_worldsKey, raw);
  }
}
