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
  const ChatCompletionResult({
    required this.success,
    this.content,
    this.errorMessage,
    this.totalTokens,
  });

  final bool success;
  final String? content;
  final String? errorMessage;

  /// 服务端回报的本次用量(usage.total_tokens / input+output 之和)。
  /// 多数兼容端点不回传时为 null。
  final int? totalTokens;
}
