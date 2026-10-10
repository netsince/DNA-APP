/// 一次补全请求的全部参数(C2:参数对象)。
///
/// 取代 `streamChatCompletion` / `createChatCompletion` 原先 15 个平铺参数:
/// 新增厂商或参数只需扩展本类与 [AppController.buildLlmRequest] 工厂,
/// 不再波及接口与全部实现。
class LlmRequest {
  const LlmRequest({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.messages,
    this.temperature = 0.7,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.topP = 1.0,
    this.topK = 0.0,
    this.minP = 0.0,
    this.repetitionPenalty = 1.0,
    this.repetitionPenaltySlope = 0.0,
    this.maxTokens,
    this.thinkingType,
    this.reasoningEffort,
    this.timeout = const Duration(seconds: 20),
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final List<Map<String, String>> messages;

  final double temperature;
  final double frequencyPenalty;
  final double presencePenalty;
  final double topP;
  final double topK;
  final double minP;
  final double repetitionPenalty;
  final double repetitionPenaltySlope;

  /// 单轮最大输出 token。null = 不发送(由服务端默认),
  /// Anthropic 则回退其内部默认值。
  final int? maxTokens;

  /// DeepSeek 思考模式:'enabled' / 'disabled'(null = 不发送)。
  final String? thinkingType;

  /// DeepSeek 思考强度:'low' / 'high' / 'max'。
  final String? reasoningEffort;

  /// 本次请求的超时（来自设置里的「请求超时」）。
  ///
  /// 非流式调用是**总时长上限**；流式调用只守护到响应头到达，body 阶段另有空闲看门狗。
  /// 带思考的模型需要调大，否则思考还没结束就被判超时。
  final Duration timeout;

  LlmRequest copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    List<Map<String, String>>? messages,
    double? temperature,
    double? frequencyPenalty,
    double? presencePenalty,
    double? topP,
    double? topK,
    double? minP,
    double? repetitionPenalty,
    double? repetitionPenaltySlope,
    int? maxTokens,
    String? thinkingType,
    String? reasoningEffort,
    Duration? timeout,
  }) {
    return LlmRequest(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      messages: messages ?? this.messages,
      temperature: temperature ?? this.temperature,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      repetitionPenaltySlope: repetitionPenaltySlope ?? this.repetitionPenaltySlope,
      maxTokens: maxTokens ?? this.maxTokens,
      thinkingType: thinkingType ?? this.thinkingType,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      timeout: timeout ?? this.timeout,
    );
  }
}
