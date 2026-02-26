import 'dialogue_style.dart';

class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    required this.completedOobe,
    required this.dialogueStyle,
  });

  factory AppSettings.empty() {
    return const AppSettings(
      baseUrl: '',
      apiKey: '',
      selectedModel: '',
      completedOobe: false,
      dialogueStyle: <DialogueTurn>[],
    );
  }

  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final bool completedOobe;
  final List<DialogueTurn> dialogueStyle;

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    bool? completedOobe,
    List<DialogueTurn>? dialogueStyle,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      completedOobe: completedOobe ?? this.completedOobe,
      dialogueStyle: dialogueStyle ?? this.dialogueStyle,
    );
  }
}
