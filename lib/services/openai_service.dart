import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/service_results.dart';

class OpenAiService {
  OpenAiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ApiCheckResult> validateApi({
    required String baseUrl,
    required String apiKey,
  }) async {
    final String normalizedBase = baseUrl.trim();
    final String normalizedKey = apiKey.trim();
    if (normalizedBase.isEmpty || normalizedKey.isEmpty) {
      return const ApiCheckResult(
        success: false,
        message: '请先填写 base URL 和 API key。',
      );
    }

    final Uri endpoint;
    try {
      endpoint = Uri.parse(_modelsEndpoint(normalizedBase));
    } catch (_) {
      return const ApiCheckResult(success: false, message: 'base URL 格式无效。');
    }

    try {
      final http.Response response = await _client.get(
        endpoint,
        headers: <String, String>{
          'Authorization': 'Bearer $normalizedKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
      debugPrint('OpenAI /models raw response: ${response.body}');

      if (response.statusCode == 200) {
        return const ApiCheckResult(success: true, message: '连接验证成功。');
      }

      return ApiCheckResult(
        success: false,
        message: _extractError(response.body, response.statusCode),
      );
    } catch (error) {
      return ApiCheckResult(
        success: false,
        message: '连接失败：$error',
      );
    }
  }

  Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final Uri endpoint = Uri.parse(_modelsEndpoint(baseUrl.trim()));

    try {
      final http.Response response = await _client.get(
        endpoint,
        headers: <String, String>{
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return ModelFetchResult(
          models: const <String>[],
          errorMessage: _extractError(response.body, response.statusCode),
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ModelFetchResult(
          models: <String>[],
          errorMessage: '模型返回格式无效。',
        );
      }

      final Object? data = decoded['data'];
      if (data is! List) {
        return const ModelFetchResult(
          models: <String>[],
          errorMessage: '模型列表为空。',
        );
      }

      final List<String> models = data
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> item) => item['id'])
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();

      return ModelFetchResult(models: models);
    } catch (error) {
      return ModelFetchResult(
        models: const <String>[],
        errorMessage: '获取模型失败：$error',
      );
    }
  }

  Future<ChatCompletionResult> createChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final String normalizedKey = apiKey.trim();
    final String normalizedModel = model.trim();
    if (normalizedKey.isEmpty || normalizedModel.isEmpty) {
      return const ChatCompletionResult(
        success: false,
        errorMessage: 'API Key 或模型不能为空。',
      );
    }

    final Uri endpoint = Uri.parse(_chatEndpoint(baseUrl.trim()));
    try {
      final http.Response response = await _client
          .post(
            endpoint,
            headers: <String, String>{
              'Authorization': 'Bearer $normalizedKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': normalizedModel,
              'messages': messages,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('OpenAI /chat/completions raw response: ${response.body}');

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

  Stream<String> streamChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final String normalizedKey = apiKey.trim();
    final String normalizedModel = model.trim();
    if (normalizedKey.isEmpty || normalizedModel.isEmpty) {
      yield '[ERROR] API Key 或模型不能为空。';
      return;
    }

    final Uri endpoint = Uri.parse(_chatEndpoint(baseUrl.trim()));
    final http.Request request = http.Request('POST', endpoint)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $normalizedKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(<String, dynamic>{
        'model': normalizedModel,
        'messages': messages,
        'temperature': 0.7,
        'stream': true,
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

  String _modelsEndpoint(String baseUrl) {
    final String trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.toLowerCase().endsWith('/v1')) {
      return '$trimmed/models';
    }
    return '$trimmed/v1/models';
  }

  String _chatEndpoint(String baseUrl) {
    final String trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.toLowerCase().endsWith('/v1')) {
      return '$trimmed/chat/completions';
    }
    return '$trimmed/v1/chat/completions';
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
}
