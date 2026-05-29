import 'prompt_strategy.dart';

class AppSettings {
  const AppSettings({
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
  });

  factory AppSettings.empty() {
    return AppSettings(
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
    );
  }

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

  AppSettings copyWith({
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
  }) {
    return AppSettings(
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
    );
  }
}
