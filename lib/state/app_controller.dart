import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/role.dart';
import '../models/world.dart';
import '../services/openai_service.dart';
import '../services/conversation_service.dart';
import '../services/role_service.dart';
import '../services/settings_service.dart';
import '../services/world_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required SettingsService settingsService,
    required OpenAiService openAiService,
    required RoleService roleService,
    required WorldService worldService,
    required ConversationService conversationService,
  })  : _settingsService = settingsService,
        _openAiService = openAiService,
        _roleService = roleService,
        _worldService = worldService,
        _conversationService = conversationService;

  final SettingsService _settingsService;
  final OpenAiService _openAiService;
  final RoleService _roleService;
  final WorldService _worldService;
  final ConversationService _conversationService;

  AppSettings _settings = AppSettings.empty();
  List<Role> _roles = <Role>[];
  List<World> _worlds = <World>[];
  List<Conversation> _conversations = <Conversation>[];

  AppSettings get settings => _settings;
  OpenAiService get openAiService => _openAiService;
  List<Role> get roles => List<Role>.unmodifiable(_roles);
  List<World> get worlds => List<World>.unmodifiable(_worlds);
  List<Conversation> get conversations => List<Conversation>.unmodifiable(_conversations);

  Future<void> initialize() async {
    _settings = await _settingsService.load();
    _roles = await _roleService.load();
    _worlds = await _worldService.load();
    _conversations = await _conversationService.load();
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

  Future<void> upsertRole(Role role) async {
    final int index = _roles.indexWhere((Role item) => item.id == role.id);
    if (index == -1) {
      _roles = <Role>[..._roles, role];
    } else {
      final List<Role> updated = <Role>[..._roles];
      updated[index] = role;
      _roles = updated;
    }
    await _roleService.save(_roles);
    notifyListeners();
  }

  Future<void> deleteRole(String id) async {
    _roles = _roles.where((Role role) => role.id != id).toList();
    await _roleService.save(_roles);
    notifyListeners();
  }

  Future<String> storeRoleImage({
    required String roleId,
    required String slot,
    required String sourcePath,
  }) async {
    return _roleService.storeImage(
      sourcePath: sourcePath,
      roleId: roleId,
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

  Future<void> upsertConversation(Conversation conversation) async {
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

  Future<void> deleteConversation(String id) async {
    _conversations = _conversations.where((Conversation item) => item.id != id).toList();
    await _conversationService.save(_conversations);
    notifyListeners();
  }

  Role? getRoleById(String id) {
    for (final Role role in _roles) {
      if (role.id == id) {
        return role;
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
}
