import 'dart:convert';

import 'package:http/http.dart' as http;

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

  String _modelsEndpoint(String baseUrl) {
    final String trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.toLowerCase().endsWith('/v1')) {
      return '$trimmed/models';
    }
    return '$trimmed/v1/models';
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
