import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import 'ui_feedback.dart';

bool ensureApiReady({
  required BuildContext context,
  required AppController controller,
}) {
  final String model = controller.settings.selectedModel;
  final String apiKey = controller.settings.apiKey;
  final String baseUrl = controller.settings.baseUrl;
  if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
    showSnack(context, '请先在设置中完成 API 与模型配置。');
    return false;
  }
  return true;
}
