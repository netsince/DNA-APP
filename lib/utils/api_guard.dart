import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import 'ui_feedback.dart';

bool ensureApiReady({
  required BuildContext context,
  required AppController controller,
}) {
  // C4:直接从激活配置实体派生,不依赖 legacy 扁平字段的同步状态。
  final String model = controller.activeModel.modelName.trim();
  final String apiKey = controller.activeProviderConfig.apiKey.trim();
  final String baseUrl = controller.activeProviderConfig.baseUrl.trim();
  if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
    showSnack(context, '请先在设置中完成 API 与模型配置。');
    return false;
  }
  return true;
}

/// 明文 HTTP 传输警示(D,不阻断):局域网/本机的 http:// 本地模型属合法场景,
/// 但公网明文传输 API Key 有被窃听风险,在校验结果文案中附加提醒。
String withTransportWarning(String baseUrl, String message) {
  if (message.isEmpty) {
    return message;
  }
  final Uri? uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || uri.scheme != 'http') {
    return message;
  }
  final String host = uri.host.toLowerCase();
  final bool isLocal = host.isEmpty ||
      host == 'localhost' ||
      host.startsWith('127.') ||
      host == '::1' ||
      host.startsWith('[::1]');
  if (isLocal) {
    return message;
  }
  return '$message\n⚠️ 当前使用明文 HTTP,API Key 可能被窃听,建议改用 HTTPS。';
}
