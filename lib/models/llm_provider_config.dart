class LlmProviderConfig {
  static const String defaultId = 'DNAAPP.MODELSETTING.PROVIDER.DEFAULT';
  static const String defaultAlias = '默认';

  final String id;
  final String alias;
  final String providerType; // 'openai', 'anthropic', 'zhipu', 'deepseek', etc.
  final String baseUrl;
  final String apiKey;

  const LlmProviderConfig({
    required this.id,
    required this.alias,
    required this.providerType,
    required this.baseUrl,
    required this.apiKey,
  });

  bool get isDefault => id == defaultId;

  factory LlmProviderConfig.defaultConfig({
    String providerType = 'openai',
    String baseUrl = '',
    String apiKey = '',
  }) {
    return LlmProviderConfig(
      id: defaultId,
      alias: defaultAlias,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias': alias,
        'providerType': providerType,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) =>
      LlmProviderConfig(
        id: json['id'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        providerType: json['providerType'] as String? ?? 'openai',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );

  LlmProviderConfig copyWith({
    String? id,
    String? alias,
    String? providerType,
    String? baseUrl,
    String? apiKey,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      providerType: providerType ?? this.providerType,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}
