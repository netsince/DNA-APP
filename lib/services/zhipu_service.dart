import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/service_results.dart';
import 'llm_provider.dart';

/// 智谱 GLM 适配器。
///
/// 智谱开放平台提供 OpenAI 兼容协议（Bearer 鉴权、相同的 SSE 流形态），
/// 但 API 版本路径是 `/v4` 而非 `/v1`，因此端点不能沿用 OpenAiService 的
/// 「一律补 /v1」逻辑。这里把版本段写死在 [defaultBaseUrl] 中，直接拼接
/// `/chat/completions` 与 `/models`，避免多出一个 `/v1`。
///
/// 该厂商的 Base URL 固定，用户只需填写 API Key，故 [fixedBaseUrl] 返回 true。
class ZhipuProvider implements LlmProvider {
  ZhipuProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get id => 'zhipu';

  @override
  String get label => '智谱 GLM';

  @override
  String get defaultBaseUrl => 'https://open.bigmodel.cn/api/paas/v4';

  @override
  bool get requiresApiKey => true;

  /// 该厂商的 Base URL 固定，无需用户填写。
  @override
  bool get fixedBaseUrl => true;

  Map<String, String> _headers(String apiKey) => <String, String>{
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
      };

  /// 归一化 baseUrl：去掉尾部斜杠后直接作为前缀，不再追加版本段。
  String _root(String baseUrl) =>
      baseUrl.trim().replaceAll(RegExp(r'/+$|/v1$'), '');

  String _chatEndpoint(String baseUrl) => '${_root(baseUrl)}/chat/completions';

  String _modelsEndpoint(String baseUrl) => '${_root(baseUrl)}/models';

  @override
  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    final String normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return const ApiCheckResult(
        success: false,
        message: '请先填写 API key。',
      );
    }

    try {
      final http.Response response = await _client
          .get(
            Uri.parse(_modelsEndpoint(baseUrl)),
            headers: _headers(normalizedKey),
          )
          .timeout(const Duration(seconds: 12));
      debugPrint('Zhipu /models raw response: ${response.body}');

      if (response.statusCode == 200) {
        return const ApiCheckResult(success: true, message: '连接验证成功。');
      }
      return ApiCheckResult(
        success: false,
        message: _extractError(response.body, response.statusCode),
      );
    } catch (error) {
      return ApiCheckResult(success: false, message: '连接失败：$error');
    }
  }

  @override
  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(_modelsEndpoint(baseUrl)),
            headers: _headers(apiKey.trim()),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return ModelFetchResult(
          models: _fallbackModels,
          errorMessage: _extractError(response.body, response.statusCode),
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ModelFetchResult(
          models: _fallbackModels,
          errorMessage: '模型返回格式无效。',
        );
      }

      final Object? data = decoded['data'];
      if (data is! List) {
        return ModelFetchResult(models: _fallbackModels);
      }

      final List<String> models = data
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> item) => item['id'])
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();

      if (models.isEmpty) {
        return ModelFetchResult(models: _fallbackModels);
      }
      return ModelFetchResult(models: models);
    } catch (error) {
      return ModelFetchResult(
        models: _fallbackModels,
        errorMessage: '获取模型失败：$error',
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
    final String normalizedKey = apiKey.trim();
    final String normalizedModel = model.trim();
    if (normalizedKey.isEmpty || normalizedModel.isEmpty) {
      return const ChatCompletionResult(
        success: false,
        errorMessage: 'API Key 或模型不能为空。',
      );
    }

    try {
      final http.Response response = await _client
          .post(
            Uri.parse(_chatEndpoint(baseUrl)),
            headers: _headers(normalizedKey),
            body: jsonEncode(<String, dynamic>{
              'model': normalizedModel,
              'messages': messages,
              'temperature': temperature,
              'frequency_penalty': frequencyPenalty,
              'presence_penalty': presencePenalty,
              ..._samplingBody(topP: topP, topK: topK),
            }),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('Zhipu /chat/completions raw response: ${response.body}');

      if (response.statusCode != 200) {
        return ChatCompletionResult(
          success: false,
          errorMessage: _extractError(response.body, response.statusCode),
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ChatCompletionResult(success: false, errorMessage: '返回格式无效。');
      }
      final Object? choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        return const ChatCompletionResult(success: false, errorMessage: '模型未返回内容。');
      }
      final Object? message = (choices.first as Map<String, dynamic>)['message'];
      if (message is! Map<String, dynamic>) {
        return const ChatCompletionResult(success: false, errorMessage: '返回内容缺失。');
      }
      final String? content = message['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        return const ChatCompletionResult(success: false, errorMessage: '返回内容为空。');
      }
      return ChatCompletionResult(success: true, content: content.trim());
    } catch (error) {
      return ChatCompletionResult(success: false, errorMessage: '请求失败：$error');
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
    final String normalizedKey = apiKey.trim();
    final String normalizedModel = model.trim();
    if (normalizedKey.isEmpty || normalizedModel.isEmpty) {
      yield '[ERROR] API Key 或模型不能为空。';
      return;
    }

    final http.Request request = http.Request('POST', Uri.parse(_chatEndpoint(baseUrl)))
      ..headers.addAll(_headers(normalizedKey))
      ..body = jsonEncode(<String, dynamic>{
        'model': normalizedModel,
        'messages': messages,
        'temperature': temperature,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'stream': true,
        ..._samplingBody(topP: topP, topK: topK),
      });

    try {
      final http.StreamedResponse response = await _client.send(request).timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        yield '[ERROR] ${_extractError(body, response.statusCode)}';
        return;
      }

      final Stream<String> lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final String line in lines) {
        if (line.isEmpty || !line.startsWith('data:')) {
          continue;
        }
        final String data = line.substring(5).trim();
        if (data == '[DONE]') {
          break;
        }
        try {
          final Object? decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            final Object? choices = decoded['choices'];
            if (choices is List && choices.isNotEmpty) {
              final Object? delta = (choices.first as Map<String, dynamic>)['delta'];
              if (delta is Map<String, dynamic>) {
                final String? reasoning = delta['reasoning_content'] as String?;
                if (reasoning != null && reasoning.isNotEmpty) {
                  yield '<think>$reasoning</think>';
                }
                final String? content = delta['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            }
          }
        } catch (_) {
          // Ignore malformed chunks.
        }
      }
    } catch (error) {
      yield '[ERROR] 请求失败：$error';
    }
  }

  /// 组装智谱支持的高级采样参数（仅 top_p / top_k，非默认值时携带）。
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

  String _extractError(String responseBody, int statusCode) {
    try {
      final Object? decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final Object? errorNode = decoded['error'];
        if (errorNode is Map<String, dynamic>) {
          final Object? message = errorNode['message'];
          if (message is String && message.trim().isNotEmpty) {
            return 'HTTP $statusCode: $message';
          }
        }
      }
    } catch (_) {
      // Keep fallback message.
    }
    return 'HTTP $statusCode: 请求失败。';
  }

  /// 智谱模型兜底列表（拉取失败时回退）。
  static const List<String> _fallbackModels = <String>[
    'glm-4.5-air',
    'glm-4.5',
    'glm-4-plus',
    'glm-4-flash',
  ];
}
