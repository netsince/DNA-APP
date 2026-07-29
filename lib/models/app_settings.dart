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
    required this.showSplashAnimation,
    required this.appIcon,
    required this.snackDurationMs,
    required this.sherpaModelSource,
    this.sherpaCustomBaseUrl,
    required this.sherpaModelReady,
    this.sherpaModelPath,
    required this.selectedVoiceModelId,
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
      showSplashAnimation: true,
      appIcon: 'default',
      snackDurationMs: 1000,
      sherpaModelSource: 'auto',
      sherpaCustomBaseUrl: null,
      sherpaModelReady: false,
      sherpaModelPath: null,
      selectedVoiceModelId: kVoiceModelDefaultId,
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
  final bool showSplashAnimation;
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
      'showSplashAnimation': showSplashAnimation,
      'appIcon': appIcon,
      'snackDurationMs': snackDurationMs,
      'sherpaModelSource': sherpaModelSource,
      'sherpaCustomBaseUrl': sherpaCustomBaseUrl,
      'sherpaModelReady': sherpaModelReady,
      'sherpaModelPath': sherpaModelPath,
      'selectedVoiceModelId': selectedVoiceModelId,
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
      showSplashAnimation: (json['showSplashAnimation'] as bool?) ?? true,
      appIcon: (json['appIcon'] as String?) ?? 'default',
      snackDurationMs: (json['snackDurationMs'] as int?) ?? 1000,
      sherpaModelSource: (json['sherpaModelSource'] as String?) ?? 'auto',
      sherpaCustomBaseUrl: json['sherpaCustomBaseUrl'] as String?,
      sherpaModelReady: (json['sherpaModelReady'] as bool?) ?? false,
      sherpaModelPath: json['sherpaModelPath'] as String?,
      selectedVoiceModelId:
          (json['selectedVoiceModelId'] as String?) ?? kVoiceModelDefaultId,
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
    bool? showSplashAnimation,
    String? appIcon,
    int? snackDurationMs,
    String? sherpaModelSource,
    String? sherpaCustomBaseUrl,
    bool? sherpaModelReady,
    String? sherpaModelPath,
    String? selectedVoiceModelId,
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
      showSplashAnimation: showSplashAnimation ?? this.showSplashAnimation,
      appIcon: appIcon ?? this.appIcon,
      snackDurationMs: snackDurationMs ?? this.snackDurationMs,
      sherpaModelSource: sherpaModelSource ?? this.sherpaModelSource,
      sherpaCustomBaseUrl: sherpaCustomBaseUrl ?? this.sherpaCustomBaseUrl,
      sherpaModelReady: sherpaModelReady ?? this.sherpaModelReady,
      sherpaModelPath: sherpaModelPath ?? this.sherpaModelPath,
      selectedVoiceModelId: selectedVoiceModelId ?? this.selectedVoiceModelId,
    );
  }
}
