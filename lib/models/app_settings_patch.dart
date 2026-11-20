/// 设置写入口的唯一实现。
///
/// ## 为什么不用 `AppSettings.fromJson` 当写通道
///
/// 直觉做法是「读 toJson、改一个键、fromJson 回来」。本仓库**不行**：
/// * `AppSettings.fromJson` 目前没有任何调用点（主链路走 SharedPreferences
///   逐字段读写），是一段未被激活的代码，完备性没有测试保护
///   （实测：`loreStickyRounds` 在 toJson 里写了，fromJson 不读）。
///   用它当写通道，等于把一个潜伏 bug 变成每次改设置都会触发。
/// * 序列化还有语义耦合：`appIcon` 合法性、`themeMode` 取值、`promptStrategy`
///   子结构都要在反序列化里再判断一遍。
///
/// 所以这里是一张**显式**的「key → 字段」表：switch 穷尽、default 直接抛。
/// 加字段忘了加声明 = 测试红（见 test/settings_spec_test.dart）。
///
/// ## copyWith 的一个坑
///
/// `copyWith` 全部用 `param ?? this.param` 合并，**无法表达「置空」**。
/// 因此 `customAccentColor` / `ttsGlobalSeed` 这类可空字段的清空走
/// [AppSettings] 上的专门方法（`clearXxx`），不要在这里用 copyWith 绕。
library;

import 'app_settings.dart';
import 'llm_model_config.dart';
import 'llm_provider_config.dart';
import 'prompt_strategy.dart';
import 'quick_reply.dart';
import '../utils/message_processor.dart' show RegexRule;

/// 设置值的类型档位。声明层用它做类型校验，写入口用它决定怎么转型。
enum SettingsValueKind { boolean, integer, decimal, text, object }

/// `AppSettings.toJson()` 的键 → 值类型。**这是 key 类型的唯一真相。**
///
/// 与 `copyWith` 的参数表逐条对应（82 条），由测试与 `toJson()` 对账：
/// 键集合必须相等、类型必须匹配运行时类型。
const Map<String, SettingsValueKind> settingsKeyKinds =
    <String, SettingsValueKind>{
      'provider': SettingsValueKind.text,
      'themeMode': SettingsValueKind.text,
      'fontFamilyMode': SettingsValueKind.text,
      'chatInputStyle': SettingsValueKind.text,
      'enableCommunity': SettingsValueKind.boolean,
      'freeImageCrop': SettingsValueKind.boolean,
      'baseUrl': SettingsValueKind.text,
      'apiKey': SettingsValueKind.text,
      'selectedModel': SettingsValueKind.text,
      'completedOobe': SettingsValueKind.boolean,
      'autoSummaryPrompt': SettingsValueKind.boolean,
      'summaryTurnInterval': SettingsValueKind.integer,
      'summaryWordThreshold': SettingsValueKind.integer,
      'requestTimeoutSeconds': SettingsValueKind.integer,
      'retrySequential': SettingsValueKind.boolean,
      'inspirationIncludeSummary': SettingsValueKind.boolean,
      'promptStrategy': SettingsValueKind.object,
      'requireAuthForArchive': SettingsValueKind.boolean,
      'requireAuthForApp': SettingsValueKind.boolean,
      'requireNameToDelete': SettingsValueKind.boolean,
      'allowDeleteMessage': SettingsValueKind.boolean,
      'autoBackup': SettingsValueKind.boolean,
      'showSplashAnimation': SettingsValueKind.boolean,
      'autoOpenLastChat': SettingsValueKind.boolean,
      'unboundedModelList': SettingsValueKind.boolean,
      'fontSizeStep': SettingsValueKind.integer,
      'updateCheckEnabled': SettingsValueKind.boolean,
      'showBottomNav': SettingsValueKind.boolean,
      'showExitToMainApp': SettingsValueKind.boolean,
      'chatQuickSidebar': SettingsValueKind.boolean,
      'chatQuickSidebarCollapsed': SettingsValueKind.boolean,
      'chatSwipeSwitch': SettingsValueKind.boolean,
      'showTokenDashboard': SettingsValueKind.boolean,
      'enableForking': SettingsValueKind.boolean,
      'enableCommandMacros': SettingsValueKind.boolean,
      'enableRegexReplacement': SettingsValueKind.boolean,
      'regexRules': SettingsValueKind.object,
      'appIcon': SettingsValueKind.text,
      'snackDurationMs': SettingsValueKind.integer,
      'accentMode': SettingsValueKind.text,
      'customAccentColor': SettingsValueKind.integer,
      'ttsEnabled': SettingsValueKind.boolean,
      'ttsGlobalSeed': SettingsValueKind.integer,
      'ttsQuoteOnly': SettingsValueKind.boolean,
      'showParenButton': SettingsValueKind.boolean,
      'showMessageAvatar': SettingsValueKind.boolean,
      'showMessageRetry': SettingsValueKind.boolean,
      'showMessageCopy': SettingsValueKind.boolean,
      'showMessageContinue': SettingsValueKind.boolean,
      'enterToSend': SettingsValueKind.boolean,
      'bgmVolume': SettingsValueKind.integer,
      'bgmSizeLimitUnlocked': SettingsValueKind.boolean,
      'chatMaskStrength': SettingsValueKind.integer,
      'chatBubbleOpacity': SettingsValueKind.integer,
      'halfScreenChat': SettingsValueKind.boolean,
      'dynamicHalfScreen': SettingsValueKind.boolean,
      'maxContextMessages': SettingsValueKind.integer,
      'maxContextTokens': SettingsValueKind.integer,
      'temperature': SettingsValueKind.decimal,
      'frequencyPenalty': SettingsValueKind.decimal,
      'presencePenalty': SettingsValueKind.decimal,
      'topP': SettingsValueKind.decimal,
      'topK': SettingsValueKind.decimal,
      'minP': SettingsValueKind.decimal,
      'repetitionPenalty': SettingsValueKind.decimal,
      'repetitionPenaltySlope': SettingsValueKind.decimal,
      'loreStickyRounds': SettingsValueKind.integer,
      'loreMaxEntries': SettingsValueKind.integer,
      'loreBudgetTokens': SettingsValueKind.integer,
      'quickReplies': SettingsValueKind.object,
      'deepseekThinkingEnabled': SettingsValueKind.boolean,
      'deepseekThinkingEffort': SettingsValueKind.text,
      'simpleModelMode': SettingsValueKind.boolean,
      'activeModelId': SettingsValueKind.text,
      'providers': SettingsValueKind.object,
      'models': SettingsValueKind.object,
    };

/// 带着写入口把值写进设置，返回**新**的 settings。
///
/// 只改 `key` 对应的那一个字段；未声明的 key 直接抛错 —— 调用方拼错键
/// 会当场炸，而不是静默写不进去。
AppSettings applySettingsPatch(AppSettings s, String key, Object? value) {
  switch (key) {
    case 'provider':
      return s.copyWith(provider: _asText(value));
    case 'themeMode':
      return s.copyWith(themeMode: _asText(value));
    case 'fontFamilyMode':
      return s.copyWith(fontFamilyMode: _asText(value));
    case 'chatInputStyle':
      return s.copyWith(chatInputStyle: _asText(value));
    case 'enableCommunity':
      return s.copyWith(enableCommunity: _asBool(value));
    case 'freeImageCrop':
      return s.copyWith(freeImageCrop: _asBool(value));
    case 'baseUrl':
      return s.copyWith(baseUrl: _asText(value));
    case 'apiKey':
      return s.copyWith(apiKey: _asText(value));
    case 'selectedModel':
      return s.copyWith(selectedModel: _asText(value));
    case 'completedOobe':
      return s.copyWith(completedOobe: _asBool(value));
    case 'autoSummaryPrompt':
      return s.copyWith(autoSummaryPrompt: _asBool(value));
    case 'summaryTurnInterval':
      return s.copyWith(summaryTurnInterval: _asInt(value));
    case 'summaryWordThreshold':
      return s.copyWith(summaryWordThreshold: _asInt(value));
    case 'requestTimeoutSeconds':
      return s.copyWith(requestTimeoutSeconds: _asInt(value));
    case 'retrySequential':
      return s.copyWith(retrySequential: _asBool(value));
    case 'inspirationIncludeSummary':
      return s.copyWith(inspirationIncludeSummary: _asBool(value));
    case 'promptStrategy':
      return s.copyWith(promptStrategy: value! as PromptStrategy);
    case 'requireAuthForArchive':
      return s.copyWith(requireAuthForArchive: _asBool(value));
    case 'requireAuthForApp':
      return s.copyWith(requireAuthForApp: _asBool(value));
    case 'requireNameToDelete':
      return s.copyWith(requireNameToDelete: _asBool(value));
    case 'allowDeleteMessage':
      return s.copyWith(allowDeleteMessage: _asBool(value));
    case 'autoBackup':
      return s.copyWith(autoBackup: _asBool(value));
    case 'showSplashAnimation':
      return s.copyWith(showSplashAnimation: _asBool(value));
    case 'autoOpenLastChat':
      return s.copyWith(autoOpenLastChat: _asBool(value));
    case 'unboundedModelList':
      return s.copyWith(unboundedModelList: _asBool(value));
    case 'fontSizeStep':
      return s.copyWith(fontSizeStep: _asInt(value));
    case 'updateCheckEnabled':
      return s.copyWith(updateCheckEnabled: _asBool(value));
    case 'showBottomNav':
      return s.copyWith(showBottomNav: _asBool(value));
    case 'showExitToMainApp':
      return s.copyWith(showExitToMainApp: _asBool(value));
    case 'chatQuickSidebar':
      return s.copyWith(chatQuickSidebar: _asBool(value));
    case 'chatQuickSidebarCollapsed':
      return s.copyWith(chatQuickSidebarCollapsed: _asBool(value));
    case 'chatSwipeSwitch':
      return s.copyWith(chatSwipeSwitch: _asBool(value));
    case 'showTokenDashboard':
      return s.copyWith(showTokenDashboard: _asBool(value));
    case 'enableForking':
      return s.copyWith(enableForking: _asBool(value));
    case 'enableCommandMacros':
      return s.copyWith(enableCommandMacros: _asBool(value));
    case 'enableRegexReplacement':
      return s.copyWith(enableRegexReplacement: _asBool(value));
    case 'regexRules':
      return s.copyWith(regexRules: value! as List<RegexRule>);
    case 'appIcon':
      return s.copyWith(appIcon: _asText(value));
    case 'snackDurationMs':
      return s.copyWith(snackDurationMs: _asInt(value));
    case 'accentMode':
      return s.copyWith(accentMode: _asText(value));
    case 'customAccentColor':
      // copyWith 用 `??` 合并，null 会被当成「不修改」，清空必须走专门的清除方法。
      return value == null
          ? s.clearCustomAccentColor()
          : s.copyWith(customAccentColor: _asInt(value));
    case 'ttsEnabled':
      return s.copyWith(ttsEnabled: _asBool(value));
    case 'ttsGlobalSeed':
      // copyWith 用 `??` 合并，null 会被当成「不修改」，清空必须走专门的清除方法。
      return value == null
          ? s.clearTtsGlobalSeed()
          : s.copyWith(ttsGlobalSeed: _asInt(value));
    case 'ttsQuoteOnly':
      return s.copyWith(ttsQuoteOnly: _asBool(value));
    case 'showParenButton':
      return s.copyWith(showParenButton: _asBool(value));
    case 'showMessageAvatar':
      return s.copyWith(showMessageAvatar: _asBool(value));
    case 'showMessageRetry':
      return s.copyWith(showMessageRetry: _asBool(value));
    case 'showMessageCopy':
      return s.copyWith(showMessageCopy: _asBool(value));
    case 'showMessageContinue':
      return s.copyWith(showMessageContinue: _asBool(value));
    case 'enterToSend':
      return s.copyWith(enterToSend: _asBool(value));
    case 'bgmVolume':
      return s.copyWith(bgmVolume: _asInt(value));
    case 'bgmSizeLimitUnlocked':
      return s.copyWith(bgmSizeLimitUnlocked: _asBool(value));
    case 'chatMaskStrength':
      return s.copyWith(chatMaskStrength: _asInt(value));
    case 'chatBubbleOpacity':
      return s.copyWith(chatBubbleOpacity: _asInt(value));
    case 'halfScreenChat':
      return s.copyWith(halfScreenChat: _asBool(value));
    case 'dynamicHalfScreen':
      return s.copyWith(dynamicHalfScreen: _asBool(value));
    case 'maxContextMessages':
      return s.copyWith(maxContextMessages: _asInt(value));
    case 'maxContextTokens':
      return s.copyWith(maxContextTokens: _asInt(value));
    case 'temperature':
      return s.copyWith(temperature: _asDouble(value));
    case 'frequencyPenalty':
      return s.copyWith(frequencyPenalty: _asDouble(value));
    case 'presencePenalty':
      return s.copyWith(presencePenalty: _asDouble(value));
    case 'topP':
      return s.copyWith(topP: _asDouble(value));
    case 'topK':
      return s.copyWith(topK: _asDouble(value));
    case 'minP':
      return s.copyWith(minP: _asDouble(value));
    case 'repetitionPenalty':
      return s.copyWith(repetitionPenalty: _asDouble(value));
    case 'repetitionPenaltySlope':
      return s.copyWith(repetitionPenaltySlope: _asDouble(value));
    case 'loreStickyRounds':
      return s.copyWith(loreStickyRounds: _asInt(value));
    case 'loreMaxEntries':
      return s.copyWith(loreMaxEntries: _asInt(value));
    case 'loreBudgetTokens':
      return s.copyWith(loreBudgetTokens: _asInt(value));
    case 'quickReplies':
      return s.copyWith(quickReplies: value! as List<QuickReply>);
    case 'deepseekThinkingEnabled':
      return s.copyWith(deepseekThinkingEnabled: _asBool(value));
    case 'deepseekThinkingEffort':
      return s.copyWith(deepseekThinkingEffort: _asText(value));
    case 'simpleModelMode':
      return s.copyWith(simpleModelMode: _asBool(value));
    case 'activeModelId':
      return s.copyWith(activeModelId: _asText(value));
    case 'providers':
      return s.copyWith(providers: value! as List<LlmProviderConfig>);
    case 'models':
      return s.copyWith(models: value! as List<LlmModelConfig>);
    default:
      throw ArgumentError.value(key, 'key', '未在 applySettingsPatch 中声明的设置键');
  }
}

bool _asBool(Object? v) {
  if (v is bool) return v;
  throw ArgumentError.value(v, 'value', '期望 bool');
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  throw ArgumentError.value(v, 'value', '期望 int');
}

double _asDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  throw ArgumentError.value(v, 'value', '期望 double');
}

String _asText(Object? v) {
  if (v is String) return v;
  if (v == null) return '';
  return v.toString();
}

