class ApiCheckResult {
  const ApiCheckResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class ModelFetchResult {
  const ModelFetchResult({required this.models, this.errorMessage});

  final List<String> models;
  final String? errorMessage;

  bool get success => errorMessage == null;
}

class ChatCompletionResult {
  const ChatCompletionResult({required this.success, this.content, this.errorMessage});

  final bool success;
  final String? content;
  final String? errorMessage;
}
