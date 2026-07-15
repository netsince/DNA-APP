import 'dart:convert';
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

import '../services/settings_service.dart';
import '../services/app_icon_service.dart';
import '../services/ta_service.dart';
import '../services/hive_service.dart';
import '../services/data_backup_service.dart';
import '../services/ta_export_import_service.dart';
import '../services/conversation_export_import_service.dart';
import '../utils/id_utils.dart';

class AppController extends ChangeNotifier {
  AppController({
    required SettingsService settingsService,
    required OpenAiService openAiService,
    required TaService taService,
  })  : _settingsService = settingsService,
        _openAiService = openAiService,
        _taService = taService,
        _hiveService = HiveService();

  final SettingsService _settingsService;
  final OpenAiService _openAiService;
  final TaService _taService;
  final HiveService _hiveService;

  AppSettings _settings = AppSettings.empty();
  List<TA> _tas = <TA>[];
  List<World> _worlds = <World>[];
  List<Conversation> _conversations = <Conversation>[];
  List<Conversation> _groupConversations = <Conversation>[];

  AppSettings get settings => _settings;
  OpenAiService get openAiService => _openAiService;
  List<TA> get tas => _tas;
  List<TA> get activeTas => _tas.where((TA t) => !t.archived).toList();
  List<World> get worlds => List<World>.unmodifiable(_worlds);
  List<World> get activeWorlds => _worlds.where((World w) => !w.archived).toList();
  List<Conversation> get conversations => List<Conversation>.unmodifiable(_conversations);
  List<Conversation> get activeConversations => _conversations.where((Conversation c) => !c.archived).toList();
  List<Conversation> get groupConversations => List<Conversation>.unmodifiable(_groupConversations);
  List<Conversation> get activeGroupConversations => _groupConversations.where((Conversation c) => !c.archived).toList();

  /// 角色 ID -> 角色 映射（用于导出时解析说话人 / 内嵌角色卡）
  Map<String, TA> get tasById {
    final Map<String, TA> map = <String, TA>{};
    for (final TA ta in _tas) {
      map[ta.id] = ta;
    }
    return map;
  }

  /// 全部对话（单聊 + 群聊）
  List<Conversation> get allConversations =>
      <Conversation>[..._conversations, ..._groupConversations];

  Future<void> initialize() async {
    await _hiveService.init();
    _settings = await _settingsService.load();
    // 启动后恢复用户选择的应用图标（仅 Android；失败不影响启动）
    if (AppIconService.isSupported) {
      try {
        final AppIconOption current = _settings.appIcon == AppIconOption.alternate.key
            ? AppIconOption.alternate
            : AppIconOption.defaultIcon;
        await AppIconService.setIcon(current);
      } catch (_) {
        // 忽略：系统未准备好或切换失败都不应阻塞应用启动
      }
    }
    _tas = await _hiveService.getTas();
    _worlds = await _hiveService.getWorlds();
    final allConversations = await _hiveService.getConversations();
    _conversations = allConversations.where((c) => !c.isGroup).toList();
    _groupConversations = allConversations.where((c) => c.isGroup).toList();
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

  Future<void> saveAuthSettings({
    required bool requireAuthForArchive,
    required bool requireAuthForApp,
  }) async {
    _settings = _settings.copyWith(
      requireAuthForArchive: requireAuthForArchive,
      requireAuthForApp: requireAuthForApp,
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveSplashAnimation({required bool showSplashAnimation}) async {
    _settings = _settings.copyWith(showSplashAnimation: showSplashAnimation);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存并应用应用图标选择。非 Android 平台仅保存设置，不做切换。
  Future<void> saveAppIcon(AppIconOption option) async {
    _settings = _settings.copyWith(appIcon: option.key);
    await _settingsService.save(_settings);
    if (AppIconService.isSupported) {
      try {
        await AppIconService.setIcon(option);
      } catch (e) {
        debugPrint('切换应用图标失败：$e');
      }
    }
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
    await _hiveService.upsertTa(ta);
    notifyListeners();
  }

  Future<void> deleteTa(String id) async {
    _tas = _tas.where((TA ta) => ta.id != id).toList();
    await _hiveService.deleteTa(id);
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
    await _hiveService.upsertTa(updated[index]);
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
    await _hiveService.upsertWorld(world);
    notifyListeners();
  }

  Future<void> deleteWorld(String id) async {
    _worlds = _worlds.where((World world) => world.id != id).toList();
    await _hiveService.deleteWorld(id);
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
    await _hiveService.upsertWorld(updated[index]);
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
    await _hiveService.upsertConversation(conversation);
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
    await _hiveService.upsertConversation(conversation);
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    _conversations = _conversations.where((Conversation item) => item.id != id).toList();
    await _hiveService.deleteConversation(id);
    notifyListeners();
  }

  Future<void> deleteGroupConversation(String id) async {
    _groupConversations = _groupConversations.where((Conversation item) => item.id != id).toList();
    await _hiveService.deleteConversation(id);
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
    await _hiveService.upsertConversation(updated[index]);
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
    await _hiveService.upsertConversation(updated[index]);
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
    await _hiveService.saveConversations(_conversations);
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
    await _hiveService.saveTas(_tas);
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
    await _hiveService.saveWorlds(_worlds);
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
    await _hiveService.saveConversations(_conversations);
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

  /// 导出全部数据（角色 / 世界 / 对话，不含设置）为 ZIP 字节
  Future<ExportImportResult<Uint8List>> exportAllData() async {
    return DataBackupService.buildZip(
      tas: _tas,
      worlds: _worlds,
      conversations: <Conversation>[
        ..._conversations,
        ..._groupConversations,
      ],
    );
  }

  /// 仅导出对话（单聊 + 群聊）为 ZIP 字节
  Future<ExportImportResult<Uint8List>> exportConversations() async {
    return DataBackupService.buildConversationsZip(
      conversations: <Conversation>[
        ..._conversations,
        ..._groupConversations,
      ],
    );
  }

  /// 从 ZIP 字节导入对话
  /// [replaceAll] 为 true 时替换全部对话，并先自动备份替换前的对话；
  /// 为 false 时仅追加不存在的对话（按 id 去重）。
  Future<ExportImportResult<DataImportReport>> importConversations(
    Uint8List zipBytes, {
    required bool replaceAll,
  }) async {
    final ExportImportResult<List<Conversation>> parsed =
        DataBackupService.parseConversationsZip(zipBytes);
    if (!parsed.success || parsed.data == null) {
      return ExportImportResult(
        success: false,
        message: parsed.message ?? '导入失败',
      );
    }
    final List<Conversation> incoming = parsed.data!;

    try {
      String? backupPath;
      String? backupError;

      if (replaceAll) {
        // 先自动备份替换前的对话
        final ExportImportResult<Uint8List> current =
            await exportConversations();
        if (current.success && current.data != null) {
          try {
            final Directory docDir = await getApplicationDocumentsDirectory();
            final Directory backupsDir =
                Directory(path.join(docDir.path, 'dna_backups'));
            if (!await backupsDir.exists()) {
              await backupsDir.create(recursive: true);
            }
            final File backupFile = File(path.join(
                backupsDir.path, 'DNA_conversations_${_timestamp()}.zip'));
            await backupFile.writeAsBytes(current.data!);
            backupPath = backupFile.path;
          } catch (e) {
            backupError = '$e';
          }
        } else {
          backupError = current.message ?? '未知错误';
        }

        _conversations =
            incoming.where((Conversation c) => !c.isGroup).toList();
        _groupConversations =
            incoming.where((Conversation c) => c.isGroup).toList();

        await _hiveService.saveConversations(<Conversation>[
          ..._conversations,
          ..._groupConversations,
        ]);
        notifyListeners();
        return ExportImportResult(
          success: true,
          data: DataImportReport(
            replaced: true,
            tasCount: 0,
            worldsCount: 0,
            conversationsCount:
                _conversations.length + _groupConversations.length,
            backupPath: backupPath,
            backupError: backupError,
          ),
        );
      }

      // 仅追加：按 id 去重
      final Set<String> existingIds = <String>{
        ..._conversations.map((Conversation c) => c.id),
        ..._groupConversations.map((Conversation c) => c.id),
      };
      final List<Conversation> newConvs = incoming
          .where((Conversation c) => !existingIds.contains(c.id))
          .toList();

      _conversations = <Conversation>[
        ..._conversations,
        ...newConvs.where((Conversation c) => !c.isGroup),
      ];
      _groupConversations = <Conversation>[
        ..._groupConversations,
        ...newConvs.where((Conversation c) => c.isGroup),
      ];

      await _hiveService.saveConversations(<Conversation>[
        ..._conversations,
        ..._groupConversations,
      ]);
      notifyListeners();
      return ExportImportResult(
        success: true,
        data: DataImportReport(
          replaced: false,
          tasCount: 0,
          worldsCount: 0,
          conversationsCount: newConvs.length,
          backupPath: null,
          backupError: null,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败：$e');
    }
  }

  /// 将指定对话导出为文本（JSON 或 Markdown）。
  ///
  /// [includeCharacterCards] 仅对 JSON 格式生效：为 true 时把角色卡（含图片与溯源）
  /// 内嵌进导出文件，便于对方再次导入。
  Future<ExportImportResult<ConversationExportResult>> exportConversationsById(
    List<String> conversationIds, {
    required bool includeCharacterCards,
    required ConversationExportFormat format,
  }) async {
    try {
      final List<Conversation> selected = allConversations
          .where((Conversation c) => conversationIds.contains(c.id))
          .toList();
      if (selected.isEmpty) {
        return const ExportImportResult(
          success: false,
          message: '没有可导出的对话',
        );
      }
      final ConversationExportResult result =
          await ConversationExportImportService.buildConversationExport(
        conversations: selected,
        tasById: tasById,
        format: format,
        includeCharacterCards: includeCharacterCards,
      );
      return ExportImportResult(success: true, data: result);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出失败：$e');
    }
  }

  /// 解析对话导入 JSON，返回结构化数据（供 UI 完成角色决议）
  ExportImportResult<ConversationImportData> parseConversationImportJson(
    String jsonString,
  ) {
    return ConversationExportImportService.parseConversationImport(jsonString);
  }

  /// 应用对话导入：先按决议处理角色（导入卡 / 替换为已有），再重映射对话中的角色 ID。
  ///
  /// [decisions] 需覆盖 [data] 中所有被引用的角色 ID。
  Future<ExportImportResult<DataImportReport>> applyConversationImport(
    ConversationImportData data,
    List<CharacterImportDecision> decisions, {
    required bool replaceAll,
  }) async {
    try {
      final Map<String, String> taIdRemap = <String, String>{};

      for (final CharacterImportDecision d in decisions) {
        if (d.importAsNew) {
          // 导入内嵌角色卡：解析 -> 处理 ID 冲突 -> 恢复图片 -> 落库
          final Map<String, dynamic>? pkg = data.embeddedPackages[d.originalTaId];
          if (pkg == null) {
            return ExportImportResult(
              success: false,
              message: '角色 ${d.originalTaId} 没有可导入的角色卡',
            );
          }
          final ExportImportResult<ImportResult> parsed =
              TaExportImportService.importCharacter(jsonEncode(pkg));
          if (!parsed.success || parsed.data == null) {
            return ExportImportResult(
              success: false,
              message: parsed.message ?? '角色卡解析失败',
            );
          }
          TA ta = parsed.data!.ta;
          // ID 冲突：永不覆盖，自动改用新 ID 导入为新角色
          if (getTaById(ta.id) != null) {
            ta = ta.copyWith(id: newId());
          }
          final ExportImportResult<TA> withImages =
              await TaExportImportService.restoreTaImages(ta, pkg);
          if (!withImages.success || withImages.data == null) {
            return ExportImportResult(
              success: false,
              message: withImages.message ?? '角色图片恢复失败',
            );
          }
          await upsertTa(withImages.data!);
          taIdRemap[d.originalTaId] = withImages.data!.id;
        } else {
          // 使用已有角色
          if (d.existingTaId == null || d.existingTaId!.isEmpty) {
            return ExportImportResult(
              success: false,
              message: '角色 ${d.originalTaId} 未选择对应已有角色',
            );
          }
          taIdRemap[d.originalTaId] = d.existingTaId!;
        }
      }

      // 重映射对话中的角色 ID
      List<Conversation> incoming = data.conversations.map((Conversation c) {
        final String newTaId = taIdRemap[c.taId] ?? c.taId;
        final List<String> newMembers = c.memberTaIds
            .map((String id) => taIdRemap[id] ?? id)
            .toList();
        final String? newActive = c.activeTaId == null
            ? null
            : (taIdRemap[c.activeTaId!] ?? c.activeTaId);
        return c.copyWith(
          taId: newTaId,
          memberTaIds: newMembers,
          activeTaId: newActive,
        );
      }).toList();

      String? backupPath;
      String? backupError;

      if (replaceAll) {
        final ExportImportResult<Uint8List> current = await exportConversations();
        if (current.success && current.data != null) {
          try {
            final Directory docDir = await getApplicationDocumentsDirectory();
            final Directory backupsDir =
                Directory(path.join(docDir.path, 'dna_backups'));
            if (!await backupsDir.exists()) {
              await backupsDir.create(recursive: true);
            }
            final File backupFile = File(path.join(
                backupsDir.path, 'DNA_conversations_${_timestamp()}.zip'));
            await backupFile.writeAsBytes(current.data!);
            backupPath = backupFile.path;
          } catch (e) {
            backupError = '$e';
          }
        } else {
          backupError = current.message ?? '未知错误';
        }

        _conversations = incoming.where((Conversation c) => !c.isGroup).toList();
        _groupConversations =
            incoming.where((Conversation c) => c.isGroup).toList();
        await _hiveService.saveConversations(<Conversation>[
          ..._conversations,
          ..._groupConversations,
        ]);
        notifyListeners();
        return ExportImportResult(
          success: true,
          data: DataImportReport(
            replaced: true,
            tasCount: 0,
            worldsCount: 0,
            conversationsCount:
                _conversations.length + _groupConversations.length,
            backupPath: backupPath,
            backupError: backupError,
          ),
        );
      }

      // 仅追加：按 id 去重
      final Set<String> existingIds = <String>{
        ..._conversations.map((Conversation c) => c.id),
        ..._groupConversations.map((Conversation c) => c.id),
      };
      final List<Conversation> newConvs =
          incoming.where((Conversation c) => !existingIds.contains(c.id)).toList();

      _conversations = <Conversation>[
        ..._conversations,
        ...newConvs.where((Conversation c) => !c.isGroup),
      ];
      _groupConversations = <Conversation>[
        ..._groupConversations,
        ...newConvs.where((Conversation c) => c.isGroup),
      ];
      await _hiveService.saveConversations(<Conversation>[
        ..._conversations,
        ..._groupConversations,
      ]);
      notifyListeners();
      return ExportImportResult(
        success: true,
        data: DataImportReport(
          replaced: false,
          tasCount: 0,
          worldsCount: 0,
          conversationsCount: newConvs.length,
          backupPath: null,
          backupError: null,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败：$e');
    }
  }

  /// 从 ZIP 字节导入数据（不含设置）
  /// [replaceAll] 为 true 时全部替换，并先自动备份替换前的数据；
  /// 为 false 时仅追加不存在的条目（按 id 去重），保留现有数据。
  Future<ExportImportResult<DataImportReport>> importData(
    Uint8List zipBytes, {
    required bool replaceAll,
  }) async {
    final ExportImportResult<ParsedBackup> parsed =
        DataBackupService.parseZip(zipBytes);
    if (!parsed.success || parsed.data == null) {
      return ExportImportResult(
        success: false,
        message: parsed.message ?? '导入失败',
      );
    }
    final ParsedBackup backup = parsed.data!;

    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory taDir = Directory(path.join(docDir.path, 'tas'));
    String? backupPath;
    String? backupError;

    try {
      if (replaceAll) {
        // 先自动备份替换前的数据
        final ExportImportResult<Uint8List> current = await exportAllData();
        if (current.success && current.data != null) {
          final Directory backupsDir =
              Directory(path.join(docDir.path, 'dna_backups'));
          if (!await backupsDir.exists()) {
            await backupsDir.create(recursive: true);
          }
          final File backupFile =
              File(path.join(backupsDir.path, 'DNA_backup_${_timestamp()}.zip'));
          await backupFile.writeAsBytes(current.data!);
          backupPath = backupFile.path;
        } else {
          backupError = current.message ?? '未知错误';
        }

        // 清空旧图片后写入新数据
        if (await taDir.exists()) {
          await taDir.delete(recursive: true);
        }
        await taDir.create(recursive: true);

        final List<TA> resolvedTas = DataBackupService.resolveTasImages(
          backup.tas,
          backup.imageBytes,
          taDir.path,
        );

        _tas = resolvedTas;
        _worlds = backup.worlds;
        _conversations =
            backup.conversations.where((Conversation c) => !c.isGroup).toList();
        _groupConversations =
            backup.conversations.where((Conversation c) => c.isGroup).toList();

        await _hiveService.saveTas(_tas);
        await _hiveService.saveWorlds(_worlds);
        await _hiveService.saveConversations(<Conversation>[
          ..._conversations,
          ..._groupConversations,
        ]);

        notifyListeners();
        return ExportImportResult(
          success: true,
          data: DataImportReport(
            replaced: true,
            tasCount: _tas.length,
            worldsCount: _worlds.length,
            conversationsCount:
                _conversations.length + _groupConversations.length,
            backupPath: backupPath,
            backupError: backupError,
          ),
        );
      }

      // 仅追加：跳过已存在的 id
      if (!await taDir.exists()) {
        await taDir.create(recursive: true);
      }

      final Set<String> existingTaIds = _tas.map((TA t) => t.id).toSet();
      final List<TA> newTas =
          backup.tas.where((TA t) => !existingTaIds.contains(t.id)).toList();
      final List<TA> resolvedNewTas = DataBackupService.resolveTasImages(
        newTas,
        backup.imageBytes,
        taDir.path,
      );

      final Set<String> existingWorldIds =
          _worlds.map((World w) => w.id).toSet();
      final List<World> newWorlds = backup.worlds
          .where((World w) => !existingWorldIds.contains(w.id))
          .toList();

      final Set<String> existingConvIds = <String>{
        ..._conversations.map((Conversation c) => c.id),
        ..._groupConversations.map((Conversation c) => c.id),
      };
      final List<Conversation> newConvs = backup.conversations
          .where((Conversation c) => !existingConvIds.contains(c.id))
          .toList();

      _tas = <TA>[..._tas, ...resolvedNewTas];
      _worlds = <World>[..._worlds, ...newWorlds];
      _conversations = <Conversation>[
        ..._conversations,
        ...newConvs.where((Conversation c) => !c.isGroup),
      ];
      _groupConversations = <Conversation>[
        ..._groupConversations,
        ...newConvs.where((Conversation c) => c.isGroup),
      ];

      await _hiveService.saveTas(_tas);
      await _hiveService.saveWorlds(_worlds);
      await _hiveService.saveConversations(<Conversation>[
        ..._conversations,
        ..._groupConversations,
      ]);

      notifyListeners();
      return ExportImportResult(
        success: true,
        data: DataImportReport(
          replaced: false,
          tasCount: newTas.length,
          worldsCount: newWorlds.length,
          conversationsCount: newConvs.length,
          backupPath: null,
          backupError: null,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '导入失败：$e');
    }
  }

  String _timestamp() {
    final DateTime d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  Future<void> clearAllData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _hiveService.clearAll();
    try {
      final Directory doc = await getApplicationDocumentsDirectory();
      final Directory taDir = Directory(path.join(doc.path, 'tas'));
      if (await taDir.exists()) {
        await taDir.delete(recursive: true);
      }
    } catch (_) {
    }
    _settings = AppSettings.empty();
    _tas = <TA>[];
    _worlds = <World>[];
    _conversations = <Conversation>[];
    _groupConversations = <Conversation>[];
    notifyListeners();
  }
}
