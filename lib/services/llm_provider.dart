import '../models/service_results.dart';

/// 大模型服务抽象。
///
/// 业务层只依赖此接口，不感知具体厂商（OpenAI / Anthropic / 本地推理等）。
/// 每个厂商实现一个子类（适配器），负责自己的鉴权头、请求体形状与流式解析。
abstract class LlmProvider {
  /// 唯一标识，存入 [AppSettings.provider]，如 'openai'、'anthropic'。
  String get id;

  /// 展示名称，用于设置页与 OOBE 选择。
  String get label;

  /// 该厂商默认的 baseUrl（用户未填写时使用）。
  String get defaultBaseUrl;

  /// 是否需要 API Key。本地推理可返回 false。
  bool get requiresApiKey;

  /// 校验 API 是否可用（连通性 / 鉴权）。
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  });

  /// 拉取可用模型列表。
  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  });

  /// 一次性补全（非流式）。
  Future<ChatCompletionResult> createChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  });

  /// 流式补全，逐块吐出可见文本。
  Stream<String> streamChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  });
}

/// 已注册的大模型 Provider 集合。
///
/// [AppController] 持有此对象，按 [AppSettings.provider] 返回对应实现，
/// 新增厂商只需在构造时把适配器加进 [providers] 即可，业务层无需改动。
class LlmProviderRegistry {
  const LlmProviderRegistry(this.providers);

  final List<LlmProvider> providers;

  /// 按 id 取 Provider；找不到时退回默认（首个）。
  LlmProvider operator [](String id) {
    for (final LlmProvider p in providers) {
      if (p.id == id) {
        return p;
      }
    }
    return providers.first;
  }

  /// 默认 Provider（列表首个）。
  LlmProvider get defaultProvider => providers.first;
}
