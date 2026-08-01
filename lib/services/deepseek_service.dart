import 'openai_service.dart';

/// DeepSeek 适配器。
///
/// DeepSeek 提供了与 OpenAI 兼容的 Chat Completions 接口，因此直接复用
/// [OpenAiService] 的请求 / 流式解析逻辑（已支持 reasoning_content 推理内容），
/// 仅覆盖 baseUrl 与端点路径（DeepSeek 端点不带 /v1 前缀）。
class DeepSeekService extends OpenAiService {
  DeepSeekService({super.client});

  @override
  String get id => 'deepseek';

  @override
  String get label => 'DeepSeek';

  @override
  String get defaultBaseUrl => 'https://api.deepseek.com';

  @override
  bool get requiresApiKey => true;

  @override
  bool get fixedBaseUrl => false;

  @override
  String modelsEndpoint(String baseUrl) {
    final String trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$trimmed/models';
  }

  @override
  String chatEndpoint(String baseUrl) {
    final String trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$trimmed/chat/completions';
  }
}
