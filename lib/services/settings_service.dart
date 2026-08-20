import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/llm_model_config.dart';
import '../models/llm_provider_config.dart';
import '../models/prompt_strategy.dart';
import '../models/quick_reply.dart';
import '../models/voice_models.dart';

class SettingsService {
  static const String _simpleModelModeKey = 'simple_model_mode';
  static const String _activeModelIdKey = 'active_model_id';
  static const String _llmProvidersKey = 'llm_providers_json';
  static const String _llmModelsKey = 'llm_models_json';
  static const String _baseUrlKey = 'base_url';
  static const String _apiKeyKey = 'api_key';
  static const String _providerKey = 'provider';
  static const String _themeModeKey = 'theme_mode';
  static const String _modelKey = 'selected_model';
  static const String _oobeKey = 'completed_oobe';
  static const String _autoSummaryPromptKey = 'auto_summary_prompt';
  static const String _summaryTurnIntervalKey = 'summary_turn_interval';
  static const String _summaryWordThresholdKey = 'summary_word_threshold';
  static const String _retrySequentialKey = 'retry_sequential';
  static const String _inspirationIncludeSummaryKey = 'inspiration_include_summary';
  static const String _promptStrategyKey = 'prompt_strategy';
  static const String _requireAuthForArchiveKey = 'require_auth_for_archive';
  static const String _requireAuthForAppKey = 'require_auth_for_app';
  static const String _requireNameToDeleteKey = 'require_name_to_delete';
  static const String _allowDeleteMessageKey = 'allow_delete_message';
  static const String _showSplashAnimationKey = 'show_splash_animation';
  static const String _appIconKey = 'app_icon';
  static const String _snackDurationMsKey = 'snack_duration_ms';
  static const String _sherpaModelSourceKey = 'sherpa_model_source';
  static const String _sherpaCustomBaseUrlKey = 'sherpa_custom_base_url';
  static const String _sherpaModelReadyKey = 'sherpa_model_ready';
  static const String _sherpaModelPathKey = 'sherpa_model_path';
  static const String _sherpaSelectedModelKey = 'sherpa_selected_model_id';
  static const String _accentModeKey = 'accent_mode';
  static const String _customAccentColorKey = 'custom_accent_color';
  static const String _ttsEnabledKey = 'tts_enabled';
  static const String _ttsGlobalSeedKey = 'tts_global_seed';
  static const String _voiceInputEnabledKey = 'voice_input_enabled';
  static const String _showParenButtonKey = 'show_paren_button';
  static const String _showMessageAvatarKey = 'show_message_avatar';
  static const String _showMessageRetryKey = 'show_message_retry';
  static const String _showMessageCopyKey = 'show_message_copy';
  static const String _showMessageContinueKey = 'show_message_continue';
  static const String _enterToSendKey = 'enter_to_send';
  static const String _showBottomNavKey = 'show_bottom_nav';
  static const String _chatMaskStrengthKey = 'chat_mask_strength';
  static const String _chatBubbleOpacityKey = 'chat_bubble_opacity';
  static const String _halfScreenChatKey = 'half_screen_chat';
  static const String _dynamicHalfScreenKey = 'dynamic_half_screen';
  static const String _maxContextMessagesKey = 'max_context_messages';
  static const String _maxContextTokensKey = 'max_context_tokens';
  static const String _temperatureKey = 'temperature';
  static const String _frequencyPenaltyKey = 'frequency_penalty';
  static const String _presencePenaltyKey = 'presence_penalty';
  static const String _loreStickyRoundsKey = 'lore_sticky_rounds';
  static const String _loreMaxEntriesKey = 'lore_max_entries';
  static const String _loreBudgetTokensKey = 'lore_budget_tokens';
  static const String _quickRepliesKey = 'quick_replies';
  static const String _autoBackupKey = 'auto_backup';
  static const String _lastAutoBackupDateKey = 'last_auto_backup_date';

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    
    PromptStrategy promptStrategy = PromptStrategy.defaults();
    final String? promptStrategyJson = prefs.getString(_promptStrategyKey);
    if (promptStrategyJson != null && promptStrategyJson.isNotEmpty) {
      try {
        final Map<String, dynamic> json = jsonDecode(promptStrategyJson) as Map<String, dynamic>;
        promptStrategy = PromptStrategy.fromJson(json);
      } catch (_) {
        // Use defaults if parsing fails.
      }
    }

    final String legacyProvider = prefs.getString(_providerKey) ?? 'openai';
    final String legacyBaseUrl = prefs.getString(_baseUrlKey) ?? '';
    final String legacyApiKey = prefs.getString(_apiKeyKey) ?? '';
    final String legacyModel = prefs.getString(_modelKey) ?? '';

    List<LlmProviderConfig> providers =
        _decodeProviders(prefs.getString(_llmProvidersKey));
    if (providers.isEmpty || !providers.any((p) => p.isDefault)) {
      providers = <LlmProviderConfig>[
        LlmProviderConfig.defaultConfig(
          providerType: legacyProvider,
          baseUrl: legacyBaseUrl,
          apiKey: legacyApiKey,
        ),
        ...providers.where((p) => !p.isDefault),
      ];
    }

    List<LlmModelConfig> models =
        _decodeModels(prefs.getString(_llmModelsKey));
    if (models.isEmpty || !models.any((m) => m.isDefault)) {
      models = <LlmModelConfig>[
        LlmModelConfig.defaultConfig(
          modelName: legacyModel,
        ),
        ...models.where((m) => !m.isDefault),
      ];
    }

    final bool simpleModelMode = prefs.getBool(_simpleModelModeKey) ?? true;
    final String activeModelId =
        prefs.getString(_activeModelIdKey) ?? LlmModelConfig.defaultId;
    
    return AppSettings(
      provider: legacyProvider,
      themeMode: prefs.getString(_themeModeKey) ?? 'system',
      baseUrl: legacyBaseUrl,
      apiKey: legacyApiKey,
      selectedModel: legacyModel,
      completedOobe: prefs.getBool(_oobeKey) ?? false,
      autoSummaryPrompt: prefs.getBool(_autoSummaryPromptKey) ?? true,
      summaryTurnInterval: prefs.getInt(_summaryTurnIntervalKey) ?? 200,
      summaryWordThreshold: prefs.getInt(_summaryWordThresholdKey) ?? 6000,
      retrySequential: prefs.getBool(_retrySequentialKey) ?? false,
      inspirationIncludeSummary: prefs.getBool(_inspirationIncludeSummaryKey) ?? false,
      promptStrategy: promptStrategy,
      requireAuthForArchive: prefs.getBool(_requireAuthForArchiveKey) ?? false,
      requireAuthForApp: prefs.getBool(_requireAuthForAppKey) ?? false,
      requireNameToDelete: prefs.getBool(_requireNameToDeleteKey) ?? true,
      allowDeleteMessage: prefs.getBool(_allowDeleteMessageKey) ?? false,
      showSplashAnimation: prefs.getBool(_showSplashAnimationKey) ?? true,
      appIcon: prefs.getString(_appIconKey) ?? 'default',
      snackDurationMs: prefs.getInt(_snackDurationMsKey) ?? 1000,
      sherpaModelSource:
          prefs.getString(_sherpaModelSourceKey) ?? 'modelscope',
      sherpaModelReady: prefs.getBool(_sherpaModelReadyKey) ?? false,
      sherpaCustomBaseUrl: prefs.getString(_sherpaCustomBaseUrlKey),
      sherpaModelPath: prefs.getString(_sherpaModelPathKey),
      selectedVoiceModelId:
          prefs.getString(_sherpaSelectedModelKey) ?? kVoiceModelDefaultId,
      accentMode: prefs.getString(_accentModeKey) ?? 'auto',
      customAccentColor: prefs.getInt(_customAccentColorKey),
      ttsEnabled: prefs.getBool(_ttsEnabledKey) ?? false,
      ttsGlobalSeed: prefs.getInt(_ttsGlobalSeedKey),
      voiceInputEnabled: prefs.getBool(_voiceInputEnabledKey) ?? false,
      showParenButton: prefs.getBool(_showParenButtonKey) ?? true,
      showMessageAvatar: prefs.getBool(_showMessageAvatarKey) ?? true,
      showMessageRetry: prefs.getBool(_showMessageRetryKey) ?? true,
      showMessageCopy: prefs.getBool(_showMessageCopyKey) ?? true,
      showMessageContinue: prefs.getBool(_showMessageContinueKey) ?? true,
      enterToSend: prefs.getBool(_enterToSendKey) ?? true,
      showBottomNav: prefs.getBool(_showBottomNavKey) ?? false,
      autoBackup: prefs.getBool(_autoBackupKey) ?? true,
      chatMaskStrength: prefs.getInt(_chatMaskStrengthKey) ?? 75,
      chatBubbleOpacity: prefs.getInt(_chatBubbleOpacityKey) ?? 100,
      halfScreenChat: prefs.getBool(_halfScreenChatKey) ?? false,
      dynamicHalfScreen: prefs.getBool(_dynamicHalfScreenKey) ?? false,
      maxContextMessages: prefs.getInt(_maxContextMessagesKey) ?? 120,
      maxContextTokens: prefs.getInt(_maxContextTokensKey) ?? 8000,
      temperature: (prefs.getDouble(_temperatureKey)) ?? 0.7,
      frequencyPenalty: (prefs.getDouble(_frequencyPenaltyKey)) ?? 0.0,
      presencePenalty: (prefs.getDouble(_presencePenaltyKey)) ?? 0.0,
      loreStickyRounds: prefs.getInt(_loreStickyRoundsKey) ?? 3,
      loreMaxEntries: prefs.getInt(_loreMaxEntriesKey) ?? 8,
      loreBudgetTokens: prefs.getInt(_loreBudgetTokensKey) ?? 0,
      quickReplies: _decodeQuickReplies(prefs.getString(_quickRepliesKey)),
      simpleModelMode: simpleModelMode,
      activeModelId: activeModelId,
      providers: providers,
      models: models,
    );
  }

  static List<LlmProviderConfig> _decodeProviders(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <LlmProviderConfig>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((Map e) => LlmProviderConfig.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <LlmProviderConfig>[];
    }
  }

  static List<QuickReply> _decodeQuickReplies(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <QuickReply>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((Map e) => QuickReply.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <QuickReply>[];
    }
  }

  static List<LlmModelConfig> _decodeModels(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <LlmModelConfig>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((Map e) => LlmModelConfig.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <LlmModelConfig>[];
    }
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, settings.provider);
    await prefs.setString(_themeModeKey, settings.themeMode);
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_apiKeyKey, settings.apiKey);
    await prefs.setString(_modelKey, settings.selectedModel);
    await prefs.setBool(_oobeKey, settings.completedOobe);
    await prefs.setBool(_autoSummaryPromptKey, settings.autoSummaryPrompt);
    await prefs.setInt(_summaryTurnIntervalKey, settings.summaryTurnInterval);
    await prefs.setInt(_summaryWordThresholdKey, settings.summaryWordThreshold);
    await prefs.setBool(_retrySequentialKey, settings.retrySequential);
    await prefs.setBool(_inspirationIncludeSummaryKey, settings.inspirationIncludeSummary);
    await prefs.setString(_promptStrategyKey, jsonEncode(settings.promptStrategy.toJson()));
    await prefs.setBool(_requireAuthForArchiveKey, settings.requireAuthForArchive);
    await prefs.setBool(_requireAuthForAppKey, settings.requireAuthForApp);
    await prefs.setBool(_requireNameToDeleteKey, settings.requireNameToDelete);
    await prefs.setBool(_allowDeleteMessageKey, settings.allowDeleteMessage);
    await prefs.setBool(_showSplashAnimationKey, settings.showSplashAnimation);
    await prefs.setString(_appIconKey, settings.appIcon);
    await prefs.setInt(_snackDurationMsKey, settings.snackDurationMs);
    await prefs.setString(_sherpaModelSourceKey, settings.sherpaModelSource);
    if (settings.sherpaCustomBaseUrl != null) {
      await prefs.setString(
          _sherpaCustomBaseUrlKey, settings.sherpaCustomBaseUrl!);
    } else {
      await prefs.remove(_sherpaCustomBaseUrlKey);
    }
    await prefs.setBool(_sherpaModelReadyKey, settings.sherpaModelReady);
    if (settings.sherpaModelPath != null) {
      await prefs.setString(_sherpaModelPathKey, settings.sherpaModelPath!);
    } else {
      await prefs.remove(_sherpaModelPathKey);
    }
    await prefs.setString(
        _sherpaSelectedModelKey, settings.selectedVoiceModelId);
    await prefs.setString(_accentModeKey, settings.accentMode);
    if (settings.customAccentColor != null) {
      await prefs.setInt(
          _customAccentColorKey, settings.customAccentColor!);
    } else {
      await prefs.remove(_customAccentColorKey);
    }
    await prefs.setBool(_ttsEnabledKey, settings.ttsEnabled);
    if (settings.ttsGlobalSeed != null) {
      await prefs.setInt(_ttsGlobalSeedKey, settings.ttsGlobalSeed!);
    } else {
      await prefs.remove(_ttsGlobalSeedKey);
    }
    await prefs.setBool(_voiceInputEnabledKey, settings.voiceInputEnabled);
    await prefs.setBool(_showParenButtonKey, settings.showParenButton);
    await prefs.setBool(_showMessageAvatarKey, settings.showMessageAvatar);
    await prefs.setBool(_showMessageRetryKey, settings.showMessageRetry);
    await prefs.setBool(_showMessageCopyKey, settings.showMessageCopy);
    await prefs.setBool(_showMessageContinueKey, settings.showMessageContinue);
    await prefs.setBool(_enterToSendKey, settings.enterToSend);
    await prefs.setBool(_showBottomNavKey, settings.showBottomNav);
    await prefs.setBool(_autoBackupKey, settings.autoBackup);
    await prefs.setInt(_chatMaskStrengthKey, settings.chatMaskStrength);
    await prefs.setInt(_chatBubbleOpacityKey, settings.chatBubbleOpacity);
    await prefs.setBool(_halfScreenChatKey, settings.halfScreenChat);
    await prefs.setBool(_dynamicHalfScreenKey, settings.dynamicHalfScreen);
    await prefs.setInt(_maxContextMessagesKey, settings.maxContextMessages);
    await prefs.setInt(_maxContextTokensKey, settings.maxContextTokens);
    await prefs.setDouble(_temperatureKey, settings.temperature);
    await prefs.setDouble(_frequencyPenaltyKey, settings.frequencyPenalty);
    await prefs.setDouble(_presencePenaltyKey, settings.presencePenalty);
    await prefs.setInt(_loreStickyRoundsKey, settings.loreStickyRounds);
    await prefs.setInt(_loreMaxEntriesKey, settings.loreMaxEntries);
    await prefs.setInt(_loreBudgetTokensKey, settings.loreBudgetTokens);
    await prefs.setString(
        _quickRepliesKey,
        jsonEncode(settings.quickReplies
            .map((QuickReply r) => r.toJson())
            .toList()));
    await prefs.setBool(_simpleModelModeKey, settings.simpleModelMode);
    await prefs.setString(_activeModelIdKey, settings.activeModelId);
    await prefs.setString(
      _llmProvidersKey,
      jsonEncode(settings.providers.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      _llmModelsKey,
      jsonEncode(settings.models.map((m) => m.toJson()).toList()),
    );
  }

  /// 读取上次自动备份的日期（格式 YYYY-MM-DD），无记录返回空串。
  Future<String> getLastAutoBackupDate() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastAutoBackupDateKey) ?? '';
  }

  /// 记录上次自动备份的日期（格式 YYYY-MM-DD）。
  Future<void> saveLastAutoBackupDate(String date) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAutoBackupDateKey, date);
  }
}
