import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_results.dart';
import 'llm_request.dart';
import 'llm_service_base.dart';
import 'llm_stream_chunk.dart';

/// 智谱 GLM 适配器。
///
/// 智谱开放平台提供 OpenAI 兼容协议(Bearer 鉴权、相同的 SSE 流形态),
/// 但 API 版本路径是 `/v4` 而非 `/v1`,且不支持 min_p/repetition 类高级采样,
/// 也不使用 DeepSeek 思考字段——请求体在此自行组装。
///
/// 该厂商的 Base URL 固定,用户只需填写 API Key,故 [fixedBaseUrl] 返回 true。
class ZhipuProvider extends LlmServiceBase {
  ZhipuProvider({super.client, super.streamClient});

  @override
  String get id => 'zhipu';

  @override
  String get label => '智谱 GLM';

  @override
  String get defaultBaseUrl => 'https://open.bigmodel.cn/api/paas/v4';

  @override
  bool get requiresApiKey => true;

  /// 该厂商的 Base URL 固定,无需用户填写。
  @override
  bool get fixedBaseUrl => true;

  @override
  Map<String, String> buildHeaders(String apiKey) => <String, String>{
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
      };

  /// 归一化 baseUrl:去掉尾部斜杠后直接作为前缀,不再追加版本段。
  String _root(String baseUrl) =>
      baseUrl.trim().replaceAll(RegExp(r'/+$|/v1$'), '');

  @override
  String chatEndpoint(String baseUrl) => '${_root(baseUrl)}/chat/completions';

  @override
  String modelsEndpoint(String baseUrl) => '${_root(baseUrl)}/models';

  @override
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      return const ApiCheckResult(success: false, message: '请先填写 API key。');
    }

    try {
      final http.Response response = await getWithTimeout(
        Uri.parse(modelsEndpoint(baseUrl)),
        buildHeaders(apiKey),
      );
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
    try {
      final http.Response response = await getWithTimeout(
        Uri.parse(modelsEndpoint(baseUrl.trim())),
        buildHeaders(apiKey.trim()),
      );

      if (response.statusCode != 200) {
        return ModelFetchResult(
          models: _fallbackModels,
          errorMessage: extractErrorMessage(response.body, response.statusCode),
        );
      }

      // B4:容忍裸数组 / data 形 / models 形等多种响应形状。
      final List<String> models =
          extractModelIds(_safeJsonDecode(response.body));
      if (models.isEmpty) {
        return const ModelFetchResult(models: _fallbackModels);
      }
      return ModelFetchResult(models: models);
    } catch (error) {
      return ModelFetchResult(
        models: _fallbackModels,
        errorMessage: '获取模型失败:$error',
      );
    }
  }

  /// 智谱请求体:OpenAI 兼容,但仅 top_p/top_k 高级采样、无思考字段;
  /// reasoning 系模型(glm-z 等)同样按能力矩阵省略采样参数(B1)。
  Map<String, dynamic> _buildBody(LlmRequest request, {bool stream = false}) {
    final bool samplingAllowed =
        LlmServiceBase.supportsSamplingControls(request.model);
    return <String, dynamic>{
      'model': request.model,
      'messages': request.messages,
      if (samplingAllowed) ...<String, dynamic>{
        'temperature': request.temperature,
        'frequency_penalty': request.frequencyPenalty,
        'presence_penalty': request.presencePenalty,
        if (request.topP != 1.0) 'top_p': request.topP,
        if (request.topK > 0) 'top_k': request.topK,
      },
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (stream) 'stream': true,
    };
  }

  @override
  Future<ChatCompletionResult> createChatCompletion(LlmRequest request) async {
    if (request.apiKey.trim().isEmpty || request.model.trim().isEmpty) {
      return const ChatCompletionResult(
        success: false,
        errorMessage: 'API Key 或模型不能为空。',
      );
    }

    try {
      final http.Response response = await client
          .post(
            Uri.parse(chatEndpoint(request.baseUrl)),
            headers: buildHeaders(request.apiKey),
            body: jsonEncode(_buildBody(request)),
          )
          .timeout(LlmServiceBase.completionTimeout);
      // C3:非流式响应解析复用基类实现,不再各持一份。
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

    final http.Request req =
        http.Request('POST', Uri.parse(chatEndpoint(request.baseUrl)))
          ..headers.addAll(buildHeaders(request.apiKey))
          ..body = jsonEncode(_buildBody(request, stream: true));

    yield* pumpSse(request: req, decodeEvent: decodeOpenAiEvent);
  }

  Object? _safeJsonDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// 智谱模型兜底列表(拉取失败时回退)。
  static const List<String> _fallbackModels = <String>[
    'glm-4.5-air',
    'glm-4.5',
    'glm-4-plus',
    'glm-4-flash',
  ];
}
