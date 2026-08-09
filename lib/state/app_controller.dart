import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/prompt_strategy.dart';
import '../models/quick_reply.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../utils/message_processor.dart';
import '../services/openai_service.dart';
import '../services/anthropic_service.dart';
import '../services/zhipu_service.dart';
import '../services/deepseek_service.dart';
import '../services/llm_provider.dart';

import '../services/settings_service.dart';
import '../services/app_icon_service.dart';
import '../services/ta_service.dart';
import '../services/hive_service.dart';
import '../services/data_backup_service.dart';
import '../services/ta_export_import_service.dart';
import '../services/conversation_export_import_service.dart';
import '../services/world_export_import_service.dart';
import '../utils/id_utils.dart';
import '../utils/ui_feedback.dart';

class AppController extends ChangeNotifier {
  AppController({
    required SettingsService settingsService,
    required OpenAiService openAiService,
    required TaService taService,
    HiveService? hiveService,
  })  : _settingsService = settingsService,
        _openAiService = openAiService,
        _taService = taService,
        _hiveService = hiveService ?? HiveService(),
        _providerRegistry = LlmProviderRegistry(<LlmProvider>[
          openAiService,
          AnthropicProvider(),
          ZhipuProvider(),
          DeepSeekService(),
        ]);

  final SettingsService _settingsService;
  final OpenAiService _openAiService;
  final TaService _taService;
  final HiveService _hiveService;

  /// 已注册的大模型 Provider 集合。新增厂商只需把对应适配器加进来。
  final LlmProviderRegistry _providerRegistry;

  AppSettings _settings = AppSettings.empty();
  List<TA> _tas = <TA>[];
  List<UserIdentity> _identities = <UserIdentity>[];
  List<World> _worlds = <World>[];
  List<Conversation> _conversations = <Conversation>[];
  List<Conversation> _groupConversations = <Conversation>[];

  AppSettings get settings => _settings;
  OpenAiService get openAiService => _openAiService;

  /// 当前是否启用 DeepSeek 思考模式（仅 DeepSeek 服务商返回非空）。
  String? get deepseekThinkingType {
    if (_settings.provider != 'deepseek') {
      return null;
    }
    return _settings.deepseekThinkingEnabled ? 'enabled' : 'disabled';
  }

  /// 当前 DeepSeek 思考强度：'low' / 'high' / 'max'（仅 DeepSeek 服务商返回）。
  String? get deepseekReasoningEffort {
    if (_settings.provider != 'deepseek') {
      return null;
    }
    return _settings.deepseekThinkingEffort;
  }

  /// 底层设置存储（供自动备份等需要读写独立偏好项的场景使用）。
  SettingsService get settingsService => _settingsService;

  /// 当前设置所选的大模型 Provider。业务层应优先使用此接口而非 openAiService。
  LlmProvider get llmProvider => _providerRegistry[settings.provider];

  /// 所有已注册的 Provider，供设置页 / OOBE 构建厂商选择列表。
  List<LlmProvider> get llmProviders => _providerRegistry.providers;

  List<TA> get tas => _tas;
  List<TA> get activeTas => _tas.where((TA t) => !t.archived).toList();
  List<UserIdentity> get identities => List<UserIdentity>.unmodifiable(_identities);
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
    // 同步底部提示（SnackBar）的显示时长到全局
    setSnackDuration(Duration(milliseconds: _settings.snackDurationMs));
    // 启动后恢复用户选择的应用图标（仅 Android；失败不影响启动）
    if (AppIconService.isSupported) {
      try {
        final AppIconOption current =
            AppIconService.optionForKey(_settings.appIcon);
        await AppIconService.setIcon(current);
      } catch (_) {
        // 忽略：系统未准备好或切换失败都不应阻塞应用启动
      }
    }
    _tas = await _hiveService.getTas();
    _identities = await _hiveService.getIdentities();
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

  /// 切换当前使用的大模型厂商。
  Future<void> saveProvider(String provider) async {
    _settings = _settings.copyWith(provider: provider.trim());
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存并应用主题模式（'system' / 'light' / 'dark'）。
  Future<void> saveThemeMode(String themeMode) async {
    _settings = _settings.copyWith(themeMode: themeMode.trim());
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

  /// 保存「删除前强制输入名称」开关（对四类可归档实体统一生效）。
  Future<void> saveRequireNameToDelete(bool value) async {
    _settings = _settings.copyWith(requireNameToDelete: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「允许在聊天页删除单条对话消息」开关。
  Future<void> saveAllowDeleteMessage(bool value) async {
    _settings = _settings.copyWith(allowDeleteMessage: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  Future<void> saveSplashAnimation({required bool showSplashAnimation}) async {
    _settings = _settings.copyWith(showSplashAnimation: showSplashAnimation);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「主页底部导航栏」开关（主页 / 群聊 / 我家 / 世界 底部显示导航栏）。
  Future<void> saveShowBottomNav(bool value) async {
    _settings = _settings.copyWith(showBottomNav: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「上下文 Token 实时仪表盘」开关。
  Future<void> saveShowTokenDashboard(bool value) async {
    _settings = _settings.copyWith(showTokenDashboard: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「从此处分叉」开关。
  Future<void> saveEnableForking(bool value) async {
    _settings = _settings.copyWith(enableForking: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「命令宏」开关。
  Future<void> saveEnableCommandMacros(bool value) async {
    _settings = _settings.copyWith(enableCommandMacros: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「正则替换」开关。
  Future<void> saveEnableRegexReplacement(bool value) async {
    _settings = _settings.copyWith(enableRegexReplacement: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存正则替换规则列表。
  Future<void> saveRegexRules(List<RegexRule> rules) async {
    _settings = _settings.copyWith(regexRules: rules);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「每日自动备份」开关。关闭后将不再进行静默自动备份。
  Future<void> saveAutoBackup(bool value) async {
    _settings = _settings.copyWith(autoBackup: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存底部提示（SnackBar）的显示时长（毫秒），并即时同步到全局。
  Future<void> saveSnackDuration(int snackDurationMs) async {
    _settings = _settings.copyWith(snackDurationMs: snackDurationMs);
    await _settingsService.save(_settings);
    setSnackDuration(Duration(milliseconds: snackDurationMs));
    notifyListeners();
  }

  /// 保存语音识别模型来源偏好。
  Future<void> saveSherpaModelSource(String source) async {
    _settings = _settings.copyWith(sherpaModelSource: source);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存自定义模型服务器根地址。
  Future<void> saveSherpaCustomBaseUrl(String? url) async {
    _settings = _settings.copyWith(sherpaCustomBaseUrl: url);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 记录模型是否已下载就绪及其本地目录。
  Future<void> setSherpaModelReady(String? modelPath) async {
    _settings = _settings.copyWith(
      sherpaModelReady: modelPath != null && modelPath.isNotEmpty,
      sherpaModelPath: modelPath,
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存当前选中的语音识别模型 id。
  Future<void> saveSelectedVoiceModel(String id) async {
    _settings = _settings.copyWith(selectedVoiceModelId: id);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存强调色（莫奈取色）模式：'auto' 或 'custom'。
  Future<void> saveAccentMode(String mode) async {
    _settings = _settings.copyWith(accentMode: mode.trim());
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存自定义强调色（ARGB 整数），仅当模式为 'custom' 时生效。
  Future<void> saveCustomAccentColor(int? color) async {
    _settings = _settings.copyWith(customAccentColor: color);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存聊天界面背景遮罩强度（0~100）。
  Future<void> saveChatMaskStrength(int chatMaskStrength) async {
    final int clamped = chatMaskStrength.clamp(0, 100);
    _settings = _settings.copyWith(chatMaskStrength: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存单次请求最多携带的历史消息条数（0 = 不限制）。
  Future<void> saveMaxContextMessages(int maxContextMessages) async {
    final int clamped = maxContextMessages.clamp(0, 1000);
    _settings = _settings.copyWith(maxContextMessages: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存单次请求历史消息的 token 预算（0 = 不限制）。
  Future<void> saveMaxContextTokens(int maxContextTokens) async {
    final int clamped = maxContextTokens.clamp(0, 100000);
    _settings = _settings.copyWith(maxContextTokens: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存摘要「按词数触发」的字符数阈值（0 = 禁用）。
  Future<void> saveSummaryWordThreshold(int summaryWordThreshold) async {
    final int clamped = summaryWordThreshold.clamp(0, 1000000);
    _settings = _settings.copyWith(summaryWordThreshold: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存作者注释内容（空串视为清除）。
  Future<void> saveAuthorNote(String? note) async {
    final String? trimmed = (note == null || note.trim().isEmpty) ? null : note.trim();
    _settings = _settings.copyWith(authorNote: trimmed);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存作者注释注入间隔（0 = 禁用深度注入）。
  Future<void> saveAuthorNoteInterval(int interval) async {
    final int clamped = interval.clamp(0, 200);
    _settings = _settings.copyWith(authorNoteInterval: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存世界词条 sticky 轮数（0 = 禁用）。
  Future<void> saveLoreStickyRounds(int rounds) async {
    final int clamped = rounds.clamp(0, 30);
    _settings = _settings.copyWith(loreStickyRounds: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存世界词条注入条数上限（0 = 不限）。
  Future<void> saveLoreMaxEntries(int maxEntries) async {
    final int clamped = maxEntries.clamp(0, 50);
    _settings = _settings.copyWith(loreMaxEntries: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存世界词条注入 token 预算（0 = 不限）。
  Future<void> saveLoreBudgetTokens(int budgetTokens) async {
    final int clamped = budgetTokens.clamp(0, 100000);
    _settings = _settings.copyWith(loreBudgetTokens: clamped);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存快速回复列表。
  Future<void> saveQuickReplies(List<QuickReply> quickReplies) async {
    _settings = _settings.copyWith(quickReplies: quickReplies);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存 DeepSeek 思考模式配置（开关与强度）。
  /// [effort] 取值 'low' / 'high' / 'max'，非法值回退 'high'。
  Future<void> saveDeepseekThinking({
    required bool enabled,
    required String effort,
  }) async {
    _settings = _settings.copyWith(
      deepseekThinkingEnabled: enabled,
      deepseekThinkingEffort: const <String>{'low', 'high', 'max'}.contains(effort)
          ? effort
          : 'high',
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存采样参数（温度 / 频率惩罚 / 存在惩罚），用于抑制复读等退化输出。
  Future<void> saveSampling({
    required double temperature,
    required double frequencyPenalty,
    required double presencePenalty,
  }) async {
    _settings = _settings.copyWith(
      temperature: temperature.clamp(0.0, 2.0),
      frequencyPenalty: frequencyPenalty.clamp(0.0, 2.0),
      presencePenalty: presencePenalty.clamp(0.0, 2.0),
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「高级采样参数」（Top-P / Top-K / Min-P / 重复惩罚 / 惩罚斜率）。
  Future<void> saveAdvancedSampling({
    required double topP,
    required double topK,
    required double minP,
    required double repetitionPenalty,
    required double repetitionPenaltySlope,
  }) async {
    _settings = _settings.copyWith(
      topP: topP.clamp(0.0, 1.0),
      topK: topK.clamp(0.0, 200.0),
      minP: minP.clamp(0.0, 1.0),
      repetitionPenalty: repetitionPenalty.clamp(1.0, 2.0),
      repetitionPenaltySlope: repetitionPenaltySlope.clamp(0.0, 1.0),
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 恢复「高级采样参数」到默认值。
  Future<void> resetAdvancedSampling() async {
    _settings = _settings.copyWith(
      topP: 1.0,
      topK: 0.0,
      minP: 0.0,
      repetitionPenalty: 1.0,
      repetitionPenaltySlope: 0.0,
    );
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「离线语音输入（STT）」开关。
  Future<void> saveVoiceInputEnabled(bool value) async {
    _settings = _settings.copyWith(voiceInputEnabled: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「端侧语音合成（TTS）」开关。
  Future<void> saveTtsEnabled(bool value) async {
    _settings = _settings.copyWith(ttsEnabled: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存全局 TTS seed（角色未设 seed 时兜底）。null 表示未设置。
  Future<void> saveTtsGlobalSeed(int? seed) async {
    _settings = _settings.copyWith(ttsGlobalSeed: seed);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「引号内容优先」开关：开启时合成优先只读引号内内容。
  Future<void> saveTtsQuoteOnly(bool value) async {
    _settings = _settings.copyWith(ttsQuoteOnly: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存「聊天输入框旁显示括号按钮」开关。
  Future<void> saveShowParenButton(bool value) async {
    _settings = _settings.copyWith(showParenButton: value);
    await _settingsService.save(_settings);
    notifyListeners();
  }

  /// 保存回车键行为：true = 回车发送、Shift+回车换行；false = 回车换行、Shift+回车发送。
  Future<void> saveEnterToSend(bool value) async {
    _settings = _settings.copyWith(enterToSend: value);
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

  /// 将 JSON 字符串写入 `<文档目录>/dna_backups/<subDir>/<fileNameBase>_<时间戳>.json`。
  /// 失败时返回 null（不阻断删除流程）。
  Future<String?> _writeBackupJson(
    String json,
    String subDir,
    String fileNameBase,
  ) async {
    try {
      final Directory docDir = await getApplicationDocumentsDirectory();
      final Directory dir =
          Directory(path.join(docDir.path, 'dna_backups', subDir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final String safeBase =
          fileNameBase.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').trim();
      final File backupFile = File(
        path.join(dir.path, '${safeBase}_${_timestamp()}.json'),
      );
      await backupFile.writeAsString(json);
      return backupFile.path;
    } catch (_) {
      return null;
    }
  }

  /// 删除角色卡并自动备份其完整 JSON（含图片）到特定目录。
  ///
  /// 备份路径：`<应用文档目录>/dna_backups/deleted_ta/TA_<名称>_<时间戳>.json`。
  /// 返回备份文件的绝对路径；导出或写盘失败时返回 null（但仍会执行删除）。
  /// 同时清理该角色在 `tas/` 目录下的图片文件，避免残留孤儿文件。
  Future<String?> deleteTaWithBackup(String id) async {
    final TA? ta = getTaById(id);
    if (ta == null) {
      return null;
    }

    String? backupPath;
    final ExportImportResult<String> exportResult =
        await TaExportImportService.exportCharacter(ta);
    if (exportResult.success && exportResult.data != null) {
      backupPath = await _writeBackupJson(
        exportResult.data!,
        'deleted_ta',
        'TA_${ta.name}',
      );
    }

    // 清理该角色的图片文件
    try {
      final Directory docDir = await getApplicationDocumentsDirectory();
      final Directory taDir = Directory(path.join(docDir.path, 'tas'));
      if (await taDir.exists()) {
        await for (final FileSystemEntity entity in taDir.list()) {
          if (entity is File &&
              path.basename(entity.path).startsWith('${ta.id}_')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {
      // 图片清理失败不阻断删除
    }

    await deleteTa(id);
    return backupPath;
  }

  /// 删除世界并自动备份其 JSON 到特定目录。
  ///
  /// 备份路径：`<应用文档目录>/dna_backups/deleted_world/World_<名称>_<时间戳>.json`。
  Future<String?> deleteWorldWithBackup(String id) async {
    final World? world = getWorldById(id);
    if (world == null) {
      return null;
    }
    String? backupPath;
    final ExportImportResult<String> exportResult =
        WorldExportImportService.exportWorld(world);
    if (exportResult.success && exportResult.data != null) {
      backupPath = await _writeBackupJson(
        exportResult.data!,
        'deleted_world',
        'World_${world.name}',
      );
    }
    await deleteWorld(id);
    return backupPath;
  }

  /// 删除对话（单聊或群聊）并自动备份其 JSON 到特定目录。
  ///
  /// 备份路径：`<应用文档目录>/dna_backups/deleted_conversations/` 下，文件名以
  /// `Conv_`（单聊）或 `Group_`（群聊）开头，后接标题与时间戳。删除方式按对话
  /// 类型分别走单聊 / 群聊删除。
  Future<String?> deleteConversationWithBackup(String id) async {
    Conversation? conv;
    try {
      conv = _conversations.firstWhere((Conversation c) => c.id == id);
    } catch (_) {
      conv = null;
    }
    if (conv == null) {
      try {
        conv = _groupConversations.firstWhere((Conversation c) => c.id == id);
      } catch (_) {
        conv = null;
      }
    }
    if (conv == null) {
      return null;
    }

    final String title = conv.isGroup
        ? (conv.groupName.trim().isNotEmpty ? conv.groupName.trim() : 'Group')
        : (getTaById(conv.taId)?.name.isNotEmpty == true
            ? getTaById(conv.taId)!.name
            : 'Conv');
    final String? backupPath = await _writeBackupJson(
      jsonEncode(conv.toJson()),
      'deleted_conversations',
      '${conv.isGroup ? 'Group' : 'Conv'}_$title',
    );

    if (conv.isGroup) {
      await deleteGroupConversation(id);
    } else {
      await deleteConversation(id);
    }
    return backupPath;
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

  Future<void> upsertIdentity(UserIdentity identity) async {
    final int index = _identities.indexWhere((UserIdentity item) => item.id == identity.id);
    if (index == -1) {
      _identities = <UserIdentity>[..._identities, identity];
    } else {
      final List<UserIdentity> updated = <UserIdentity>[..._identities];
      updated[index] = identity;
      _identities = updated;
    }
    await _hiveService.upsertIdentity(identity);
    notifyListeners();
  }

  Future<void> deleteIdentity(String id) async {
    _identities = _identities.where((UserIdentity i) => i.id != id).toList();
    await _hiveService.deleteIdentity(id);
    notifyListeners();
  }

  UserIdentity? getIdentityById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final UserIdentity identity in _identities) {
      if (identity.id == id) {
        return identity;
      }
    }
    return null;
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

  /// 置顶/取消置顶某个会话。
  Future<void> setConversationPinned({
    required String id,
    required bool pinned,
  }) async {
    final int index = _conversations.indexWhere((Conversation item) => item.id == id);
    if (index == -1) {
      return;
    }
    final Conversation current = _conversations[index];
    if (current.pinned == pinned) {
      return;
    }
    final List<Conversation> updated = <Conversation>[..._conversations];
    updated[index] = current.copyWith(pinned: pinned);
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
      identities: _identities,
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
            identitiesCount: 0,
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
            identitiesCount: 0,
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
            identitiesCount: 0,
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
            identitiesCount: 0,
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
            identitiesCount: _identities.length,
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

      final Set<String> existingIdentityIds =
          _identities.map((UserIdentity i) => i.id).toSet();
      final List<UserIdentity> newIdentities = backup.identities
          .where((UserIdentity i) => !existingIdentityIds.contains(i.id))
          .toList();

      _tas = <TA>[..._tas, ...resolvedNewTas];
      _worlds = <World>[..._worlds, ...newWorlds];
      _identities = <UserIdentity>[..._identities, ...newIdentities];
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
      await _hiveService.saveIdentities(_identities);
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
          identitiesCount: newIdentities.length,
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
    setSnackDuration(const Duration(milliseconds: 1000));
    _tas = <TA>[];
    _worlds = <World>[];
    _conversations = <Conversation>[];
    _groupConversations = <Conversation>[];
    notifyListeners();
  }
}
