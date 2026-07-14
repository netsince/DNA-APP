import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/prompt_strategy.dart';

class SettingsService {
  static const String _baseUrlKey = 'base_url';
  static const String _apiKeyKey = 'api_key';
  static const String _modelKey = 'selected_model';
  static const String _oobeKey = 'completed_oobe';
  static const String _autoSummaryPromptKey = 'auto_summary_prompt';
  static const String _summaryTurnIntervalKey = 'summary_turn_interval';
  static const String _retrySequentialKey = 'retry_sequential';
  static const String _inspirationIncludeSummaryKey = 'inspiration_include_summary';
  static const String _promptStrategyKey = 'prompt_strategy';
  static const String _requireAuthForArchiveKey = 'require_auth_for_archive';
  static const String _requireAuthForAppKey = 'require_auth_for_app';
  static const String _showSplashAnimationKey = 'show_splash_animation';
  static const String _appIconKey = 'app_icon';

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
    
    return AppSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      selectedModel: prefs.getString(_modelKey) ?? '',
      completedOobe: prefs.getBool(_oobeKey) ?? false,
      autoSummaryPrompt: prefs.getBool(_autoSummaryPromptKey) ?? true,
      summaryTurnInterval: prefs.getInt(_summaryTurnIntervalKey) ?? 200,
      retrySequential: prefs.getBool(_retrySequentialKey) ?? false,
      inspirationIncludeSummary: prefs.getBool(_inspirationIncludeSummaryKey) ?? false,
      promptStrategy: promptStrategy,
      requireAuthForArchive: prefs.getBool(_requireAuthForArchiveKey) ?? false,
      requireAuthForApp: prefs.getBool(_requireAuthForAppKey) ?? false,
      showSplashAnimation: prefs.getBool(_showSplashAnimationKey) ?? true,
      appIcon: prefs.getString(_appIconKey) ?? 'default',
    );
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_apiKeyKey, settings.apiKey);
    await prefs.setString(_modelKey, settings.selectedModel);
    await prefs.setBool(_oobeKey, settings.completedOobe);
    await prefs.setBool(_autoSummaryPromptKey, settings.autoSummaryPrompt);
    await prefs.setInt(_summaryTurnIntervalKey, settings.summaryTurnInterval);
    await prefs.setBool(_retrySequentialKey, settings.retrySequential);
    await prefs.setBool(_inspirationIncludeSummaryKey, settings.inspirationIncludeSummary);
    await prefs.setString(_promptStrategyKey, jsonEncode(settings.promptStrategy.toJson()));
    await prefs.setBool(_requireAuthForArchiveKey, settings.requireAuthForArchive);
    await prefs.setBool(_requireAuthForAppKey, settings.requireAuthForApp);
    await prefs.setBool(_showSplashAnimationKey, settings.showSplashAnimation);
    await prefs.setString(_appIconKey, settings.appIcon);
  }
}
