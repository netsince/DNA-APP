import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/prompt_strategy.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../services/openai_service.dart';
import '../services/conversation_service.dart';
import '../services/group_conversation_service.dart';

import '../services/ta_service.dart';
import '../services/settings_service.dart';
import '../services/world_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required SettingsService settingsService,
    required OpenAiService openAiService,
    required TaService taService,
    required WorldService worldService,
    required ConversationService conversationService,
    required GroupConversationService groupConversationService,
  })  : _settingsService = settingsService,
        _openAiService = openAiService,
        _taService = taService,
        _worldService = worldService,
        _conversationService = conversationService,
        _groupConversationService = groupConversationService;

  final SettingsService _settingsService;
  final OpenAiService _openAiService;
  final TaService _taService;
  final WorldService _worldService;
  final ConversationService _conversationService;
  final GroupConversationService _groupConversationService;

  AppSettings _settings = AppSettings.empty();
  List<TA> _tas = <TA>[];
  List<World> _worlds = <World>[];
  List<Conversation> _conversations = <Conversation>[];
  List<Conversation> _groupConversations = <Conversation>[];

  AppSettings get settings => _settings;
  OpenAiService get openAiService => _openAiService;
  List<TA> get tas => _tas;
  List<World> get worlds => List<World>.unmodifiable(_worlds);
  List<Conversation> get conversations => List<Conversation>.unmodifiable(_conversations);
  List<Conversation> get groupConversations => List<Conversation>.unmodifiable(_groupConversations);

  Future<void> initialize() async {
    _settings = await _settingsService.load();
    _tas = await _taService.load();
    _worlds = await _worldService.load();
    _conversations = await _conversationService.load();
    _groupConversations = await _groupConversationService.load();
    notifyListeners();
  }

  Future<void> saveApiConfig({
    required String baseUrl,
    required String apiKey,
  }) async {
    _settings = _settings.copyWith(
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveSelectedModel(String model) async {
    _settings = _settings.copyWith(selectedModel: model.trim());
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> completeOobe() async {
    _settings = _settings.copyWith(completedOobe: true);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> restartOobe() async {
    _settings = _settings.copyWith(completedOobe: false);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveSummarySettings({
    required bool autoSummaryPrompt,
    required int summaryTurnInterval,
  }) async {
    _settings = _settings.copyWith(
      autoSummaryPrompt: autoSummaryPrompt,
      summaryTurnInterval: summaryTurnInterval,
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveRetryStrategy({required bool retrySequential}) async {
    _settings = _settings.copyWith(retrySequential: retrySequential);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveInspirationSettings({required bool includeSummary}) async {
    _settings = _settings.copyWith(
      inspirationIncludeSummary: includeSummary,
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> savePromptStrategy(PromptStrategy strategy) async {
    _settings = _settings.copyWith(promptStrategy: strategy);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> upsertTa(TA ta) async {
    final int index = _tas.indexWhere((TA item) => item.id == ta.id);
    if (index == -1) {
      _tas = <TA>[..._tas, ta];
    } else {
      final List<TA> updated = <TA>[..._tas];
      updated[index] = ta;
      _tas = updated;
    }
    await _taService.save(_tas);
    notifyListeners();
  }

  Future<void> deleteTa(String id) async {
    _tas = _tas.where((TA ta) => ta.id != id).toList();
    await _taService.save(_tas);
    notifyListeners();
  }

  Future<void> setTaArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _tas.indexWhere((TA item) => item.id == id);
    if (index == -1) {
      return;
    }
    final TA current = _tas[index];
    if (current.archived == archived) {
      return;
    }
    final List<TA> updated = <TA>[..._tas];
    updated[index] = current.copyWith(archived: archived);
    _tas = updated;
    await _taService.save(_tas);
    notifyListeners();
  }

  Future<String> storeTaImage({
    required String taId,
    required String slot,
    required String sourcePath,
  }) async {
    return _taService.storeImage(
      sourcePath: sourcePath,
      taId: taId,
      slot: slot,
    );
  }

  Future<void> upsertWorld(World world) async {
    final int index = _worlds.indexWhere((World item) => item.id == world.id);
    if (index == -1) {
      _worlds = <World>[..._worlds, world];
    } else {
      final List<World> updated = <World>[..._worlds];
      updated[index] = world;
      _worlds = updated;
    }
    await _worldService.save(_worlds);
    notifyListeners();
  }

  Future<void> deleteWorld(String id) async {
    _worlds = _worlds.where((World world) => world.id != id).toList();
    await _worldService.save(_worlds);
    notifyListeners();
  }

  Future<void> setWorldArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _worlds.indexWhere((World item) => item.id == id);
    if (index == -1) {
      return;
    }
    final World current = _worlds[index];
    if (current.archived == archived) {
      return;
    }
    final List<World> updated = <World>[..._worlds];
    updated[index] = current.copyWith(archived: archived);
    _worlds = updated;
    await _worldService.save(_worlds);
    notifyListeners();
  }

  Future<void> upsertConversation(Conversation conversation) async {
    if (conversation.isGroup) {
      await upsertGroupConversation(conversation);
      return;
    }
    final int index = _conversations.indexWhere((Conversation item) => item.id == conversation.id);
    if (index == -1) {
      _conversations = <Conversation>[..._conversations, conversation];
    } else {
      final List<Conversation> updated = <Conversation>[..._conversations];
      updated[index] = conversation;
      _conversations = updated;
    }
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Future<void> upsertGroupConversation(Conversation conversation) async {
    if (!conversation.isGroup) {
      conversation = conversation.copyWith(isGroup: true);
    }
    final int index =
        _groupConversations.indexWhere((Conversation item) => item.id == conversation.id);
    if (index == -1) {
      _groupConversations = <Conversation>[..._groupConversations, conversation];
    } else {
      final List<Conversation> updated = <Conversation>[..._groupConversations];
      updated[index] = conversation;
      _groupConversations = updated;
    }
    await _groupConversationService.save(_groupConversations);
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    _conversations = _conversations.where((Conversation item) => item.id != id).toList();
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Future<void> deleteGroupConversation(String id) async {
    _groupConversations = _groupConversations.where((Conversation item) => item.id != id).toList();
    await _groupConversationService.save(_groupConversations);
    notifyListeners();
  }

  Future<void> setConversationArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _conversations.indexWhere((Conversation item) => item.id == id);
    if (index == -1) {
      return;
    }
    final Conversation current = _conversations[index];
    if (current.archived == archived) {
      return;
    }
    final List<Conversation> updated = <Conversation>[..._conversations];
    updated[index] = current.copyWith(archived: archived);
    _conversations = updated;
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Future<void> setGroupConversationArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _groupConversations.indexWhere((Conversation item) => item.id == id);
    if (index == -1) {
      return;
    }
    final Conversation current = _groupConversations[index];
    if (current.archived == archived) {
      return;
    }
    final List<Conversation> updated = <Conversation>[..._groupConversations];
    updated[index] = current.copyWith(archived: archived);
    _groupConversations = updated;
    await _groupConversationService.save(_groupConversations);
    notifyListeners();
  }

  Future<void> reorderConversationSubset(List<String> orderedIds) async {
    if (orderedIds.isEmpty) {
      return;
    }
    final Set<String> subset = orderedIds.toSet();
    if (subset.length != orderedIds.length) {
      return;
    }
    final Map<String, Conversation> byId = <String, Conversation>{
      for (final Conversation c in _conversations) c.id: c,
    };
    for (final String id in orderedIds) {
      if (!byId.containsKey(id)) {
        return;
      }
    }
    int cursor = 0;
    final List<Conversation> updated = <Conversation>[];
    for (final Conversation c in _conversations) {
      if (!subset.contains(c.id)) {
        updated.add(c);
        continue;
      }
      updated.add(byId[orderedIds[cursor]]!);
      cursor += 1;
    }
    _conversations = updated;
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Future<void> reorderTas(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _tas.length) {
      return;
    }
    if (newIndex < 0 || newIndex > _tas.length) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final List<TA> updated = List<TA>.from(_tas);
    final TA moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _tas = updated;
    await _taService.save(_tas);
    notifyListeners();
  }

  Future<void> reorderWorlds(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _worlds.length) {
      return;
    }
    if (newIndex < 0 || newIndex > _worlds.length) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final List<World> updated = List<World>.from(_worlds);
    final World moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _worlds = updated;
    await _worldService.save(_worlds);
    notifyListeners();
  }

  Future<void> reorderConversations(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _conversations.length) {
      return;
    }
    if (newIndex < 0 || newIndex > _conversations.length) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final List<Conversation> updated = List<Conversation>.from(_conversations);
    final Conversation moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _conversations = updated;
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Conversation? getGroupById(String id) {
    for (final Conversation conversation in _groupConversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  TA? getTaById(String id) {
    for (final TA ta in _tas) {
      if (ta.id == id) {
        return ta;
      }
    }
    return null;
  }

  World? getWorldById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final World world in _worlds) {
      if (world.id == id) {
        return world;
      }
    }
    return null;
  }

  Future<void> clearAllData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      final Directory doc = await getApplicationDocumentsDirectory();
      if (await doc.exists()) {
        await doc.delete(recursive: true);
      }
    } catch (_) {
      // Ignore cleanup errors.
    }
    _settings = AppSettings.empty();
    _tas = <TA>[];
    _worlds = <World>[];
    _conversations = <Conversation>[];
    _groupConversations = <Conversation>[];
    notifyListeners();
  }
}
