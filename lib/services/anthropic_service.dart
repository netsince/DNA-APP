import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_results.dart';
import 'llm_request.dart';
import 'llm_service_base.dart';
import 'llm_stream_chunk.dart';

/// Anthropic (Claude) 适配器。
///
/// 与 OpenAI 的差异:
///  - 鉴权走 `x-api-key` + `anthropic-version` 头,而非 `Bearer`。
///  - `system` 是顶层参数,不能放进 messages。
///  - 必须携带 `max_tokens`(可用模型配置覆盖,默认 8192)。
///  - 流式是标准 event/data SSE:text_delta → 正文,thinking_delta → 思考分片。
///
/// 传输保障(超时/看门狗/[LlmErrorChunk] 契约/真取消)由 [LlmServiceBase] 统一承载。
class AnthropicProvider extends LlmServiceBase {
  AnthropicProvider({super.client, super.streamClient});

  /// 单轮最大输出 token 的默认值(Anthropic 必填;模型配置可覆盖)。
  static const int defaultMaxTokens = 8192;

  @override
  String get id => 'anthropic';

  @override
  String get label => 'Anthropic (Claude)';

  @override
  String get defaultBaseUrl => 'https://api.anthropic.com';

  @override
  bool get requiresApiKey => true;

  @override
  bool get fixedBaseUrl => false;

  @override
  Map<String, String> buildHeaders(String apiKey) => <String, String>{
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      };

  /// 归一化 baseUrl:去掉尾部斜杠与多余的 `/v1`,得到 API 根地址。
  String _apiRoot(String baseUrl) {
    String s = baseUrl.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/v1')) {
      s = s.substring(0, s.length - 3);
    }
    return s;
  }

  @override
  String chatEndpoint(String baseUrl) => '${_apiRoot(baseUrl)}/v1/messages';

  @override
  String modelsEndpoint(String baseUrl) => '${_apiRoot(baseUrl)}/v1/models';

  /// 从 OpenAI 形态的消息列表里拆出 system 文本与对话消息。
  ({String? system, List<Map<String, String>> convo}) _splitSystem(
    List<Map<String, String>> messages,
  ) {
    final StringBuffer systemBuf = StringBuffer();
    final List<Map<String, String>> convo = <Map<String, String>>[];
    for (final Map<String, String> m in messages) {
      final String role = m['role'] ?? '';
      final String content = m['content'] ?? '';
      if (role == 'system') {
        if (systemBuf.isNotEmpty) {
          systemBuf.write('\n\n');
        }
        systemBuf.write(content);
      } else {
        convo.add(<String, String>{'role': role, 'content': content});
      }
    }
    final String? system = systemBuf.isEmpty ? null : systemBuf.toString();
    return (system: system, convo: convo);
  }

  /// 组装 Anthropic 请求体。采样仅 top_p/top_k(非默认值时携带),
  /// temperature 始终发送;max_tokens 用配置值或默认值(E/B5)。
  Map<String, dynamic> _buildBody(LlmRequest request,
      {required bool stream}) {
    final (:String? system, :List<Map<String, String>> convo) =
        _splitSystem(request.messages);
    return <String, dynamic>{
      'model': request.model,
      'max_tokens': request.maxTokens ?? defaultMaxTokens,
      'temperature': request.temperature,
      if (stream) 'stream': true,
      'messages': convo,
      if (request.topP != 1.0) 'top_p': request.topP,
      if (request.topK > 0) 'top_k': request.topK,
      'system': ?system,
    };
  }

  int _sumAnthropicUsage(Map<String, dynamic>? usage) {
    if (usage == null) {
      return 0;
    }
    final Object? input = usage['input_tokens'];
    final Object? output = usage['output_tokens'];
    final int i = input is num ? input.toInt() : 0;
    final int o = output is num ? output.toInt() : 0;
    return i + o;
  }

  @override
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final http.Response res =
          await getWithTimeout(Uri.parse(modelsEndpoint(baseUrl)), buildHeaders(apiKey));
      return interpretModelsProbe(res);
    } catch (e) {
      return ApiCheckResult(success: false, message: e.toString());
    }
  }

  @override
  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final http.Response res = await getWithTimeout(
        Uri.parse(modelsEndpoint(baseUrl)),
        buildHeaders(apiKey),
      );
      if (res.statusCode != 200) {
        return ModelFetchResult(
          models: _fallbackModels,
          errorMessage: extractErrorMessage(res.body, res.statusCode),
        );
      }
      // B4:统一走基类的形状容忍提取。
      final List<String> models = extractModelIds(_safeJsonDecode(res.body));
      if (models.isEmpty) {
        return const ModelFetchResult(models: _fallbackModels);
      }
      return ModelFetchResult(models: models);
    } catch (e) {
      return ModelFetchResult(
        models: _fallbackModels,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletion(LlmRequest request) async {
    try {
      final http.Response res = await client
          .post(
            Uri.parse(chatEndpoint(request.baseUrl)),
            headers: buildHeaders(request.apiKey),
            body: jsonEncode(_buildBody(request, stream: false)),
          )
          .timeout(LlmServiceBase.completionTimeout);
      if (res.statusCode != 200) {
        return ChatCompletionResult(
          success: false,
          errorMessage: extractErrorMessage(res.body, res.statusCode),
        );
      }
      final Object? decoded = _safeJsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return const ChatCompletionResult(success: false, errorMessage: '返回格式无效。');
      }
      final List<dynamic> content =
          decoded['content'] as List<dynamic>? ?? <dynamic>[];
      final String text = content
          .where((dynamic b) =>
              b is Map<String, dynamic> && b['type'] == 'text')
          .map((dynamic b) => (b as Map<String, dynamic>)['text'] as String? ?? '')
          .join();
      if (text.trim().isEmpty) {
        return const ChatCompletionResult(success: false, errorMessage: '返回内容为空。');
      }
      return ChatCompletionResult(
        success: true,
        content: text,
        totalTokens:
            _sumAnthropicUsage(decoded['usage'] as Map<String, dynamic>?),
      );
    } catch (e) {
      return ChatCompletionResult(success: false, errorMessage: e.toString());
    }
  }

  @override
  Stream<LlmStreamChunk> streamChatCompletion(LlmRequest request) {
    final Uri endpoint = Uri.parse(chatEndpoint(request.baseUrl));
    final http.Request req = http.Request('POST', endpoint)
      ..headers.addAll(buildHeaders(request.apiKey))
      ..body = jsonEncode(_buildBody(request, stream: true));
    return pumpSse(request: req, decodeEvent: _decodeAnthropicEvent);
  }

  /// Anthropic SSE 事件解码。
  /// text_delta → 正文;thinking_delta → 思考分片(扩展思考);
  /// error 事件 / data 内 error 节点 → 错误分片;message_stop → 终止。
  SseDecode _decodeAnthropicEvent(String? event, String data) {
    try {
      final Object? decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        return const SseDecode();
      }
      if (event == 'error' || decoded['type'] == 'error') {
        final Object? err = decoded['error'];
        final String message = err is Map<String, dynamic>
            ? (err['message'] as String? ?? '流式请求失败')
            : '流式请求失败';
        return SseDecode(chunks: <LlmStreamChunk>[LlmErrorChunk(message)]);
      }
      switch (event) {
        case 'content_block_delta':
          final Map<String, dynamic> delta =
              decoded['delta'] as Map<String, dynamic>? ?? <String, dynamic>{};
          final String type = delta['type'] as String? ?? '';
          if (type == 'text_delta') {
            final String text = delta['text'] as String? ?? '';
            if (text.isNotEmpty) {
              return SseDecode(chunks: <LlmStreamChunk>[LlmContentChunk(text)]);
            }
          } else if (type == 'thinking_delta') {
            final String text = delta['thinking'] as String? ?? '';
            if (text.isNotEmpty) {
              return SseDecode(
                  chunks: <LlmStreamChunk>[LlmReasoningChunk(text)]);
            }
          }
          return const SseDecode();
        case 'message_stop':
          return const SseDecode(done: true);
        default:
          return const SseDecode();
      }
    } catch (_) {
      return const SseDecode();
    }
  }

  Object? _safeJsonDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Anthropic 模型兜底列表(/models 不可用时回退)。
  static const List<String> _fallbackModels = <String>[
    'claude-opus-4-5',
    'claude-sonnet-4-5',
    'claude-sonnet-4-0',
    'claude-haiku-4-5',
  ];
}
