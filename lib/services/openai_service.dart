import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_results.dart';
import 'llm_request.dart';
import 'llm_service_base.dart';
import 'llm_stream_chunk.dart';

/// OpenAI 兼容适配器(OpenAI 及一切兼容网关/本地推理)。
///
/// 传输保障、SSE 解析、能力矩阵、端点规则全部由 [LlmServiceBase] 承载;
/// 本类只提供鉴权头与端点路径。
class OpenAiService extends LlmServiceBase {
  OpenAiService({super.client, super.streamClient});

  @override
  String get id => 'openai';

  @override
  String get label => 'OpenAI 兼容';

  @override
  String get defaultBaseUrl => 'https://api.openai.com/v1';

  @override
  bool get requiresApiKey => true;

  @override
  bool get fixedBaseUrl => false;

  @override
  Map<String, String> buildHeaders(String apiKey) => <String, String>{
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
      };

  @override
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    if (baseUrl.trim().isEmpty || apiKey.trim().isEmpty) {
      return const ApiCheckResult(
        success: false,
        message: '请先填写 base URL 和 API key。',
      );
    }

    final Uri endpoint;
    try {
      endpoint = Uri.parse(modelsEndpoint(baseUrl));
    } catch (_) {
      return const ApiCheckResult(success: false, message: 'base URL 格式无效。');
    }

    try {
      final http.Response response =
          await getWithTimeout(endpoint, buildHeaders(apiKey));
      return interpretModelsProbe(response);
    } catch (error) {
      return ApiCheckResult(success: false, message: '连接失败:$error');
    }
  }

  @override
  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final Uri endpoint = Uri.parse(modelsEndpoint(baseUrl.trim()));

    try {
      final http.Response response =
          await getWithTimeout(endpoint, buildHeaders(apiKey.trim()));

      if (response.statusCode != 200) {
        return ModelFetchResult(
          models: const <String>[],
          errorMessage: extractErrorMessage(response.body, response.statusCode),
        );
      }

      // B4:容忍裸数组 / data 形 / models 形等多种响应形状。
      // 泛型兼容网关无法给出有意义的兜底列表,失败仍返回空列表。
      final List<String> models = extractModelIds(_safeJsonDecode(response.body));
      if (models.isEmpty) {
        return const ModelFetchResult(
          models: <String>[],
          errorMessage: '模型列表为空。',
        );
      }
      return ModelFetchResult(models: models);
    } catch (error) {
      return ModelFetchResult(
        models: const <String>[],
        errorMessage: '获取模型失败:$error',
      );
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletion(LlmRequest request) async {
    if (request.apiKey.trim().isEmpty || request.model.trim().isEmpty) {
      return const ChatCompletionResult(
        success: false,
        errorMessage: 'API Key 或模型不能为空。',
      );
    }

    final Uri endpoint = Uri.parse(chatEndpoint(request.baseUrl));
    try {
      final http.Response response = await client
          .post(
            endpoint,
            headers: buildHeaders(request.apiKey),
            body: jsonEncode(buildOpenAiCompatibleBody(request)),
          )
          .timeout(LlmServiceBase.completionTimeout);
      return parseOpenAiChatResponse(response);
    } catch (error) {
      return ChatCompletionResult(success: false, errorMessage: '请求失败:$error');
    }
  }

  @override
  Stream<LlmStreamChunk> streamChatCompletion(LlmRequest request) async* {
    if (request.apiKey.trim().isEmpty || request.model.trim().isEmpty) {
      yield const LlmErrorChunk('API Key 或模型不能为空。');
      return;
    }
    yield* streamOpenAiCompatible(request);
  }

  Object? _safeJsonDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// 经典 OpenAI 兼容拼接规则(含 `#` 逃生口与 vX 段检测,见基类)。
  @override
  String modelsEndpoint(String baseUrl) =>
      joinOpenAiEndpoint(baseUrl, '/models');

  @override
  String chatEndpoint(String baseUrl) =>
      joinOpenAiEndpoint(baseUrl, '/chat/completions');
}
