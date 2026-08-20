class LlmModelConfig {
  static const String defaultId = 'DNAAPP.MODELSETTING.MODEL.DEFAULT';
  static const String defaultAlias = '默认';

  final String id;
  final String alias;
  final String providerId;
  final String modelName;

  /// 是否启用自定义采样参数。若为 false 则继承全局采样设置。
  final bool customSamplingEnabled;

  final double? temperature;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final double? topP;
  final double? topK;
  final double? minP;
  final double? repetitionPenalty;
  final double? repetitionPenaltySlope;
  final int? maxContextMessages;
  final int? maxContextTokens;
  final bool? deepseekThinkingEnabled;
  final String? deepseekThinkingEffort;

  const LlmModelConfig({
    required this.id,
    required this.alias,
    required this.providerId,
    required this.modelName,
    this.customSamplingEnabled = false,
    this.temperature,
    this.frequencyPenalty,
    this.presencePenalty,
    this.topP,
    this.topK,
    this.minP,
    this.repetitionPenalty,
    this.repetitionPenaltySlope,
    this.maxContextMessages,
    this.maxContextTokens,
    this.deepseekThinkingEnabled,
    this.deepseekThinkingEffort,
  });

  bool get isDefault => id == defaultId;

  factory LlmModelConfig.defaultConfig({
    String providerId = 'DNAAPP.MODELSETTING.PROVIDER.DEFAULT',
    String modelName = '',
  }) {
    return LlmModelConfig(
      id: defaultId,
      alias: defaultAlias,
      providerId: providerId,
      modelName: modelName,
      customSamplingEnabled: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias': alias,
        'providerId': providerId,
        'modelName': modelName,
        'customSamplingEnabled': customSamplingEnabled,
        if (temperature != null) 'temperature': temperature,
        if (frequencyPenalty != null) 'frequencyPenalty': frequencyPenalty,
        if (presencePenalty != null) 'presencePenalty': presencePenalty,
        if (topP != null) 'topP': topP,
        if (topK != null) 'topK': topK,
        if (minP != null) 'minP': minP,
        if (repetitionPenalty != null)
          'repetitionPenalty': repetitionPenalty,
        if (repetitionPenaltySlope != null)
          'repetitionPenaltySlope': repetitionPenaltySlope,
        if (maxContextMessages != null)
          'maxContextMessages': maxContextMessages,
        if (maxContextTokens != null)
          'maxContextTokens': maxContextTokens,
        if (deepseekThinkingEnabled != null)
          'deepseekThinkingEnabled': deepseekThinkingEnabled,
        if (deepseekThinkingEffort != null)
          'deepseekThinkingEffort': deepseekThinkingEffort,
      };

  factory LlmModelConfig.fromJson(Map<String, dynamic> json) => LlmModelConfig(
        id: json['id'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        modelName: json['modelName'] as String? ?? '',
        customSamplingEnabled:
            json['customSamplingEnabled'] as bool? ?? false,
        temperature: (json['temperature'] as num?)?.toDouble(),
        frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
        presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
        topP: (json['topP'] as num?)?.toDouble(),
        topK: (json['topK'] as num?)?.toDouble(),
        minP: (json['minP'] as num?)?.toDouble(),
        repetitionPenalty:
            (json['repetitionPenalty'] as num?)?.toDouble(),
        repetitionPenaltySlope:
            (json['repetitionPenaltySlope'] as num?)?.toDouble(),
        maxContextMessages: json['maxContextMessages'] as int?,
        maxContextTokens: json['maxContextTokens'] as int?,
        deepseekThinkingEnabled: json['deepseekThinkingEnabled'] as bool?,
        deepseekThinkingEffort: json['deepseekThinkingEffort'] as String?,
      );

  LlmModelConfig copyWith({
    String? id,
    String? alias,
    String? providerId,
    String? modelName,
    bool? customSamplingEnabled,
    double? temperature,
    double? frequencyPenalty,
    double? presencePenalty,
    double? topP,
    double? topK,
    double? minP,
    double? repetitionPenalty,
    double? repetitionPenaltySlope,
    int? maxContextMessages,
    int? maxContextTokens,
    bool? deepseekThinkingEnabled,
    String? deepseekThinkingEffort,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      providerId: providerId ?? this.providerId,
      modelName: modelName ?? this.modelName,
      customSamplingEnabled:
          customSamplingEnabled ?? this.customSamplingEnabled,
      temperature: temperature ?? this.temperature,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      repetitionPenaltySlope:
          repetitionPenaltySlope ?? this.repetitionPenaltySlope,
      maxContextMessages: maxContextMessages ?? this.maxContextMessages,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      deepseekThinkingEnabled:
          deepseekThinkingEnabled ?? this.deepseekThinkingEnabled,
      deepseekThinkingEffort:
          deepseekThinkingEffort ?? this.deepseekThinkingEffort,
    );
  }
}
