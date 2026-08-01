import 'prompt_strategy.dart';
import 'voice_models.dart';

class AppSettings {
  const AppSettings({
    required this.provider,
    required this.themeMode,
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    required this.completedOobe,
    required this.autoSummaryPrompt,
    required this.summaryTurnInterval,
    required this.retrySequential,
    required this.inspirationIncludeSummary,
    required this.promptStrategy,
    required this.requireAuthForArchive,
    required this.requireAuthForApp,
    required this.requireNameToDelete,
    required this.allowDeleteMessage,
    required this.autoBackup,
    required this.showSplashAnimation,
    required this.showBottomNav,
    required this.appIcon,
    required this.snackDurationMs,
    required this.sherpaModelSource,
    this.sherpaCustomBaseUrl,
    required this.sherpaModelReady,
    this.sherpaModelPath,
    required this.selectedVoiceModelId,
    required this.accentMode,
    this.customAccentColor,
    required this.voiceInputEnabled,
    required this.ttsEnabled,
    this.ttsGlobalSeed,
    this.ttsQuoteOnly = true,
  });

  factory AppSettings.empty() {
    return AppSettings(
      provider: 'openai',
      themeMode: 'system',
      baseUrl: '',
      apiKey: '',
      selectedModel: '',
      completedOobe: false,
      autoSummaryPrompt: true,
      summaryTurnInterval: 200,
      retrySequential: false,
      inspirationIncludeSummary: false,
      promptStrategy: PromptStrategy.defaults(),
      requireAuthForArchive: false,
      requireAuthForApp: false,
      requireNameToDelete: true,
      allowDeleteMessage: false,
      autoBackup: true,
      showSplashAnimation: true,
      showBottomNav: false,
      appIcon: 'default',
      snackDurationMs: 1000,
      sherpaModelSource: 'auto',
      sherpaCustomBaseUrl: null,
      sherpaModelReady: false,
      sherpaModelPath: null,
      selectedVoiceModelId: kVoiceModelDefaultId,
      accentMode: 'auto',
      customAccentColor: null,
      voiceInputEnabled: false,
      ttsEnabled: false,
      ttsGlobalSeed: null,
      ttsQuoteOnly: true,
    );
  }

  final String provider;
  final String themeMode;
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final bool completedOobe;
  final bool autoSummaryPrompt;
  final int summaryTurnInterval;
  final bool retrySequential;
  final bool inspirationIncludeSummary;
  final PromptStrategy promptStrategy;
  final bool requireAuthForArchive;
  final bool requireAuthForApp;

  /// 删除前是否强制输入完整名称。
  /// 开启时：输入对应名称（角色名 / 世界名 / 对话角色名 / 群成员名）→ 5 秒滚动确认（可反悔）。
  /// 关闭时：改为长按右下角按钮 5 秒删除（滚动同步进行）。对四类可归档实体统一生效。
  final bool requireNameToDelete;

  /// 是否允许在聊天页删除单条对话消息（长按/右键菜单显示「删除本条」）。
  final bool allowDeleteMessage;

  /// 是否开启每日自动备份（默认开启）。开启后每天首次进入应用时在软件外部
  /// 静默生成一份全量备份，保留最近 5 天，全程无提示。
  final bool autoBackup;

  final bool showSplashAnimation;

  /// 是否在主页等页面底部显示「主页 / 群聊 / 我家 / 世界」导航栏。默认关闭。
  final bool showBottomNav;

  final String appIcon;
  final int snackDurationMs;

  /// 语音识别模型来源偏好：'auto' | 'modelscope' | 'github' | 'custom'。
  /// 'auto' 才会探测并回退；其余为严格单选，失败直接报错。
  final String sherpaModelSource;

  /// 自定义模型服务器根地址（source 为 'custom' 时生效）。
  final String? sherpaCustomBaseUrl;

  /// 模型是否已下载就绪（本地存在可用模型）。
  final bool sherpaModelReady;

  /// 已下载模型的本地目录路径。
  final String? sherpaModelPath;

  /// 当前选中的语音识别模型 id。
  final String selectedVoiceModelId;

  /// 强调色（莫奈取色）模式：'auto' 跟随系统/角色卡；'custom' 使用自定义色。
  final String accentMode;

  /// 自定义强调色（ARGB 整数），仅当 [accentMode] 为 'custom' 时生效。
  final int? customAccentColor;

  /// 是否启用离线语音输入（STT）。关闭时聊天输入框不显示麦克风按钮。
  final bool voiceInputEnabled;

  /// 是否启用端侧语音合成（TTS）。
  final bool ttsEnabled;

  /// 全局 TTS seed：角色未单独设置 seed 时使用（保证音色稳定）。
  final int? ttsGlobalSeed;

  /// 合成时是否「引号内容优先」：开启时优先只读引号内的内容，
  /// 无引号内容则读全文；关闭时始终读全文。两者都永远排除括号内容。
  final bool ttsQuoteOnly;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'provider': provider,
      'themeMode': themeMode,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'selectedModel': selectedModel,
      'completedOobe': completedOobe,
      'autoSummaryPrompt': autoSummaryPrompt,
      'summaryTurnInterval': summaryTurnInterval,
      'retrySequential': retrySequential,
      'inspirationIncludeSummary': inspirationIncludeSummary,
      'promptStrategy': promptStrategy.toJson(),
      'requireAuthForArchive': requireAuthForArchive,
      'requireAuthForApp': requireAuthForApp,
      'requireNameToDelete': requireNameToDelete,
      'allowDeleteMessage': allowDeleteMessage,
      'autoBackup': autoBackup,
      'showSplashAnimation': showSplashAnimation,
      'showBottomNav': showBottomNav,
      'appIcon': appIcon,
      'snackDurationMs': snackDurationMs,
      'sherpaModelSource': sherpaModelSource,
      'sherpaCustomBaseUrl': sherpaCustomBaseUrl,
      'sherpaModelReady': sherpaModelReady,
      'sherpaModelPath': sherpaModelPath,
      'selectedVoiceModelId': selectedVoiceModelId,
      'accentMode': accentMode,
      'customAccentColor': customAccentColor,
      'voiceInputEnabled': voiceInputEnabled,
      'ttsEnabled': ttsEnabled,
      'ttsGlobalSeed': ttsGlobalSeed,
      'ttsQuoteOnly': ttsQuoteOnly,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final PromptStrategy promptStrategy = json['promptStrategy'] is Map
        ? PromptStrategy.fromJson(
            (json['promptStrategy'] as Map).cast<String, dynamic>(),
          )
        : PromptStrategy.defaults();
    return AppSettings(
      provider: (json['provider'] as String?) ?? 'openai',
      themeMode: (json['themeMode'] as String?) ?? 'system',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      selectedModel: (json['selectedModel'] as String?) ?? '',
      completedOobe: (json['completedOobe'] as bool?) ?? false,
      autoSummaryPrompt: (json['autoSummaryPrompt'] as bool?) ?? true,
      summaryTurnInterval: (json['summaryTurnInterval'] as int?) ?? 200,
      retrySequential: (json['retrySequential'] as bool?) ?? false,
      inspirationIncludeSummary:
          (json['inspirationIncludeSummary'] as bool?) ?? false,
      promptStrategy: promptStrategy,
      requireAuthForArchive: (json['requireAuthForArchive'] as bool?) ?? false,
      requireAuthForApp: (json['requireAuthForApp'] as bool?) ?? false,
      requireNameToDelete: (json['requireNameToDelete'] as bool?) ?? true,
      allowDeleteMessage: (json['allowDeleteMessage'] as bool?) ?? false,
      autoBackup: (json['autoBackup'] as bool?) ?? true,
      showSplashAnimation: (json['showSplashAnimation'] as bool?) ?? true,
      showBottomNav: (json['showBottomNav'] as bool?) ?? false,
      appIcon: (json['appIcon'] as String?) ?? 'default',
      snackDurationMs: (json['snackDurationMs'] as int?) ?? 1000,
      sherpaModelSource: (json['sherpaModelSource'] as String?) ?? 'auto',
      sherpaCustomBaseUrl: json['sherpaCustomBaseUrl'] as String?,
      sherpaModelReady: (json['sherpaModelReady'] as bool?) ?? false,
      sherpaModelPath: json['sherpaModelPath'] as String?,
      selectedVoiceModelId:
          (json['selectedVoiceModelId'] as String?) ?? kVoiceModelDefaultId,
      accentMode: (json['accentMode'] as String?) ?? 'auto',
      customAccentColor: json['customAccentColor'] as int?,
      voiceInputEnabled: (json['voiceInputEnabled'] as bool?) ?? false,
      ttsEnabled: (json['ttsEnabled'] as bool?) ?? false,
      ttsGlobalSeed: json['ttsGlobalSeed'] as int?,
      ttsQuoteOnly: (json['ttsQuoteOnly'] as bool?) ?? true,
    );
  }

  AppSettings copyWith({
    String? provider,
    String? themeMode,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    bool? completedOobe,
    bool? autoSummaryPrompt,
    int? summaryTurnInterval,
    bool? retrySequential,
    bool? inspirationIncludeSummary,
    PromptStrategy? promptStrategy,
    bool? requireAuthForArchive,
    bool? requireAuthForApp,
    bool? requireNameToDelete,
    bool? allowDeleteMessage,
    bool? autoBackup,
    bool? showSplashAnimation,
    bool? showBottomNav,
    String? appIcon,
    int? snackDurationMs,
    String? sherpaModelSource,
    String? sherpaCustomBaseUrl,
    bool? sherpaModelReady,
    String? sherpaModelPath,
    String? selectedVoiceModelId,
    String? accentMode,
    int? customAccentColor,
    bool? voiceInputEnabled,
    bool? ttsEnabled,
    int? ttsGlobalSeed,
    bool? ttsQuoteOnly,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      themeMode: themeMode ?? this.themeMode,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      completedOobe: completedOobe ?? this.completedOobe,
      autoSummaryPrompt: autoSummaryPrompt ?? this.autoSummaryPrompt,
      summaryTurnInterval: summaryTurnInterval ?? this.summaryTurnInterval,
      retrySequential: retrySequential ?? this.retrySequential,
      inspirationIncludeSummary: inspirationIncludeSummary ?? this.inspirationIncludeSummary,
      promptStrategy: promptStrategy ?? this.promptStrategy,
      requireAuthForArchive: requireAuthForArchive ?? this.requireAuthForArchive,
      requireAuthForApp: requireAuthForApp ?? this.requireAuthForApp,
      requireNameToDelete: requireNameToDelete ?? this.requireNameToDelete,
      allowDeleteMessage: allowDeleteMessage ?? this.allowDeleteMessage,
      autoBackup: autoBackup ?? this.autoBackup,
      showSplashAnimation: showSplashAnimation ?? this.showSplashAnimation,
      showBottomNav: showBottomNav ?? this.showBottomNav,
      appIcon: appIcon ?? this.appIcon,
      snackDurationMs: snackDurationMs ?? this.snackDurationMs,
      sherpaModelSource: sherpaModelSource ?? this.sherpaModelSource,
      sherpaCustomBaseUrl: sherpaCustomBaseUrl ?? this.sherpaCustomBaseUrl,
      sherpaModelReady: sherpaModelReady ?? this.sherpaModelReady,
      sherpaModelPath: sherpaModelPath ?? this.sherpaModelPath,
      selectedVoiceModelId: selectedVoiceModelId ?? this.selectedVoiceModelId,
      accentMode: accentMode ?? this.accentMode,
      customAccentColor: customAccentColor ?? this.customAccentColor,
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      ttsGlobalSeed: ttsGlobalSeed ?? this.ttsGlobalSeed,
      ttsQuoteOnly: ttsQuoteOnly ?? this.ttsQuoteOnly,
    );
  }
}
