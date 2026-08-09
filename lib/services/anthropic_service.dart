import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_results.dart';
import 'llm_provider.dart';

/// Anthropic (Claude) 适配器。
///
/// 与 OpenAI 的差异：
///  - 鉴权走 `x-api-key` + `anthropic-version` 头，而非 `Bearer`。
///  - `system` 是顶层参数，不能放进 messages。
///  - 必须携带 `max_tokens`。
///  - 流式是标准 `event:`/`data:` SSE，`text_delta` 在 `content_block_delta` 中。
class AnthropicProvider implements LlmProvider {
  AnthropicProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单轮最大输出 token（Anthropic 必填）。
  static const int _maxTokens = 8192;

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

  Map<String, String> _headers(String apiKey) => <String, String>{
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      };

  /// 归一化 baseUrl：去掉尾部斜杠与多余的 `/v1`，得到 API 根地址。
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

  /// 组装 Anthropic 支持的高级采样参数（仅 top_p / top_k，非默认值时携带）。
  Map<String, dynamic> _samplingBody({
    required double topP,
    required double topK,
  }) {
    final Map<String, dynamic> out = <String, dynamic>{};
    if (topP != 1.0) {
      out['top_p'] = topP;
    }
    if (topK > 0) {
      out['top_k'] = topK;
    }
    return out;
  }

  String _messagesEndpoint(String baseUrl) => '${_apiRoot(baseUrl)}/v1/messages';

  String _modelsEndpoint(String baseUrl) => '${_apiRoot(baseUrl)}/v1/models';

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

  @override
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final http.Response res = await _client.get(
        Uri.parse(_modelsEndpoint(baseUrl)),
        headers: _headers(apiKey),
      );
      if (res.statusCode == 200) {
        return ApiCheckResult(success: true, message: '连接成功');
      }
      return ApiCheckResult(
        success: false,
        message: _extractError(res.body) ?? '校验失败 (${res.statusCode})',
      );
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
      final http.Response res = await _client.get(
        Uri.parse(_modelsEndpoint(baseUrl)),
        headers: _headers(apiKey),
      );
      if (res.statusCode != 200) {
        return ModelFetchResult(
          models: _fallbackModels,
          errorMessage: _extractError(res.body) ?? '拉取模型失败 (${res.statusCode})',
        );
      }
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      final List<dynamic> data = json['data'] as List<dynamic>? ?? <dynamic>[];
      final List<String> models = data
          .map((dynamic e) => (e as Map<String, dynamic>)['id'] as String?)
          .where((String? id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();
      if (models.isEmpty) {
        return ModelFetchResult(models: _fallbackModels);
      }
      models.sort();
      return ModelFetchResult(models: models);
    } catch (e) {
      return ModelFetchResult(
        models: _fallbackModels,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    double frequencyPenalty = 0.0,
    double presencePenalty = 0.0,
    double topP = 1.0,
    double topK = 0.0,
    double minP = 0.0,
    double repetitionPenalty = 1.0,
    double repetitionPenaltySlope = 0.0,
    String? thinkingType,
    String? reasoningEffort,
  }) async {
    try {
      final (:String? system, :List<Map<String, String>> convo) =
          _splitSystem(messages);
      final Map<String, dynamic> body = <String, dynamic>{
        'model': model,
        'max_tokens': _maxTokens,
        'temperature': temperature,
        'messages': convo,
        ..._samplingBody(topP: topP, topK: topK),
      };
      if (system != null) {
        body['system'] = system;
      }
      final http.Response res = await _client.post(
        Uri.parse(_messagesEndpoint(baseUrl)),
        headers: _headers(apiKey),
        body: jsonEncode(body),
      );
      if (res.statusCode != 200) {
        return ChatCompletionResult(
          success: false,
          errorMessage: _extractError(res.body) ?? '请求失败 (${res.statusCode})',
        );
      }
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      final List<dynamic> content =
          json['content'] as List<dynamic>? ?? <dynamic>[];
      final String text = content
          .where((dynamic b) =>
              (b as Map<String, dynamic>)['type'] == 'text')
          .map((dynamic b) => (b as Map<String, dynamic>)['text'] as String? ?? '')
          .join();
      return ChatCompletionResult(success: true, content: text);
    } catch (e) {
      return ChatCompletionResult(success: false, errorMessage: e.toString());
    }
  }

  @override
  Stream<String> streamChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    double frequencyPenalty = 0.0,
    double presencePenalty = 0.0,
    double topP = 1.0,
    double topK = 0.0,
    double minP = 0.0,
    double repetitionPenalty = 1.0,
    double repetitionPenaltySlope = 0.0,
    String? thinkingType,
    String? reasoningEffort,
  }) async* {
    final (:String? system, :List<Map<String, String>> convo) =
        _splitSystem(messages);
    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'max_tokens': _maxTokens,
      'temperature': temperature,
      'stream': true,
      'messages': convo,
      ..._samplingBody(topP: topP, topK: topK),
    };
    if (system != null) {
      body['system'] = system;
    }

    final http.Request request =
        http.Request('POST', Uri.parse(_messagesEndpoint(baseUrl)))
          ..headers.addAll(_headers(apiKey))
          ..body = jsonEncode(body);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw Exception('请求发送失败: $e');
    }

    if (response.statusCode != 200) {
      final String bodyText = await response.stream.bytesToString();
      throw Exception(_extractError(bodyText) ?? '流式请求失败 (${response.statusCode})');
    }

    String event = '';
    String dataBuf = '';
    await for (final String line
        in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        // 空行表示一个 SSE 事件结束。
        if (event == 'content_block_delta' && dataBuf.isNotEmpty) {
          final String? text = _parseDelta(dataBuf);
          if (text != null) {
            yield text;
          }
        }
        event = '';
        dataBuf = '';
        continue;
      }
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataBuf = line.substring(5).trim();
      }
    }
  }

  String? _parseDelta(String data) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(data) as Map<String, dynamic>;
      final Map<String, dynamic> delta =
          json['delta'] as Map<String, dynamic>? ?? <String, dynamic>{};
      if (delta['type'] == 'text_delta') {
        final String? text = delta['text'] as String?;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    } catch (_) {
      // 忽略无法解析的分片。
    }
    return null;
  }

  String? _extractError(String body) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      final Map<String, dynamic>? err =
          json['error'] as Map<String, dynamic>?;
      if (err != null) {
        return err['message'] as String? ?? err['type'] as String?;
      }
    } catch (_) {
      // 非 JSON 错误体，返回原始文本（截断）。
      return body.length > 200 ? body.substring(0, 200) : body;
    }
    return null;
  }

  /// Anthropic 没有稳定的「列出模型」接口时使用的兜底列表。
  static const List<String> _fallbackModels = <String>[
    'claude-opus-4-5',
    'claude-sonnet-4-5',
    'claude-sonnet-4-0',
    'claude-haiku-4-5',
  ];
}
