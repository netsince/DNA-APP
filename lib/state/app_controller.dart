import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/dialogue_style.dart';
import '../models/role.dart';
import '../models/world.dart';
import '../services/openai_service.dart';
import '../services/role_service.dart';
import '../services/settings_service.dart';
import '../services/world_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required SettingsService settingsService,
    required OpenAiService openAiService,
    required RoleService roleService,
    required WorldService worldService,
  })  : _settingsService = settingsService,
        _openAiService = openAiService,
        _roleService = roleService,
        _worldService = worldService;

  final SettingsService _settingsService;
  final OpenAiService _openAiService;
  final RoleService _roleService;
  final WorldService _worldService;

  AppSettings _settings = AppSettings.empty();
  List<Role> _roles = <Role>[];
  List<World> _worlds = <World>[];

  AppSettings get settings => _settings;
  OpenAiService get openAiService => _openAiService;
  List<Role> get roles => List<Role>.unmodifiable(_roles);
  List<World> get worlds => List<World>.unmodifiable(_worlds);

  Future<void> initialize() async {
    _settings = await _settingsService.load();
    _roles = await _roleService.load();
    _worlds = await _worldService.load();
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

  Future<void> saveDialogueStyle(List<DialogueTurn> turns) async {
    _settings = _settings.copyWith(dialogueStyle: List<DialogueTurn>.from(turns));
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
}
