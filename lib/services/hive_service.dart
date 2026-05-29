import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../models/conversation.dart';

class HiveService {
  static const String _tasBox = 'tas';
  static const String _worldsBox = 'worlds';
  static const String _conversationsBox = 'conversations';
  static const String _settingsBox = 'settings';

  Future<void> init() async {
    await Hive.initFlutter();
  }

  Future<List<TA>> getTas() async {
    final box = await Hive.openBox<String>(_tasBox);
    return box.values.map((json) => TA.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveTas(List<TA> tas) async {
    final box = await Hive.openBox<String>(_tasBox);
    await box.clear();
    for (int i = 0; i < tas.length; i++) {
      await box.put(i.toString(), jsonEncode(tas[i].toJson()));
    }
  }

  Future<void> upsertTa(TA ta) async {
    final box = await Hive.openBox<String>(_tasBox);
    final tas = await getTas();
    final index = tas.indexWhere((t) => t.id == ta.id);
    if (index >= 0) {
      await box.putAt(index, jsonEncode(ta.toJson()));
    } else {
      await box.add(jsonEncode(ta.toJson()));
    }
  }

  Future<void> deleteTa(String id) async {
    final box = await Hive.openBox<String>(_tasBox);
    final tas = await getTas();
    final index = tas.indexWhere((t) => t.id == id);
    if (index >= 0) {
      await box.deleteAt(index);
    }
  }

  Future<List<World>> getWorlds() async {
    final box = await Hive.openBox<String>(_worldsBox);
    return box.values.map((json) => World.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveWorlds(List<World> worlds) async {
    final box = await Hive.openBox<String>(_worldsBox);
    await box.clear();
    for (int i = 0; i < worlds.length; i++) {
      await box.put(i.toString(), jsonEncode(worlds[i].toJson()));
    }
  }

  Future<void> upsertWorld(World world) async {
    final box = await Hive.openBox<String>(_worldsBox);
    final worlds = await getWorlds();
    final index = worlds.indexWhere((w) => w.id == world.id);
    if (index >= 0) {
      await box.putAt(index, jsonEncode(world.toJson()));
    } else {
      await box.add(jsonEncode(world.toJson()));
    }
  }

  Future<void> deleteWorld(String id) async {
    final box = await Hive.openBox<String>(_worldsBox);
    final worlds = await getWorlds();
    final index = worlds.indexWhere((w) => w.id == id);
    if (index >= 0) {
      await box.deleteAt(index);
    }
  }

  Future<List<Conversation>> getConversations() async {
    final box = await Hive.openBox<String>(_conversationsBox);
    return box.values.map((json) => Conversation.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    final box = await Hive.openBox<String>(_conversationsBox);
    await box.clear();
    for (int i = 0; i < conversations.length; i++) {
      await box.put(i.toString(), jsonEncode(conversations[i].toJson()));
    }
  }

  Future<void> upsertConversation(Conversation conversation) async {
    final box = await Hive.openBox<String>(_conversationsBox);
    final conversations = await getConversations();
    final index = conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      await box.putAt(index, jsonEncode(conversation.toJson()));
    } else {
      await box.add(jsonEncode(conversation.toJson()));
    }
  }

  Future<void> deleteConversation(String id) async {
    final box = await Hive.openBox<String>(_conversationsBox);
    final conversations = await getConversations();
    final index = conversations.indexWhere((c) => c.id == id);
    if (index >= 0) {
      await box.deleteAt(index);
    }
  }

  Future<void> clearAll() async {
    await Hive.deleteBoxFromDisk(_tasBox);
    await Hive.deleteBoxFromDisk(_worldsBox);
    await Hive.deleteBoxFromDisk(_conversationsBox);
    await Hive.deleteBoxFromDisk(_settingsBox);
  }
}
