import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:dna/services/shared_prefs.dart';

import '../models/app_settings.dart';
import '../models/app_settings_patch.dart';
import '../models/llm_model_config.dart';
import '../models/llm_provider_config.dart';

/// 一个设置字段的**存储规格**：JSON 键 ↔ pref 键 + 值类型。
class PrefSpec {
  const PrefSpec(this.prefKey, this.kind);
  final String prefKey;
  final SettingsValueKind kind;
}

/// 设置字段的**唯一一张表**：字段名 → 存储规格。
///
/// 以前「哪些字段要被存/读」这件事分散在多处：`save()` 里 60 多行 `setXxx`、
/// `load()` 里 60 多行 `getXxx`、patch 的 `settingsKeyKinds`、模型的
/// `toJson`/`fromJson`…… 各处各自维护一份清单，于是必然漂移：
///
/// **实测漂移结果：有 15 个设置项在模型与设置界面里都存在，但 save/load 里
/// 从来没有它们** —— 用户改完重启就回默认值（高级采样 topP/topK/minP、两个
/// repetition penalty、请求超时、检查更新、Token 面板、允许分叉、命令宏、
/// 正则替换与正则规则、TTS 引号优先、deepseek 思考开关与强度）。
///
/// 现在 save/load/saveOne 全部由这张表驱动，`settings_storage_test` 会逐键
/// 往返校验，并且有一条守卫断言「每个可写键都必须在这张表里」。
const Map<String, PrefSpec> kPrefSpecs = <String, PrefSpec>{
  'accentMode': PrefSpec('accent_mode', SettingsValueKind.text),
  'allowDeleteMessage': PrefSpec('allow_delete_message', SettingsValueKind.boolean),
  'appIcon': PrefSpec('app_icon', SettingsValueKind.text),
  'autoBackup': PrefSpec('auto_backup', SettingsValueKind.boolean),
  'autoOpenLastChat': PrefSpec('auto_open_last_chat', SettingsValueKind.boolean),
  'autoSummaryPrompt': PrefSpec('auto_summary_prompt', SettingsValueKind.boolean),
  'bgmSizeLimitUnlocked': PrefSpec('bgm_size_limit_unlocked', SettingsValueKind.boolean),
  'bgmVolume': PrefSpec('bgm_volume', SettingsValueKind.integer),
  'chatBubbleOpacity': PrefSpec('chat_bubble_opacity', SettingsValueKind.integer),
  'chatInputStyle': PrefSpec('chat_input_style', SettingsValueKind.text),
  'chatMaskStrength': PrefSpec('chat_mask_strength', SettingsValueKind.integer),
  'chatQuickSidebar': PrefSpec('chat_quick_sidebar', SettingsValueKind.boolean),
  'chatQuickSidebarCollapsed': PrefSpec('chat_quick_sidebar_collapsed', SettingsValueKind.boolean),
  'chatSwipeSwitch': PrefSpec('chat_swipe_switch', SettingsValueKind.boolean),
  'completedOobe': PrefSpec('completed_oobe', SettingsValueKind.boolean),
  'customAccentColor': PrefSpec('custom_accent_color', SettingsValueKind.integer),
  'deepseekThinkingEffort': PrefSpec('deepseek_thinking_effort', SettingsValueKind.text),
  'deepseekThinkingEnabled': PrefSpec('deepseek_thinking_enabled', SettingsValueKind.boolean),
  'developerOptionsUnlocked': PrefSpec('developer_options_unlocked', SettingsValueKind.boolean),
  'dynamicHalfScreen': PrefSpec('dynamic_half_screen', SettingsValueKind.boolean),
  'enableCommandMacros': PrefSpec('enable_command_macros', SettingsValueKind.boolean),
  'enableCommunity': PrefSpec('enable_community', SettingsValueKind.boolean),
  'enableForking': PrefSpec('enable_forking', SettingsValueKind.boolean),
  'enableRegexReplacement': PrefSpec('enable_regex_replacement', SettingsValueKind.boolean),
  'enterToSend': PrefSpec('enter_to_send', SettingsValueKind.boolean),
  'fontFamilyMode': PrefSpec('font_family_mode', SettingsValueKind.text),
  'fontSizeStep': PrefSpec('font_size_step', SettingsValueKind.integer),
  'freeImageCrop': PrefSpec('free_image_crop', SettingsValueKind.boolean),
  'frequencyPenalty': PrefSpec('frequency_penalty', SettingsValueKind.decimal),
  'halfScreenChat': PrefSpec('half_screen_chat', SettingsValueKind.boolean),
  'inspirationIncludeSummary': PrefSpec('inspiration_include_summary', SettingsValueKind.boolean),
  'loreBudgetTokens': PrefSpec('lore_budget_tokens', SettingsValueKind.integer),
  'loreMaxEntries': PrefSpec('lore_max_entries', SettingsValueKind.integer),
  'loreStickyRounds': PrefSpec('lore_sticky_rounds', SettingsValueKind.integer),
  'maxContextMessages': PrefSpec('max_context_messages', SettingsValueKind.integer),
  'maxContextTokens': PrefSpec('max_context_tokens', SettingsValueKind.integer),
  'minP': PrefSpec('min_p', SettingsValueKind.decimal),
  'presencePenalty': PrefSpec('presence_penalty', SettingsValueKind.decimal),
  'promptStrategy': PrefSpec('prompt_strategy', SettingsValueKind.object),
  'quickReplies': PrefSpec('quick_replies', SettingsValueKind.object),
  'regexRules': PrefSpec('regex_rules', SettingsValueKind.object),
  'repetitionPenalty': PrefSpec('repetition_penalty', SettingsValueKind.decimal),
  'repetitionPenaltySlope': PrefSpec('repetition_penalty_slope', SettingsValueKind.decimal),
  'requestTimeoutSeconds': PrefSpec('request_timeout_seconds', SettingsValueKind.integer),
  'requireAuthForApp': PrefSpec('require_auth_for_app', SettingsValueKind.boolean),
  'requireAuthForArchive': PrefSpec('require_auth_for_archive', SettingsValueKind.boolean),
  'requireNameToDelete': PrefSpec('require_name_to_delete', SettingsValueKind.boolean),
  'retrySequential': PrefSpec('retry_sequential', SettingsValueKind.boolean),
  'showBottomNav': PrefSpec('show_bottom_nav', SettingsValueKind.boolean),
  'showExitToMainApp': PrefSpec('show_exit_to_main_app', SettingsValueKind.boolean),
  'showMessageAvatar': PrefSpec('show_message_avatar', SettingsValueKind.boolean),
  'showMessageContinue': PrefSpec('show_message_continue', SettingsValueKind.boolean),
  'showMessageCopy': PrefSpec('show_message_copy', SettingsValueKind.boolean),
  'showMessageRetry': PrefSpec('show_message_retry', SettingsValueKind.boolean),
  'showParenButton': PrefSpec('show_paren_button', SettingsValueKind.boolean),
  'showTokenDashboard': PrefSpec('show_token_dashboard', SettingsValueKind.boolean),
  'showUploadButton': PrefSpec('show_upload_button', SettingsValueKind.boolean),
  'simpleModelMode': PrefSpec('simple_model_mode', SettingsValueKind.boolean),
  'snackDurationMs': PrefSpec('snack_duration_ms', SettingsValueKind.integer),
  'splashAnimation': PrefSpec('splash_animation', SettingsValueKind.text),
  'summaryTurnInterval': PrefSpec('summary_turn_interval', SettingsValueKind.integer),
  'summaryWordThreshold': PrefSpec('summary_word_threshold', SettingsValueKind.integer),
  'temperature': PrefSpec('temperature', SettingsValueKind.decimal),
  'themeMode': PrefSpec('theme_mode', SettingsValueKind.text),
  'topK': PrefSpec('top_k', SettingsValueKind.decimal),
  'topP': PrefSpec('top_p', SettingsValueKind.decimal),
  'ttsEnabled': PrefSpec('tts_enabled', SettingsValueKind.boolean),
  'ttsGlobalSeed': PrefSpec('tts_global_seed', SettingsValueKind.integer),
  'ttsQuoteOnly': PrefSpec('tts_quote_only', SettingsValueKind.boolean),
  'unboundedModelList': PrefSpec('unbounded_model_list', SettingsValueKind.boolean),
  'updateCheckEnabled': PrefSpec('update_check_enabled', SettingsValueKind.boolean),
};

class SettingsService {
  // ---- 宽松读取 ----
  //
  // 这些偏好的类型由「谁最后写的」决定，而不是由键名决定：旧版本可能写过 int，
  // 手动改过 prefs 文件，外部工具写过字符串 —— 任何一种都会让
  // SharedPreferences.getDouble / getInt 直接抛类型错误。
  //
  // 而 load() 在 runApp 之前执行：一旦它抛出，应用启动后没有窗口，
  // 用户看到的是「点了没反应」，也很难查到原因。所以数值型偏好一律走宽松读取，
  // 读不出来就退回 null（由模型自己的默认值兜底）。

  static double? _readDouble(SharedPreferences p, String key) {
    final Object? raw = p.get(key);
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  static int? _readInt(SharedPreferences p, String key) {
    final Object? raw = p.get(key);
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// 按规格读一个字段，返回可放进 JSON 的值；读不到返回 null（由模型兜底）。
  static Object? _readSpec(SharedPreferences prefs, PrefSpec spec) {
    switch (spec.kind) {
      case SettingsValueKind.boolean:
        final Object? raw = prefs.get(spec.prefKey);
        if (raw is bool) return raw;
        if (raw is String) return raw == 'true';
        return null;
      case SettingsValueKind.integer:
        return _readInt(prefs, spec.prefKey);
      case SettingsValueKind.decimal:
        return _readDouble(prefs, spec.prefKey);
      case SettingsValueKind.text:
        final Object? raw = prefs.get(spec.prefKey);
        return raw is String ? raw : null;
      case SettingsValueKind.object:
        final String? raw = prefs.getString(spec.prefKey);
        if (raw == null || raw.isEmpty) return null;
        try {
          return jsonDecode(raw);
        } catch (_) {
          return null;
        }
    }
  }

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPrefs.instance;

    // 1) 按表读出一份「像 toJson 的」map。
    final Map<String, dynamic> json = <String, dynamic>{};
    for (final MapEntry<String, PrefSpec> e in kPrefSpecs.entries) {
      final Object? value = _readSpec(prefs, e.value);
      if (value != null) json[e.key] = value;
    }

    // 2) 旧存档迁移：老版本只有一个布尔开屏开关，关掉过的人继续不播。
    if (json['splashAnimation'] == null) {
      final bool? legacy = prefs.getBool('show_splash_animation');
      if (legacy != null) json['splashAnimation'] = legacy ? 'logoDraw' : 'none';
    }

    // 3) 服务商 / 模型列表是复合对象，且要保证「默认项一定存在」：
    //    早年只有 provider/baseUrl/apiKey/model 四个扁平键，没有列表。
    final String legacyProvider =
        prefs.getString('provider') ?? LlmProviderConfig.defaultProviderType;
    final String legacyBaseUrl = prefs.getString('base_url') ?? '';
    final String legacyApiKey = prefs.getString('api_key') ?? '';
    final String legacyModel = prefs.getString('selected_model') ?? '';
    json['provider'] = legacyProvider;
    json['baseUrl'] = legacyBaseUrl;
    json['apiKey'] = legacyApiKey;
    json['selectedModel'] = legacyModel;

    List<LlmProviderConfig> providers = _decodeProviders(json['providers']);
    if (providers.isEmpty || !providers.any((LlmProviderConfig p) => p.isDefault)) {
      providers = <LlmProviderConfig>[
        LlmProviderConfig.defaultConfig(
          providerType: legacyProvider,
          baseUrl: legacyBaseUrl,
          apiKey: legacyApiKey,
        ),
        ...providers.where((LlmProviderConfig p) => !p.isDefault),
      ];
    }
    json['providers'] =
        providers.map((LlmProviderConfig p) => p.toJson()).toList();

    List<LlmModelConfig> models = _decodeModels(json['models']);
    if (models.isEmpty || !models.any((LlmModelConfig m) => m.isDefault)) {
      models = <LlmModelConfig>[
        LlmModelConfig.defaultConfig(modelName: legacyModel),
        ...models.where((LlmModelConfig m) => !m.isDefault),
      ];
    }
    json['models'] = models.map((LlmModelConfig m) => m.toJson()).toList();

    // 4) 剩下的默认值交给模型自己（`AppSettings.fromJson` 里 `?? 默认值`）。
    return AppSettings.fromJson(json);
  }

  static List<LlmProviderConfig> _decodeProviders(Object? raw) {
    final Object? decoded = raw is String ? _tryDecode(raw) : raw;
    if (decoded is! List) return const <LlmProviderConfig>[];
    return decoded
        .whereType<Map>()
        .map((Map e) => LlmProviderConfig.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static List<LlmModelConfig> _decodeModels(Object? raw) {
    final Object? decoded = raw is String ? _tryDecode(raw) : raw;
    if (decoded is! List) return const <LlmModelConfig>[];
    return decoded
        .whereType<Map>()
        .map((Map e) => LlmModelConfig.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// 全量写（导入 / 重置 / 迁移这类场景用它）。日常改一个键请用 [saveOne]。
  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPrefs.instance;
    final Map<String, dynamic> json = settings.toJson();
    for (final MapEntry<String, PrefSpec> e in kPrefSpecs.entries) {
      await _writeSpec(prefs, e.value, json[e.key]);
    }
  }

  /// **只写一个键**。
  ///
  /// 以前「改一个开关」会触发 [save] 的全量写：65 次 prefs 调用 + 一次 78 字段
  /// 序列化（审计 F-7）。现在只落这一个键。
  Future<void> saveOne(String jsonKey, Object? value) async {
    final PrefSpec? spec = kPrefSpecs[jsonKey];
    if (spec == null) {
      throw ArgumentError.value(jsonKey, 'jsonKey', '没有对应的 pref 存储规格');
    }
    final SharedPreferences prefs = await SharedPrefs.instance;
    await _writeSpec(prefs, spec, value);
  }

  static Future<void> _writeSpec(
    SharedPreferences prefs,
    PrefSpec spec,
    Object? value,
  ) async {
    // 置空 = 删键（customAccentColor / ttsGlobalSeed 的「恢复默认」语义）。
    if (value == null) {
      await prefs.remove(spec.prefKey);
      return;
    }
    switch (spec.kind) {
      case SettingsValueKind.boolean:
        await prefs.setBool(spec.prefKey, value as bool);
      case SettingsValueKind.integer:
        await prefs.setInt(spec.prefKey, (value as num).toInt());
      case SettingsValueKind.decimal:
        await prefs.setDouble(spec.prefKey, (value as num).toDouble());
      case SettingsValueKind.text:
        await prefs.setString(spec.prefKey, value.toString());
      case SettingsValueKind.object:
        await prefs.setString(spec.prefKey, jsonEncode(value));
    }
  }

  /// 读取上次自动备份的日期（格式 YYYY-MM-DD），无记录返回空串。
  Future<String> getLastAutoBackupDate() async {
    final SharedPreferences prefs = await SharedPrefs.instance;
    return prefs.getString('last_auto_backup_date') ?? '';
  }

  /// 记录上次自动备份的日期（格式 YYYY-MM-DD）。
  Future<void> saveLastAutoBackupDate(String date) async {
    final SharedPreferences prefs = await SharedPrefs.instance;
    await prefs.setString('last_auto_backup_date', date);
  }
}
