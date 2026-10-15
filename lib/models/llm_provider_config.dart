class LlmProviderConfig {
  static const String defaultId = 'DNAAPP.MODELSETTING.PROVIDER.DEFAULT';
  static const String defaultAlias = '默认';

  /// 新装 / 新建配置时的默认服务商。
  ///
  /// 选 DeepSeek 而不是 OpenAI：对国内用户不需要额外解决代理，而且它的
  /// Base URL 是固定的（见 LlmProvider.fixedBaseUrl），OOBE 里少填一个字段，
  /// 新用户从「打开」到「能用」的距离最短。
  ///
  /// **改默认值只改这一处**。此前 'openai' 字面量散在 6 个地方（empty()、
  /// fromJson、settings_service 的 legacy 兜底、provider 编辑页……），
  /// 改一个漏一个就会出现「默认选中 A、兜底却给 B」。
  static const String defaultProviderType = 'deepseek';

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
    String providerType = defaultProviderType,
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
        providerType: json['providerType'] as String? ?? defaultProviderType,
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
