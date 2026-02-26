class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    required this.completedOobe,
  });

  factory AppSettings.empty() {
    return const AppSettings(
      baseUrl: '',
      apiKey: '',
      selectedModel: '',
      completedOobe: false,
    );
  }

  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final bool completedOobe;

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    bool? completedOobe,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      completedOobe: completedOobe ?? this.completedOobe,
    );
  }
}
